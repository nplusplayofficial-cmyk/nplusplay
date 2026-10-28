-- N+ PLAY legacy referral contract: one 20-point virtual reward per referred account.
-- Award only on a new approval transition for a DEMO_CREDIT request >= 200.
-- Does not back-credit historical approvals and does not modify existing wallet rows at migration time.
BEGIN;

DO $preflight$
BEGIN
  IF to_regclass('public.deposit_requests') IS NULL
     OR to_regclass('public.nplus_demo_referrals') IS NULL
     OR to_regclass('public.demo_wallets') IS NULL
     OR to_regclass('public.demo_wallet_transactions') IS NULL THEN
    RAISE EXCEPTION 'Required N+ demo referral/request/wallet tables are missing.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='deposit_requests' AND column_name='payment_method')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='deposit_requests' AND column_name='status')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='deposit_requests' AND column_name='amount')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='deposit_requests' AND column_name='user_id') THEN
    RAISE EXCEPTION 'deposit_requests must include payment_method/status/amount/user_id.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='nplus_demo_referrals' AND column_name='user_id')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='nplus_demo_referrals' AND column_name='referrer_user_id')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='nplus_demo_referrals' AND column_name='referred_user_id')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='nplus_demo_referrals' AND column_name='qualifying_request_id')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='nplus_demo_referrals' AND column_name='qualifying_request_amount')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='nplus_demo_referrals' AND column_name='reward_credits')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='nplus_demo_referrals' AND column_name='reward_amount')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='nplus_demo_referrals' AND column_name='qualified_at')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='nplus_demo_referrals' AND column_name='rewarded_at')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='nplus_demo_referrals' AND column_name='awarded_at') THEN
    RAISE EXCEPTION 'nplus_demo_referrals is missing columns required by the 200/20 lifecycle.';
  END IF;
END
$preflight$;

CREATE OR REPLACE FUNCTION public.nplus_demo_referral_apply(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_code text := upper(trim(coalesce(p_code,'')));
  v_referrer uuid;
  v_existing_referrer uuid;
  v_rows integer;
BEGIN
  IF v_actor IS NULL THEN
    RETURN jsonb_build_object('success',false,'reason','authentication_required','message','Please sign in before applying a referral code.');
  END IF;
  IF v_code='' THEN
    RETURN jsonb_build_object('success',false,'reason','invalid_code','message','No referral code was supplied.');
  END IF;

  SELECT user_id INTO v_referrer
  FROM public.nplus_demo_referral_codes
  WHERE upper(coalesce(referral_code,code))=v_code
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success',false,'reason','code_not_found','message','Referral code was not found.');
  END IF;
  IF v_referrer=v_actor THEN
    RETURN jsonb_build_object('success',false,'reason','self_referral','message','You cannot use your own referral code.');
  END IF;

  INSERT INTO public.nplus_demo_referrals
    (user_id,referrer_user_id,referred_user_id,referral_code,status,reward_amount,reward_credits,created_at)
  VALUES (v_referrer,v_referrer,v_actor,v_code,'pending',0.00,20.00,clock_timestamp())
  ON CONFLICT (referred_user_id) DO NOTHING;
  GET DIAGNOSTICS v_rows=ROW_COUNT;

  IF v_rows=1 THEN
    RETURN jsonb_build_object('success',true,'reason','attached','status','pending',
      'qualifying_virtual_credits',200,'reward_virtual_points',20,
      'message','Referral attached. An approved DEMO_CREDIT request of at least 200 virtual points triggers one 20-point demo reward.');
  END IF;

  SELECT coalesce(user_id,referrer_user_id) INTO v_existing_referrer
  FROM public.nplus_demo_referrals WHERE referred_user_id=v_actor;

  IF v_existing_referrer=v_referrer THEN
    RETURN jsonb_build_object('success',true,'applied',false,'already_applied',true,
      'status',(SELECT status FROM public.nplus_demo_referrals WHERE referred_user_id=v_actor),
      'message','This referral is already attached to your account.');
  END IF;
  RETURN jsonb_build_object('success',false,'reason','already_referred',
    'message','A referral is already attached to this account. It cannot be changed.');
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_award_referral_on_approved_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  v_referral_id uuid;
  v_referrer_id uuid;
  v_before numeric(18,2);
  v_after numeric(18,2);
BEGIN
  IF NEW.status IS DISTINCT FROM 'approved'
     OR OLD.status IS NOT DISTINCT FROM NEW.status
     OR NEW.payment_method IS DISTINCT FROM 'DEMO_CREDIT'
     OR NEW.amount IS NULL
     OR NEW.amount::text IN ('NaN','Infinity','-Infinity')
     OR NEW.amount < 200.00 THEN
    RETURN NEW;
  END IF;

  SELECT id,coalesce(user_id,referrer_user_id)
  INTO v_referral_id,v_referrer_id
  FROM public.nplus_demo_referrals
  WHERE referred_user_id=NEW.user_id
    AND status='pending'
  FOR UPDATE;

  IF NOT FOUND THEN RETURN NEW; END IF;

  UPDATE public.nplus_demo_referrals
  SET status='rewarded',
      qualifying_request_id=NEW.id,
      qualifying_request_amount=round(NEW.amount,2),
      reward_amount=20.00,
      reward_credits=20.00,
      qualified_at=coalesce(qualified_at,clock_timestamp()),
      rewarded_at=clock_timestamp(),
      awarded_at=clock_timestamp()
  WHERE id=v_referral_id AND status='pending'
  RETURNING coalesce(user_id,referrer_user_id) INTO v_referrer_id;

  IF NOT FOUND THEN RETURN NEW; END IF;

  SELECT balance INTO v_before
  FROM public.demo_wallets
  WHERE user_id=v_referrer_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Referrer demo wallet is missing; approval and reward must be retried after wallet repair.';
  END IF;

  v_after:=v_before+20.00;
  UPDATE public.demo_wallets SET balance=v_after,updated_at=clock_timestamp()
  WHERE user_id=v_referrer_id;

  INSERT INTO public.demo_wallet_transactions
    (user_id,delta,balance_before,balance_after,type,source,note)
  VALUES
    (v_referrer_id,20.00,v_before,v_after,'REFERRAL_REWARD','REFERRAL',
     format('One-time demo referral reward. Approved DEMO_CREDIT request %s; qualification amount %s. No cash value.',
       NEW.id,round(NEW.amount,2)));

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS nplus_demo_referral_approved_request ON public.deposit_requests;
CREATE TRIGGER nplus_demo_referral_approved_request
AFTER UPDATE OF status ON public.deposit_requests
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status='approved')
EXECUTE FUNCTION public.nplus_demo_award_referral_on_approved_request();

