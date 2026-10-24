-- Privacy-safe, server-backed aggregate activity feed for the public homepage.
-- Returns only game key + count; no user identifiers, bet amounts, selections, or outcomes.
begin;

create or replace function public.nplus_recent_demo_activity(
  p_window_minutes integer default 60
)
returns table(game_key text, activity_count bigint)
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_since timestamptz := statement_timestamp()
    - make_interval(mins => least(greatest(coalesce(p_window_minutes, 60), 1), 60));
  v_until timestamptz := statement_timestamp();
begin
  return query
  select 'WINGO'::text, count(*)::bigint
  from public.nplus_wingo_demo_bets b
  where b.created_at >= v_since and b.created_at <= v_until
  having count(*) > 0
  union all
  select 'MOTORACE'::text, count(*)::bigint
  from public.nplus_moto_demo_bets b
  where b.created_at >= v_since and b.created_at <= v_until
  having count(*) > 0
  union all
  select 'AVIATOR'::text, count(*)::bigint
  from public.nplus_aviator_demo_bets b
  where b.created_at >= v_since and b.created_at <= v_until
  having count(*) > 0
  order by 1;
end;
$function$;

revoke all on function public.nplus_recent_demo_activity(integer) from public;
grant execute on function public.nplus_recent_demo_activity(integer) to anon, authenticated;

commit;
