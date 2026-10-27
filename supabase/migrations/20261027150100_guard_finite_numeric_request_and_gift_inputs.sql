-- Split finite-numeric RPC hardening migration.
-- Candidate logic was tested in isolated PostgreSQL and the full local replay.
-- No wallet balances or user rows are rewritten; only RPC function bodies are replaced.
BEGIN;

CREATE OR REPLACE FUNCTION public.nplus_create_demo_deposit_request(p_amount numeric, p_request_token uuid, p_request_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_user_id uuid:=auth.uid(); v_amount numeric(12,2); v_id uuid; v_existing_amount numeric; v_status text; v_note text:=left(trim(coalesce(p_request_note,'')),180);
BEGIN
 IF v_user_id IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
 IF p_request_token IS NULL THEN RAISE EXCEPTION 'Request token is required.'; END IF;
 IF p_amount IS NULL OR p_amount::text IN ('NaN','Infinity','-Infinity') THEN RAISE EXCEPTION 'Demo deposit amount must be finite.'; END IF;
 v_amount:=round(p_amount,2);
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

CREATE OR REPLACE FUNCTION public.nplus_create_demo_withdrawal_request(p_amount numeric, p_request_token uuid, p_request_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE v_user_id uuid:=auth.uid(); v_amount numeric(12,2); v_balance numeric; v_id uuid; v_existing_amount numeric; v_status text; v_note text:=left(trim(coalesce(p_request_note,'')),180);
BEGIN
 IF v_user_id IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
 IF p_request_token IS NULL THEN RAISE EXCEPTION 'Request token is required.'; END IF;
 IF p_amount IS NULL OR p_amount::text IN ('NaN','Infinity','-Infinity') THEN RAISE EXCEPTION 'Demo withdrawal request amount must be finite.'; END IF;
 v_amount:=round(p_amount,2);
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

CREATE OR REPLACE FUNCTION public.nplus_demo_admin_create_gift_code(p_code text, p_amount numeric, p_max_claims integer DEFAULT 1000, p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_code text := upper(trim(coalesce(p_code,'')));
  v_actor uuid := auth.uid();
BEGIN
  IF NOT coalesce(public.nplus_is_admin(),false) THEN RAISE EXCEPTION 'Administrator access required.' USING ERRCODE='42501'; END IF;
  IF v_code !~ '^[A-Z0-9_-]{4,24}$' THEN
    RETURN jsonb_build_object('success',false,'reason','invalid_code','message','Use 4–24 letters, digits, underscores, or hyphens.');
  END IF;
  IF p_amount IS NULL OR p_amount::text IN ('NaN','Infinity','-Infinity') OR p_amount <= 0 OR p_amount > 1000000 OR p_amount <> round(p_amount,2) THEN
    RETURN jsonb_build_object('success',false,'reason','invalid_amount','message','Enter a positive demo amount up to 1,000,000.');
  END IF;
  IF coalesce(p_max_claims,0) < 1 OR p_max_claims > 1000000 THEN
    RETURN jsonb_build_object('success',false,'reason','invalid_limit','message','Claim limit must be between 1 and 1,000,000.');
  END IF;
  INSERT INTO public.nplus_demo_gift_codes(code,amount,active,max_claims,expires_at,created_by)
  VALUES(v_code,p_amount,true,p_max_claims,p_expires_at,v_actor);
  RETURN jsonb_build_object('success',true,'code',v_code,'amount',p_amount,'max_claims',p_max_claims);
EXCEPTION WHEN unique_violation THEN
  RETURN jsonb_build_object('success',false,'reason','already_exists','message','That gift code already exists.');
END;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_approve_deposit(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  v_admin_id uuid := auth.uid();
  v_role text;
  v_request public.deposit_requests%rowtype;
  v_before numeric(12,2);
  v_after numeric(12,2);
begin
  if v_admin_id is null then
    raise exception 'Authentication required.';
  end if;

  select lower(coalesce(p.role, ''))
  into v_role
  from public.profiles p
  where p.id = v_admin_id;

  if coalesce(v_role, '') <> 'admin' then
    raise exception 'Admin access required.';
  end if;

  if p_request_id is null then
    raise exception 'Deposit request ID is required.';
  end if;

  select *
  into v_request
  from public.deposit_requests
  where id = p_request_id
  for update;

  if not found then
    raise exception 'Deposit request not found.';
  end if;

  if v_request.status <> 'pending' then
    raise exception 'Request has already been reviewed.';
  end if;

  if v_request.amount is null or v_request.amount::text IN ('NaN','Infinity','-Infinity') or v_request.amount < 100 or v_request.amount > 50000 then
    raise exception 'Deposit request amount is invalid.';
  end if;

  select w.balance
  into v_before
  from public.demo_wallets w
  where w.user_id = v_request.user_id
  for update;

  if not found then
    raise exception 'User wallet not found.';
  end if;

  v_after := v_before + round(v_request.amount, 2);

  update public.demo_wallets
  set balance = v_after,
      updated_at = clock_timestamp()
  where user_id = v_request.user_id;

  insert into public.demo_wallet_transactions(
    user_id, delta, balance_before, balance_after, type, source, note
  )
  values(
    v_request.user_id,
    round(v_request.amount, 2),
    v_before,
    v_after,
    'credit',
    'admin_deposit',
    'Virtual deposit request approved by admin'
  );

  update public.deposit_requests
  set status = 'approved',
      reviewed_at = clock_timestamp(),
      reviewed_by = v_admin_id
  where id = v_request.id;

  return jsonb_build_object(
    'success', true,
    'request_id', v_request.id,
    'amount', round(v_request.amount, 2),
    'balance_before', v_before,
    'balance_after', v_after
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_gift_redeem(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_code text := upper(trim(coalesce(p_code,'')));
  v_amount numeric(12,2);
  v_max integer;
  v_count integer;
  v_expires timestamptz;
  v_before numeric(14,2);
  v_after numeric(14,2);
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentication required.'; END IF;
  IF v_code = '' THEN RETURN jsonb_build_object('success',false,'reason','invalid_code','message','Enter a gift code.'); END IF;

  SELECT amount, max_claims, claims_count, expires_at
    INTO v_amount, v_max, v_count, v_expires
    FROM public.nplus_demo_gift_codes
   WHERE code = v_code AND active = true
   FOR UPDATE;

  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'reason','not_found','message','Gift code is invalid or inactive.'); END IF;
  IF v_amount IS NULL OR v_amount::text IN ('NaN','Infinity','-Infinity')
     OR v_amount <= 0 OR v_amount > 1000000 THEN
    RETURN jsonb_build_object('success',false,'reason','invalid_amount','message','The stored demo gift amount is invalid.');
  END IF;
  IF v_expires IS NOT NULL AND v_expires <= now() THEN
    RETURN jsonb_build_object('success',false,'reason','expired','message','This demo gift code has expired.');
  END IF;
  IF v_count >= v_max THEN RETURN jsonb_build_object('success',false,'reason','fully_claimed','message','This demo gift code has reached its claim limit.'); END IF;

  INSERT INTO public.nplus_demo_gift_claims(user_id, code, amount)
  VALUES (v_actor, v_code, v_amount)
  ON CONFLICT (user_id, code) DO NOTHING;

  IF NOT FOUND THEN RETURN jsonb_build_object('success',false,'reason','already_claimed','message','This code was already redeemed on this account.'); END IF;

  UPDATE public.nplus_demo_gift_codes SET claims_count = claims_count + 1 WHERE code = v_code;

  INSERT INTO public.demo_wallets(user_id, balance) VALUES (v_actor, 0)
  ON CONFLICT (user_id) DO NOTHING;
  UPDATE public.demo_wallets SET balance = balance + v_amount, updated_at = now()
    WHERE user_id = v_actor RETURNING balance - v_amount, balance INTO v_before, v_after;
  IF NOT FOUND THEN RAISE EXCEPTION 'Demo wallet not found.'; END IF;

  INSERT INTO public.demo_wallet_transactions(user_id,delta,balance_before,balance_after,type,source,note)
  VALUES (v_actor,v_amount,v_before,v_after,'GIFT_REWARD','GIFT',format('Demo gift code %s',v_code));

  INSERT INTO public.nplus_demo_vip_state(user_id,experience_points)
  VALUES (v_actor,v_amount::bigint)
  ON CONFLICT (user_id) DO UPDATE
    SET experience_points = public.nplus_demo_vip_state.experience_points + EXCLUDED.experience_points,
        updated_at = now();

  RETURN jsonb_build_object('success',true,'code',v_code,'amount',v_amount,
    'wallet_balance',v_after,'message',format('Added %s virtual demo points.',v_amount));
END;
$function$;

COMMIT;
