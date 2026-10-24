
BEGIN;

-- Emergency release-safety gate: keep game UI/backend entry points paused
-- until authenticated end-to-end settlement tests are completed.
UPDATE public.game_settings
SET enabled = false
WHERE upper(game_key) IN ('WINGO','K3','5D','TRX','AVIATOR','MOTO');

-- Settlement is a shared round operation. It must not be callable by arbitrary
-- authenticated players; these routines must be invoked by trusted service jobs.
REVOKE EXECUTE ON FUNCTION public.nplus_wingo_demo_settle_round(integer,bigint)
  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.nplus_moto_demo_settle_round(bigint)
  FROM PUBLIC, anon, authenticated;

-- The public homepage currently uses this read-only aggregate feed. It contains
-- only game key + aggregate counts; grant remains intentional for anon visitors.
-- No phone lookup permission is reintroduced.
COMMIT;
