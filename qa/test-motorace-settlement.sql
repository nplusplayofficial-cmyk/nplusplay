\set ON_ERROR_STOP on

-- Uses the disposable database/bootstrap prepared by test-wingo-settlement.sql.
create table if not exists public.game_settings (
  game_key text primary key,
  game_name text not null,
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by uuid
);
insert into public.game_settings(game_key,game_name,enabled)
values ('MOTO','MOTO RACE',true)
on conflict (game_key) do nothing;

\ir ../sql/NPLUS_PLAY_MOTORACE_SCHEMA.sql
\ir ../sql/NPLUS_PLAY_MOTORACE_RPC.sql

do $tests$
declare
  v_user uuid := '33333333-3333-4333-8333-333333333333';
  v_request uuid := '44444444-4444-4444-8444-444444444444';
  v_round jsonb;
  v_placed jsonb;
  v_retry jsonb;
  v_settled jsonb;
  v_settled_again jsonb;
  v_bets jsonb;
  v_history jsonb;
  v_idx bigint;
  v_starts timestamptz;
  v_ends timestamptz;
  v_balance numeric(12,2);
  v_before_count integer;
  v_after_count integer;
begin
  insert into auth.users(id,email) values(v_user,'moto-qa@example.invalid');
  insert into public.demo_wallets(user_id,balance) values(v_user,108.00);
  perform set_config('request.jwt.claim.sub',v_user::text,true);

  v_round := public.nplus_moto_demo_current_round();
  if v_round ? 'outcome' then raise exception 'MotoRace current-round RPC leaked outcome before betting closed.'; end if;
  v_idx := (v_round->>'round_index')::bigint;
  v_starts := (v_round->>'starts_at')::timestamptz;
  v_ends := (v_round->>'ends_at')::timestamptz;

  -- Keep the bet safely outside the five-second cutoff.
  if extract(epoch from (v_ends-clock_timestamp())) <= 12 then
    delete from public.nplus_moto_demo_rounds r
    where r.round_index=v_idx
      and not exists(select 1 from public.nplus_moto_demo_bets b where b.round_id=r.id);
    perform pg_sleep(greatest(0.5,extract(epoch from (v_ends-clock_timestamp()))+0.5));
    v_round := public.nplus_moto_demo_current_round();
    v_idx := (v_round->>'round_index')::bigint;
    v_starts := (v_round->>'starts_at')::timestamptz;
    v_ends := (v_round->>'ends_at')::timestamptz;
  end if;

  v_placed := public.nplus_moto_demo_place_bet(
    '{"kind":"bike","value":8,"position":1,"qty":1,"multi":1}'::jsonb,
    10.00,
    v_request
  );
  if coalesce(v_placed->>'bet_id','')='' then raise exception 'MotoRace place-bet RPC returned no bet ID.'; end if;
  if (v_placed->>'fee')::numeric<>0.15 or (v_placed->>'total')::numeric<>10.15 then
    raise exception 'Expected server-computed fee/debit 0.15 / 10.15, got % / %.',v_placed->>'fee',v_placed->>'total';
  end if;

  select balance into v_balance from public.demo_wallets where user_id=v_user;
  if v_balance<>97.85 then raise exception 'Expected 97.85 after MotoRace debit, got %.',v_balance; end if;

  v_before_count := (select count(*) from public.demo_wallet_transactions where user_id=v_user and type='GAME_BET');
  v_retry := public.nplus_moto_demo_place_bet(
    '{"kind":"bike","value":8,"position":1,"qty":1,"multi":1}'::jsonb,10.00,v_request
  );
  v_after_count := (select count(*) from public.demo_wallet_transactions where user_id=v_user and type='GAME_BET');
  select balance into v_balance from public.demo_wallets where user_id=v_user;
  if v_balance<>97.85 or v_before_count<>1 or v_after_count<>1
    or coalesce((v_retry->>'duplicate_request')::boolean,false) is not true then
    raise exception 'MotoRace idempotent retry repeated a debit.';
  end if;

  begin
    perform public.nplus_moto_demo_place_bet(
      '{"kind":"bike","value":9,"position":1,"qty":1,"multi":1}'::jsonb,10.00,v_request
    );
    raise exception 'MotoRace request-id replay with changed payload should be rejected.';
  exception when others then
    if sqlerrm not like '%already used for a different MotoRace bet%' then raise; end if;
  end;

  -- Test against a known past server round, using a deterministic outcome in this disposable DB only.
  v_idx := floor(extract(epoch from clock_timestamp())/60)::bigint-1;
  v_starts := to_timestamp(v_idx*60);
  v_ends := v_starts+interval '60 seconds';
  update public.nplus_moto_demo_rounds
  set round_index=v_idx,starts_at=v_starts,ends_at=v_ends,
      outcome='[8,1,2,3,4,5,6,7,9,10]'::jsonb
  where id=(v_placed->>'round_id')::uuid;

  v_settled := public.nplus_moto_demo_settle_round(v_idx);
  if v_settled->>'status'<>'settled' or jsonb_array_length(v_settled->'outcome')<>10 then
    raise exception 'MotoRace did not return a settled server outcome.';
  end if;
  if jsonb_array_length(v_settled->'bets')<>1
    or v_settled->'bets'->0->>'status'<>'won'
    or (v_settled->'bets'->0->>'payout')::numeric<>20.00 then
    raise exception 'Expected one MotoRace winner paid 20.00: %.',v_settled->'bets';
  end if;

  select balance into v_balance from public.demo_wallets where user_id=v_user;
  if v_balance<>117.85 then raise exception 'Expected 117.85 after MotoRace payout, got %.',v_balance; end if;

  v_settled_again := public.nplus_moto_demo_settle_round(v_idx);
  select balance into v_balance from public.demo_wallets where user_id=v_user;
  select count(*) into v_after_count from public.demo_wallet_transactions where user_id=v_user and type='GAME_WIN';
  if v_balance<>117.85 or v_after_count<>1 then raise exception 'MotoRace repeated settlement double-credited wallet.'; end if;

  v_bets := public.nplus_moto_demo_my_bets(100);
  if jsonb_array_length(v_bets)<>1 or v_bets->0->>'status'<>'won'
    or v_bets->0->>'period' is null then raise exception 'MotoRace server bet recovery failed.'; end if;

  v_history := public.nplus_moto_demo_history(100);
  if jsonb_array_length(v_history)<>1 or jsonb_array_length(v_history->0->'outcome')<>10 then
    raise exception 'MotoRace server history failed.';
  end if;

  if has_table_privilege('anon','public.nplus_moto_demo_bets','SELECT')
     or has_table_privilege('authenticated','public.nplus_moto_demo_bets','SELECT') then
    raise exception 'Direct MotoRace bet-table reads are granted.';
  end if;
  if has_function_privilege('anon','public.nplus_moto_demo_place_bet(jsonb,numeric,uuid)','EXECUTE')
     or not has_function_privilege('authenticated','public.nplus_moto_demo_place_bet(jsonb,numeric,uuid)','EXECUTE') then
    raise exception 'MotoRace placement RPC grants are incorrect.';
  end if;
  if has_function_privilege('anon','public.nplus_moto_demo_reveal_round(bigint)','EXECUTE')
     or not has_function_privilege('authenticated','public.nplus_moto_demo_reveal_round(bigint)','EXECUTE') then
    raise exception 'MotoRace reveal RPC grants are incorrect.';
  end if;

  update public.game_settings set enabled=false where game_key='MOTO';
  begin
    perform public.nplus_moto_demo_place_bet(
      '{"kind":"bike","value":8,"position":1,"qty":1,"multi":1}'::jsonb,
      1.00,
      gen_random_uuid()
    );
    raise exception 'TEST_FAILURE: disabled MotoRace accepted a new bet.';
  exception when others then
    if sqlerrm not like '%MotoRace betting is disabled by admin%' then raise; end if;
  end;
  update public.game_settings set enabled=true where game_key='MOTO';

  raise notice 'MotoRace server-settlement tests passed.';
end
$tests$;
