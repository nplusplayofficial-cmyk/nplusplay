-- POST-ROLLOUT ONLY. Do not run before the server-settlement frontend is deployed.
-- The current production main branch still calls nplus_wallet_change with positive
-- GAME_WIN deltas from WINGO/MotoRace/Aviator. Running this against that frontend
-- would make winning bets fail to credit. Review the security branch and all
-- direct wallet-RPC callers, deploy matching server-side settlement RPCs, and
-- complete isolated Supabase regression testing first.
--
-- This guard preserves negative demo-stake debits for any remaining legacy UI,
-- but rejects every caller-supplied positive credit. Server-side game settlement,
-- admin adjustment and admin-approved demo deposits update wallets/ledger in
-- their own trusted SECURITY DEFINER transactions and must not call this RPC.
-- It does not alter/reset any existing wallet balance.

begin;

create or replace function public.nplus_wallet_change(
  p_delta numeric,
  p_type text default 'GAME'::text,
  p_source text default 'SYSTEM'::text,
  p_note text default ''::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user_id uuid;
  v_before numeric;
  v_after numeric;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if p_delta is null
     or p_delta = 'Infinity'::numeric
     or p_delta = '-Infinity'::numeric then
    raise exception 'Invalid wallet amount.';
  end if;

  if p_delta > 0 then
    raise exception 'Positive virtual credits must be awarded by server-authoritative settlement or admin approval.'
      using errcode = '42501';
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
      updated_at = now()
  where user_id = v_user_id;

  insert into public.demo_wallet_transactions (
    user_id, delta, balance_before, balance_after, type, source, note
  )
  values (
    v_user_id, p_delta, v_before, v_after,
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

commit;
