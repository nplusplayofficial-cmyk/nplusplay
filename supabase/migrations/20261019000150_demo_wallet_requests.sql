-- N+ PLAY demo-only deposit/withdrawal requests.
-- Candidate-only SQL. Test on an isolated database; don't run against production without separate release approval.
-- Withdrawal review changes request status only: it never deducts credits or makes a cash payout.
BEGIN;
ALTER TABLE public.deposit_requests
 ADD COLUMN IF NOT EXISTS request_token uuid,
 ADD COLUMN IF NOT EXISTS payment_method text NOT NULL DEFAULT 'DEMO_CREDIT',
 ADD COLUMN IF NOT EXISTS request_note text;
DO $migration$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM pg_constraint WHERE conname='deposit_requests_demo_method_check' AND conrelid='public.deposit_requests'::regclass) THEN
  ALTER TABLE public.deposit_requests ADD CONSTRAINT deposit_requests_demo_method_check CHECK(payment_method='DEMO_CREDIT');
 END IF;
END
$migration$;
CREATE UNIQUE INDEX IF NOT EXISTS deposit_requests_user_request_token_uidx ON public.deposit_requests(user_id,request_token) WHERE request_token IS NOT NULL;
CREATE TABLE IF NOT EXISTS public.withdrawal_requests(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
 amount numeric(12,2) NOT NULL CHECK(amount>0 AND amount<=100000),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','rejected')),
 request_token uuid NOT NULL, request_note text, review_note text,
 created_at timestamptz NOT NULL DEFAULT clock_timestamp(), reviewed_at timestamptz,
 reviewed_by uuid REFERENCES auth.users(id),
 CONSTRAINT withdrawal_requests_user_token_key UNIQUE(user_id,request_token),
 CONSTRAINT withdrawal_requests_review_state_check CHECK(
  (status='pending' AND reviewed_at IS NULL AND reviewed_by IS NULL)
  OR (status IN ('approved','rejected') AND reviewed_at IS NOT NULL AND reviewed_by IS NOT NULL))
);
CREATE UNIQUE INDEX IF NOT EXISTS withdrawal_requests_one_pending_per_user_uidx ON public.withdrawal_requests(user_id) WHERE status='pending';
ALTER TABLE public.withdrawal_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS withdrawal_requests_owner_admin_read ON public.withdrawal_requests;
CREATE POLICY withdrawal_requests_owner_admin_read ON public.withdrawal_requests FOR SELECT TO authenticated USING(user_id=auth.uid() OR EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=auth.uid() AND lower(coalesce(p.role,''))='admin'));
REVOKE ALL ON TABLE public.withdrawal_requests FROM PUBLIC,anon,authenticated;
GRANT SELECT ON TABLE public.withdrawal_requests TO authenticated;
REVOKE INSERT ON TABLE public.deposit_requests FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.nplus_create_demo_deposit_request(p_amount numeric,p_request_token uuid,p_request_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $function$
DECLARE v_user_id uuid:=auth.uid(); v_amount numeric(12,2):=round(coalesce(p_amount,0),2); v_id uuid; v_existing_amount numeric; v_status text; v_note text:=left(trim(coalesce(p_request_note,'')),180);
BEGIN
 IF v_user_id IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
 IF p_request_token IS NULL THEN RAISE EXCEPTION 'Request token is required.'; END IF;
 IF v_amount<100 OR v_amount>50000 THEN RAISE EXCEPTION 'Demo deposit amount must be between 100 and 50000 credits.'; END IF;
 INSERT INTO public.deposit_requests(user_id,amount,status,created_at,request_token,payment_method,request_note)
 VALUES(v_user_id,v_amount,'pending',clock_timestamp(),p_request_token,'DEMO_CREDIT',nullif(v_note,''))
 ON CONFLICT(user_id,request_token) WHERE request_token IS NOT NULL DO NOTHING RETURNING id INTO v_id;
 IF v_id IS NULL THEN
  SELECT id,amount,status INTO v_id,v_existing_amount,v_status FROM public.deposit_requests WHERE user_id=v_user_id AND request_token=p_request_token;
  IF NOT FOUND THEN RAISE EXCEPTION 'Could not recover the existing request.'; END IF;
  IF round(v_existing_amount,2)<>v_amount THEN RAISE EXCEPTION 'Request token was already used with a different amount.'; END IF;
  RETURN jsonb_build_object('success',true,'request_id',v_id,'amount',v_amount,'status',v_status,'duplicate_request',true,'wallet_changed',false,'message','Demo request recovered; no credits were added.');
 END IF;
 RETURN jsonb_build_object('success',true,'request_id',v_id,'amount',v_amount,'status','pending','duplicate_request',false,'wallet_changed',false,'message','Demo request submitted for review; no credits were added.');
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_create_demo_withdrawal_request(p_amount numeric,p_request_token uuid,p_request_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $function$
DECLARE v_user_id uuid:=auth.uid(); v_amount numeric(12,2):=round(coalesce(p_amount,0),2); v_balance numeric; v_id uuid; v_existing_amount numeric; v_status text; v_note text:=left(trim(coalesce(p_request_note,'')),180);
BEGIN
 IF v_user_id IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
 IF p_request_token IS NULL THEN RAISE EXCEPTION 'Request token is required.'; END IF;
 IF v_amount<=0 OR v_amount>100000 THEN RAISE EXCEPTION 'Invalid demo request amount.'; END IF;
 SELECT balance INTO v_balance FROM public.demo_wallets WHERE user_id=v_user_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Demo wallet not found.'; END IF;
 IF v_amount>v_balance THEN RAISE EXCEPTION 'Request exceeds the current demo balance.'; END IF;
 INSERT INTO public.withdrawal_requests(user_id,amount,status,request_token,request_note)
 VALUES(v_user_id,v_amount,'pending',p_request_token,coalesce(nullif(v_note,''),'Demo-only request; no cash payout.'))
 ON CONFLICT DO NOTHING RETURNING id INTO v_id;
 IF v_id IS NULL THEN
  SELECT id,amount,status INTO v_id,v_existing_amount,v_status FROM public.withdrawal_requests WHERE user_id=v_user_id AND request_token=p_request_token;
  IF FOUND THEN
   IF round(v_existing_amount,2)<>v_amount THEN RAISE EXCEPTION 'Request token was already used with a different amount.'; END IF;
   RETURN jsonb_build_object('success',true,'request_id',v_id,'amount',v_amount,'status',v_status,'duplicate_request',true,'wallet_changed',false,'cash_paid',false);
  END IF;
  RAISE EXCEPTION 'A pending demo request already exists. Resolve it before creating another.';
 END IF;
 RETURN jsonb_build_object('success',true,'request_id',v_id,'amount',v_amount,'status','pending','duplicate_request',false,'wallet_changed',false,'cash_paid',false,'message','Demo-only request submitted; no credits were deducted and no cash will be paid.');
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_admin_resolve_demo_withdrawal(p_request_id uuid,p_decision text,p_review_note text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public AS $function$
DECLARE v_admin_id uuid:=auth.uid(); v_role text; v_request public.withdrawal_requests%rowtype; v_decision text:=lower(trim(coalesce(p_decision,'')));
BEGIN
 IF v_admin_id IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
 SELECT lower(coalesce(role,'')) INTO v_role FROM public.profiles WHERE id=v_admin_id;
 IF coalesce(v_role,'')<>'admin' THEN RAISE EXCEPTION 'Admin access required.'; END IF;
 IF p_request_id IS NULL THEN RAISE EXCEPTION 'Request ID is required.'; END IF;
 IF v_decision NOT IN ('approved','rejected') THEN RAISE EXCEPTION 'Decision must be approved or rejected.'; END IF;
 SELECT * INTO v_request FROM public.withdrawal_requests WHERE id=p_request_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Demo withdrawal request not found.'; END IF;
 IF v_request.status<>'pending' THEN RAISE EXCEPTION 'Request has already been reviewed.'; END IF;
 UPDATE public.withdrawal_requests SET status=v_decision,reviewed_at=clock_timestamp(),reviewed_by=v_admin_id,review_note=left(trim(coalesce(p_review_note,'')),180) WHERE id=p_request_id;
 RETURN jsonb_build_object('success',true,'request_id',p_request_id,'status',v_decision,'wallet_changed',false,'cash_paid',false,'message','Demo review completed only; no cash payout and no wallet change.');
END;
$function$;
REVOKE ALL ON FUNCTION public.nplus_create_demo_deposit_request(numeric,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_create_demo_deposit_request(numeric,uuid,text) TO authenticated;
REVOKE ALL ON FUNCTION public.nplus_create_demo_withdrawal_request(numeric,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_create_demo_withdrawal_request(numeric,uuid,text) TO authenticated;
REVOKE ALL ON FUNCTION public.nplus_admin_resolve_demo_withdrawal(uuid,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.nplus_admin_resolve_demo_withdrawal(uuid,text,text) TO authenticated;
COMMIT;
