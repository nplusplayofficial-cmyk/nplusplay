-- N+ PLAY / N+ ADMIN: missing Users-page RPCs.
-- Draft migration only. Test in isolated PostgreSQL/Supabase before production.
-- These functions expose profile/wallet data only to signed-in users whose
-- current public.profiles.role is exactly 'admin'. No auth.users secrets are returned.

begin;

create or replace function public.nplus_admin_user_directory(
  p_search text default '',
  p_limit integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user_id uuid := auth.uid();
  v_role text;
  v_search text := left(trim(coalesce(p_search, '')), 160);
  v_rows jsonb;
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

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'user_id', x.id,
        'id', x.id,
        'uid', x.uid,
        'display_name', x.display_name,
        'email', x.email,
        'phone', x.phone,
        'role', x.role,
        'created_at', x.created_at,
        'balance', coalesce(w.balance, 0)
      )
      order by x.created_at desc, x.id
    ),
    '[]'::jsonb
  )
  into v_rows
  from (
    select p.*
    from public.profiles p
    where v_search = ''
       or concat_ws(' ', p.uid, p.display_name, p.email, p.phone, p.id::text)
          ilike '%' || v_search || '%'
    order by p.created_at desc, p.id
    limit least(greatest(coalesce(p_limit, 200), 1), 200)
  ) x
  left join public.demo_wallets w on w.user_id = x.id;

  return jsonb_build_object('rows', v_rows, 'count', jsonb_array_length(v_rows));
end;
$function$;

create or replace function public.nplus_admin_user_transactions(
  p_user_id uuid,
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_admin_id uuid := auth.uid();
  v_role text;
  v_rows jsonb;
begin
  if v_admin_id is null then
    raise exception 'Authentication required.';
  end if;
  if p_user_id is null then
    raise exception 'Target user is required.';
  end if;

  select lower(coalesce(p.role, ''))
  into v_role
  from public.profiles p
  where p.id = v_admin_id;

  if coalesce(v_role, '') <> 'admin' then
    raise exception 'Admin access required.';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', t.id,
        'user_id', t.user_id,
        'delta', t.delta,
        'balance_before', t.balance_before,
        'balance_after', t.balance_after,
        'type', t.type,
        'source', t.source,
        'note', t.note,
        'created_at', t.created_at
      )
      order by t.created_at desc, t.id desc
    ),
    '[]'::jsonb
  )
  into v_rows
  from (
    select t.*
    from public.demo_wallet_transactions t
    where t.user_id = p_user_id
    order by t.created_at desc, t.id desc
    limit least(greatest(coalesce(p_limit, 100), 1), 200)
  ) t;

  return jsonb_build_object('rows', v_rows, 'count', jsonb_array_length(v_rows));
end;
$function$;

-- Drop the legacy same-signature RPC if its parameter names/body are from an older build.
-- CREATE OR REPLACE cannot rename input parameters, so remove this signature first.
drop function if exists public.nplus_admin_adjust_demo_wallet(uuid, numeric, text);

create or replace function public.nplus_admin_adjust_demo_wallet(
  p_target_user uuid,
  p_delta numeric,
  p_note text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_admin_id uuid := auth.uid();
  v_role text;
  v_before numeric(12,2);
  v_after numeric(12,2);
  v_delta numeric(12,2);
  v_note text := trim(coalesce(p_note, ''));
begin
  if v_admin_id is null then
    raise exception 'Authentication required.';
  end if;
  if p_target_user is null then
    raise exception 'Target user is required.';
  end if;

  select lower(coalesce(p.role, ''))
  into v_role
  from public.profiles p
  where p.id = v_admin_id;

  if coalesce(v_role, '') <> 'admin' then
    raise exception 'Admin access required.';
  end if;

  if p_delta is null or p_delta::text in ('Infinity', '-Infinity', 'NaN')
     or p_delta = 0 or p_delta < -1000000 or p_delta > 1000000
     or p_delta <> round(p_delta, 2) then
    raise exception 'Adjustment must be between -1000000 and 1000000 credits, with at most two decimals.';
  end if;
  if length(v_note) < 4 or length(v_note) > 300 then
    raise exception 'Enter an adjustment reason between 4 and 300 characters.';
  end if;

  select w.balance
  into v_before
  from public.demo_wallets w
  where w.user_id = p_target_user
  for update;

  if not found then
    raise exception 'Target wallet not found.';
  end if;

  v_delta := p_delta;
  v_after := v_before + v_delta;
  if v_after < 0 then
    raise exception 'Adjustment would make the virtual balance negative.';
  end if;

  update public.demo_wallets
  set balance = v_after, updated_at = clock_timestamp()
  where user_id = p_target_user;

  insert into public.demo_wallet_transactions(
    user_id, delta, balance_before, balance_after, type, source, note
  )
  values(
    p_target_user, v_delta, v_before, v_after,
    'ADMIN_ADJUSTMENT', 'NPLUS_ADMIN', v_note
  );

  return jsonb_build_object(
    'success', true,
    'target_user', p_target_user,
    'before', v_before,
    'after', v_after,
    'delta', v_delta,
    'note', v_note
  );
end;
$function$;

revoke all on function public.nplus_admin_user_directory(text, integer) from public, anon, authenticated;
revoke all on function public.nplus_admin_user_transactions(uuid, integer) from public, anon, authenticated;
revoke all on function public.nplus_admin_adjust_demo_wallet(uuid, numeric, text) from public, anon, authenticated;

grant execute on function public.nplus_admin_user_directory(text, integer) to authenticated;
grant execute on function public.nplus_admin_user_transactions(uuid, integer) to authenticated;
grant execute on function public.nplus_admin_adjust_demo_wallet(uuid, numeric, text) to authenticated;

commit;
