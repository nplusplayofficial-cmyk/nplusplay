\set ON_ERROR_STOP on

-- Disposable PostgreSQL-only harness for the WINGO server-settlement migration.
-- This stubs the Supabase tables/functions used by the migration; it is not a
-- substitute for a live Supabase staging test.

do $bootstrap$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end
$bootstrap$;

create schema if not exists auth;
create table auth.users (
  id uuid primary key,
  email text
);

create or replace function auth.uid()
returns uuid
language sql
stable
as $function$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$function$;

create table public.demo_wallets (
  user_id uuid primary key references auth.users(id),
  balance numeric(12,2) not null,
  updated_at timestamptz not null default now()
);

create table public.demo_wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  delta numeric(12,2) not null,
  balance_before numeric(12,2) not null,
  balance_after numeric(12,2) not null,
  type text not null,
  source text,
  note text,
  created_at timestamptz not null default now()
);

create table public.wingo_manual_results (
  id uuid primary key default gen_random_uuid(),
  duration_seconds integer not null,
  period text not null,
  mode text not null,
  color text,
  number integer,
  size text,
  created_at timestamptz not null default now()
);

\ir ../sql/NPLUS_PLAY_SERVER_SETTLEMENT_FOUNDATION.sql

do $tests$
declare
  v_user uuid := '11111111-1111-4111-8111-111111111111';
  v_request uuid := '22222222-2222-4222-8222-222222222222';
  v_round jsonb;
  v_placed jsonb;
  v_repeat jsonb;
  v_changed jsonb;
  v_settled jsonb;
  v_settled_again jsonb;
  v_round_id uuid;
  v_round_index bigint;
  v_start timestamptz;
  v_end timestamptz;
  v_period text;
  v_balance numeric(12,2);
  v_before_count integer;
  v_after_count integer;
