-- Candidate-only compatibility fix for an overloaded Admin WINGO RPC.
-- Read-only production catalog audit found both 4-arg and 5-arg overloads have
-- DEFAULT arguments. That makes calls with four arguments ambiguous in PostgreSQL.
-- This replacement preserves the 5-argument function body but removes defaults from
-- its arguments. The 4-argument overload remains the intended compatibility route
-- for calls with four or fewer arguments; five-argument callers remain supported.
-- NOT APPLIED TO PRODUCTION. Reconcile this change against the canonical migration
-- chain and test on the verified restored/disposable database before any rollout.

BEGIN;

-- PostgreSQL does not permit CREATE OR REPLACE to remove existing parameter defaults.
-- Deliberately use DROP without CASCADE: any dependency blocks the patch for review.
DROP FUNCTION public.nplus_admin_set_wingo_demo(integer,text,text,integer,text);

CREATE FUNCTION public.nplus_admin_set_wingo_demo(p_duration integer, p_mode text, p_color text, p_number integer, p_size text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role text;
  v_mode text := upper(trim(coalesce(p_mode, 'AUTO')));
  v_color text := upper(trim(coalesce(p_color, '')));
  v_size text := upper(trim(coalesce(p_size, '')));
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  select lower(coalesce(role, ''))
    into v_role
  from public.profiles
  where id = auth.uid();

  if coalesce(v_role, '') <> 'admin' then
    raise exception 'Admin access required.';
  end if;

  if p_duration not in (30,60,180,300) then
    raise exception 'Invalid WINGO duration.';
  end if;

  if v_mode not in ('AUTO','MANUAL','RANDOM') then
    raise exception 'Invalid WINGO mode.';
  end if;

  if v_mode = 'MANUAL' then
    if v_color not in ('GREEN','VIOLET','RED') then
      raise exception 'Manual WINGO color is required.';
    end if;

    if p_number is null or p_number < 0 or p_number > 9 then
      raise exception 'Manual WINGO number must be between 0 and 9.';
    end if;

    if v_size not in ('BIG','SMALL') then
      raise exception 'Manual WINGO size is required.';
    end if;
  end if;

  insert into public.demo_game_controls (
    game_key,
    duration_seconds,
    mode,
    color,
    number,
    result,
    updated_by,
    updated_at
  )
  values (
    'WINGO',
    p_duration,
    v_mode,
    nullif(v_color, ''),
    p_number,
    case
      when v_mode = 'MANUAL'
        then v_color || ' ' || p_number::text || ' · ' || v_size
      when v_mode = 'RANDOM'
        then 'RANDOM DEMO'
      else
        'AUTO'
    end,
    auth.uid(),
    now()
  )
  on conflict (game_key, duration_seconds)
  do update set
    mode = excluded.mode,
    color = excluded.color,
    number = excluded.number,
    result = excluded.result,
    updated_by = auth.uid(),
    updated_at = now();

  return jsonb_build_object(
    'success', true,
    'duration', p_duration,
    'mode', v_mode,
    'color', nullif(v_color, ''),
    'number', p_number,
    'size', nullif(v_size, ''),
    'result',
      case
        when v_mode = 'MANUAL'
          then v_color || ' ' || p_number::text || ' · ' || v_size
        when v_mode = 'RANDOM'
          then 'RANDOM DEMO'
        else 'AUTO'
      end
  );
end;
$function$;

-- Restore the audited grants explicitly after the drop/recreate. Non-admin calls still
-- execute through the RPC grant and are rejected by the function's internal role guard.
REVOKE ALL ON FUNCTION public.nplus_admin_set_wingo_demo(integer,text,text,integer,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_admin_set_wingo_demo(integer,text,text,integer,text)
  TO authenticated, service_role;

COMMIT;
