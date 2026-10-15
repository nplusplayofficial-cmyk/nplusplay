-- N+ PLAY profile-role / demo-deposit safeguards (review before running).
-- Run only after a verified database backup and review of existing RLS policies.
-- This does not solve client-controlled game win credits in nplus_wallet_change.

BEGIN;

CREATE OR REPLACE FUNCTION public.nplus_guard_profile_role_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $function$
DECLARE
    v_actor_id uuid;
    v_actor_role text;
BEGIN
    IF NEW.role IS DISTINCT FROM OLD.role THEN
        v_actor_id := auth.uid();
        IF v_actor_id IS NOT NULL THEN
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

-- The existing stricter policy deposit_requests_insert requires own user_id, positive
-- amount, and status='pending'. Remove the duplicate weaker policy that only checks owner/status.
DROP POLICY IF EXISTS users_insert_own_deposit_requests ON public.deposit_requests;

DO $block$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'public.deposit_requests'::regclass
          AND conname = 'nplus_deposit_amount_positive_check'
    ) THEN
        ALTER TABLE public.deposit_requests
          ADD CONSTRAINT nplus_deposit_amount_positive_check
          CHECK (amount IS NOT NULL AND amount > 0) NOT VALID;
    END IF;
END;
$block$;

COMMIT;

-- Verify with read-only queries after applying:
-- SELECT tgname FROM pg_trigger WHERE tgrelid='public.profiles'::regclass AND NOT tgisinternal;
-- SELECT policyname, cmd, with_check FROM pg_policies
--   WHERE schemaname='public' AND tablename='deposit_requests';
-- SELECT conname, convalidated FROM pg_constraint
--   WHERE conrelid='public.deposit_requests'::regclass
--     AND conname='nplus_deposit_amount_positive_check';
