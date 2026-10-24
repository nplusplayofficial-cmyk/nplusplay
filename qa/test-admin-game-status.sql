\set ON_ERROR_STOP on

create table if not exists public.game_settings (
  game_key text primary key,
  game_name text not null,
  enabled boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by uuid
);
insert into public.game_settings(game_key,game_name,enabled)
values
 ('WINGO','WINGO',true),('K3','K3 WINGO',true),('5D','5D',true),
 ('TRX','TRX WINGO',true),('AVIATOR','AVIATOR',true),('MOTO','MOTO RACE',true)
on conflict(game_key) do nothing;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id),
  uid text not null unique,
  display_name text,
  email text,
  phone text,
  role text not null default 'user',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

\ir ../sql/NPLUS_PLAY_ADMIN_GAME_STATUS.sql

do $tests$
declare
  v_admin uuid := 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
  v_user uuid := 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
  v_result jsonb;
  v_enabled boolean;
  v_updated_by uuid;
  v_key text;
begin
  insert into auth.users(id,email)
  values (v_admin,'game-admin-qa@example.invalid'),(v_user,'game-user-qa@example.invalid');

  insert into public.profiles(id,uid,display_name,email,phone,role)
  values
    (v_admin,'QA-GAME-ADMIN','Game Admin QA','game-admin-qa@example.invalid','9000000081','admin'),
    (v_user,'QA-GAME-USER','Game User QA','game-user-qa@example.invalid','9000000082','user');

  if exists (
    select 1 from public.game_settings
    where game_key in ('K3','5D','TRX') and enabled is distinct from false
  ) then
    raise exception 'Migration did not default K3/5D/TRX to disabled.';
  end if;

  perform set_config('request.jwt.claim.sub',v_admin::text,true);
  v_result:=public.nplus_set_game_status('WINGO',false);
  if coalesce((v_result->>'enabled')::boolean,true) is not false then
    raise exception 'Admin status RPC did not return disabled.';
  end if;
  select enabled,updated_by into v_enabled,v_updated_by
    from public.game_settings where game_key='WINGO';
  if v_enabled is not false or v_updated_by<>v_admin then
    raise exception 'Admin status RPC did not persist disabled status and actor.';
  end if;

  v_result:=public.nplus_set_game_status('WINGO',true);
  select enabled into v_enabled from public.game_settings where game_key='WINGO';
  if v_enabled is not true then raise exception 'Admin status RPC did not re-enable the allowed WINGO flag.'; end if;

  -- Every game without approved server payout rules must remain disabled.
  foreach v_result in array array['K3'::jsonb, '5D'::jsonb, 'TRX'::jsonb] loop
    -- This array loop is deliberately not used for RPC arguments; test each exact key below.
    null;
  end loop;
  foreach v_enabled in array array[false, false, false] loop
    null;
  end loop;
  perform public.nplus_set_game_status('K3',false);
  perform public.nplus_set_game_status('5D',false);
  perform public.nplus_set_game_status('TRX',false);
  foreach v_key in array array['K3','5D','TRX'] loop
    begin
      perform public.nplus_set_game_status(v_key,true);
      raise exception 'TEST_FAILURE: paused % was re-enabled without payout approval.',v_key;
    exception when others then
      if sqlerrm not like '%Payout rules pending%' then raise; end if;
    end;
    select enabled into v_enabled from public.game_settings where game_key=v_key;
    if v_enabled is not false then raise exception 'Server guard did not preserve paused % status.',v_key; end if;
  end loop;

  begin
    perform public.nplus_set_game_status('WINGO',null::boolean);
    raise exception 'TEST_FAILURE: null status should be rejected.';
  exception when others then
    if sqlerrm not like '%Enabled status must be true or false%' then raise; end if;
  end;

  begin
    perform public.nplus_set_game_status('UNKNOWN',false);
    raise exception 'TEST_FAILURE: unknown game key should be rejected.';
  exception when others then
    if sqlerrm not like '%Invalid game%' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub',v_user::text,true);
  begin
    perform public.nplus_set_game_status('WINGO',false);
    raise exception 'TEST_FAILURE: non-admin changed game status.';
  exception when others then
    if sqlerrm<>'Admin access required.' then raise; end if;
  end;

  if has_function_privilege('anon','public.nplus_set_game_status(text,boolean)','EXECUTE') then
    raise exception 'Anonymous EXECUTE is enabled on the game status RPC.';
  end if;
  if not has_function_privilege('authenticated','public.nplus_set_game_status(text,boolean)','EXECUTE') then
    raise exception 'Authenticated EXECUTE is missing from the role-guarded game status RPC.';
  end if;

  perform set_config('request.jwt.claim.sub','',true);
  begin
    perform public.nplus_set_game_status('WINGO',false);
    raise exception 'TEST_FAILURE: unauthenticated changed game status.';
  exception when others then
    if sqlerrm<>'Authentication required.' then raise; end if;
  end;

  raise notice 'N+ ADMIN game status tests passed.';
end
$tests$;
