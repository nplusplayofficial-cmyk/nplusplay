-- N+ ADMIN global game-status RPC.
-- Safe additive/re-runnable migration. Game keys match the existing game_settings table.
begin;

-- Keep games without approved server payout rules disabled whenever this
-- reviewed migration is rolled out. The Admin RPC below also refuses re-enable.
update public.game_settings
set enabled = false,
    updated_at = clock_timestamp()
where game_key in ('K3','5D','TRX');

create or replace function public.nplus_set_game_status(
  p_game_key text,
  p_enabled boolean
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user_id uuid := auth.uid();
  v_role text;
  v_key text := upper(trim(coalesce(p_game_key, '')));
  v_name text;
begin
  if v_user_id is null then
    raise exception 'Authentication required.';
  end if;

  select lower(coalesce(p.role, ''))
    into v_role
  from public.profiles p
  where p.id = v_user_id;

  if coalesce(v_role, '') <> 'admin' then
    raise exception 'Admin access required.';
  end if;

  if p_enabled is null then
    raise exception 'Enabled status must be true or false.';
  end if;

  if v_key not in ('WINGO','K3','5D','TRX','AVIATOR','MOTO') then
    raise exception 'Invalid game.';
  end if;

  if p_enabled and v_key in ('K3','5D','TRX') and (
    to_regclass('public.nplus_demo_lottery_rounds') is null
    or to_regprocedure('public.nplus_demo_lottery_snapshot(text,integer)') is null
    or to_regprocedure('public.nplus_demo_lottery_place_bet(text,integer,text,text,numeric,uuid)') is null
  ) then
    raise exception 'Server-authoritative demo settlement is not installed.';
  end if;

  update public.game_settings
  set enabled = p_enabled,
      updated_at = clock_timestamp(),
      updated_by = v_user_id
  where game_key = v_key
  returning game_name into v_name;

  if not found then
    raise exception 'Game setting not found.';
  end if;

  return jsonb_build_object(
    'game_key', v_key,
    'game_name', v_name,
    'enabled', p_enabled,
    'updated_by', v_user_id
  );
end;
$function$;

revoke all on function public.nplus_set_game_status(text, boolean) from public, anon, authenticated;
grant execute on function public.nplus_set_game_status(text, boolean) to authenticated;

commit;
