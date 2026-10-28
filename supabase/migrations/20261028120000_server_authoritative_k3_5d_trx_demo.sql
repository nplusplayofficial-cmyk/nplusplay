-- N+ PLAY server-authoritative K3, 5D, and TRX demo settlement.
-- Virtual demo credits only. No cash settlement or real-money wagering.
-- Games remain disabled until Admin explicitly enables them after verification.
BEGIN;

CREATE TABLE IF NOT EXISTS public.nplus_demo_lottery_rounds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_key text NOT NULL CHECK (game_key IN ('K3','5D','TRX')),
  duration_seconds integer NOT NULL CHECK (duration_seconds IN (60,180,300,600)),
  round_slot bigint NOT NULL,
  period text NOT NULL UNIQUE,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','settled')),
  outcome jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  settled_at timestamptz,
  UNIQUE (game_key,duration_seconds,round_slot),
  CHECK (ends_at > starts_at),
  CHECK ((status='open' AND settled_at IS NULL) OR (status='settled' AND settled_at IS NOT NULL))
);

CREATE TABLE IF NOT EXISTS public.nplus_demo_lottery_bets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  round_id uuid NOT NULL REFERENCES public.nplus_demo_lottery_rounds(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  request_id uuid NOT NULL,
  selection_type text NOT NULL,
  selection_value text NOT NULL,
  stake numeric(12,2) NOT NULL CHECK (stake >= 1 AND stake <= 10000),
  payout numeric(12,2) NOT NULL DEFAULT 0 CHECK (payout >= 0),
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','won','lost')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  settled_at timestamptz,
  UNIQUE (user_id,request_id),
  CHECK ((status='pending' AND settled_at IS NULL) OR (status IN ('won','lost') AND settled_at IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS nplus_demo_lottery_rounds_due_idx
  ON public.nplus_demo_lottery_rounds(game_key,duration_seconds,ends_at)
  WHERE status='open';
CREATE INDEX IF NOT EXISTS nplus_demo_lottery_bets_round_status_idx
  ON public.nplus_demo_lottery_bets(round_id,status);
CREATE INDEX IF NOT EXISTS nplus_demo_lottery_bets_user_created_idx
  ON public.nplus_demo_lottery_bets(user_id,created_at DESC);

ALTER TABLE public.nplus_demo_lottery_rounds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nplus_demo_lottery_bets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.nplus_demo_lottery_rounds FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.nplus_demo_lottery_bets FROM PUBLIC, anon, authenticated;

-- Outcome stays private in the rounds table. Browser roles only receive it after settlement.
CREATE OR REPLACE FUNCTION public.nplus_demo_lottery_make_outcome(p_game_key text)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  v_key text := upper(trim(coalesce(p_game_key,'')));
  v_a integer;
  v_b integer;
  v_c integer;
  v_sum integer;
  v_digits integer[];
  v_last integer;
  v_color text;
  v_size text;
  v_parity text;
BEGIN
  IF v_key='K3' THEN
    v_a := floor(random()*6)::integer + 1;
    v_b := floor(random()*6)::integer + 1;
    v_c := floor(random()*6)::integer + 1;
    v_sum := v_a+v_b+v_c;
    RETURN jsonb_build_object(
      'dice',jsonb_build_array(v_a,v_b,v_c),
      'sum',v_sum,
      'size',CASE WHEN v_sum<=10 THEN 'SMALL' ELSE 'BIG' END,
      'parity',CASE WHEN mod(v_sum,2)=0 THEN 'EVEN' ELSE 'ODD' END
    );
  ELSIF v_key='5D' THEN
    v_digits := ARRAY[
      floor(random()*10)::integer,
      floor(random()*10)::integer,
      floor(random()*10)::integer,
      floor(random()*10)::integer,
      floor(random()*10)::integer
    ];
    v_sum := v_digits[1]+v_digits[2]+v_digits[3]+v_digits[4]+v_digits[5];
    RETURN jsonb_build_object(
      'digits',to_jsonb(v_digits),
      'sum',v_sum,
      'size',CASE WHEN v_sum>=23 THEN 'BIG' ELSE 'SMALL' END,
      'parity',CASE WHEN mod(v_sum,2)=0 THEN 'EVEN' ELSE 'ODD' END
    );
  ELSIF v_key='TRX' THEN
    v_digits := ARRAY[
      floor(random()*10)::integer,
      floor(random()*10)::integer,
      floor(random()*10)::integer,
      floor(random()*10)::integer,
      floor(random()*10)::integer
    ];
    v_sum := v_digits[1]+v_digits[2]+v_digits[3]+v_digits[4]+v_digits[5];
    v_last := v_digits[5];
    v_color := CASE
      WHEN v_last IN (0,5) THEN 'VIOLET'
      WHEN v_last IN (1,3,7,9) THEN 'GREEN'
      ELSE 'RED'
    END;
    RETURN jsonb_build_object(
      'digits',to_jsonb(v_digits),
      'sum',v_sum,
      'last_digit',v_last,
      'color',v_color,
      'size',CASE WHEN v_last>=5 THEN 'BIG' ELSE 'SMALL' END,
      'parity',CASE WHEN mod(v_last,2)=0 THEN 'EVEN' ELSE 'ODD' END
    );
  END IF;
  RAISE EXCEPTION 'Unsupported demo lottery game.';
END;
$function$;

-- Gross return multipliers include the original stake and are for virtual demo points only.
-- K3 supports Big/Small and Odd/Even only: 2x gross on a win.
-- 5D supports per-position exact digit (10x) and per-position size/parity (2x).
-- TRX supports last-digit exact (10x), Green/Red (2.5x), Violet (5x), and last-digit size (2x).
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
  v_target integer;
BEGIN
  IF p_outcome IS NULL OR jsonb_typeof(p_outcome)<>'object' THEN RETURN 0; END IF;

  IF v_key='K3' THEN
    IF v_type='size' AND v_value IN ('BIG','SMALL') AND v_value=p_outcome->>'size' THEN RETURN 2; END IF;
    IF v_type='parity' AND v_value IN ('ODD','EVEN') AND v_value=p_outcome->>'parity' THEN RETURN 2; END IF;
    RETURN 0;
  ELSIF v_key='5D' THEN
    IF v_value !~ '^[A-E]:(BIG|SMALL|ODD|EVEN|[0-9])$' THEN RETURN 0; END IF;
    v_index := strpos('ABCDE',split_part(v_value,':',1));
    IF v_index NOT BETWEEN 1 AND 5 THEN RETURN 0; END IF;
    v_digits := p_outcome->'digits';
    IF jsonb_typeof(v_digits)<>'array' OR jsonb_array_length(v_digits)<>5 THEN RETURN 0; END IF;
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

-- Internal settlement helper. It is not executable directly via the REST API.
CREATE OR REPLACE FUNCTION public.nplus_demo_lottery_settle_due(
  p_game_key text,
  p_duration_seconds integer
)
RETURNS integer
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  v_key text := upper(trim(coalesce(p_game_key,'')));
  v_now timestamptz := clock_timestamp();
  v_round public.nplus_demo_lottery_rounds%rowtype;
  v_bet public.nplus_demo_lottery_bets%rowtype;
  v_multiplier numeric;
  v_payout numeric(12,2);
  v_before numeric(12,2);
  v_after numeric(12,2);
  v_count integer := 0;
BEGIN
  IF v_key NOT IN ('K3','5D','TRX') OR p_duration_seconds NOT IN (60,180,300,600) THEN
    RAISE EXCEPTION 'Unsupported demo lottery settlement request.';
  END IF;

  FOR v_round IN
    SELECT * FROM public.nplus_demo_lottery_rounds
    WHERE game_key=v_key AND duration_seconds=p_duration_seconds
      AND status='open' AND ends_at<=v_now
    ORDER BY round_slot
    LIMIT 20
    FOR UPDATE SKIP LOCKED
  LOOP
    FOR v_bet IN
      SELECT * FROM public.nplus_demo_lottery_bets
      WHERE round_id=v_round.id AND status='pending'
      ORDER BY user_id,created_at,id
      FOR UPDATE
    LOOP
      v_multiplier := public.nplus_demo_lottery_payout_multiplier(
        v_key,v_bet.selection_type,v_bet.selection_value,v_round.outcome
      );
      IF v_multiplier>0 THEN
        v_payout := round(v_bet.stake*v_multiplier,2);
        SELECT balance INTO v_before
        FROM public.demo_wallets WHERE user_id=v_bet.user_id FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Demo wallet not found while settling a lottery bet.'; END IF;
        v_after := v_before+v_payout;
        UPDATE public.demo_wallets SET balance=v_after,updated_at=clock_timestamp()
        WHERE user_id=v_bet.user_id;
        INSERT INTO public.demo_wallet_transactions(user_id,delta,balance_before,balance_after,type,source,note)
        VALUES(v_bet.user_id,v_payout,v_before,v_after,'GAME_WIN',v_key,
          format('%s server demo settlement bet_id=%s period=%s multiplier=%s',v_key,v_bet.id,v_round.period,v_multiplier));
        UPDATE public.nplus_demo_lottery_bets
        SET status='won',payout=v_payout,settled_at=clock_timestamp()
        WHERE id=v_bet.id;
      ELSE
        UPDATE public.nplus_demo_lottery_bets
        SET status='lost',payout=0,settled_at=clock_timestamp()
        WHERE id=v_bet.id;
      END IF;
    END LOOP;

    UPDATE public.nplus_demo_lottery_rounds
    SET status='settled',settled_at=clock_timestamp()
    WHERE id=v_round.id AND status='open';
    IF FOUND THEN v_count:=v_count+1; END IF;
  END LOOP;
  RETURN v_count;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_lottery_snapshot(
  p_game_key text,
  p_duration_seconds integer
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
  v_now timestamptz := clock_timestamp();
  v_slot bigint;
  v_start timestamptz;
  v_end timestamptz;
  v_period text;
  v_round public.nplus_demo_lottery_rounds%rowtype;
  v_enabled boolean := false;
  v_history jsonb := '[]'::jsonb;
  v_bets jsonb := '[]'::jsonb;
BEGIN
  IF v_user IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  IF v_key NOT IN ('K3','5D','TRX') THEN RAISE EXCEPTION 'Unsupported demo lottery game.'; END IF;
  IF p_duration_seconds NOT IN (60,180,300,600) OR (v_key='TRX' AND p_duration_seconds<>60) THEN
    RAISE EXCEPTION 'Unsupported demo lottery duration.';
  END IF;

  PERFORM public.nplus_demo_lottery_settle_due(v_key,p_duration_seconds);

  v_slot := floor(extract(epoch from v_now)/p_duration_seconds)::bigint;
  v_start := to_timestamp(v_slot*p_duration_seconds);
  v_end := v_start+make_interval(secs=>p_duration_seconds);
  v_period := to_char(v_start AT TIME ZONE 'Asia/Kolkata','YYYYMMDDHH24MI')
    || '-' || v_key || '-' || p_duration_seconds || '-' || v_slot::text;

  INSERT INTO public.nplus_demo_lottery_rounds(game_key,duration_seconds,round_slot,period,starts_at,ends_at,outcome)
  VALUES(v_key,p_duration_seconds,v_slot,v_period,v_start,v_end,public.nplus_demo_lottery_make_outcome(v_key))
  ON CONFLICT(game_key,duration_seconds,round_slot) DO NOTHING;

  SELECT * INTO v_round FROM public.nplus_demo_lottery_rounds
  WHERE game_key=v_key AND duration_seconds=p_duration_seconds AND round_slot=v_slot;

  SELECT coalesce(enabled,false) INTO v_enabled FROM public.game_settings WHERE game_key=v_key;

  SELECT coalesce(jsonb_agg(x.item ORDER BY x.round_slot DESC),'[]'::jsonb) INTO v_history
  FROM (
    SELECT r.round_slot,
      jsonb_build_object('period',r.period,'round_slot',r.round_slot,'starts_at',r.starts_at,
        'ends_at',r.ends_at,'status',r.status,'result',r.outcome,'settled_at',r.settled_at) AS item
    FROM public.nplus_demo_lottery_rounds r
    WHERE r.game_key=v_key AND r.duration_seconds=p_duration_seconds AND r.status='settled'
    ORDER BY r.round_slot DESC LIMIT 30
  ) x;

  SELECT coalesce(jsonb_agg(x.item ORDER BY x.created_at DESC),'[]'::jsonb) INTO v_bets
  FROM (
    SELECT b.created_at,
      jsonb_build_object('bet_id',b.id,'period',r.period,'round_status',r.status,
        'selection_type',b.selection_type,'selection_value',b.selection_value,
        'stake',b.stake,'payout',b.payout,'status',b.status,'created_at',b.created_at,'settled_at',b.settled_at) AS item
    FROM public.nplus_demo_lottery_bets b
    JOIN public.nplus_demo_lottery_rounds r ON r.id=b.round_id
    WHERE b.user_id=v_user AND r.game_key=v_key AND r.duration_seconds=p_duration_seconds
    ORDER BY b.created_at DESC LIMIT 50
  ) x;

  RETURN jsonb_build_object(
    'game_key',v_key,'duration_seconds',p_duration_seconds,
    'current_round',jsonb_build_object('period',v_round.period,'round_slot',v_round.round_slot,
      'starts_at',v_round.starts_at,'ends_at',v_round.ends_at,'status',v_round.status,
      'betting_enabled',v_enabled,'server_time',v_now),
    'history',v_history,'my_bets',v_bets
  );
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
    IF NOT ((v_type='size' AND v_value IN ('BIG','SMALL')) OR (v_type='parity' AND v_value IN ('ODD','EVEN'))) THEN
      RAISE EXCEPTION 'K3 demo rules support only Big/Small and Odd/Even selections.';
    END IF;
  ELSIF v_key='5D' THEN
    IF v_type='digit' AND v_value ~ '^[A-E]:[0-9]$' THEN NULL;
    ELSIF v_type='size' AND v_value ~ '^[A-E]:(BIG|SMALL)$' THEN NULL;
    ELSIF v_type='parity' AND v_value ~ '^[A-E]:(ODD|EVEN)$' THEN NULL;
    ELSE RAISE EXCEPTION '5D demo selection is invalid; use a digit, size or parity for position A-E.';
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

-- Keep the existing Admin/role/worker checks and unlock K3/5D/TRX only after these RPCs exist.
CREATE OR REPLACE FUNCTION public.nplus_set_game_status(p_game_key text, p_enabled boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  v_user_id uuid := auth.uid();
  v_role text;
  v_key text := upper(trim(coalesce(p_game_key, '')));
  v_name text;
  v_worker_scheduled boolean := false;
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  SELECT lower(coalesce(p.role, '')) INTO v_role FROM public.profiles AS p WHERE p.id = v_user_id;
  IF coalesce(v_role, '') <> 'admin' THEN RAISE EXCEPTION 'Admin access required.'; END IF;
  IF p_enabled IS NULL THEN RAISE EXCEPTION 'Enabled status must be true or false.'; END IF;
  IF v_key NOT IN ('WINGO','K3','5D','TRX','AVIATOR','MOTO') THEN RAISE EXCEPTION 'Invalid game.'; END IF;

  IF p_enabled AND v_key IN ('K3','5D','TRX') AND (
    to_regclass('public.nplus_demo_lottery_rounds') IS NULL
    OR to_regprocedure('public.nplus_demo_lottery_snapshot(text,integer)') IS NULL
    OR to_regprocedure('public.nplus_demo_lottery_place_bet(text,integer,text,text,numeric,uuid)') IS NULL
  ) THEN
    RAISE EXCEPTION 'Server-authoritative demo settlement is not installed.';
  END IF;

  IF p_enabled AND v_key = 'WINGO' AND (
    to_regclass('public.nplus_wingo_demo_rounds') IS NULL
    OR to_regprocedure('public.nplus_wingo_demo_current_round(integer)') IS NULL
    OR to_regprocedure('public.nplus_wingo_demo_place_bet(integer,jsonb,numeric,uuid)') IS NULL
    OR to_regprocedure('public.nplus_wingo_demo_settle_round(integer,bigint)') IS NULL
  ) THEN RAISE EXCEPTION 'WINGO server settlement is not installed.'; END IF;

  IF p_enabled AND v_key = 'MOTO' AND (
    to_regclass('public.nplus_moto_demo_rounds') IS NULL
    OR to_regprocedure('public.nplus_moto_demo_current_round()') IS NULL
    OR to_regprocedure('public.nplus_moto_demo_place_bet(jsonb,numeric,uuid)') IS NULL
    OR to_regprocedure('public.nplus_moto_demo_settle_round(bigint)') IS NULL
  ) THEN RAISE EXCEPTION 'MotoRace server settlement is not installed.'; END IF;

  IF p_enabled AND v_key = 'AVIATOR' AND (
    to_regclass('public.nplus_aviator_demo_rounds') IS NULL
    OR to_regclass('public.nplus_aviator_worker_health') IS NULL
    OR to_regprocedure('public.nplus_aviator_demo_current_round()') IS NULL
    OR to_regprocedure('public.nplus_aviator_demo_place_bet(uuid,integer,numeric,uuid,numeric)') IS NULL
    OR to_regprocedure('public.nplus_aviator_demo_worker_tick()') IS NULL
  ) THEN RAISE EXCEPTION 'Aviator server settlement is not installed.'; END IF;

  IF p_enabled AND v_key='AVIATOR' THEN
    IF to_regclass('cron.job') IS NULL THEN RAISE EXCEPTION 'Aviator scheduler is not installed.'; END IF;
    EXECUTE 'SELECT EXISTS (SELECT 1 FROM cron.job WHERE jobname=$1 AND database=current_database() AND active)'
      INTO v_worker_scheduled USING 'nplus-aviator-worker';
    IF NOT v_worker_scheduled THEN RAISE EXCEPTION 'Aviator scheduler is not active.'; END IF;
  END IF;

  UPDATE public.game_settings SET enabled=p_enabled,updated_at=clock_timestamp(),updated_by=v_user_id
  WHERE game_key=v_key RETURNING game_name INTO v_name;
  IF NOT FOUND THEN RAISE EXCEPTION 'Game setting not found.'; END IF;
  RETURN jsonb_build_object('game_key',v_key,'game_name',v_name,'enabled',p_enabled,'updated_by',v_user_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.nplus_demo_lottery_make_outcome(text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.nplus_demo_lottery_payout_multiplier(text,text,text,jsonb) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.nplus_demo_lottery_settle_due(text,integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.nplus_demo_lottery_snapshot(text,integer) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.nplus_demo_lottery_place_bet(text,integer,text,text,numeric,uuid) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.nplus_set_game_status(text,boolean) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.nplus_demo_lottery_snapshot(text,integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_lottery_place_bet(text,integer,text,text,numeric,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_set_game_status(text,boolean) TO authenticated;

COMMIT;
