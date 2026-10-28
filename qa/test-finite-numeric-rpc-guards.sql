\set ON_ERROR_STOP on
-- Disposable PostgreSQL semantic regression for the explicit finite numeric guard.
CREATE OR REPLACE FUNCTION public.nplus_test_finite_numeric(p_value numeric)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  IF p_value IS NULL OR p_value::text IN ('NaN','Infinity','-Infinity') THEN RETURN false; END IF;
  RETURN true;
END;
$$;
DO $tests$
BEGIN
  IF public.nplus_test_finite_numeric('NaN'::numeric)
     OR public.nplus_test_finite_numeric('Infinity'::numeric)
     OR public.nplus_test_finite_numeric('-Infinity'::numeric)
     OR public.nplus_test_finite_numeric(NULL::numeric) THEN
    RAISE EXCEPTION 'FAIL: NaN/Infinity/NULL accepted';
  END IF;
  IF NOT public.nplus_test_finite_numeric(0.01)
     OR NOT public.nplus_test_finite_numeric(500.00)
     OR NOT public.nplus_test_finite_numeric(100000.00) THEN
    RAISE EXCEPTION 'FAIL: finite numeric rejected';
  END IF;
  IF ('NaN'::numeric < 1) OR ('NaN'::numeric > 100000)
     OR ('NaN'::numeric <> round('NaN'::numeric,2)) THEN
    RAISE NOTICE 'PostgreSQL NaN bypasses ordinary range/precision checks as expected.';
  ELSE
    RAISE NOTICE 'Numeric comparison semantics differ; reassess the guard requirement.';
  END IF;
  RAISE NOTICE 'PASS: NaN, ±Infinity, NULL rejected; finite amounts accepted.';
END
$tests$;
SELECT 'PASS: finite numeric guard semantics' AS result;
