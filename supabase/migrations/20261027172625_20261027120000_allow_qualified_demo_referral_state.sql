-- N+ PLAY demo referral lifecycle: allow an Admin-verified "qualified" state.
-- A qualified referral is eligibility for a virtual demo tier claim, not a paid
-- reward on the referral row. The tier reward is credited separately and once
-- through nplus_demo_claim_referral_bonus().
-- Candidate migration only. Do not deploy to production until backup/replay and
-- hosted authenticated E2E gates pass.
BEGIN;

DO $preflight$
BEGIN
  IF to_regclass('public.nplus_demo_referrals') IS NULL THEN
    RAISE EXCEPTION 'Required table public.nplus_demo_referrals is missing.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='nplus_demo_referrals'
      AND column_name='status'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='nplus_demo_referrals'
      AND column_name='reward_amount'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='nplus_demo_referrals'
      AND column_name='qualifying_request_id'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='nplus_demo_referrals'
      AND column_name='qualified_at'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='nplus_demo_referrals'
      AND column_name='rewarded_at'
  ) THEN
    RAISE EXCEPTION 'Required referral lifecycle columns are missing; inspect schema lineage before applying this candidate migration.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.nplus_demo_referrals
    WHERE NOT (
      (status='pending'
        AND qualifying_request_id IS NULL
        AND qualified_at IS NULL
        AND rewarded_at IS NULL)
      OR (status='qualified'
        AND qualifying_request_id IS NULL
        AND qualified_at IS NOT NULL
        AND rewarded_at IS NULL
        AND reward_amount = 0.00)
      OR (status='rewarded'
        AND qualifying_request_id IS NOT NULL
        AND qualified_at IS NOT NULL
        AND rewarded_at IS NOT NULL)
    )
  ) THEN
    RAISE EXCEPTION 'Existing referral row does not match pending/qualified/rewarded lifecycle contract; inspect rows before replacing the constraints.';
  END IF;
END
$preflight$;

ALTER TABLE public.nplus_demo_referrals
  DROP CONSTRAINT IF EXISTS nplus_demo_referrals_status_check,
  DROP CONSTRAINT IF EXISTS nplus_demo_referrals_reward_state_check;

ALTER TABLE public.nplus_demo_referrals
  ADD CONSTRAINT nplus_demo_referrals_status_check
  CHECK (status IN ('pending','qualified','rewarded'));

ALTER TABLE public.nplus_demo_referrals
  ADD CONSTRAINT nplus_demo_referrals_reward_state_check
  CHECK (
    (status='pending'
      AND qualifying_request_id IS NULL
      AND qualified_at IS NULL
      AND rewarded_at IS NULL)
    OR
    (status='qualified'
      AND qualifying_request_id IS NULL
      AND qualified_at IS NOT NULL
      AND rewarded_at IS NULL
      AND reward_amount = 0.00)
    OR
    (status='rewarded'
      AND qualifying_request_id IS NOT NULL
      AND qualified_at IS NOT NULL
      AND rewarded_at IS NOT NULL)
  );

COMMENT ON CONSTRAINT nplus_demo_referrals_status_check
  ON public.nplus_demo_referrals IS
  'Allowed lifecycle states: pending, Admin-qualified for a virtual tier, or rewarded.';

COMMENT ON CONSTRAINT nplus_demo_referrals_reward_state_check
  ON public.nplus_demo_referrals IS
  'Qualified means Admin-verified tier eligibility only; virtual tier rewards are separately claimed once.';

COMMIT;
