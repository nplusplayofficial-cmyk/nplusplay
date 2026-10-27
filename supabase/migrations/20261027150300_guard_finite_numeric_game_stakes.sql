-- Split finite-numeric RPC hardening migration.
-- Candidate logic was tested in isolated PostgreSQL and the full local replay.
-- No wallet balances or user rows are rewritten; only RPC function bodies are replaced.
BEGIN;

CREATE OR REPLACE FUNCTION public.nplus_aviator_demo_place_bet(p_round_id uuid, p_slot integer, p_stake numeric, p_request_id uuid, p_auto_cashout numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
 if p_stake is null or p_stake::text IN ('NaN','Infinity','-Infinity') or p_stake<1 or p_stake>100000 or p_stake<>round(p_stake,2) then
   raise exception 'Demo stake must be between 1 and 100000 credits.';
 end if;
 if p_auto_cashout is not null and (p_auto_cashout::text IN ('NaN','Infinity','-Infinity') or p_auto_cashout<1.01 or p_auto_cashout>1000) then
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

CREATE OR REPLACE FUNCTION public.nplus_moto_demo_place_bet(p_selection jsonb, p_stake numeric, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
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
 if p_stake is null or p_stake::text IN ('NaN','Infinity','-Infinity') or p_stake<1 or p_stake>100000 or p_stake<>round(p_stake,2) then raise exception 'Demo stake must be between 1 and 100000 credits.'; end if;
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

CREATE OR REPLACE FUNCTION public.nplus_wingo_demo_place_bet(p_duration_seconds integer, p_selection jsonb, p_stake numeric, p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := clock_timestamp();
  v_epoch numeric;
  v_index bigint;
  v_start timestamptz;
  v_end timestamptz;
  v_round public.nplus_wingo_demo_rounds%rowtype;
  v_bet public.nplus_wingo_demo_bets%rowtype;
  v_inserted_id uuid;
  v_stake numeric(12,2);
  v_unit_amount numeric(12,2);
  v_balance_before numeric(12,2);
  v_balance_after numeric(12,2);
  v_type text;
  v_value text;
  v_qty integer;
  v_multi integer;
  v_code text;
  v_period text;
begin
  if v_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if p_duration_seconds not in (30, 60, 180, 300) then
    raise exception 'Unsupported WINGO duration.';
  end if;
  if p_request_id is null then
    raise exception 'Request id is required.';
  end if;
  if p_selection is null or jsonb_typeof(p_selection) <> 'object' then
    raise exception 'Invalid selection.';
  end if;

  v_type := lower(coalesce(p_selection->>'type', ''));
  v_value := coalesce(p_selection->>'value', '');

  if v_type not in ('number', 'color', 'size') then
    raise exception 'Unsupported WINGO selection type.';
  end if;
  if v_type = 'number' and not (v_value ~ '^[0-9]$') then
    raise exception 'Number selection must be from 0 to 9.';
  elsif v_type = 'color' and upper(v_value) not in ('RED', 'GREEN', 'VIOLET') then
    raise exception 'Unsupported color selection.';
  elsif v_type = 'size' and upper(v_value) not in ('BIG', 'SMALL') then
    raise exception 'Unsupported size selection.';
  end if;

  if coalesce(p_selection->>'qty', '') <> ''
     and (p_selection->>'qty') !~ '^[0-9]{1,3}$' then
    raise exception 'WINGO quantity must be between 1 and 100.';
  end if;
  if coalesce(p_selection->>'multi', '') <> ''
     and (p_selection->>'multi') !~ '^[0-9]{1,3}$' then
    raise exception 'Unsupported WINGO multiplier.';
  end if;

  v_qty := coalesce(nullif(p_selection->>'qty', '')::integer, 1);
  v_multi := coalesce(nullif(p_selection->>'multi', '')::integer, 1);
  if v_qty not between 1 and 100 then
    raise exception 'WINGO quantity must be between 1 and 100.';
  end if;
  if v_multi not in (1,5,10,20,50,100) then
    raise exception 'Unsupported WINGO multiplier.';
  end if;

  if coalesce(p_selection->>'amount', '') <> '' then
    if (p_selection->>'amount') !~ '^[0-9]+([.][0-9]{1,2})?$' then
      raise exception 'Invalid WINGO unit amount.';
    end if;
    v_unit_amount := (p_selection->>'amount')::numeric(12,2);
    if v_unit_amount <= 0
       or round(v_unit_amount * v_qty * v_multi, 2) <> round(p_stake, 2) then
      raise exception 'WINGO amount, quantity and multiplier do not match the total stake.';
    end if;
  end if;

  if p_stake is null or p_stake::text IN ('NaN','Infinity','-Infinity')
     or p_stake < 1 or p_stake > 100000
     or p_stake <> round(p_stake, 2) then
    raise exception 'Demo stake must be between 1 and 100000 credits.';
  end if;
  v_stake := p_stake;

  -- Resolve retries first, including those arriving after the betting cutoff.
  select * into v_bet
  from public.nplus_wingo_demo_bets
  where user_id = v_user_id and request_id = p_request_id;

  if found then
    if v_bet.selection <> p_selection or v_bet.stake <> v_stake then
      raise exception 'Request id was already used for a different bet.';
    end if;

    select balance into v_balance_after
    from public.demo_wallets
    where user_id = v_user_id;

    return jsonb_build_object(
      'bet_id', v_bet.id,
      'round_id', v_bet.round_id,
      'round_index', (select r.round_index from public.nplus_wingo_demo_rounds r where r.id = v_bet.round_id),
      'stake', v_bet.stake,
      'balance', v_balance_after,
      'status', v_bet.status,
      'duplicate_request', true
    );
  end if;

  if not exists (
    select 1 from public.game_settings
    where game_key = 'WINGO' and enabled = true
  ) then
    raise exception 'WINGO betting is disabled by admin.';
  end if;

  v_epoch := extract(epoch from v_now);
  v_index := floor(v_epoch / p_duration_seconds)::bigint;
  v_start := to_timestamp(v_index * p_duration_seconds);
  v_end := v_start + make_interval(secs => p_duration_seconds);

  if v_now >= v_end - interval '5 seconds' then
    raise exception 'Betting is closed for this round.';
  end if;

  insert into public.nplus_wingo_demo_rounds (
    duration_seconds, round_index, starts_at, ends_at, outcome
  )
  values (
    p_duration_seconds, v_index, v_start, v_end,
    public.nplus_wingo_make_outcome()
  )
  on conflict (duration_seconds, round_index) do nothing;

  select * into v_round
  from public.nplus_wingo_demo_rounds
  where duration_seconds = p_duration_seconds
    and round_index = v_index
  for update;

  if v_round.status <> 'open' or v_now >= v_round.ends_at - interval '5 seconds' then
    raise exception 'Betting is closed for this round.';
  end if;

  insert into public.nplus_wingo_demo_bets (
    round_id, user_id, request_id, selection, stake
  )
  values (
    v_round.id, v_user_id, p_request_id, p_selection, v_stake
  )
  on conflict (user_id, request_id) do nothing
  returning id into v_inserted_id;

  if v_inserted_id is null then
    select * into v_bet
    from public.nplus_wingo_demo_bets
    where user_id = v_user_id and request_id = p_request_id;

    if v_bet.round_id <> v_round.id
       or v_bet.selection <> p_selection
       or v_bet.stake <> v_stake then
      raise exception 'Request id was already used for a different bet.';
    end if;

    select balance into v_balance_after
    from public.demo_wallets
    where user_id = v_user_id;

    return jsonb_build_object(
      'bet_id', v_bet.id,
      'round_id', v_round.id,
      'round_index', v_round.round_index,
      'stake', v_bet.stake,
      'balance', v_balance_after,
      'status', v_bet.status,
      'duplicate_request', true
    );
  end if;

  select balance into v_balance_before
  from public.demo_wallets
  where user_id = v_user_id
  for update;

  if not found then
    raise exception 'Wallet not found.';
  end if;
  if v_balance_before < v_stake then
    raise exception 'Insufficient virtual balance.';
  end if;

  v_balance_after := v_balance_before - v_stake;
  update public.demo_wallets
  set balance = v_balance_after,
      updated_at = clock_timestamp()
  where user_id = v_user_id;

  -- Preserve the existing N+ ADMIN WINGO round-report ledger format.
  v_code := case p_duration_seconds
    when 30 then '1000'
    when 60 then '2000'
    when 180 then '3000'
    when 300 then '4000'
  end;
  v_period :=
    to_char(v_round.starts_at at time zone 'Asia/Kolkata', 'YYYYMMDD')
    || v_code
    || lpad(mod(v_round.round_index, 100000)::text, 5, '0');

  insert into public.demo_wallet_transactions (
    user_id, delta, balance_before, balance_after, type, source, note
  )
  values (
    v_user_id, -v_stake, v_balance_before, v_balance_after,
    'GAME_BET', 'WINGO',
    format(
      'WINGO BET %s type=%s value=%s qty=%s multi=%s bet_id=%s',
      v_period, v_type, v_value, v_qty, v_multi, v_inserted_id
    )
  );

  return jsonb_build_object(
    'bet_id', v_inserted_id,
    'round_id', v_round.id,
    'round_index', v_round.round_index,
    'stake', v_stake,
    'balance', v_balance_after,
    'status', 'pending',
    'duplicate_request', false
  );
end;
$function$;

COMMIT;
