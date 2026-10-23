-- N+ PLAY live safety/performance follow-up.
-- Applied to live Supabase project pcrxlqduygvzchzxsmdv on 2026-10-23.
-- Preserves row predicates while evaluating auth.uid() once per statement and
-- adds indexes for foreign-key columns identified by Supabase advisors.
-- Does not touch balances, game status, or application rows.

CREATE INDEX IF NOT EXISTS idx_manual_deposits_user_id_fk
  ON public.manual_deposits (user_id);
CREATE INDEX IF NOT EXISTS idx_nplus_demo_gift_claims_code_fk
  ON public.nplus_demo_gift_claims (code);
CREATE INDEX IF NOT EXISTS idx_nplus_demo_gift_codes_created_by_fk
  ON public.nplus_demo_gift_codes (created_by);
CREATE INDEX IF NOT EXISTS idx_nplus_demo_referral_bonus_claims_invitee_count_fk
  ON public.nplus_demo_referral_bonus_claims (invitee_count);
CREATE INDEX IF NOT EXISTS idx_nplus_demo_referral_qualifications_verified_by_fk
  ON public.nplus_demo_referral_qualifications (verified_by);
CREATE INDEX IF NOT EXISTS idx_nplus_demo_support_requests_handled_by_fk
  ON public.nplus_demo_support_requests (handled_by);
CREATE INDEX IF NOT EXISTS idx_withdraw_requests_user_id_fk
  ON public.withdraw_requests (user_id);
CREATE INDEX IF NOT EXISTS idx_withdrawal_requests_reviewed_by_fk
  ON public.withdrawal_requests (reviewed_by);

-- This policy is redundant: profiles_own_update already enforces the same
-- owner-only UPDATE predicate with both USING and WITH CHECK.
DROP POLICY IF EXISTS profiles_update_own_display_name ON public.profiles;

-- Keep preferences private to the signed-in owner; auth.uid() is statement-scoped.
DROP POLICY IF EXISTS user_preferences_select_own ON public.user_preferences;
CREATE POLICY user_preferences_select_own ON public.user_preferences
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS user_preferences_insert_own ON public.user_preferences;
CREATE POLICY user_preferences_insert_own ON public.user_preferences
  FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS user_preferences_update_own ON public.user_preferences;
CREATE POLICY user_preferences_update_own ON public.user_preferences
  FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

-- Owner/admin read access for requests; only authenticated clients need these
-- policies. The combined deposit SELECT policy avoids overlapping permissive rules.
DROP POLICY IF EXISTS "Admins can view all deposits" ON public.manual_deposits;
DROP POLICY IF EXISTS "Users can view own deposit" ON public.manual_deposits;
CREATE POLICY manual_deposits_owner_admin_read ON public.manual_deposits
  FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = (SELECT auth.uid()) AND p.role = 'admin'
    )
  );

DROP POLICY IF EXISTS "Users can insert own deposit" ON public.manual_deposits;
CREATE POLICY "Users can insert own deposit" ON public.manual_deposits
  FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can insert own bank" ON public.user_bank_details;
CREATE POLICY "Users can insert own bank" ON public.user_bank_details
  FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can view own bank" ON public.user_bank_details;
CREATE POLICY "Users can view own bank" ON public.user_bank_details
  FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can update own bank" ON public.user_bank_details;
CREATE POLICY "Users can update own bank" ON public.user_bank_details
  FOR UPDATE TO authenticated
  USING ((SELECT auth.uid()) = user_id)
  WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can insert own withdraw" ON public.withdraw_requests;
CREATE POLICY "Users can insert own withdraw" ON public.withdraw_requests
  FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can view own withdraw" ON public.withdraw_requests;
CREATE POLICY "Users can view own withdraw" ON public.withdraw_requests
  FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS withdrawal_requests_owner_admin_read ON public.withdrawal_requests;
CREATE POLICY withdrawal_requests_owner_admin_read ON public.withdrawal_requests
  FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = (SELECT auth.uid())
        AND lower(coalesce(p.role, '')) = 'admin'
    )
  );

-- This public aggregate-only landing-page feed is intentionally retained: it
-- returns bounded game counts only and never exposes PII, bets, or balances.
COMMENT ON FUNCTION public.nplus_recent_demo_activity(integer) IS
  'Intentionally public aggregate-only landing-page feed; returns game_key and activity_count only, with p_window_minutes clamped to 5..1440. No user identifiers, individual bets, balances, or personal data.';
