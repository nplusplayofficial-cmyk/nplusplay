\set ON_ERROR_STOP on

-- Disposable PostgreSQL regression for the post-rollout phone-enumeration revoke.
-- This intentionally simulates the old public RPC only inside the CI database.

do $roles$
begin
  if not exists (select 1 from pg_roles where rolname='anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then
    create role authenticated nologin;
  end if;
end
$roles$;

create or replace function public.nplus_phone_is_registered(p_phone text)
returns boolean
language sql
security definer
set search_path=pg_catalog
as $function$
  select false
$function$;

grant execute on function public.nplus_phone_is_registered(text) to public, anon, authenticated;

do $precheck$
begin
  if not has_function_privilege('anon','public.nplus_phone_is_registered(text)','EXECUTE')
     or not has_function_privilege('authenticated','public.nplus_phone_is_registered(text)','EXECUTE') then
    raise exception 'Test setup did not reproduce the legacy phone-lookup grants.';
  end if;
end
$precheck$;

\ir ../sql/POST_ROLLOUT_REVOKE_PHONE_ENUMERATION.sql

do $postcheck$
begin
  if has_function_privilege('anon','public.nplus_phone_is_registered(text)','EXECUTE')
     or has_function_privilege('authenticated','public.nplus_phone_is_registered(text)','EXECUTE') then
    raise exception 'Phone-registration enumeration RPC remains executable after the post-rollout revoke.';
  end if;
end
$postcheck$;

select 'PASS: phone enumeration execute privileges revoked in disposable PostgreSQL' as result;
