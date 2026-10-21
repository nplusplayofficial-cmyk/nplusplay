-- DRAFT: Aviator worker recovery. Review and test before deployment.
-- This file does NOT install pg_cron or schedule a job.
-- Apply only after the existing Aviator schema and RPCs are available.

begin;

create table if not exists public.nplus_aviator_worker_health (
  singleton_key boolean primary key default true check (singleton_key),
  last_started_at timestamptz,
  last_success_at timestamptz,
  last_error_at timestamptz,
  consecutive_failures integer not null default 0
    check (consecutive_failures >= 0),
  last_round_id uuid,
  last_error text,
  updated_at timestamptz not null default clock_timestamp()
);

insert into public.nplus_aviator_worker_health(singleton_key)
values (true)
on conflict (singleton_key) do nothing;

alter table public.nplus_aviator_worker_health enable row level security;
revoke all on table public.nplus_aviator_worker_health
  from public, anon, authenticated;

create or replace function public.nplus_aviator_demo_advance_round_internal()
returns jsonb
language plpgsql volatile security definer
set search_path=pg_catalog,public
as $function$
declare

 v_now timestamptz:=clock_timestamp();
 v_round public.nplus_aviator_demo_rounds%rowtype;
 v_cp numeric(8,2);
 v_flight_seconds double precision;
 v_mult numeric(8,2);
 v_elapsed double precision;
 v_phase text;
 v_bet public.nplus_aviator_demo_bets%rowtype;
 v_before numeric(12,2);
 v_after numeric(12,2);
 v_payout numeric(12,2);
