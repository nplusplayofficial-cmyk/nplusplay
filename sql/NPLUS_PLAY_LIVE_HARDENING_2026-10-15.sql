-- N+ PLAY live hardening snapshot — 2026-10-15
-- These operations were applied to the connected production project and read-only verified.
-- Re-running is intended to be idempotent; review all statements before reusing elsewhere.
-- Does NOT implement server-authoritative game settlement.
-- Backup archive used before the live patch: nplus-play-full-2026-10-15.dump
-- Keep that dump private; it contains auth, wallet, and other sensitive data.

BEGIN;

-- Prevent self-promotion through profiles.role updates.
CREATE OR REPLACE FUNCTION public.nplus_guard_profile_role_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $function$
DECLARE
  v_actor_id uuid;
  v_actor_role text;
  v_jwt_role text;
BEGIN
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    v_actor_id := auth.uid();
    IF v_actor_id IS NULL THEN
      v_jwt_role := auth.role();
      IF v_jwt_role IN ('anon', 'authenticated') THEN
        RAISE EXCEPTION 'Only an administrator can change profile roles.'
          USING ERRCODE = '42501';
      END IF;
    ELSE
      SELECT lower(coalesce(p.role, ''))
        INTO v_actor_role
        FROM public.profiles AS p
       WHERE p.id = v_actor_id;
      IF coalesce(v_actor_role, '') <> 'admin' THEN
        RAISE EXCEPTION 'Only an administrator can change profile roles.'
          USING ERRCODE = '42501';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION public.nplus_guard_profile_role_update() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS nplus_guard_profile_role_update ON public.profiles;
CREATE TRIGGER nplus_guard_profile_role_update
BEFORE UPDATE OF role ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.nplus_guard_profile_role_update();

-- The auth.users INSERT trigger invokes this function internally; it should not
-- also be exposed as a callable PostgREST RPC.
REVOKE ALL ON FUNCTION public.create_nplus_profile() FROM PUBLIC, anon, authenticated;

-- Keep unauthenticated users from invoking admin and wallet SECURITY DEFINER RPCs.
-- These functions still perform their own admin/auth checks; signed-in execute remains.
DO $revoke_anonymous$
DECLARE f record;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure AS signature
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public'
       AND p.prosecdef
       AND (
         left(p.proname, 12) = 'nplus_admin_'
         OR p.proname IN ('nplus_wallet_change','nplus_set_game_status','nplus_is_admin')
       )
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', f.signature);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', f.signature);
  END LOOP;
END;
$revoke_anonymous$;

-- Browser clients can read only their own wallet and ledger; writes use approved RPCs.
ALTER TABLE public.demo_wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.demo_wallet_transactions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.demo_wallets FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.demo_wallet_transactions FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.demo_wallets TO authenticated;
GRANT SELECT ON TABLE public.demo_wallet_transactions TO authenticated;

DROP POLICY IF EXISTS "wallet own row" ON public.demo_wallets;
DROP POLICY IF EXISTS wallet_own_row ON public.demo_wallets;
CREATE POLICY wallet_own_row ON public.demo_wallets FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "wallet tx own rows" ON public.demo_wallet_transactions;
DROP POLICY IF EXISTS wallet_tx_own_rows ON public.demo_wallet_transactions;
CREATE POLICY wallet_tx_own_rows ON public.demo_wallet_transactions FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- Profile reads: own row or admin; profile updates remain own-row and role changes
-- are separately blocked by the trigger unless the actor is an administrator.
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "profiles own row" ON public.profiles;
DROP POLICY IF EXISTS profiles_owner_or_admin_read ON public.profiles;
CREATE POLICY profiles_owner_or_admin_read ON public.profiles FOR SELECT TO authenticated
  USING (id = (SELECT auth.uid()) OR (SELECT public.nplus_is_admin()));

DROP POLICY IF EXISTS "profiles own update" ON public.profiles;
DROP POLICY IF EXISTS profiles_own_update ON public.profiles;
CREATE POLICY profiles_own_update ON public.profiles FOR UPDATE TO authenticated
  USING (id = (SELECT auth.uid()))
  WITH CHECK (id = (SELECT auth.uid()));

-- Consolidate deposit request policies: own/admin SELECT; authenticated users can
-- INSERT only a positive, pending request owned by themselves.
ALTER TABLE public.deposit_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS admins_select_deposit_requests ON public.deposit_requests;
DROP POLICY IF EXISTS "admins_select_deposit_requests" ON public.deposit_requests;
DROP POLICY IF EXISTS users_select_own_deposit_requests ON public.deposit_requests;
DROP POLICY IF EXISTS "users_select_own_deposit_requests" ON public.deposit_requests;
DROP POLICY IF EXISTS deposit_requests_select ON public.deposit_requests;
CREATE POLICY deposit_requests_select ON public.deposit_requests FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()) OR (SELECT public.nplus_is_admin()));

DROP POLICY IF EXISTS users_insert_own_deposit_requests ON public.deposit_requests;
DROP POLICY IF EXISTS "users_insert_own_deposit_requests" ON public.deposit_requests;
DROP POLICY IF EXISTS deposit_requests_insert ON public.deposit_requests;
CREATE POLICY deposit_requests_insert ON public.deposit_requests FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()) AND amount > 0 AND status = 'pending');

-- Admin-only update access for game settings.
ALTER TABLE public.game_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admins can update game settings" ON public.game_settings;
DROP POLICY IF EXISTS game_settings_admin_update ON public.game_settings;
CREATE POLICY game_settings_admin_update ON public.game_settings FOR UPDATE TO authenticated
  USING ((SELECT public.nplus_is_admin()))
  WITH CHECK ((SELECT public.nplus_is_admin()));

ALTER TABLE public.demo_game_controls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wingo_manual_results ENABLE ROW LEVEL SECURITY;

-- Align fallback wallet default with the account-creation trigger (₹108).
-- This changes future inserts only; existing balances are not modified.
ALTER TABLE public.demo_wallets ALTER COLUMN balance SET DEFAULT 108.00;

-- Advisor-recommended covering indexes.
CREATE INDEX IF NOT EXISTS deposit_requests_reviewed_by_idx ON public.deposit_requests(reviewed_by);
CREATE INDEX IF NOT EXISTS game_settings_updated_by_idx ON public.game_settings(updated_by);
CREATE INDEX IF NOT EXISTS demo_wallet_transactions_user_created_idx
  ON public.demo_wallet_transactions(user_id, created_at DESC);

COMMIT;

-- Intentionally not revoked here: current live auth.html calls
-- nplus_phone_is_registered during signup. Remove that frontend call and add a
-- verified unique-phone constraint before restricting this RPC, or signup will break.
-- CRITICAL: nplus_wallet_change still trusts client-provided positive deltas. Do not
-- call game payouts tamper-resistant until server-generated outcomes, persisted bets,
-- atomic settlement, and replay protection are implemented and tested.
