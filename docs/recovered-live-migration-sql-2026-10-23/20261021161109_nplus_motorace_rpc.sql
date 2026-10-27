-- MotoRace server RPCs. Apply after NPLUS_PLAY_MOTORACE_SCHEMA.sql.
-- The current UI rules are authoritative here: 1.5% fee; winning stake returns 2x.
-- No client-selected outcome or payout amount is trusted.

begin;

create or replace function public.nplus_moto_demo_make_outcome()
returns jsonb language sql volatile security definer
set search_path=pg_catalog,public
as $function$
 select to_jsonb(array_agg(n order by random())) from generate_series(1,10) as g(n);
$function$;

create or replace function public.nplus_moto_demo_is_win(p_selection jsonb,p_outcome jsonb)
returns boolean language plpgsql immutable security definer
set search_path=pg_catalog,public
as $function$
declare k text:=lower(coalesce(p_selection->>'kind',''));
 v text:=upper(coalesce(p_selection->>'value',''));
 pos integer; n integer;
begin
 if jsonb_typeof(p_outcome)<>'array' or jsonb_typeof(p_selection)<>'object'
    or coalesce(p_selection->>'position','') !~ '^[123]$' then return false; end if;
 pos:=(p_selection->>'position')::integer;
 n:=(p_outcome->>(pos-1))::integer;
 if k='bike' then return coalesce(p_selection->>'value','') ~ '^(10|[1-9])$' and (p_selection->>'value')::integer=n;
 elsif k='oe' then return (v='ODD' and mod(n,2)=1) or (v='EVEN' and mod(n,2)=0);
 elsif k='bs' then return (v='BIG' and n>=6) or (v='SMALL' and n<=5);
 end if;
 return false;
exception when others then return false;
end;
$function$;

create or replace function public.nplus_moto_demo_current_round()
returns jsonb language plpgsql volatile security definer
set search_path=pg_catalog,public
as $function$
declare u uuid:=auth.uid(); now_at timestamptz:=clock_timestamp(); idx bigint; st timestamptz; en timestamptz; r public.nplus_moto_demo_rounds%rowtype;
begin
 if u is null then raise exception 'Authentication required.'; end if;
 idx:=floor(extract(epoch from now_at)/60)::bigint; st:=to_timestamp(idx*60); en:=st+interval '60 seconds';
 insert into public.nplus_moto_demo_rounds(round_index,starts_at,ends_at,outcome)
 values(idx,st,en,public.nplus_moto_demo_make_outcome()) on conflict(round_index) do nothing;
 select * into r from public.nplus_moto_demo_rounds where round_index=idx;
 return jsonb_build_object('round_id',r.id,'round_index',r.round_index,
  'period',to_char(r.starts_at at time zone 'Asia/Kolkata','YYYYMMDDHH24MI'),
  'starts_at',r.starts_at,'ends_at',r.ends_at,'status',r.status,'betting_enabled',coalesce((select gs.enabled from public.game_settings gs where gs.game_key='MOTO'),false),'server_time',now_at);
end;
$function$;

-- Allowed only after the last-five-seconds bet cutoff; no result is exposed earlier.
create or replace function public.nplus_moto_demo_reveal_round(p_round_index bigint)
returns jsonb language plpgsql volatile security definer
set search_path=pg_catalog,public
as $function$
declare u uuid:=auth.uid(); now_at timestamptz:=clock_timestamp(); idx bigint; r public.nplus_moto_demo_rounds%rowtype;
begin
 if u is null then raise exception 'Authentication required.'; end if;
 idx:=floor(extract(epoch from now_at)/60)::bigint;
 if p_round_index is null or p_round_index<>idx then raise exception 'Only the current MotoRace round can be revealed.'; end if;
 insert into public.nplus_moto_demo_rounds(round_index,starts_at,ends_at,outcome)
 values(idx,to_timestamp(idx*60),to_timestamp(idx*60)+interval '60 seconds',public.nplus_moto_demo_make_outcome())
 on conflict(round_index) do nothing;
 select * into r from public.nplus_moto_demo_rounds where round_index=idx;
 if now_at<r.ends_at-interval '5 seconds' then raise exception 'MotoRace result is hidden until betting closes.'; end if;
 return jsonb_build_object('round_index',r.round_index,
  'period',to_char(r.starts_at at time zone 'Asia/Kolkata','YYYYMMDDHH24MI'),
  'outcome',r.outcome,'server_time',now_at);
