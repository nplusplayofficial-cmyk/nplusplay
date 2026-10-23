-- Remove standalone duplicate unique indexes while preserving the primary key
-- and constraint-backed unique index that continue enforcing the same keys.
-- Applied to live Supabase project pcrxlqduygvzchzxsmdv on 2026-10-23.
DROP INDEX IF EXISTS public.nplus_demo_referral_codes_user_uidx;
DROP INDEX IF EXISTS public.nplus_demo_referrals_referred_uidx;
