-- Expand K3 and 5D server-authoritative virtual/demo selections.
-- No rows, rounds, wallets, bets, user profiles, or ledger entries are modified.
BEGIN;

-- K3 gross returns are probability-derived from 216 equally likely three-dice outcomes.
-- 5D SUM gross return is 2x for supported aggregate classes. Multipliers include stake.
CREATE OR REPLACE FUNCTION public.nplus_demo_lottery_payout_multiplier(
  p_game_key text,
  p_selection_type text,
  p_selection_value text,
  p_outcome jsonb
)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  v_key text := upper(coalesce(p_game_key,''));
  v_type text := lower(coalesce(p_selection_type,''));
  v_value text := upper(coalesce(p_selection_value,''));
  v_digits jsonb;
  v_index integer;
  v_digit integer;
  v_sum integer;
  v_target integer;
  v_a integer;
  v_b integer;
  v_c integer;
  v_ways integer[];
BEGIN
  IF p_outcome IS NULL OR jsonb_typeof(p_outcome)<>'object' THEN RETURN 0; END IF;

  IF v_key='K3' THEN
    v_digits := p_outcome->'dice';
    IF jsonb_typeof(v_digits)<>'array' OR jsonb_array_length(v_digits)<>3 THEN RETURN 0; END IF;
    v_a := (v_digits->>0)::integer;
    v_b := (v_digits->>1)::integer;
    v_c := (v_digits->>2)::integer;
    IF v_a NOT BETWEEN 1 AND 6 OR v_b NOT BETWEEN 1 AND 6 OR v_c NOT BETWEEN 1 AND 6 THEN RETURN 0; END IF;
    v_sum := v_a+v_b+v_c;

    IF v_type='size' AND v_value IN ('BIG','SMALL') THEN
      IF (v_value='SMALL' AND v_sum<=10) OR (v_value='BIG' AND v_sum>=11) THEN RETURN 2; END IF;
    ELSIF v_type='parity' AND v_value IN ('ODD','EVEN') THEN
      IF (v_value='EVEN' AND mod(v_sum,2)=0) OR (v_value='ODD' AND mod(v_sum,2)=1) THEN RETURN 2; END IF;
    ELSIF v_type='sum' AND v_value ~ '^(3|[4-9]|1[0-8])$' THEN
      v_target := v_value::integer;
      IF v_sum=v_target THEN
        v_ways := ARRAY[1,3,6,10,15,21,25,27,27,25,21,15,10,6,3,1];
        RETURN 216::numeric / v_ways[v_target-2];
      END IF;
    ELSIF v_type='single' AND v_value ~ '^[1-6]$' THEN
      v_target := v_value::integer;
      IF v_a=v_target OR v_b=v_target OR v_c=v_target THEN RETURN 216::numeric / 91; END IF;
    ELSIF v_type='double' AND (v_value='ANY' OR v_value ~ '^[1-6]$') THEN
      IF v_value='ANY' AND (v_a=v_b OR v_a=v_c OR v_b=v_c) THEN RETURN 216::numeric / 96; END IF;
      IF v_value ~ '^[1-6]$' THEN
        v_target := v_value::integer;
        IF ((CASE WHEN v_a=v_target THEN 1 ELSE 0 END)
            + (CASE WHEN v_b=v_target THEN 1 ELSE 0 END)
            + (CASE WHEN v_c=v_target THEN 1 ELSE 0 END))>=2 THEN
          RETURN 216::numeric / 16;
        END IF;
      END IF;
    ELSIF v_type='triple' AND (v_value='ANY' OR v_value ~ '^[1-6]$') THEN
      IF v_a=v_b AND v_b=v_c THEN
        IF v_value='ANY' THEN RETURN 36; END IF;
        v_target := v_value::integer;
        IF v_a=v_target THEN RETURN 216; END IF;
      END IF;
    ELSIF v_type='different' AND v_value='ALL' THEN
      IF v_a<>v_b AND v_a<>v_c AND v_b<>v_c THEN RETURN 216::numeric / 120; END IF;
    END IF;
    RETURN 0;

  ELSIF v_key='5D' THEN
    v_digits := p_outcome->'digits';
    IF jsonb_typeof(v_digits)<>'array' OR jsonb_array_length(v_digits)<>5 THEN RETURN 0; END IF;
    IF EXISTS (
      SELECT 1 FROM jsonb_array_elements_text(v_digits) d(value)
      WHERE d.value !~ '^[0-9]$'
    ) THEN RETURN 0; END IF;

    IF v_value ~ '^SUM:(BIG|SMALL)$' AND v_type='size' THEN
      IF split_part(v_value,':',2)=upper(coalesce(p_outcome->>'size','')) THEN RETURN 2; END IF;
      RETURN 0;
    ELSIF v_value ~ '^SUM:(ODD|EVEN)$' AND v_type='parity' THEN
      IF split_part(v_value,':',2)=upper(coalesce(p_outcome->>'parity','')) THEN RETURN 2; END IF;
      RETURN 0;
    END IF;

    IF v_value !~ '^[A-E]:(BIG|SMALL|ODD|EVEN|[0-9])$' THEN RETURN 0; END IF;
    v_index := strpos('ABCDE',split_part(v_value,':',1));
    IF v_index NOT BETWEEN 1 AND 5 THEN RETURN 0; END IF;
    v_digit := (v_digits->>(v_index-1))::integer;
    IF v_type='digit' THEN
      IF split_part(v_value,':',2) ~ '^[0-9]$' AND split_part(v_value,':',2)::integer=v_digit THEN RETURN 10; END IF;
    ELSIF v_type='size' THEN
      IF split_part(v_value,':',2)='BIG' AND v_digit>=5 THEN RETURN 2; END IF;
      IF split_part(v_value,':',2)='SMALL' AND v_digit<=4 THEN RETURN 2; END IF;
    ELSIF v_type='parity' THEN
      IF split_part(v_value,':',2)='EVEN' AND mod(v_digit,2)=0 THEN RETURN 2; END IF;
      IF split_part(v_value,':',2)='ODD' AND mod(v_digit,2)=1 THEN RETURN 2; END IF;
    END IF;
    RETURN 0;

  ELSIF v_key='TRX' THEN
    v_digits := p_outcome->'digits';
    IF jsonb_typeof(v_digits)<>'array' OR jsonb_array_length(v_digits)<>5 THEN RETURN 0; END IF;
    IF EXISTS (
      SELECT 1 FROM jsonb_array_elements_text(v_digits) d(value)
      WHERE d.value !~ '^[0-9]$'
    ) THEN RETURN 0; END IF;
    v_digit := (v_digits->>4)::integer;
    IF v_type='digit' THEN
      IF v_value ~ '^[0-9]$' AND v_value::integer=v_digit THEN RETURN 10; END IF;
    ELSIF v_type='color' THEN
      IF v_value='GREEN' AND v_digit IN (1,3,7,9) THEN RETURN 2.5; END IF;
      IF v_value='RED' AND v_digit IN (2,4,6,8) THEN RETURN 2.5; END IF;
      IF v_value='VIOLET' AND v_digit IN (0,5) THEN RETURN 5; END IF;
    ELSIF v_type='size' THEN
      IF v_value='BIG' AND v_digit>=5 THEN RETURN 2; END IF;
      IF v_value='SMALL' AND v_digit<=4 THEN RETURN 2; END IF;
    END IF;
  END IF;

  RETURN 0;