begin


 -- All clients resolve the same active round, including around first-load races.
 perform pg_advisory_xact_lock(74190311);
 select * into v_round
 from public.nplus_aviator_demo_rounds
 order by round_index desc
 limit 1
 for update;

 if found then
   -- Server-side auto cash-out is authoritative. Client polling only triggers this check;
   -- the credited multiplier is the stored target, never the client multiplier.
   if v_now>=v_round.flight_starts_at and v_now<v_round.crashes_at
      and v_round.status<>'crashed' then
     v_elapsed:=extract(epoch from (v_now-v_round.flight_starts_at));
     v_mult:=round((1.0+0.12*v_elapsed+0.019*v_elapsed*v_elapsed)::numeric,2);
     for v_bet in
       select * from public.nplus_aviator_demo_bets
       where round_id=v_round.id and status='open'
         and auto_cashout is not null and auto_cashout<=v_mult and auto_cashout<v_round.crash_point
       order by user_id,id
       for update
     loop
       select balance into v_before from public.demo_wallets
       where user_id=v_bet.user_id for update;
       if not found then raise exception 'Wallet missing during Aviator auto cash-out.'; end if;
       v_payout:=round(v_bet.stake*v_bet.auto_cashout,2);
       v_after:=v_before+v_payout;
       update public.demo_wallets set balance=v_after,updated_at=clock_timestamp()
       where user_id=v_bet.user_id;
       insert into public.demo_wallet_transactions(user_id,delta,balance_before,balance_after,type,source,note)
       values(v_bet.user_id,v_payout,v_before,v_after,'GAME_WIN','AVIATOR',
         format('Aviator server auto cash-out bet %s at %sx',v_bet.id,v_bet.auto_cashout));
       update public.nplus_aviator_demo_bets
       set status='cashed_out',cashout_multiplier=v_bet.auto_cashout,payout=v_payout,settled_at=clock_timestamp()
       where id=v_bet.id;
     end loop;
   end if;

   if v_now>=v_round.crashes_at and v_round.status<>'crashed' then
     -- Late polling must not lose a server-qualified auto cash-out that was
     -- below the crash point. Targets equal to or above the crash point never pay.
     for v_bet in
       select * from public.nplus_aviator_demo_bets
       where round_id=v_round.id and status='open'
         and auto_cashout is not null
         and auto_cashout<v_round.crash_point
       order by user_id,id
       for update
     loop
       select balance into v_before from public.demo_wallets
       where user_id=v_bet.user_id for update;
       if not found then raise exception 'Wallet missing during late Aviator auto cash-out.'; end if;
       v_payout:=round(v_bet.stake*v_bet.auto_cashout,2);
       v_after:=v_before+v_payout;
       update public.demo_wallets set balance=v_after,updated_at=clock_timestamp()
       where user_id=v_bet.user_id;
       insert into public.demo_wallet_transactions(user_id,delta,balance_before,balance_after,type,source,note)
       values(v_bet.user_id,v_payout,v_before,v_after,'GAME_WIN','AVIATOR',
         format('Aviator late server auto cash-out bet %s at %sx before crash',v_bet.id,v_bet.auto_cashout));
       update public.nplus_aviator_demo_bets
       set status='cashed_out',cashout_multiplier=v_bet.auto_cashout,payout=v_payout,settled_at=clock_timestamp()
       where id=v_bet.id;
     end loop;

     update public.nplus_aviator_demo_rounds
     set status='crashed',crashed_at=crashes_at
     where id=v_round.id returning * into v_round;
     update public.nplus_aviator_demo_bets
     set status='lost',payout=0,settled_at=clock_timestamp()
     where round_id=v_round.id and status='open';
   end if;

   -- Preserve the existing round for its short crash animation grace period.
   if v_now < v_round.crashes_at+interval '2.2 seconds' then
     if v_round.status='crashed' then
       v_phase:='CRASH';
       v_mult:=v_round.crash_point;
     elsif v_now<v_round.flight_starts_at then
       v_phase:='WAIT';
       v_mult:=1.00;
     else
       v_phase:='FLY';
       v_elapsed:=extract(epoch from (v_now-v_round.flight_starts_at));
       v_mult:=least(v_round.crash_point,round((1.0+0.12*v_elapsed+0.019*v_elapsed*v_elapsed)::numeric,2));
     end if;
     return jsonb_build_object(
       'round_id',v_round.id,
       'round_index',v_round.round_index,
       'phase',v_phase,
       'created_at',v_round.created_at,
       'flight_starts_at',v_round.flight_starts_at,
       'betting_enabled',coalesce((select gs.enabled from public.game_settings gs where gs.game_key='AVIATOR'),false),'server_time',v_now,
       'current_multiplier',v_mult,
       'crash_point',case when v_phase='CRASH' then v_round.crash_point else null end,
       'wait_seconds',greatest(0,extract(epoch from (v_round.flight_starts_at-v_now)))
     );
   end if;
 end if;

 v_now:=clock_timestamp();
 v_cp:=public.nplus_aviator_demo_make_crash_point();
 v_flight_seconds:=public.nplus_aviator_demo_flight_seconds(v_cp);
 insert into public.nplus_aviator_demo_rounds(
   flight_starts_at,crashes_at,crash_point,status
 ) values (
   v_now+interval '5 seconds',
   v_now+interval '5 seconds'+make_interval(secs=>v_flight_seconds),
   v_cp,
   'waiting'
 ) returning * into v_round;

 return jsonb_build_object(
   'round_id',v_round.id,
   'round_index',v_round.round_index,
   'phase','WAIT',
   'created_at',v_round.created_at,
   'flight_starts_at',v_round.flight_starts_at,
   'betting_enabled',coalesce((select gs.enabled from public.game_settings gs where gs.game_key='AVIATOR'),false),'server_time',v_now,
   'current_multiplier',1.00,
   'crash_point',null,
   'wait_seconds',5.0
 );
end;
$function$;

create or replace function public.nplus_aviator_demo_current_round()
returns jsonb
language plpgsql volatile security definer
set search_path=pg_catalog,public
as $function$
declare
  v_user uuid := auth.uid();
  v_now timestamptz := clock_timestamp();
  v_round public.nplus_aviator_demo_rounds%rowtype;
  v_elapsed double precision;
  v_mult numeric(8,2);
  v_phase text;
