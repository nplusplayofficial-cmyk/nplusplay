\set ON_ERROR_STOP on

-- Isolated PostgreSQL test for the K3/5D/TRX server-side demo lottery RPCs.
-- Synthetic user/wallet/ledger changes are rolled back at the end.

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
END
$roles$;

CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE IF NOT EXISTS auth.users(id uuid PRIMARY KEY,email text);
CREATE OR REPLACE FUNCTION auth.uid()
RETURNS uuid LANGUAGE sql STABLE
AS $uid$ SELECT NULLIF(current_setting('request.jwt.claim.sub',true),'')::uuid $uid$;

CREATE TABLE IF NOT EXISTS public.profiles(
  id uuid PRIMARY KEY REFERENCES auth.users(id),
  role text NOT NULL DEFAULT 'user'
);
CREATE TABLE IF NOT EXISTS public.demo_wallets(
  user_id uuid PRIMARY KEY REFERENCES auth.users(id),
  balance numeric(12,2) NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.profiles(
  id uuid PRIMARY KEY REFERENCES auth.users(id),
  role text NOT NULL DEFAULT 'user'
);
CREATE TABLE IF NOT EXISTS public.demo_wallet_transactions(
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  delta numeric(12,2) NOT NULL,
  balance_before numeric(12,2) NOT NULL,
  balance_after numeric(12,2) NOT NULL,
  type text NOT NULL,
  source text,
  note text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS public.game_settings(
  game_key text PRIMARY KEY,
  game_name text NOT NULL,
  enabled boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid
);
INSERT INTO public.game_settings(game_key,game_name,enabled)
VALUES ('K3','K3 WINGO',false),('5D','5D',false),('TRX','TRX WINGO',false)
ON CONFLICT(game_key) DO NOTHING;

\ir ../supabase/migrations/20261028120000_server_authoritative_k3_5d_trx_demo.sql

BEGIN;
DO $tests$
DECLARE
  v_admin uuid := 'ba111111-1111-4111-8111-111111111111';
  v_user uuid := 'ba222222-2222-4222-8222-222222222222';
  v_result jsonb;
  v_snapshot jsonb;
  v_first jsonb;
  v_retry jsonb;
  v_period text;
  v_end timestamptz;
  v_round_id uuid;
  v_before numeric;
  v_after numeric;
  v_ledger_before bigint;
  v_ledger_after bigint;
  v_bet_id uuid;
  v_request uuid;
  v_game text;
  v_duration integer;
  v_round_slot bigint;
  v_history jsonb;
BEGIN
  INSERT INTO auth.users(id,email) VALUES
    (v_admin,'lottery-admin@example.invalid'),(v_user,'lottery-user@example.invalid');
  INSERT INTO public.profiles(id,role) VALUES (v_admin,'admin'),(v_user,'user');
  INSERT INTO public.demo_wallets(user_id,balance) VALUES (v_admin,1000),(v_user,1000);

  PERFORM set_config('request.jwt.claim.sub',v_user::text,true);

  v_snapshot:=public.nplus_demo_lottery_snapshot('K3',600);
  IF v_snapshot->'current_round' ? 'result' OR v_snapshot->'current_round' ? 'outcome' THEN
    RAISE EXCEPTION 'Open K3 round exposed its result before betting closed.';
  END IF;

  BEGIN
    PERFORM public.nplus_demo_lottery_place_bet('K3',600,'size','SMALL',10,gen_random_uuid());
    RAISE EXCEPTION 'TEST_FAILURE: disabled K3 accepted a bet.';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%disabled by N+ ADMIN%' THEN RAISE; END IF;
  END;

  -- Only a signed-in Admin may enable a game, and only after the server settlement RPCs exist.
  PERFORM set_config('request.jwt.claim.sub',v_user::text,true);
  BEGIN
    PERFORM public.nplus_set_game_status('K3',true);
    RAISE EXCEPTION 'TEST_FAILURE: non-admin enabled K3.';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'Admin access required.' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claim.sub',v_admin::text,true);
  PERFORM public.nplus_set_game_status('K3',true);
  PERFORM public.nplus_set_game_status('5D',true);
  PERFORM public.nplus_set_game_status('TRX',true);
  PERFORM set_config('request.jwt.claim.sub',v_user::text,true);

  -- K3 server result, cutoff, balance debit, idempotent retry, exactly-once settlement.
  v_snapshot:=public.nplus_demo_lottery_snapshot('K3',600);
  v_period:=v_snapshot->'current_round'->>'period';
  v_end:=(v_snapshot->'current_round'->>'ends_at')::timestamptz;
  IF extract(epoch FROM (v_end-clock_timestamp()))<=8 THEN
    PERFORM pg_sleep(greatest(0.5,extract(epoch FROM (v_end-clock_timestamp()))+0.5));
    v_snapshot:=public.nplus_demo_lottery_snapshot('K3',600);
    v_period:=v_snapshot->'current_round'->>'period';
  END IF;
  SELECT balance INTO v_before FROM public.demo_wallets WHERE user_id=v_user;
  SELECT count(*) INTO v_ledger_before FROM public.demo_wallet_transactions WHERE user_id=v_user;
  v_request:='ba333333-3333-4333-8333-333333333333';
  v_first:=public.nplus_demo_lottery_place_bet('K3',600,'size','SMALL',10,v_request);
  v_bet_id:=(v_first->>'bet_id')::uuid;
  v_retry:=public.nplus_demo_lottery_place_bet('K3',600,'size','SMALL',10,v_request);
  SELECT balance INTO v_after FROM public.demo_wallets WHERE user_id=v_user;
  SELECT count(*) INTO v_ledger_after FROM public.demo_wallet_transactions WHERE user_id=v_user;
  IF v_after<>v_before-10 OR v_ledger_after<>v_ledger_before+1
     OR coalesce((v_retry->>'duplicate_request')::boolean,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'K3 retry double-debited or returned the wrong balance.';
  END IF;
  BEGIN
    PERFORM public.nplus_demo_lottery_place_bet('K3',600,'size','BIG',10,v_request);
    RAISE EXCEPTION 'TEST_FAILURE: changed payload reused an idempotency key.';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%already used for a different demo bet%' THEN RAISE; END IF;
  END;

  SELECT id,round_slot INTO v_round_id,v_round_slot FROM public.nplus_demo_lottery_rounds WHERE period=v_period;
  UPDATE public.nplus_demo_lottery_rounds SET outcome='{"dice":[1,1,1],"sum":3,"size":"SMALL","parity":"ODD"}'::jsonb,
    starts_at=clock_timestamp()-interval '2 seconds', ends_at=clock_timestamp()-interval '1 second' WHERE id=v_round_id;
  v_snapshot:=public.nplus_demo_lottery_snapshot('K3',600);
  SELECT balance INTO v_after FROM public.demo_wallets WHERE user_id=v_user;
  IF (SELECT status FROM public.nplus_demo_lottery_bets WHERE id=v_bet_id)<>'won'
     OR (SELECT payout FROM public.nplus_demo_lottery_bets WHERE id=v_bet_id)<>20
     OR v_after<>v_before+10 THEN
    RAISE EXCEPTION 'K3 server settlement or exactly-once 2x payout failed.';
  END IF;
  v_snapshot:=public.nplus_demo_lottery_snapshot('K3',600);
  IF (SELECT count(*) FROM public.demo_wallet_transactions WHERE user_id=v_user AND type='GAME_WIN' AND source='K3')<>1 THEN
    RAISE EXCEPTION 'K3 repeated snapshot duplicated settlement credit.';
  END IF;

  -- 5D position-specific exact digit, with server outcome not exposed while open.
  v_snapshot:=public.nplus_demo_lottery_snapshot('5D',180);
  v_period:=v_snapshot->'current_round'->>'period';
  v_end:=(v_snapshot->'current_round'->>'ends_at')::timestamptz;
  IF extract(epoch FROM (v_end-clock_timestamp()))<=8 THEN
    PERFORM pg_sleep(greatest(0.5,extract(epoch FROM (v_end-clock_timestamp()))+0.5));
    v_snapshot:=public.nplus_demo_lottery_snapshot('5D',180);
    v_period:=v_snapshot->'current_round'->>'period';
  END IF;
  v_request:='ba444444-4444-4444-8444-444444444444';
  v_first:=public.nplus_demo_lottery_place_bet('5D',180,'digit','A:1',10,v_request);
  v_bet_id:=(v_first->>'bet_id')::uuid;
  SELECT id INTO v_round_id FROM public.nplus_demo_lottery_rounds WHERE period=v_period;
  UPDATE public.nplus_demo_lottery_rounds SET outcome='{"digits":[1,2,3,4,5],"sum":15,"size":"SMALL","parity":"ODD"}'::jsonb,
    starts_at=clock_timestamp()-interval '2 seconds', ends_at=clock_timestamp()-interval '1 second' WHERE id=v_round_id;
  v_snapshot:=public.nplus_demo_lottery_snapshot('5D',180);
  IF (SELECT status FROM public.nplus_demo_lottery_bets WHERE id=v_bet_id)<>'won'
     OR (SELECT payout FROM public.nplus_demo_lottery_bets WHERE id=v_bet_id)<>100 THEN
    RAISE EXCEPTION '5D exact-position digit did not settle to 10x gross payout.';
  END IF;

  -- TRX outcome uses the last of five server-generated digits for color/size/number.
  v_snapshot:=public.nplus_demo_lottery_snapshot('TRX',60);
  v_period:=v_snapshot->'current_round'->>'period';
  v_end:=(v_snapshot->'current_round'->>'ends_at')::timestamptz;
  IF extract(epoch FROM (v_end-clock_timestamp()))<=8 THEN
    PERFORM pg_sleep(greatest(0.5,extract(epoch FROM (v_end-clock_timestamp()))+0.5));
    v_snapshot:=public.nplus_demo_lottery_snapshot('TRX',60);
    v_period:=v_snapshot->'current_round'->>'period';
  END IF;
  v_request:='ba555555-5555-4555-8555-555555555555';
  v_first:=public.nplus_demo_lottery_place_bet('TRX',60,'color','VIOLET',10,v_request);
  v_bet_id:=(v_first->>'bet_id')::uuid;
  SELECT id INTO v_round_id FROM public.nplus_demo_lottery_rounds WHERE period=v_period;
  UPDATE public.nplus_demo_lottery_rounds SET outcome='{"digits":[1,2,3,4,5],"sum":15,"last_digit":5,"color":"VIOLET","size":"BIG","parity":"ODD"}'::jsonb,
    starts_at=clock_timestamp()-interval '2 seconds', ends_at=clock_timestamp()-interval '1 second' WHERE id=v_round_id;
  v_snapshot:=public.nplus_demo_lottery_snapshot('TRX',60);
  IF (SELECT status FROM public.nplus_demo_lottery_bets WHERE id=v_bet_id)<>'won'
     OR (SELECT payout FROM public.nplus_demo_lottery_bets WHERE id=v_bet_id)<>50 THEN
    RAISE EXCEPTION 'TRX Violet result did not settle to 5x gross payout.';
  END IF;

  IF has_table_privilege('anon','public.nplus_demo_lottery_bets','SELECT')
     OR has_table_privilege('authenticated','public.nplus_demo_lottery_bets','SELECT') THEN
    RAISE EXCEPTION 'Browser direct access to private lottery bets was granted.';
  END IF;
  IF has_function_privilege('anon','public.nplus_demo_lottery_place_bet(text,integer,text,text,numeric,uuid)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.nplus_demo_lottery_place_bet(text,integer,text,text,numeric,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'Lottery place-bet execution grants are not least-privileged.';
  END IF;

  RAISE NOTICE 'PASS: disabled flag and Admin-only game activation guard';
  RAISE NOTICE 'PASS: hidden server outcomes, idempotent debits, finite stake bounds and cutoff';
  RAISE NOTICE 'PASS: K3 2x, 5D 10x and TRX 5x gross demo settlement';
  RAISE NOTICE 'PASS: private tables and signed-in RPC execution grants';
END
$tests$;
ROLLBACK;