EXCEPTION WHEN OTHERS THEN
  RETURN 0;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_lottery_place_bet(
  p_game_key text,
  p_duration_seconds integer,
  p_selection_type text,
  p_selection_value text,
  p_stake numeric,
  p_request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_key text := upper(trim(coalesce(p_game_key,'')));
  v_type text := lower(trim(coalesce(p_selection_type,'')));
  v_value text := upper(trim(coalesce(p_selection_value,'')));
  v_now timestamptz := clock_timestamp();
  v_slot bigint;
  v_start timestamptz;
  v_end timestamptz;
  v_period text;
  v_round public.nplus_demo_lottery_rounds%rowtype;
  v_bet public.nplus_demo_lottery_bets%rowtype;
  v_balance_before numeric(12,2);
  v_balance_after numeric(12,2);
  v_updated_rows integer;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  IF v_key NOT IN ('K3','5D','TRX') THEN RAISE EXCEPTION 'Unsupported demo lottery game.'; END IF;
  IF p_request_id IS NULL THEN RAISE EXCEPTION 'Request id is required.'; END IF;
  IF p_duration_seconds NOT IN (60,180,300,600) OR (v_key='TRX' AND p_duration_seconds<>60) THEN
    RAISE EXCEPTION 'Unsupported demo lottery duration.';
  END IF;
  IF p_stake IS NULL OR p_stake::text IN ('NaN','Infinity','-Infinity')
     OR p_stake<1 OR p_stake>10000 OR p_stake<>round(p_stake,2) THEN
    RAISE EXCEPTION 'Demo stake must be finite and between 1 and 10000 credits.';
  END IF;

  IF v_key='K3' THEN
    IF (v_type='size' AND v_value IN ('BIG','SMALL'))
       OR (v_type='parity' AND v_value IN ('ODD','EVEN')) THEN NULL;
    ELSIF v_type='sum' AND v_value ~ '^(3|[4-9]|1[0-8])$' THEN NULL;
    ELSIF v_type='single' AND v_value ~ '^[1-6]$' THEN NULL;
    ELSIF v_type='double' AND (v_value='ANY' OR v_value ~ '^[1-6]$') THEN NULL;
    ELSIF v_type='triple' AND (v_value='ANY' OR v_value ~ '^[1-6]$') THEN NULL;
    ELSIF v_type='different' AND v_value='ALL' THEN NULL;
    ELSE
      RAISE EXCEPTION 'K3 demo selection is invalid; choose Big/Small, Odd/Even, total 3-18, a single number, pair, triple or all-different.';
    END IF;
  ELSIF v_key='5D' THEN
    IF v_type='digit' AND v_value ~ '^[A-E]:[0-9]$' THEN NULL;
    ELSIF v_type='size' AND v_value ~ '^(A|B|C|D|E|SUM):(BIG|SMALL)$' THEN NULL;
    ELSIF v_type='parity' AND v_value ~ '^(A|B|C|D|E|SUM):(ODD|EVEN)$' THEN NULL;
    ELSE RAISE EXCEPTION '5D demo selection is invalid; use a digit, size or parity for position A-E, or Big/Small/Odd/Even for SUM.';
    END IF;
  ELSIF v_key='TRX' THEN
    IF v_type='digit' AND v_value ~ '^[0-9]$' THEN NULL;
    ELSIF v_type='size' AND v_value IN ('BIG','SMALL') THEN NULL;
    ELSIF v_type='color' AND v_value IN ('GREEN','RED','VIOLET') THEN NULL;
    ELSE RAISE EXCEPTION 'TRX demo selection is invalid.';
    END IF;
  END IF;

  -- Serialize idempotency tokens for a caller; replays never debit the wallet twice.
  PERFORM pg_advisory_xact_lock(hashtext(v_user::text),hashtext(p_request_id::text));
  v_now:=clock_timestamp();
  SELECT * INTO v_bet FROM public.nplus_demo_lottery_bets
  WHERE user_id=v_user AND request_id=p_request_id;
  IF FOUND THEN
    IF v_bet.selection_type<>v_type OR v_bet.selection_value<>v_value OR v_bet.stake<>p_stake
       OR NOT EXISTS (
         SELECT 1 FROM public.nplus_demo_lottery_rounds existing_round
         WHERE existing_round.id=v_bet.round_id
           AND existing_round.game_key=v_key
           AND existing_round.duration_seconds=p_duration_seconds
       ) THEN
      RAISE EXCEPTION 'Request id was already used for a different demo bet.';
    END IF;
    SELECT balance INTO v_balance_after FROM public.demo_wallets WHERE user_id=v_user;
    RETURN jsonb_build_object('success',true,'duplicate_request',true,'bet_id',v_bet.id,
      'period',(SELECT period FROM public.nplus_demo_lottery_rounds WHERE id=v_bet.round_id),
      'stake',v_bet.stake,'payout',v_bet.payout,'status',v_bet.status,'balance',v_balance_after);
  END IF;

  IF NOT EXISTS(SELECT 1 FROM public.game_settings WHERE game_key=v_key AND enabled=true) THEN
    RAISE EXCEPTION 'This demo game is disabled by N+ ADMIN.';
  END IF;

  PERFORM public.nplus_demo_lottery_settle_due(v_key,p_duration_seconds);
  -- Refresh time after settling other due rounds; do not accept a bet using a stale timestamp.
  v_now:=clock_timestamp();

  v_slot:=floor(extract(epoch from v_now)/p_duration_seconds)::bigint;
  v_start:=to_timestamp(v_slot*p_duration_seconds);
  v_end:=v_start+make_interval(secs=>p_duration_seconds);
  IF v_now>=v_end-interval '5 seconds' THEN RAISE EXCEPTION 'Betting is closed for this round.'; END IF;
  v_period:=to_char(v_start AT TIME ZONE 'Asia/Kolkata','YYYYMMDDHH24MI')
    || '-' || v_key || '-' || p_duration_seconds || '-' || v_slot::text;

  INSERT INTO public.nplus_demo_lottery_rounds(game_key,duration_seconds,round_slot,period,starts_at,ends_at,outcome)
  VALUES(v_key,p_duration_seconds,v_slot,v_period,v_start,v_end,public.nplus_demo_lottery_make_outcome(v_key))
  ON CONFLICT(game_key,duration_seconds,round_slot) DO NOTHING;

  SELECT * INTO v_round FROM public.nplus_demo_lottery_rounds
  WHERE game_key=v_key AND duration_seconds=p_duration_seconds AND round_slot=v_slot
  FOR UPDATE;
  v_now:=clock_timestamp();
  IF v_round.status<>'open' OR v_now>=v_round.ends_at-interval '5 seconds' THEN
    RAISE EXCEPTION 'Betting is closed for this round.';
  END IF;

  SELECT balance INTO v_balance_before FROM public.demo_wallets WHERE user_id=v_user FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Demo wallet not found.'; END IF;
  IF v_balance_before<p_stake THEN RAISE EXCEPTION 'Insufficient virtual demo balance.'; END IF;
  v_balance_after:=v_balance_before-p_stake;
  UPDATE public.demo_wallets SET balance=v_balance_after,updated_at=clock_timestamp() WHERE user_id=v_user;

  INSERT INTO public.nplus_demo_lottery_bets(round_id,user_id,request_id,selection_type,selection_value,stake)
  VALUES(v_round.id,v_user,p_request_id,v_type,v_value,p_stake)
  RETURNING * INTO v_bet;

  INSERT INTO public.demo_wallet_transactions(user_id,delta,balance_before,balance_after,type,source,note)
  VALUES(v_user,-p_stake,v_balance_before,v_balance_after,'GAME_BET',v_key,
    format('%s BET %s type=%s value=%s bet_id=%s',v_key,v_round.period,v_type,v_value,v_bet.id));

  RETURN jsonb_build_object('success',true,'bet_id',v_bet.id,'period',v_round.period,
    'stake',v_bet.stake,'payout',0,'status',v_bet.status,'balance',v_balance_after,
    'betting_closes_at',v_round.ends_at-interval '5 seconds');
END;
$function$;

REVOKE ALL ON FUNCTION public.nplus_demo_lottery_payout_multiplier(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_lottery_payout_multiplier(text,text,text,jsonb) TO service_role;

REVOKE ALL ON FUNCTION public.nplus_demo_lottery_place_bet(text,integer,text,text,numeric,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.nplus_demo_lottery_place_bet(text,integer,text,text,numeric,uuid) TO authenticated;

COMMIT;
