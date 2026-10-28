
begin;

create or replace function public.nplus_wallet_change(
  p_delta numeric,
  p_type text default 'GAME',
  p_source text default 'SYSTEM',
  p_note text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user_id uuid;
  v_before numeric;
  v_after numeric;
  v_type text;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception using errcode = '42501',
      message = 'Authentication required.';
  end if;

  if p_delta is null
     or p_delta = 'Infinity'::numeric
     or p_delta = '-Infinity'::numeric
     or p_delta = 'NaN'::numeric then
    raise exception using errcode = '22023',
      message = 'Invalid wallet amount.';
  end if;

  if p_delta > 0 then
    raise exception using errcode = '42501',
      message = 'Generic wallet credits are disabled; use an authorized server transaction.';
  end if;

  v_type := upper(trim(coalesce(p_type, '')));

  if v_type in ('GAME_BET', 'GAME_WIN') then
    raise exception using errcode = '42501',
      message = 'Game wallet changes must use the server-authoritative game RPC.';
  end if;

  if p_delta = 0 then
    raise exception using errcode = '22023',
      message = 'Wallet change must be non-zero.';
  end if;

  select balance
    into v_before
  from public.demo_wallets
  where user_id = v_user_id
  for update;

  if not found then
    raise exception 'Wallet not found.';
  end if;

  v_after := v_before + p_delta;

  if v_after < 0 then
    raise exception 'Insufficient virtual balance.';
  end if;

  update public.demo_wallets
  set balance = v_after,
      updated_at = clock_timestamp()
  where user_id = v_user_id;

  insert into public.demo_wallet_transactions (
    user_id, delta, balance_before, balance_after, type, source, note
  )
  values (
    v_user_id,
    p_delta,
    v_before,
    v_after,
    coalesce(nullif(trim(p_type), ''), 'GAME'),
    coalesce(nullif(trim(p_source), ''), 'SYSTEM'),
    coalesce(p_note, '')
  );

  return jsonb_build_object(
    'user_id', v_user_id,
    'before', v_before,
    'after', v_after,
    'delta', p_delta
  );
end;
$function$;

revoke all on function public.nplus_wallet_change(numeric, text, text, text)
  from public, anon;
grant execute on function public.nplus_wallet_change(numeric, text, text, text)
  to authenticated;

commit;
