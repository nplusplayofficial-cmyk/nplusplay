-- SECURITY CANDIDATE ONLY — NOT A PRODUCTION MIGRATION.
-- Keep outside supabase/migrations until Work #1 migration source/replay review passes.
-- Apply only in an isolated staging database first; verify admin save, public QR read,
-- and non-admin denial before promoting through the reviewed migration chain.

BEGIN;

-- Keep payment recipient details publicly readable for the Deposit page, but only
-- authenticated admins may change them. Remove excess direct table privileges first.
REVOKE ALL PRIVILEGES ON TABLE public.payment_settings FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.payment_settings TO anon, authenticated;
GRANT UPDATE ON TABLE public.payment_settings TO authenticated;

DROP POLICY IF EXISTS "Allow admin update" ON public.payment_settings;
DROP POLICY IF EXISTS payment_settings_admin_update ON public.payment_settings;

CREATE POLICY payment_settings_admin_update
ON public.payment_settings
AS PERMISSIVE
FOR UPDATE
TO authenticated
USING (public.nplus_is_admin())
WITH CHECK (public.nplus_is_admin());

-- These legacy tables have policies for signed-in owners/admin UI only, not anonymous
-- callers. Remove unused anonymous/public table grants as defense in depth while
-- preserving the existing authenticated policies and privileges.
REVOKE ALL PRIVILEGES ON TABLE
  public.manual_deposits,
  public.user_bank_details,
  public.withdraw_requests
FROM PUBLIC, anon;

-- Only admins may add a payment QR object. Public object reads remain enabled so the
-- customer Deposit page can display the published QR image.
DROP POLICY IF EXISTS "Admin Upload" ON storage.objects;
DROP POLICY IF EXISTS payment_qr_admin_upload ON storage.objects;

CREATE POLICY payment_qr_admin_upload
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'payment_qr'
  AND public.nplus_is_admin()
);

-- The current QR upload page accepts image files. Limit abuse and disallow active
-- SVG/HTML content in this public bucket. PNG/JPEG/WebP are supported.
DO $bucket_limit$
BEGIN
  UPDATE storage.buckets
     SET file_size_limit = 5242880,
         allowed_mime_types = ARRAY['image/png', 'image/jpeg', 'image/webp']::text[]
   WHERE id = 'payment_qr';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Required storage bucket payment_qr was not found';
  END IF;
END
$bucket_limit$;

COMMIT;

-- Required staging regression:
-- 1. anon can SELECT payment_settings but cannot UPDATE/INSERT/DELETE it.
-- 2. authenticated non-admin cannot change payment_settings.
-- 3. authenticated admin can UPDATE id=1 and upload a PNG/JPEG/WebP QR under 5 MiB.
-- 4. authenticated non-admin upload to payment_qr is rejected by Storage RLS.
-- 5. Deposit page can still read/display the public QR.