begin
  if v_user is null then
    raise exception 'Authentication required.';
  end if;

  select *
    into v_round
  from public.nplus_aviator_demo_rounds
  order by round_index desc
  limit 1;

  if not found then
    raise exception 'Aviator round is not initialized by the server worker.';
  end if;

  if v_round.status = 'crashed' then
    v_phase := 'CRASH';
    v_mult := v_round.crash_point;
  elsif v_now < v_round.flight_starts_at then
    v_phase := 'WAIT';
    v_mult := 1.00;
  else
    v_elapsed := extract(epoch from (v_now - v_round.flight_starts_at));
    v_mult := round(
      (1.0 + 0.12 * v_elapsed + 0.019 * v_elapsed * v_elapsed)::numeric,
      2
    );

    if v_now >= v_round.crashes_at or v_mult >= v_round.crash_point then
      v_phase := 'CRASH';
      v_mult := v_round.crash_point;
    else
      v_phase := 'FLY';
      v_mult := least(v_round.crash_point, v_mult);
    end if;
  end if;

  return jsonb_build_object(
    'round_id', v_round.id,
    'round_index', v_round.round_index,
    'phase', v_phase,
    'created_at', v_round.created_at,
    'flight_starts_at', v_round.flight_starts_at,
    'betting_enabled',
      coalesce(
        (select gs.enabled
         from public.game_settings gs
         where gs.game_key = 'AVIATOR'),
        false
      )
      and exists (
        select 1
        from public.nplus_aviator_worker_health h
        where h.singleton_key = true
          and h.last_success_at >= v_now - interval '10 seconds'
      ),
    'server_time', v_now,
    'current_multiplier', v_mult,
    'crash_point',
      case when v_phase = 'CRASH' then v_round.crash_point else null end,
    'wait_seconds',
      greatest(0, extract(epoch from (v_round.flight_starts_at - v_now)))
  );
end;
$function$;

create or replace function public.nplus_aviator_demo_place_bet(
 p_round_id uuid,
 p_slot integer,
 p_stake numeric,
 p_request_id uuid,
 p_auto_cashout numeric default null
)
returns jsonb
language plpgsql volatile security definer
set search_path=pg_catalog,public
as $function$
declare
 v_user uuid:=auth.uid();
 v_now timestamptz:=clock_timestamp();
 v_round public.nplus_aviator_demo_rounds%rowtype;
 v_bet public.nplus_aviator_demo_bets%rowtype;
 v_inserted uuid;
 v_stake numeric(12,2);
 v_before numeric(12,2);
 v_after numeric(12,2);
begin
 if v_user is null then raise exception 'Authentication required.'; end if;
 if p_round_id is null or p_request_id is null then raise exception 'Round and request IDs are required.'; end if;
 if p_slot not in (0,1) then raise exception 'Invalid Aviator bet slot.'; end if;
 if p_stake is null or p_stake<1 or p_stake>100000 or p_stake<>round(p_stake,2) then
   raise exception 'Demo stake must be between 1 and 100000 credits.';
 end if;
 if p_auto_cashout is not null and (p_auto_cashout<1.01 or p_auto_cashout>1000) then
   raise exception 'Auto cash-out must be between 1.01x and 1000x.';
 end if;
 v_stake:=p_stake;

 select * into v_bet from public.nplus_aviator_demo_bets
 where user_id=v_user and request_id=p_request_id;
 if found then
   if v_bet.round_id<>p_round_id or v_bet.slot<>p_slot or v_bet.stake<>v_stake
      or v_bet.auto_cashout is distinct from p_auto_cashout then
     raise exception 'Request ID already used for a different Aviator bet.';
   end if;
   select balance into v_after from public.demo_wallets where user_id=v_user;
   return jsonb_build_object('bet_id',v_bet.id,'round_id',v_bet.round_id,'slot',v_bet.slot,
     'stake',v_bet.stake,'status',v_bet.status,'payout',v_bet.payout,'balance',v_after,
     'auto_cashout',v_bet.auto_cashout,'duplicate_request',true);
 end if;

 if not exists (
   select 1
   from public.nplus_aviator_worker_health h
   where h.singleton_key = true
     and h.last_success_at >= clock_timestamp() - interval '10 seconds'
 ) then
   raise exception 'Aviator betting is temporarily paused because the server worker heartbeat is stale.';
 end if;
 if not exists (select 1 from public.game_settings where game_key='AVIATOR' and enabled=true) then
   raise exception 'Aviator betting is disabled by admin.';
 end if;

 select * into v_round from public.nplus_aviator_demo_rounds
 where id=p_round_id for update;
 if not found then raise exception 'Aviator round not found.'; end if;
 if v_round.status<>'waiting' or v_now>=v_round.flight_starts_at then
   raise exception 'Betting is closed for this Aviator round.';
 end if;

 insert into public.nplus_aviator_demo_bets(round_id,user_id,request_id,slot,stake,auto_cashout)
 values(p_round_id,v_user,p_request_id,p_slot,v_stake,p_auto_cashout)
 on conflict(user_id,request_id) do nothing returning id into v_inserted;
 if v_inserted is null then
   select * into v_bet from public.nplus_aviator_demo_bets where user_id=v_user and request_id=p_request_id;
   select balance into v_after from public.demo_wallets where user_id=v_user;
   return jsonb_build_object('bet_id',v_bet.id,'round_id',v_bet.round_id,'slot',v_bet.slot,
     'stake',v_bet.stake,'status',v_bet.status,'payout',v_bet.payout,'balance',v_after,
     'auto_cashout',v_bet.auto_cashout,'duplicate_request',true);
 end if;

 select balance into v_before from public.demo_wallets where user_id=v_user for update;
 if not found then raise exception 'Wallet not found.'; end if;
 if v_before<v_stake then raise exception 'Insufficient virtual balance.'; end if;
 v_after:=v_before-v_stake;
 update public.demo_wallets set balance=v_after,updated_at=clock_timestamp() where user_id=v_user;
 insert into public.demo_wallet_transactions(user_id,delta,balance_before,balance_after,type,source,note)
 values(v_user,-v_stake,v_before,v_after,'GAME_BET','AVIATOR',
   format('Aviator server bet %s slot %s',v_inserted,p_slot+1));
 return jsonb_build_object('bet_id',v_inserted,'round_id',p_round_id,'slot',p_slot,
   'stake',v_stake,'status','open','payout',0,'balance',v_after,
   'auto_cashout',p_auto_cashout,'duplicate_request',false);
