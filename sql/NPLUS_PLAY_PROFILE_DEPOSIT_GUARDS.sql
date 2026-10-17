-- N+ PLAY profile-role / demo-deposit safeguards (review before running).
-- The equivalent live hardening was applied on 2026-10-15 after a verified custom-format backup.
-- See sql/NPLUS_PLAY_LIVE_HARDENING_2026-10-15.sql for the full live migration.
-- This file is a small standalone variant, not a complete game-settlement fix.

BEGIN;

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
FOR EACH ROW
EXECUTE FUNCTION public.nplus_guard_profile_role_update();

-- The stricter existing INSERT policy already requires the request owner, a positive
-- amount, and status='pending'. Remove the duplicate weaker policy.
DROP POLICY IF EXISTS users_insert_own_deposit_requests ON public.deposit_requests;

COMMIT;

-- Never run on production without a verified backup and policy review.
-- This does NOT prevent arbitrary positive GAME_WIN deltas in nplus_wallet_change.
