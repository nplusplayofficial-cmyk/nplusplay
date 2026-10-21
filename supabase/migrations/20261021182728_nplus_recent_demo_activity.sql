begin;

create or replace function public.nplus_recent_demo_activity(
  p_window_minutes integer default 60
)
returns table (
  game_key text,
  activity_count bigint
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $function$
  with cutoff as (
    select statement_timestamp()
      - make_interval(
          mins => least(
            greatest(coalesce(p_window_minutes, 60), 5),
            1440
          )
        ) as since_ts
  ),
  events as (
    select
      'WINGO'::text as game_key,
      count(*)::bigint as activity_count,
      max(b.created_at) as latest_at
    from public.nplus_wingo_demo_bets b
    cross join cutoff c
    where b.created_at >= c.since_ts

    union all

    select
      'MOTORACE'::text as game_key,
      count(*)::bigint as activity_count,
      max(b.created_at) as latest_at
    from public.nplus_moto_demo_bets b
    cross join cutoff c
    where b.created_at >= c.since_ts

    union all

    select
      'AVIATOR'::text as game_key,
      count(*)::bigint as activity_count,
      max(b.created_at) as latest_at
    from public.nplus_aviator_demo_bets b
    cross join cutoff c
    where b.created_at >= c.since_ts
  )
  select e.game_key, e.activity_count
  from events e
  where e.activity_count > 0
  order by e.latest_at desc;
$function$;

revoke all on function public.nplus_recent_demo_activity(integer)
  from public, anon, authenticated;

grant execute on function public.nplus_recent_demo_activity(integer)
  to anon, authenticated;

commit;
