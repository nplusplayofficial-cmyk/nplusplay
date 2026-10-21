\set ON_ERROR_STOP on

-- Test only after the base Aviator schema/RPC and fixture test.
\ir ../sql/NPLUS_PLAY_AVIATOR_SCHEDULER_RECOVERY.sql

do $worker_tests$
declare
  v_user uuid := '55555555-5555-4555-8555-555555555555';
  v_result jsonb;
  v_last_success timestamptz;
begin
  perform set_config('request.jwt.claim.sub', v_user::text, true);

  -- Worker internals must not be callable by browser roles.
  if has_function_privilege(
       'anon',
       'public.nplus_aviator_demo_worker_tick()',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.nplus_aviator_demo_worker_tick()',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'public.nplus_aviator_demo_advance_round_internal()',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.nplus_aviator_demo_advance_round_internal()',
       'EXECUTE'
     ) then
    raise exception 'Aviator worker execution is exposed to browser roles.';
  end if;

  if has_table_privilege(
       'anon',
       'public.nplus_aviator_worker_health',
       'SELECT'
     )
     or has_table_privilege(
       'authenticated',
       'public.nplus_aviator_worker_health',
       'SELECT'
     ) then
    raise exception 'Aviator worker health is readable by browser roles.';
  end if;

  update public.game_settings
  set enabled = true
  where game_key = 'AVIATOR';

  -- Execute one worker tick and verify its heartbeat.
  v_result := public.nplus_aviator_demo_worker_tick();

  if coalesce((v_result->>'ok')::boolean, false) is not true then
    raise exception 'Aviator worker tick failed: %', v_result;
  end if;

  select last_success_at
  into v_last_success
  from public.nplus_aviator_worker_health
  where singleton_key = true;

  if v_last_success is null
     or v_last_success < clock_timestamp() - interval '10 seconds' then
    raise exception 'Successful Aviator worker tick did not refresh heartbeat.';
  end if;

  -- A stale heartbeat must block new bets.
  update public.nplus_aviator_worker_health
  set last_success_at = clock_timestamp() - interval '11 seconds'
  where singleton_key = true;

  begin
    perform public.nplus_aviator_demo_place_bet(
      gen_random_uuid(),
      0,
      1.00,
      gen_random_uuid(),
      null
    );

    raise exception 'TEST_FAILURE: stale heartbeat accepted a bet.';
  exception
    when others then
      if sqlerrm not like '%heartbeat is stale%' then
        raise;
      end if;
  end;

  -- A subsequent successful tick must restore a fresh heartbeat.
  v_result := public.nplus_aviator_demo_worker_tick();

  if coalesce((v_result->>'ok')::boolean, false) is not true then
    raise exception 'Aviator worker could not recover after stale heartbeat: %', v_result;
  end if;

  select last_success_at
  into v_last_success
  from public.nplus_aviator_worker_health
  where singleton_key = true;

  if v_last_success is null
     or v_last_success < clock_timestamp() - interval '10 seconds' then
    raise exception 'Recovered Aviator worker heartbeat is still stale.';
  end if;

  -- Disabling the game must continue to reject new bets.
  update public.game_settings
  set enabled = false
  where game_key = 'AVIATOR';

  begin
    perform public.nplus_aviator_demo_place_bet(
      gen_random_uuid(),
      0,
      1.00,
      gen_random_uuid(),
      null
    );

    raise exception 'TEST_FAILURE: disabled Aviator accepted a bet.';
  exception
    when others then
      if sqlerrm not like '%Aviator betting is disabled by admin%' then
        raise;
      end if;
  end;

  update public.game_settings
  set enabled = true
  where game_key = 'AVIATOR';

  raise notice 'Aviator worker regression tests passed.';
end
$worker_tests$;