end;
$function$;

create or replace function public.nplus_moto_demo_place_bet(p_selection jsonb,p_stake numeric,p_request_id uuid)
returns jsonb language plpgsql volatile security definer
set search_path=pg_catalog,public
as $function$
declare u uuid:=auth.uid(); now_at timestamptz:=clock_timestamp(); idx bigint; st timestamptz; en timestamptz;
 r public.nplus_moto_demo_rounds%rowtype; b public.nplus_moto_demo_bets%rowtype; bid uuid;
 stake_amt numeric(12,2); fee_amt numeric(12,2); debit_amt numeric(12,2);
 before_amt numeric(12,2); after_amt numeric(12,2); k text; v text;
begin
 if u is null then raise exception 'Authentication required.'; end if;
 if p_request_id is null or p_selection is null or jsonb_typeof(p_selection)<>'object' then raise exception 'Request id and selection are required.'; end if;
 k:=lower(coalesce(p_selection->>'kind','')); v:=upper(coalesce(p_selection->>'value',''));
 if k not in ('bike','oe','bs') or coalesce(p_selection->>'position','') !~ '^[123]$' then raise exception 'Unsupported MotoRace selection or position.'; end if;
 if (k='bike' and not(coalesce(p_selection->>'value','') ~ '^(10|[1-9])$'))
  or (k='oe' and v not in ('ODD','EVEN')) or (k='bs' and v not in ('BIG','SMALL')) then raise exception 'Invalid MotoRace selection value.'; end if;
 if p_stake is null or p_stake<1 or p_stake>100000 or p_stake<>round(p_stake,2) then raise exception 'Demo stake must be between 1 and 100000 credits.'; end if;
 stake_amt:=p_stake; fee_amt:=round(stake_amt*0.015,2); debit_amt:=stake_amt+fee_amt;

 select * into b from public.nplus_moto_demo_bets where user_id=u and request_id=p_request_id;
 if found then
  if b.selection<>p_selection or b.stake<>stake_amt then raise exception 'Request id was already used for a different MotoRace bet.'; end if;
  select balance into after_amt from public.demo_wallets where user_id=u;
  return jsonb_build_object('bet_id',b.id,'round_id',b.round_id,
   'round_index',(select x.round_index from public.nplus_moto_demo_rounds x where x.id=b.round_id),
   'period',(select to_char(x.starts_at at time zone 'Asia/Kolkata','YYYYMMDDHH24MI') from public.nplus_moto_demo_rounds x where x.id=b.round_id),
   'stake',b.stake,'fee',b.fee,'total',b.amount_debited,'balance',after_amt,'status',b.status,'duplicate_request',true);
 end if;

 if not exists (select 1 from public.game_settings where game_key='MOTO' and enabled=true) then
  raise exception 'MotoRace betting is disabled by admin.';
 end if;

 idx:=floor(extract(epoch from now_at)/60)::bigint; st:=to_timestamp(idx*60); en:=st+interval '60 seconds';
 if now_at>=en-interval '5 seconds' then raise exception 'Betting is closed for this round.'; end if;
 insert into public.nplus_moto_demo_rounds(round_index,starts_at,ends_at,outcome)
 values(idx,st,en,public.nplus_moto_demo_make_outcome()) on conflict(round_index) do nothing;
 select * into r from public.nplus_moto_demo_rounds where round_index=idx for update;
 if r.status<>'open' or now_at>=r.ends_at-interval '5 seconds' then raise exception 'Betting is closed for this round.'; end if;

 insert into public.nplus_moto_demo_bets(round_id,user_id,request_id,selection,stake,fee,amount_debited)
 values(r.id,u,p_request_id,p_selection,stake_amt,fee_amt,debit_amt)
 on conflict(user_id,request_id) do nothing returning id into bid;
 if bid is null then
  select * into b from public.nplus_moto_demo_bets where user_id=u and request_id=p_request_id;
  if b.selection<>p_selection or b.stake<>stake_amt then raise exception 'Request id was already used for a different MotoRace bet.'; end if;
  select balance into after_amt from public.demo_wallets where user_id=u;
  return jsonb_build_object('bet_id',b.id,'round_id',b.round_id,'round_index',r.round_index,
   'period',to_char(r.starts_at at time zone 'Asia/Kolkata','YYYYMMDDHH24MI'),
   'stake',b.stake,'fee',b.fee,'total',b.amount_debited,'balance',after_amt,'status',b.status,'duplicate_request',true);
 end if;

 select balance into before_amt from public.demo_wallets where user_id=u for update;
 if not found then raise exception 'Wallet not found.'; end if;
 if before_amt<debit_amt then raise exception 'Insufficient virtual balance.'; end if;
 after_amt:=before_amt-debit_amt;
 update public.demo_wallets set balance=after_amt,updated_at=clock_timestamp() where user_id=u;
 insert into public.demo_wallet_transactions(user_id,delta,balance_before,balance_after,type,source,note)
 values(u,-debit_amt,before_amt,after_amt,'GAME_BET','MOTORACE',format('MotoRace server bet %s stake %s fee %s',bid,stake_amt,fee_amt));
 return jsonb_build_object('bet_id',bid,'round_id',r.id,'round_index',r.round_index,
  'period',to_char(r.starts_at at time zone 'Asia/Kolkata','YYYYMMDDHH24MI'),
  'stake',stake_amt,'fee',fee_amt,'total',debit_amt,'balance',after_amt,'status','pending','duplicate_request',false);
