-- Candidate migration: guard finite numeric inputs before rounding, casts, or range comparisons.
-- Function bodies were fetched from the live PostgreSQL catalog read-only on 2026-10-27.
-- Only validation conditions and validation-before-narrowing order were changed.
-- Existing roles, fixed search_path, amount ranges, wallet locks, idempotency, and
-- settlement/ledger business logic are retained. Candidate only; production rollout remains gated.

BEGIN;

CREATE OR REPLACE FUNCTION public.nplus_create_demo_deposit_request(p_amount numeric, p_request_token uuid, p_request_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_user_id uuid:=auth.uid(); v_amount numeric(12,2); v_id uuid; v_existing_amount numeric; v_status text; v_note text:=left(trim(coalesce(p_request_note,'')),180);
BEGIN
 IF v_user_id IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
 IF p_request_token IS NULL THEN RAISE EXCEPTION 'Request token is required.'; END IF;
 IF p_amount IS NULL OR p_amount::text IN ('NaN','Infinity','-Infinity') THEN RAISE EXCEPTION 'Demo deposit amount must be finite.'; END IF;
 v_amount:=round(p_amount,2);
 IF v_amount<100 OR v_amount>50000 THEN RAISE EXCEPTION 'Demo deposit amount must be between 100 and 50000 credits.'; END IF;
 INSERT INTO public.deposit_requests(user_id,amount,status,created_at,request_token,payment_method,request_note)
 VALUES(v_user_id,v_amount,'pending',clock_timestamp(),p_request_token,'DEMO_CREDIT',nullif(v_note,''))
 ON CONFLICT(user_id,request_token) WHERE request_token IS NOT NULL DO NOTHING RETURNING id INTO v_id;
 IF v_id IS NULL THEN
  SELECT id,amount,status INTO v_id,v_existing_amount,v_status FROM public.deposit_requests WHERE user_id=v_user_id AND request_token=p_request_token;
  IF NOT FOUND THEN RAISE EXCEPTION 'Could not recover the existing request.'; END IF;
  IF round(v_existing_amount,2)<>v_amount THEN RAISE EXCEPTION 'Request token was already used with a different amount.'; END IF;
  RETURN jsonb_build_object('success',true,'request_id',v_id,'amount',v_amount,'status',v_status,'duplicate_request',true,'wallet_changed',false,'message','Demo request recovered; no credits were added.');
 END IF;
 RETURN jsonb_build_object('success',true,'request_id',v_id,'amount',v_amount,'status','pending','duplicate_request',false,'wallet_changed',false,'message','Demo request submitted for review; no credits were added.');
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_create_demo_withdrawal_request(p_amount numeric, p_request_token uuid, p_request_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_user_id uuid:=auth.uid(); v_amount numeric(12,2); v_balance numeric; v_id uuid; v_existing_amount numeric; v_status text; v_note text:=left(trim(coalesce(p_request_note,'')),180);
BEGIN
 IF v_user_id IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
 IF p_request_token IS NULL THEN RAISE EXCEPTION 'Request token is required.'; END IF;
 IF p_amount IS NULL OR p_amount::text IN ('NaN','Infinity','-Infinity') THEN RAISE EXCEPTION 'Demo withdrawal request amount must be finite.'; END IF;
 v_amount:=round(p_amount,2);
 IF v_amount<=0 OR v_amount>100000 THEN RAISE EXCEPTION 'Invalid demo request amount.'; END IF;
 SELECT balance INTO v_balance FROM public.demo_wallets WHERE user_id=v_user_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Demo wallet not found.'; END IF;
 IF v_amount>v_balance THEN RAISE EXCEPTION 'Request exceeds the current demo balance.'; END IF;
 INSERT INTO public.withdrawal_requests(user_id,amount,status,request_token,request_note)
 VALUES(v_user_id,v_amount,'pending',p_request_token,coalesce(nullif(v_note,''),'Demo-only request; no cash payout.'))
 ON CONFLICT DO NOTHING RETURNING id INTO v_id;
 IF v_id IS NULL THEN
  SELECT id,amount,status INTO v_id,v_existing_amount,v_status FROM public.withdrawal_requests WHERE user_id=v_user_id AND request_token=p_request_token;
  IF FOUND THEN
   IF round(v_existing_amount,2)<>v_amount THEN RAISE EXCEPTION 'Request token was already used with a different amount.'; END IF;
   RETURN jsonb_build_object('success',true,'request_id',v_id,'amount',v_amount,'status',v_status,'duplicate_request',true,'wallet_changed',false,'cash_paid',false);
  END IF;
  RAISE EXCEPTION 'A pending demo request already exists. Resolve it before creating another.';
 END IF;
 RETURN jsonb_build_object('success',true,'request_id',v_id,'amount',v_amount,'status','pending','duplicate_request',false,'wallet_changed',false,'cash_paid',false,'message','Demo-only request submitted; no credits were deducted and no cash will be paid.');
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_admin_create_gift_code(p_code text, p_amount numeric, p_max_claims integer DEFAULT 1000, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_code text := upper(trim(coalesce(p_code,'')));
  v_actor uuid := auth.uid();
BEGIN
  IF NOT coalesce(public.nplus_is_admin(),false) THEN RAISE EXCEPTION 'Administrator access required.' USING ERRCODE='42501'; END IF;
  IF v_code !~ '^[A-Z0-9_-]{4,24}$' THEN
    RETURN jsonb_build_object('success',false,'reason','invalid_code','message','Use 4–24 letters, digits, underscores, or hyphens.');
  END IF;
  IF p_amount IS NULL OR p_amount::text IN ('NaN','Infinity','-Infinity') OR p_amount <= 0 OR p_amount > 1000000 OR p_amount <> round(p_amount,2) THEN
    RETURN jsonb_build_object('success',false,'reason','invalid_amount','message','Enter a positive demo amount up to 1,000,000.');
  END IF;
  IF coalesce(p_max_claims,0) < 1 OR p_max_claims > 1000000 THEN
    RETURN jsonb_build_object('success',false,'reason','invalid_limit','message','Claim limit must be between 1 and 1,000,000.');
  END IF;
  INSERT INTO public.nplus_demo_gift_codes(code,amount,active,max_claims,expires_at,created_by)
  VALUES(v_code,p_amount,true,p_max_claims,p_expires_at,v_actor);
  RETURN jsonb_build_object('success',true,'code',v_code,'amount',p_amount,'max_claims',p_max_claims);
EXCEPTION WHEN unique_violation THEN
  RETURN jsonb_build_object('success',false,'reason','already_exists','message','That gift code already exists.');
END;
$function$;

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

CREATE OR REPLACE FUNCTION public.nplus_demo_safe_transfer(p_direction text, p_amount numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_direction text := upper(trim(coalesce(p_direction,'')));
  v_amount numeric(14,2);
  v_wallet numeric(14,2);
  v_safe numeric(14,2);
  v_before numeric(14,2);
  v_after numeric(14,2);
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  IF v_direction NOT IN ('IN','OUT') THEN RETURN jsonb_build_object('success',false,'reason','invalid_direction','message','Choose IN or OUT.'); END IF;
  IF p_amount IS NULL
     OR p_amount::text IN ('NaN','Infinity','-Infinity')
     OR p_amount > 999999999999.99
     OR p_amount <= 0
     OR p_amount <> round(p_amount,2) THEN
    RETURN jsonb_build_object('success',false,'reason','invalid_amount','message','Enter a finite positive virtual amount with at most 2 decimals.');
  END IF;
  v_amount := p_amount;

  INSERT INTO public.nplus_demo_safe_balances(user_id,balance) VALUES (v_actor,0)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT balance INTO v_wallet FROM public.demo_wallets WHERE user_id=v_actor FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Demo wallet not found.'; END IF;
  SELECT balance INTO v_safe FROM public.nplus_demo_safe_balances WHERE user_id=v_actor FOR UPDATE;

  IF v_direction='IN' THEN
    IF v_wallet < v_amount THEN RETURN jsonb_build_object('success',false,'reason','insufficient_wallet','message','Not enough virtual wallet points.'); END IF;
    UPDATE public.demo_wallets SET balance=balance-v_amount,updated_at=now() WHERE user_id=v_actor RETURNING balance INTO v_wallet;
    UPDATE public.nplus_demo_safe_balances SET balance=balance+v_amount,updated_at=now() WHERE user_id=v_actor RETURNING balance INTO v_safe;
    INSERT INTO public.demo_wallet_transactions(user_id,delta,balance_before,balance_after,type,source,note)
      VALUES(v_actor,-v_amount,v_wallet+v_amount,v_wallet,'SAFE_TRANSFER','SAFE','Moved virtual points into safe');
  ELSE
    IF v_safe < v_amount THEN RETURN jsonb_build_object('success',false,'reason','insufficient_safe','message','Not enough virtual safe points.'); END IF;
    UPDATE public.nplus_demo_safe_balances SET balance=balance-v_amount,updated_at=now() WHERE user_id=v_actor RETURNING balance INTO v_safe;
    UPDATE public.demo_wallets SET balance=balance+v_amount,updated_at=now() WHERE user_id=v_actor RETURNING balance-v_amount,balance INTO v_before,v_wallet;
    INSERT INTO public.demo_wallet_transactions(user_id,delta,balance_before,balance_after,type,source,note)
      VALUES(v_actor,v_amount,v_before,v_wallet,'SAFE_TRANSFER','SAFE','Moved virtual points out of safe');
  END IF;

  INSERT INTO public.nplus_demo_safe_transfers(user_id,direction,amount,wallet_after,safe_after)
  VALUES(v_actor,v_direction,v_amount,v_wallet,v_safe);

  RETURN jsonb_build_object('success',true,'direction',v_direction,'amount',v_amount,
    'wallet_balance',v_wallet,'safe_balance',v_safe,
    'message','Virtual demo points transferred successfully. No interest is calculated.');
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_admin_qualify_referral(p_referred_user_id uuid, p_verified_virtual_amount numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_referrer uuid;
  v_status text;
BEGIN
  IF NOT coalesce(public.nplus_is_admin(), false) THEN
    RAISE EXCEPTION 'Administrator access required.' USING ERRCODE='42501';
  END IF;
  IF p_referred_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'referral_not_found',
      'message', 'No referral record exists for that account.');
  END IF;

  IF p_verified_virtual_amount IS NULL
     OR p_verified_virtual_amount::text IN ('NaN', 'Infinity', '-Infinity') THEN
    RETURN jsonb_build_object('success', false, 'reason', 'invalid_verified_amount',
      'message', 'Verified amount must be a finite numeric value.');
  END IF;

  IF p_verified_virtual_amount < 500.00 THEN
    RETURN jsonb_build_object('success', false, 'reason', 'qualification_below_minimum',
      'message', 'Verify at least 500 virtual demo points for this invited account.');
  END IF;

  SELECT user_id, status INTO v_referrer, v_status
  FROM public.nplus_demo_referrals
  WHERE referred_user_id = p_referred_user_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'reason', 'referral_not_found',
      'message', 'No referral record exists for that account.');
  END IF;
  IF v_status = 'qualified' THEN
    RETURN jsonb_build_object('success', false, 'reason', 'already_qualified',
      'message', 'This invited account is already verified.');
  END IF;
  IF v_status <> 'pending' THEN
    RETURN jsonb_build_object('success', false, 'reason', 'invalid_status',
      'message', 'Only a pending invitation can be verified.');
  END IF;

  INSERT INTO public.nplus_demo_referral_qualifications
    (referred_user_id, referrer_user_id, qualifying_virtual_amount, verified_by, verified_at)
  VALUES (p_referred_user_id, v_referrer, p_verified_virtual_amount, v_actor, now())
  ON CONFLICT (referred_user_id) DO NOTHING;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'reason', 'already_qualified',
      'message', 'This invited account is already verified.');
  END IF;

  UPDATE public.nplus_demo_referrals
  SET status = 'qualified', reward_amount = 0, qualifying_request_id = NULL, qualified_at = now()
  WHERE referred_user_id = p_referred_user_id AND status = 'pending';

  RETURN jsonb_build_object('success', true, 'reason', 'qualified',
    'referrer_user_id', v_referrer, 'referred_user_id', p_referred_user_id,
    'verified_virtual_amount', p_verified_virtual_amount,
    'message', 'Invited account verified for the Daman-reference demo bonus tiers.');
END;
$function$;


CREATE OR REPLACE FUNCTION public.nplus_approve_deposit(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_admin_id uuid := auth.uid();
  v_role text;
  v_request public.deposit_requests%rowtype;
  v_before numeric(12,2);
  v_after numeric(12,2);
begin
  if v_admin_id is null then
    raise exception 'Authentication required.';
  end if;

  select lower(coalesce(p.role, ''))
  into v_role
  from public.profiles p
  where p.id = v_admin_id;

  if coalesce(v_role, '') <> 'admin' then
    raise exception 'Admin access required.';
  end if;

  if p_request_id is null then
    raise exception 'Deposit request ID is required.';
  end if;

  select *
  into v_request
  from public.deposit_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'Deposit request not found.';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'Request has already been reviewed.';
  end if;

  if v_request.amount is null or v_request.amount::text IN ('NaN','Infinity','-Infinity') or v_request.amount < 100 or v_request.amount > 50000 then
    raise exception 'Deposit request amount is invalid.';
  end if;

  select w.balance
  into v_before
  from public.demo_wallets w
  where w.user_id = v_request.user_id
  for update;

  if not found then
    raise exception 'User wallet not found.';
  end if;

  v_after := v_before + round(v_request.amount, 2);

  update public.demo_wallets
  set balance = v_after,
      updated_at = clock_timestamp()
  where user_id = v_request.user_id;

  insert into public.demo_wallet_transactions(
    user_id, delta, balance_before, balance_after, type, source, note
  )
  values(
    v_request.user_id,
    round(v_request.amount, 2),
    v_before,
    v_after,
    'credit',
    'admin_deposit',
    'Virtual deposit request approved by admin'
  );

  update public.deposit_requests
  set status = 'approved',
      reviewed_at = clock_timestamp(),
      reviewed_by = v_admin_id
  where id = v_request.id;

  return jsonb_build_object(
    'success', true,
    'request_id', v_request.id,
    'amount', round(v_request.amount, 2),
    'balance_before', v_before,
    'balance_after', v_after
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_gift_redeem(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_code text := upper(trim(coalesce(p_code,'')));
  v_amount numeric(12,2);
  v_max integer;
  v_count integer;
  v_expires timestamptz;
  v_before numeric(14,2);
  v_after numeric(14,2);
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  IF v_code = '' THEN RETURN jsonb_build_object('success',false,'reason','invalid_code','message','Enter a gift code.'); END IF;

  SELECT amount, max_claims, claims_count, expires_at
    INTO v_amount, v_max, v_count, v_expires
    FROM public.nplus_demo_gift_codes
   WHERE code = v_code AND active = true
   FOR UPDATE;

  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'reason','not_found','message','Gift code is invalid or inactive.'); END IF;
  IF v_amount IS NULL OR v_amount::text IN ('NaN','Infinity','-Infinity')
     OR v_amount <= 0 OR v_amount > 1000000 THEN
    RETURN jsonb_build_object('success',false,'reason','invalid_amount','message','The stored demo gift amount is invalid.');
  END IF;
  IF v_expires IS NOT NULL AND v_expires <= now() THEN
    RETURN jsonb_build_object('success',false,'reason','expired','message','This demo gift code has expired.');
  END IF;
  IF v_count >= v_max THEN RETURN jsonb_build_object('success',false,'reason','fully_claimed','message','This demo gift code has reached its claim limit.'); END IF;

  INSERT INTO public.nplus_demo_gift_claims(user_id, code, amount)
  VALUES (v_actor, v_code, v_amount)
  ON CONFLICT (user_id, code) DO NOTHING;

  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'reason','already_claimed','message','This code was already redeemed on this account.'); END IF;

  UPDATE public.nplus_demo_gift_codes SET claims_count = claims_count + 1 WHERE code = v_code;

  INSERT INTO public.demo_wallets(user_id, balance) VALUES (v_actor, 0)
  ON CONFLICT (user_id) DO NOTHING;
  UPDATE public.demo_wallets SET balance = balance + v_amount, updated_at = now()
    WHERE user_id = v_actor RETURNING balance - v_amount, balance INTO v_before, v_after;
  IF NOT FOUND THEN RAISE EXCEPTION 'Demo wallet not found.'; END IF;

  INSERT INTO public.demo_wallet_transactions(user_id,delta,balance_before,balance_after,type,source,note)
  VALUES (v_actor,v_amount,v_before,v_after,'GIFT_REWARD','GIFT',format('Demo gift code %s',v_code));

  INSERT INTO public.nplus_demo_vip_state(user_id,experience_points)
  VALUES (v_actor,v_amount::bigint)
  ON CONFLICT (user_id) DO UPDATE
    SET experience_points = public.nplus_demo_vip_state.experience_points + EXCLUDED.experience_points,
        updated_at = now();

  RETURN jsonb_build_object('success',true,'code',v_code,'amount',v_amount,
    'wallet_balance',v_after,'message',format('Added %s virtual demo points.',v_amount));
END;
$function$;

COMMIT;