begin
  insert into auth.users(id, email) values (v_user, 'qa-user@example.invalid');
  insert into public.demo_wallets(user_id, balance) values (v_user, 108.00);
  perform set_config('request.jwt.claim.sub', v_user::text, true);

  -- Verify authentication and that the current-round RPC doesn't leak outcomes.
  v_round := public.nplus_wingo_demo_current_round(30);
  if v_round ? 'outcome' then
    raise exception 'Current round leaked its outcome before close.';
  end if;
  v_round_index := (v_round->>'round_index')::bigint;
  v_round_id := (v_round->>'round_id')::uuid;

  -- Avoid the five-second cutoff window, then place one real test bet.
  v_end := (v_round->>'ends_at')::timestamptz;
  if extract(epoch from (v_end - clock_timestamp())) <= 12 then
    perform pg_sleep(greatest(0.5, extract(epoch from (v_end - clock_timestamp())) + 0.5));
    v_round := public.nplus_wingo_demo_current_round(30);
    v_round_index := (v_round->>'round_index')::bigint;
    v_round_id := (v_round->>'round_id')::uuid;
  end if;

  v_placed := public.nplus_wingo_demo_place_bet(
    30, '{"type":"number","value":"8"}'::jsonb, 10.00, v_request
  );
  if coalesce((v_placed->>'bet_id')::text, '') = '' then
    raise exception 'Place-bet RPC did not return a bet id.';
  end if;

  select balance into v_balance from public.demo_wallets where user_id = v_user;
  if v_balance <> 98.00 then
    raise exception 'Expected 98.00 after first debit, got %.', v_balance;
  end if;

  select count(*) into v_before_count
  from public.demo_wallet_transactions
  where user_id = v_user and type = 'GAME_BET';

  -- Same request id must not debit twice.
  v_repeat := public.nplus_wingo_demo_place_bet(
    30, '{"type":"number","value":"8"}'::jsonb, 10.00, v_request
  );
  select balance into v_balance from public.demo_wallets where user_id = v_user;
  select count(*) into v_after_count
  from public.demo_wallet_transactions
  where user_id = v_user and type = 'GAME_BET';
  if v_balance <> 98.00 or v_before_count <> 1 or v_after_count <> 1
     or coalesce((v_repeat->>'duplicate_request')::boolean, false) is not true then
    raise exception 'Idempotent placement retry duplicated a debit.';
  end if;

  -- Reusing an idempotency key with different content must fail.
  begin
    perform public.nplus_wingo_demo_place_bet(
      30, '{"type":"number","value":"8"}'::jsonb, 11.00, v_request
    );
    raise exception 'Expected changed-payload retry to be rejected.';
  exception when others then
    if sqlerrm not like '%already used for a different bet%' then
      raise;
    end if;
  end;

  -- Model a completed round deterministically and use the existing admin
  -- manual-result feature, so settlement tests do not depend on RNG.
  v_round_index := floor(extract(epoch from clock_timestamp()) / 30)::bigint - 1;
  v_start := to_timestamp(v_round_index * 30);
  v_end := v_start + interval '30 seconds';
  update public.nplus_wingo_demo_rounds
     set round_index = v_round_index, starts_at = v_start, ends_at = v_end
   where id = v_round_id;

  v_period :=
    to_char(v_start at time zone 'Asia/Kolkata', 'YYYYMMDD')
    || '1000'
    || lpad(mod(v_round_index, 100000)::text, 5, '0');

  insert into public.wingo_manual_results(
    duration_seconds, period, mode, color, number, size
  ) values (30, v_period, 'MANUAL', 'RED', 8, 'BIG');

  -- A retry after the cutoff should still return the original bet, not charge again.
  v_repeat := public.nplus_wingo_demo_place_bet(
    30, '{"type":"number","value":"8"}'::jsonb, 10.00, v_request
  );
  select balance into v_balance from public.demo_wallets where user_id = v_user;
  if v_balance <> 98.00 then
    raise exception 'Late idempotent retry changed the wallet balance.';
  end if;

  v_settled := public.nplus_wingo_demo_settle_round(30, v_round_index);
  if (v_settled->'outcome'->>'number')::integer <> 8 then
    raise exception 'Manual server outcome was not used during settlement.';
  end if;
  if jsonb_array_length(v_settled->'bets') <> 1 then
    raise exception 'Settlement did not return the authenticated user bet.';
  end if;
  if v_settled->'bets'->0->>'status' <> 'won'
     or (v_settled->'bets'->0->>'payout')::numeric <> 88.20 then
    raise exception 'Server payout amount/status incorrect: %.', v_settled->'bets'->0;
  end if;

  select balance into v_balance from public.demo_wallets where user_id = v_user;
  if v_balance <> 186.20 then
    raise exception 'Expected balance 186.20 after one settlement, got %.', v_balance;
  end if;

  v_settled_again := public.nplus_wingo_demo_settle_round(30, v_round_index);
  select balance into v_balance from public.demo_wallets where user_id = v_user;
  if v_balance <> 186.20 then
    raise exception 'Repeated settlement credited the wallet twice.';
  end if;

  select count(*) into v_after_count
  from public.demo_wallet_transactions
  where user_id = v_user and type = 'GAME_WIN';
  if v_after_count <> 1 then
    raise exception 'Expected one GAME_WIN ledger entry, found %.', v_after_count;
  end if;

  -- Direct browser reads must remain blocked; RPCs are only for signed-in users.
  if has_table_privilege('anon', 'public.nplus_wingo_demo_bets', 'SELECT')
     or has_table_privilege('authenticated', 'public.nplus_wingo_demo_bets', 'SELECT') then
    raise exception 'Direct browser reads of private bet records are granted.';
  end if;
  if has_function_privilege('anon', 'public.nplus_wingo_demo_place_bet(integer,jsonb,numeric,uuid)', 'EXECUTE') then
    raise exception 'Anonymous execution of place-bet RPC is granted.';
  end if;
  if not has_function_privilege('authenticated', 'public.nplus_wingo_demo_place_bet(integer,jsonb,numeric,uuid)', 'EXECUTE') then
    raise exception 'Authenticated execution of place-bet RPC is missing.';
  end if;

  -- Public invocation without a user must fail.
  perform set_config('request.jwt.claim.sub', '', true);
  begin
    perform public.nplus_wingo_demo_current_round(30);
    raise exception 'Expected unauthenticated round request to be rejected.';
  exception when others then
    if sqlerrm <> 'Authentication required.' then
      raise;
    end if;
  end;

  raise notice 'WINGO server-settlement tests passed.';
end
$tests$;