CREATE OR REPLACE FUNCTION public.nplus_demo_referral_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  v_actor uuid:=auth.uid();
  v_code text;
  v_payload jsonb;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  v_code:=public.nplus_demo_ensure_referral_code(v_actor);

  SELECT jsonb_build_object(
    'success',true,
    'demo_only',true,
    'referral_code',v_code,
    'referral_link','auth.html?ref='||v_code,
    'referral_count',count(*),
    'pending_count',count(*) FILTER(WHERE r.status='pending'),
    'qualified_count',count(*) FILTER(WHERE r.status='qualified'),
    'rewarded_count',count(*) FILTER(WHERE r.status='rewarded'),
    'total_rewards',coalesce(sum(r.reward_amount) FILTER(WHERE r.status='rewarded'),0),
    'qualifying_virtual_credits',200,
    'reward_virtual_points',20,
    'referrals',coalesce(jsonb_agg(jsonb_build_object(
      'uid',p.uid,
      'display_name',coalesce(nullif(p.display_name,''),'N+ member'),
      'status',r.status,
      'qualifying_virtual_amount',coalesce(q.qualifying_virtual_amount,r.qualifying_request_amount),
      'qualified_at',coalesce(q.verified_at,r.qualified_at),
      'created_at',r.created_at,
      'awarded_at',coalesce(r.awarded_at,r.rewarded_at),
      'reward_points',CASE WHEN r.status='rewarded' THEN r.reward_amount ELSE 0 END
    ) ORDER BY r.created_at DESC) FILTER(WHERE r.referred_user_id IS NOT NULL),'[]'::jsonb)
  ) INTO v_payload
  FROM public.nplus_demo_referrals r
  LEFT JOIN public.profiles p ON p.id=r.referred_user_id
  LEFT JOIN public.nplus_demo_referral_qualifications q ON q.referred_user_id=r.referred_user_id
  WHERE coalesce(r.user_id,r.referrer_user_id)=v_actor;

  IF v_payload IS NULL THEN
    RETURN jsonb_build_object('success',true,'demo_only',true,'referral_code',v_code,
      'referral_link','auth.html?ref='||v_code,'referral_count',0,'pending_count',0,
      'qualified_count',0,'rewarded_count',0,'total_rewards',0,
      'qualifying_virtual_credits',200,'reward_virtual_points',20,'referrals','[]'::jsonb);
  END IF;
  RETURN v_payload;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_referral_bonus_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
