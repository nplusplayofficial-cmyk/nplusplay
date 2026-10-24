\set ON_ERROR_STOP on

-- Run only after the disposable WINGO, MotoRace and Aviator schema tests.
\ir ../sql/NPLUS_PLAY_RECENT_DEMO_ACTIVITY.sql

do $tests$
declare
  v_rows integer;
  v_bad integer;
  v_result text;
begin
  select count(*) into v_rows
  from public.nplus_recent_demo_activity(60);

  if v_rows > 3 then
    raise exception 'Activity feed returned more than the three supported game categories.';
  end if;

  select count(*) into v_bad
  from public.nplus_recent_demo_activity(60)
  where game_key not in ('WINGO','MOTORACE','AVIATOR')
     or activity_count <= 0;
  if v_bad <> 0 then
    raise exception 'Activity feed returned an unsupported key or non-positive count.';
  end if;

  select pg_get_function_result('public.nplus_recent_demo_activity(integer)'::regprocedure)
    into v_result;
  if v_result <> 'TABLE(game_key text, activity_count bigint)' then
    raise exception 'Activity feed exposes an unexpected result contract: %.',v_result;
  end if;

  if not has_function_privilege('anon','public.nplus_recent_demo_activity(integer)','EXECUTE') then
    raise exception 'Anonymous execution is required for the privacy-safe public aggregate feed.';
  end if;
  if not has_function_privilege('authenticated','public.nplus_recent_demo_activity(integer)','EXECUTE') then
    raise exception 'Authenticated execution is missing for the activity feed.';
  end if;

  -- Window input is clamped; both boundary inputs must remain valid.
  perform * from public.nplus_recent_demo_activity(0);
  perform * from public.nplus_recent_demo_activity(999);

  raise notice 'Privacy-safe recent demo activity feed tests passed.';
end
$tests$;
