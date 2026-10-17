-- N+ ADMIN deposit action RPCs.
-- Idempotent approve/reject and admin-only execution.
-- Safe additive migration; this does not create or change any user wallet rows.

begin;

create or replace function public.nplus_approve_deposit(p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_admin_id uuid := auth.uid();
  v_role text;
  v_request public.deposit_requests%rowtype;
  v_before numeric(12,2);
  v_after numeric(12,2);
begin
  if v_admin_id is null then
    raise exception 'Authentication required.';
  end if;

  select lower(coalesce(p.role, ''))
  into v_role
  from public.profiles p
  where p.id = v_admin_id;

  if coalesce(v_role, '') <> 'admin' then
    raise exception 'Admin access required.';
  end if;

  if p_request_id is null then
    raise exception 'Deposit request ID is required.';
  end if;

  select *
  into v_request
  from public.deposit_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'Deposit request not found.';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'Request has already been reviewed.';
  end if;

  if v_request.amount is null or v_request.amount <= 0 then
    raise exception 'Deposit request amount is invalid.';
  end if;

  select w.balance
  into v_before
  from public.demo_wallets w
  where w.user_id = v_request.user_id
  for update;

  if not found then
    raise exception 'User wallet not found.';
  end if;

  v_after := v_before + round(v_request.amount, 2);

  update public.demo_wallets
  set balance = v_after,
      updated_at = clock_timestamp()
  where user_id = v_request.user_id;

  insert into public.demo_wallet_transactions(
    user_id, delta, balance_before, balance_after, type, source, note
  )
  values(
    v_request.user_id,
    round(v_request.amount, 2),
    v_before,
    v_after,
    'credit',
    'admin_deposit',
    'Virtual deposit request approved by admin'
  );

  update public.deposit_requests
  set status = 'approved',
      reviewed_at = clock_timestamp(),
      reviewed_by = v_admin_id
  where id = v_request.id;

  return jsonb_build_object(
    'success', true,
    'request_id', v_request.id,
    'amount', round(v_request.amount, 2),
    'balance_before', v_before,
    'balance_after', v_after
  );
end;
$function$;

create or replace function public.nplus_reject_deposit(p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_admin_id uuid := auth.uid();
  v_role text;
  v_request public.deposit_requests%rowtype;
begin
  if v_admin_id is null then
    raise exception 'Authentication required.';
  end if;

  select lower(coalesce(p.role, ''))
  into v_role
  from public.profiles p
  where p.id = v_admin_id;

  if coalesce(v_role, '') <> 'admin' then
    raise exception 'Admin access required.';
  end if;

  if p_request_id is null then
    raise exception 'Deposit request ID is required.';
  end if;

  select *
  into v_request
  from public.deposit_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'Deposit request not found.';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'Request has already been reviewed.';
  end if;

  update public.deposit_requests
  set status = 'rejected',
      reviewed_at = clock_timestamp(),
      reviewed_by = v_admin_id
  where id = v_request.id;

  return jsonb_build_object(
    'success', true,
    'request_id', v_request.id,
    'amount', round(v_request.amount, 2),
    'status', 'rejected'
  );
end;
$function$;

revoke all on function public.nplus_approve_deposit(uuid) from public, anon, authenticated;
revoke all on function public.nplus_reject_deposit(uuid) from public, anon, authenticated;
grant execute on function public.nplus_approve_deposit(uuid) to authenticated;
grant execute on function public.nplus_reject_deposit(uuid) to authenticated;

commit;
