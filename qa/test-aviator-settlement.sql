\set ON_ERROR_STOP on
\ir ../sql/NPLUS_PLAY_AVIATOR_SCHEMA.sql
\ir ../sql/NPLUS_PLAY_AVIATOR_RPC.sql

do $tests$
declare
 u uuid:='55555555-5555-4555-8555-555555555555';
 r jsonb; placed jsonb; auto_placed jsonb; current_state jsonb;
 cashed jsonb; retry jsonb; mine jsonb; history jsonb; lost_bet jsonb; loss_result jsonb;
 round_id uuid; lost_round_id uuid; request_one uuid:='66666666-6666-4666-8666-666666666666';
 request_two uuid:='77777777-7777-4777-8777-777777777777';
 request_three uuid:='88888888-8888-4888-8888-888888888888';
 balance_after numeric(12,2); payout_one numeric(12,2); multiplier_one numeric(8,2);
 win_count integer; bet_count integer;
begin
 insert into auth.users(id,email) values(u,'aviator-qa@example.invalid');
 insert into public.demo_wallets(user_id,balance) values(u,108.00);
 perform set_config('request.jwt.claim.sub',u::text,true);

 r:=public.nplus_aviator_demo_current_round();
 if coalesce(r->>'crash_point','')<>'' or r ? 'crashes_at' then
   raise exception 'Aviator current-round RPC leaks crash point/timing before crash.';
 end if;
 round_id:=(r->>'round_id')::uuid;

 placed:=public.nplus_aviator_demo_place_bet(round_id,0,10.00,request_one,null);
 if placed->>'status'<>'open' then raise exception 'Aviator bet placement failed.'; end if;
 auto_placed:=public.nplus_aviator_demo_place_bet(round_id,1,5.00,request_two,2.00);
 if auto_placed->>'status'<>'open' or (auto_placed->>'auto_cashout')::numeric<>2.00 then
  raise exception 'Aviator auto bet placement failed.';
 end if;
 select balance into balance_after from public.demo_wallets where user_id=u;
 if balance_after<>93.00 then raise exception 'Aviator expected 93 after two stakes, got %.',balance_after; end if;

 -- Force a deterministic flying state in this disposable database only.
 update public.nplus_aviator_demo_rounds
 set flight_starts_at=clock_timestamp()-interval '20 seconds',
     crashes_at=clock_timestamp()+interval '10 minutes',
     crash_point=100,
     status='flying'
 where id=round_id;

 -- Current-round polling must trigger the server-owned auto cash-out at 2x.
 current_state:=public.nplus_aviator_demo_current_round();
 select balance into balance_after from public.demo_wallets where user_id=u;
 if balance_after<>103.00 then raise exception 'Aviator server auto cash-out should return 10, got balance %.',balance_after; end if;
 if coalesce(current_state->>'crash_point','')<>'' or current_state ? 'crashes_at' then
   raise exception 'Aviator flying response leaked crash point/timing.';
 end if;

 -- Manual cash-out multiplier and payout are determined by server time, not request data.
 cashed:=public.nplus_aviator_demo_cashout((placed->>'bet_id')::uuid);
 if cashed->>'status'<>'cashed_out' then raise exception 'Aviator server manual cash-out failed: %.',cashed; end if;
 payout_one:=(cashed->>'payout')::numeric;
 multiplier_one:=(cashed->>'multiplier')::numeric;
 if payout_one<>round(10.00*multiplier_one,2) or multiplier_one<1.01 then
  raise exception 'Aviator server payout does not match server multiplier.';
 end if;

 retry:=public.nplus_aviator_demo_cashout((placed->>'bet_id')::uuid);
 select balance into balance_after from public.demo_wallets where user_id=u;
 if retry->>'status'<>'cashed_out' or balance_after<>round(103.00+payout_one,2) then
  raise exception 'Aviator repeated cash-out credited twice.';
 end if;
 select count(*) into win_count from public.demo_wallet_transactions where user_id=u and type='GAME_WIN';
 if win_count<>2 then raise exception 'Expected exactly two Aviator ledger credits (manual and auto), found %.',win_count; end if;

 mine:=public.nplus_aviator_demo_my_bets(100);
 if jsonb_array_length(mine)<>2 then raise exception 'Aviator server bet recovery failed.'; end if;
 history:=public.nplus_aviator_demo_history(100);
 if jsonb_typeof(history)<>'array' then raise exception 'Aviator history RPC did not return an array.'; end if;

 -- End the forced test round so the RPC creates a fresh waiting round.
 update public.nplus_aviator_demo_rounds
 set crashes_at=clock_timestamp()-interval '3 seconds',status='flying'
 where id=round_id;

 -- Place a fresh test bet, expire its round and verify it loses without a credit.
 r:=public.nplus_aviator_demo_current_round();
 lost_round_id:=(r->>'round_id')::uuid;
 lost_bet:=public.nplus_aviator_demo_place_bet(lost_round_id,0,2.00,request_three,null);
 update public.nplus_aviator_demo_rounds
 set flight_starts_at=clock_timestamp()-interval '20 seconds',
     crashes_at=clock_timestamp()-interval '1 second',
     crash_point=1.50,
     status='flying'
 where id=lost_round_id;

 loss_result:=public.nplus_aviator_demo_cashout((lost_bet->>'bet_id')::uuid);
 if loss_result->>'status'<>'lost' then raise exception 'Cash-out after crash should be rejected as loss.'; end if;
 select balance into balance_after from public.demo_wallets where user_id=u;
 if balance_after<>round(101.00+payout_one,2) then
  raise exception 'Aviator post-crash cash-out changed balance unexpectedly: %.',balance_after;
 end if;

 if has_table_privilege('anon','public.nplus_aviator_demo_bets','SELECT')
    or has_table_privilege('authenticated','public.nplus_aviator_demo_bets','SELECT') then
  raise exception 'Direct Aviator bet-table reads are granted.';
 end if;
 if has_function_privilege('anon','public.nplus_aviator_demo_place_bet(uuid,integer,numeric,uuid,numeric)','EXECUTE')
    or not has_function_privilege('authenticated','public.nplus_aviator_demo_place_bet(uuid,integer,numeric,uuid,numeric)','EXECUTE') then
  raise exception 'Aviator placement RPC grants are incorrect.';
 end if;
 if has_function_privilege('anon','public.nplus_aviator_demo_cashout(uuid)','EXECUTE')
    or not has_function_privilege('authenticated','public.nplus_aviator_demo_cashout(uuid)','EXECUTE') then
  raise exception 'Aviator cash-out RPC grants are incorrect.';
 end if;
 raise notice 'Aviator server-settlement tests passed.';
end
$tests$;