DECLARE
  v_actor uuid:=auth.uid();
  v_invited integer:=0;
  v_rewarded integer:=0;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  SELECT count(*),count(*) FILTER(WHERE status='rewarded')
  INTO v_invited,v_rewarded
  FROM public.nplus_demo_referrals
  WHERE coalesce(user_id,referrer_user_id)=v_actor;
  RETURN jsonb_build_object('success',true,'demo_only',true,
    'invited_count',v_invited,'qualified_count',v_rewarded,
    'qualification_amount',200,'reward_amount',20,
    'campaign_active',false,'tiers','[]'::jsonb,
    'notice','Single-level rule: one approved DEMO_CREDIT request of at least 200 earns the inviter 20 virtual points once. Tier claims are disabled.');
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_claim_referral_bonus(p_invitee_count integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
BEGIN
  RETURN jsonb_build_object('success',false,'reason','tier_claims_disabled',
    'message','Tiered referral claims are disabled. The approved rule is one 20-point virtual reward for a new approved DEMO_CREDIT request of at least 200.');
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_admin_qualify_referral(
  p_referred_user_id uuid,
  p_verified_virtual_amount numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
BEGIN
  IF NOT coalesce(public.nplus_is_admin(),false) THEN
    RAISE EXCEPTION 'Administrator access required.' USING ERRCODE='42501';
  END IF;
  RETURN jsonb_build_object('success',false,'reason','approval_driven',
    'message','Manual referral qualification is disabled. Only approval of a DEMO_CREDIT request of at least 200 virtual points triggers the once-only reward.');
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_admin_referrals(p_limit integer DEFAULT 100)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
BEGIN
  IF NOT coalesce(public.nplus_is_admin(),false) THEN
    RAISE EXCEPTION 'Administrator access required.' USING ERRCODE='42501';
  END IF;
  RETURN coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'referrer_uid',inviter.uid,
      'referred_uid',invitee.uid,
      'referred_user_id',r.referred_user_id,
      'referrer_user_id',coalesce(r.user_id,r.referrer_user_id),
      'referral_code',r.referral_code,
      'status',r.status,
      'reward_points',CASE WHEN r.status='rewarded' THEN r.reward_amount ELSE 0 END,
      'qualifying_virtual_amount',coalesce(q.qualifying_virtual_amount,r.qualifying_request_amount),
      'qualified_at',coalesce(q.verified_at,r.qualified_at),
      'created_at',r.created_at,
      'awarded_at',coalesce(r.awarded_at,r.rewarded_at)
    ) ORDER BY r.created_at DESC)
    FROM (
      SELECT * FROM public.nplus_demo_referrals ORDER BY created_at DESC
      LIMIT greatest(1,least(coalesce(p_limit,100),500))
    ) r
    LEFT JOIN public.profiles inviter ON inviter.id=coalesce(r.user_id,r.referrer_user_id)
    LEFT JOIN public.profiles invitee ON invitee.id=r.referred_user_id
    LEFT JOIN public.nplus_demo_referral_qualifications q ON q.referred_user_id=r.referred_user_id
  ),'[]'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_admin_vip_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public'
AS $function$
BEGIN
  IF NOT coalesce(public.nplus_is_admin(),false) THEN
    RAISE EXCEPTION 'Administrator access required.' USING ERRCODE='42501';
  END IF;
  RETURN jsonb_build_object(
    'success',true,
    'users',(SELECT count(*) FROM public.profiles WHERE lower(coalesce(role,'user'))<>'admin'),
    'referrals_total',(SELECT count(*) FROM public.nplus_demo_referrals),
    'referrals_pending',(SELECT count(*) FROM public.nplus_demo_referrals WHERE status='pending'),
    'referrals_rewarded',(SELECT count(*) FROM public.nplus_demo_referrals WHERE status='rewarded'),
    'referral_points_awarded',(SELECT coalesce(sum(reward_amount),0) FROM public.nplus_demo_referrals WHERE status='rewarded'),
    'referrals_qualified',(SELECT count(*) FROM public.nplus_demo_referral_qualifications),
    'gift_codes',(SELECT count(*) FROM public.nplus_demo_gift_codes),
    'gift_claims',(SELECT count(*) FROM public.nplus_demo_gift_claims),
    'attendance_claims',(SELECT count(*) FROM public.nplus_demo_attendance_claims),
    'notice','All rewards are virtual demo points only. One-time 200/20 referral rule is active after migration.'
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.nplus_demo_award_referral_on_approved_request() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.nplus_demo_claim_referral_bonus(integer) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.nplus_demo_referral_bonus_dashboard() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.nplus_demo_admin_qualify_referral(uuid,numeric) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.nplus_demo_referral_apply(text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.nplus_demo_referral_dashboard() FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.nplus_demo_referral_apply(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_referral_dashboard() TO authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_referral_bonus_dashboard() TO authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_demo_admin_qualify_referral(uuid,numeric) TO authenticated;

COMMIT;
