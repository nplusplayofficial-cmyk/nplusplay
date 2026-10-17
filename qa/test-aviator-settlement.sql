\set ON_ERROR_STOP on
\ir ../sql/NPLUS_PLAY_AVIATOR_SCHEMA.sql
\ir ../sql/NPLUS_PLAY_AVIATOR_RPC.sql

do $tests$
declare
 u uuid:='55555555-5555-4555-8555-555555555555';
 r jsonb; placed jsonb; auto_placed jsonb; current_state jsonb;
 cashed jsonb; retry jsonb; mine jsonb; history jsonb; lost_bet jsonb; loss_result jsonb; late_manual_bet jsonb;
 multiplier_auto_bet jsonb; multiplier_manual_bet jsonb; multiplier_row public.nplus_aviator_demo_bets%rowtype;
 round_id uuid; lost_round_id uuid; request_one uuid:='66666666-6666-4666-8666-666666666666';
 request_two uuid:='77777777-7777-4777-8777-777777777777';
 request_three uuid:='88888888-8888-4888-8888-888888888888';
 request_four uuid:='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
 request_five uuid:='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
 request_six uuid:='99999999-9999-4999-8999-999999999996';
 request_seven uuid:='99999999-9999-4999-8999-999999999997';
 late_bet jsonb;
 late_row public.nplus_aviator_demo_bets%rowtype;
 late_round_id uuid;
 multiplier_round_id uuid;
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

 -- Force the prior crash beyond the visual grace period and open another round.
 update public.nplus_aviator_demo_rounds
 set crashes_at=clock_timestamp()-interval '3 seconds',status='crashed'
 where id=lost_round_id;

 r:=public.nplus_aviator_demo_current_round();
 late_round_id:=(r->>'round_id')::uuid;
 late_bet:=public.nplus_aviator_demo_place_bet(late_round_id,0,2.00,request_four,2.00);
 late_manual_bet:=public.nplus_aviator_demo_place_bet(late_round_id,1,1.00,request_five,null);

 -- Simulate all background polling being delayed until a manual cash-out request arrives
 -- after crash. The server must settle eligible auto targets first, then mark remaining
 -- bets lost; a client request cannot change the crash result.
 update public.nplus_aviator_demo_rounds
 set flight_starts_at=clock_timestamp()-interval '20 seconds',
     crashes_at=clock_timestamp()-interval '4 seconds',
     crash_point=3.00,
     status='flying'
 where id=late_round_id;

 loss_result:=public.nplus_aviator_demo_cashout((late_manual_bet->>'bet_id')::uuid);
 if loss_result->>'status'<>'lost' then
   raise exception 'Manual cash-out after crash must lose.';
 end if;

 select * into late_row
 from public.nplus_aviator_demo_bets
 where user_id=u and request_id=request_four;
 if late_row.status<>'cashed_out' or late_row.cashout_multiplier<>2.00 or late_row.payout<>4.00 then
   raise exception 'Late-finalized Aviator auto cash-out did not pay once at 2x.';
 end if;

 select balance into balance_after from public.demo_wallets where user_id=u;
 if balance_after<>round(102.00+payout_one,2) then
   raise exception 'Late-finalized auto cash-out expected balance %; got %.',round(102.00+payout_one,2),balance_after;
 end if;
 select count(*) into win_count from public.demo_wallet_transactions where user_id=u and type='GAME_WIN';
 if win_count<>3 then
   raise exception 'Expected one late auto-cashout credit; GAME_WIN count is %.',win_count;
 end if;
 select count(*) into bet_count from public.nplus_aviator_demo_bets b
 where b.user_id=u and b.round_id=late_round_id and b.status='lost';
 if bet_count<>1 then
   raise exception 'Only the manual bet should be marked lost after late finalization.';
 end if;

 -- Separately exercise the boundary where the server multiplier reaches the crash
 -- point while the stored estimated deadline is still in the future.
 update public.nplus_aviator_demo_rounds
 set crashed_at=clock_timestamp()-interval '3 seconds'
 where id=late_round_id;

 r:=public.nplus_aviator_demo_current_round();
 multiplier_round_id:=(r->>'round_id')::uuid;
 multiplier_auto_bet:=public.nplus_aviator_demo_place_bet(multiplier_round_id,0,2.00,request_six,2.00);
 multiplier_manual_bet:=public.nplus_aviator_demo_place_bet(multiplier_round_id,1,1.00,request_seven,null);

 update public.nplus_aviator_demo_rounds
 set flight_starts_at=clock_timestamp()-interval '20 seconds',
     crashes_at=clock_timestamp()+interval '20 seconds',
     crash_point=3.00,
     status='flying'
 where id=multiplier_round_id;

 loss_result:=public.nplus_aviator_demo_cashout((multiplier_manual_bet->>'bet_id')::uuid);
 if loss_result->>'status'<>'lost' then
   raise exception 'Manual cash-out after multiplier crossed crash point must lose.';
 end if;

 select * into multiplier_row
 from public.nplus_aviator_demo_bets
 where user_id=u and request_id=request_six;
 if multiplier_row.status<>'cashed_out' or multiplier_row.cashout_multiplier<>2.00 or multiplier_row.payout<>4.00 then
   raise exception 'Multiplier-crossing crash finalization did not settle auto cash-out once at 2x.';
 end if;

 select balance into balance_after from public.demo_wallets where user_id=u;
 if balance_after<>round(103.00+payout_one,2) then
   raise exception 'Multiplier-crossing auto cash-out expected balance %; got %.',round(103.00+payout_one,2),balance_after;
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