end;
$function$;

create or replace function public.nplus_moto_demo_settle_round(p_round_index bigint)
returns jsonb language plpgsql volatile security definer
set search_path=pg_catalog,public
as $function$
declare u uuid:=auth.uid(); now_at timestamptz:=clock_timestamp(); current_idx bigint; st timestamptz; en timestamptz;
 r public.nplus_moto_demo_rounds%rowtype; b public.nplus_moto_demo_bets%rowtype;
 won boolean; payout_amt numeric(12,2); before_amt numeric(12,2); after_amt numeric(12,2); mine jsonb;
begin
 if u is null then raise exception 'Authentication required.'; end if;
 current_idx:=floor(extract(epoch from now_at)/60)::bigint;
 if p_round_index is null or p_round_index>=current_idx or p_round_index<current_idx-500 then raise exception 'Round index is invalid or too old.'; end if;
 st:=to_timestamp(p_round_index*60); en:=st+interval '60 seconds';
 insert into public.nplus_moto_demo_rounds(round_index,starts_at,ends_at,outcome)
 values(p_round_index,st,en,public.nplus_moto_demo_make_outcome()) on conflict(round_index) do nothing;
 select * into r from public.nplus_moto_demo_rounds where round_index=p_round_index for update;
 if now_at<r.ends_at then raise exception 'MotoRace round has not finished yet.'; end if;

 if r.status<>'settled' then
  for b in select * from public.nplus_moto_demo_bets where round_id=r.id and status='pending' order by user_id,id for update loop
   won:=public.nplus_moto_demo_is_win(b.selection,r.outcome);
   if won then
    payout_amt:=round(b.stake*2,2);
    select balance into before_amt from public.demo_wallets where user_id=b.user_id for update;
    if not found then raise exception 'Wallet not found while settling MotoRace bet.'; end if;
    after_amt:=before_amt+payout_amt;
    update public.demo_wallets set balance=after_amt,updated_at=clock_timestamp() where user_id=b.user_id;
    insert into public.demo_wallet_transactions(user_id,delta,balance_before,balance_after,type,source,note)
    values(b.user_id,payout_amt,before_amt,after_amt,'GAME_WIN','MOTORACE',format('MotoRace server settlement %s round %s',b.id,r.round_index));
    update public.nplus_moto_demo_bets set status='won',payout=payout_amt,settled_at=clock_timestamp() where id=b.id;
   else
    update public.nplus_moto_demo_bets set status='lost',payout=0,settled_at=clock_timestamp() where id=b.id;
   end if;
  end loop;
  update public.nplus_moto_demo_rounds set status='settled',settled_at=clock_timestamp() where id=r.id returning * into r;
 end if;

 select coalesce(jsonb_agg(jsonb_build_object('bet_id',b0.id,'selection',b0.selection,'stake',b0.stake,'fee',b0.fee,
  'total',b0.amount_debited,'status',b0.status,'payout',b0.payout,'settled_at',b0.settled_at) order by b0.created_at,b0.id),'[]'::jsonb)
 into mine from public.nplus_moto_demo_bets b0 where b0.round_id=r.id and b0.user_id=u;
 return jsonb_build_object('round_id',r.id,'round_index',r.round_index,
  'period',to_char(r.starts_at at time zone 'Asia/Kolkata','YYYYMMDDHH24MI'),
  'status',r.status,'outcome',r.outcome,'bets',mine);