end;
$function$;

create or replace function public.nplus_aviator_demo_worker_tick()
returns jsonb
language plpgsql volatile security definer
set search_path=pg_catalog,public
as $function$
declare
  v_state jsonb;
  v_now timestamptz;
  v_error text;
begin
  insert into public.nplus_aviator_worker_health(singleton_key)
  values (true)
  on conflict (singleton_key) do nothing;

  update public.nplus_aviator_worker_health
  set last_started_at = clock_timestamp(),
      last_error = null,
      updated_at = clock_timestamp()
  where singleton_key = true;

  begin
    v_state := public.nplus_aviator_demo_advance_round_internal();
    v_now := clock_timestamp();

    update public.nplus_aviator_worker_health
    set last_success_at = v_now,
        consecutive_failures = 0,
        last_error = null,
        last_round_id = nullif(v_state->>'round_id', '')::uuid,
        updated_at = v_now
    where singleton_key = true;

    return jsonb_build_object(
      'ok', true,
      'round_id', v_state->>'round_id',
      'phase', v_state->>'phase',
      'heartbeat_at', v_now
    );
  exception when others then
    v_error := left(sqlerrm, 1000);

    update public.nplus_aviator_worker_health
    set last_error_at = clock_timestamp(),
        consecutive_failures = consecutive_failures + 1,
        last_error = v_error,
        updated_at = clock_timestamp()
    where singleton_key = true;

    return jsonb_build_object(
      'ok', false,
      'error', v_error,
      'heartbeat_at', clock_timestamp()
    );
  end;
end;
$function$;

revoke all on function public.nplus_aviator_demo_advance_round_internal()
  from public, anon, authenticated;

revoke all on function public.nplus_aviator_demo_worker_tick()
  from public, anon, authenticated;

revoke all on function public.nplus_aviator_demo_current_round()
  from public, anon, authenticated;
grant execute on function public.nplus_aviator_demo_current_round()
  to authenticated;

revoke all on function public.nplus_aviator_demo_place_bet(uuid,integer,numeric,uuid,numeric)
  from public, anon, authenticated;
grant execute on function public.nplus_aviator_demo_place_bet(uuid,integer,numeric,uuid,numeric)
  to authenticated;

commit;