end;
$function$;

create or replace function public.nplus_moto_demo_my_bets(p_limit integer default 100)
returns jsonb language plpgsql stable security definer
set search_path=pg_catalog,public
as $function$
declare u uuid:=auth.uid(); rows jsonb;
begin
 if u is null then raise exception 'Authentication required.'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('bet_id',b.id,'request_id',b.request_id,'round_id',r.id,'round_index',r.round_index,
  'period',to_char(r.starts_at at time zone 'Asia/Kolkata','YYYYMMDDHH24MI'),'starts_at',r.starts_at,'ends_at',r.ends_at,
  'selection',b.selection,'stake',b.stake,'fee',b.fee,'total',b.amount_debited,'status',b.status,'payout',b.payout,'created_at',b.created_at,
  'settled_at',b.settled_at,'outcome',case when r.status='settled' then r.outcome else null end) order by b.created_at desc),'[]'::jsonb)
 into rows from (
  select b0.* from public.nplus_moto_demo_bets b0 where b0.user_id=u order by b0.created_at desc limit least(greatest(coalesce(p_limit,100),1),200)
 ) b join public.nplus_moto_demo_rounds r on r.id=b.round_id;
 return rows;
end;
$function$;

create or replace function public.nplus_moto_demo_history(p_limit integer default 100)
returns jsonb language plpgsql stable security definer
set search_path=pg_catalog,public
as $function$
declare u uuid:=auth.uid(); rows jsonb;
begin
 if u is null then raise exception 'Authentication required.'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('round_index',q.round_index,'period',q.period,'starts_at',q.starts_at,'ends_at',q.ends_at,
  'status',q.status,'outcome',q.outcome,'settled_at',q.settled_at) order by q.starts_at desc),'[]'::jsonb)
 into rows from (
  select r.*,to_char(r.starts_at at time zone 'Asia/Kolkata','YYYYMMDDHH24MI') as period
  from public.nplus_moto_demo_rounds r where r.status='settled' and r.ends_at<=clock_timestamp()
  order by r.starts_at desc limit least(greatest(coalesce(p_limit,100),1),500)
 ) q;
 return rows;
end;
$function$;

revoke all on function public.nplus_moto_demo_make_outcome() from public,anon,authenticated;
revoke all on function public.nplus_moto_demo_is_win(jsonb,jsonb) from public,anon,authenticated;
revoke all on function public.nplus_moto_demo_current_round() from public,anon,authenticated;
revoke all on function public.nplus_moto_demo_reveal_round(bigint) from public,anon,authenticated;
revoke all on function public.nplus_moto_demo_place_bet(jsonb,numeric,uuid) from public,anon,authenticated;
revoke all on function public.nplus_moto_demo_settle_round(bigint) from public,anon,authenticated;
revoke all on function public.nplus_moto_demo_my_bets(integer) from public,anon,authenticated;
revoke all on function public.nplus_moto_demo_history(integer) from public,anon,authenticated;
grant execute on function public.nplus_moto_demo_current_round() to authenticated;
grant execute on function public.nplus_moto_demo_reveal_round(bigint) to authenticated;
grant execute on function public.nplus_moto_demo_place_bet(jsonb,numeric,uuid) to authenticated;
grant execute on function public.nplus_moto_demo_settle_round(bigint) to authenticated;
grant execute on function public.nplus_moto_demo_my_bets(integer) to authenticated;
grant execute on function public.nplus_moto_demo_history(integer) to authenticated;

commit;
