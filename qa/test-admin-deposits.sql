\set ON_ERROR_STOP on

create table if not exists public.deposit_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  amount numeric(12,2) not null check (amount > 0),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id)
);

\ir ../sql/NPLUS_PLAY_ADMIN_DEPOSIT_ACTIONS.sql

do $tests$
declare
  v_admin uuid := '12121212-1212-4121-8121-121212121212';
  v_user uuid := '23232323-2323-4232-8232-232323232323';
  v_request_approve uuid;
  v_request_reject uuid;
  v_request_pending uuid;
  v_approved jsonb;
  v_rejected jsonb;
  v_balance numeric(12,2);
  v_count integer;
  v_status text;
begin
  insert into auth.users(id,email)
  values
    (v_admin,'deposit-admin-qa@example.invalid'),
    (v_user,'deposit-user-qa@example.invalid');

  insert into public.profiles(id,uid,display_name,email,phone,role)
  values
    (v_admin,'QA-DEP-ADMIN','Deposit Admin QA','deposit-admin-qa@example.invalid','9000000011','admin'),
    (v_user,'QA-DEP-USER','Deposit User QA','deposit-user-qa@example.invalid','9000000012','user');

  insert into public.demo_wallets(user_id,balance) values(v_user,108.00);

  insert into public.deposit_requests(user_id,amount,status)
  values(v_user,25.00,'pending') returning id into v_request_approve;
  insert into public.deposit_requests(user_id,amount,status)
  values(v_user,50.00,'pending') returning id into v_request_reject;
  insert into public.deposit_requests(user_id,amount,status)
  values(v_user,15.00,'pending') returning id into v_request_pending;

  perform set_config('request.jwt.claim.sub',v_admin::text,true);

  v_approved := public.nplus_approve_deposit(v_request_approve);
  if coalesce((v_approved->>'success')::boolean,false) is not true
     or (v_approved->>'balance_before')::numeric<>108.00
     or (v_approved->>'balance_after')::numeric<>133.00 then
    raise exception 'Deposit approval did not credit the exact requested amount.';
  end if;

  select balance into v_balance from public.demo_wallets where user_id=v_user;
  select status into v_status from public.deposit_requests where id=v_request_approve;
  select count(*) into v_count from public.demo_wallet_transactions
  where user_id=v_user and source='admin_deposit' and delta=25.00;
  if v_balance<>133.00 or v_status<>'approved' or v_count<>1 then
    raise exception 'Approved deposit wallet/status/ledger are inconsistent.';
  end if;

  begin
    perform public.nplus_approve_deposit(v_request_approve);
    raise exception 'TEST_FAILURE: deposit was approved twice.';
  exception when others then
    if sqlerrm not like '%Request has already been reviewed%' then raise; end if;
  end;

  v_rejected := public.nplus_reject_deposit(v_request_reject);
  select balance into v_balance from public.demo_wallets where user_id=v_user;
  select status into v_status from public.deposit_requests where id=v_request_reject;
  select count(*) into v_count from public.demo_wallet_transactions
  where user_id=v_user and source='admin_deposit' and delta=50.00;
  if v_rejected->>'status'<>'rejected' or v_balance<>133.00
     or v_status<>'rejected' or v_count<>0 then
    raise exception 'Rejected deposit changed wallet balance or created a credit ledger row.';
  end if;

  perform set_config('request.jwt.claim.sub',v_user::text,true);

  begin
    perform public.nplus_approve_deposit(v_request_pending);
    raise exception 'TEST_FAILURE: non-admin approved a deposit.';
  exception when others then
    if sqlerrm not like '%Admin access required%' then raise; end if;
  end;
  begin
    perform public.nplus_reject_deposit(v_request_pending);
    raise exception 'TEST_FAILURE: non-admin rejected a deposit.';
  exception when others then
    if sqlerrm not like '%Admin access required%' then raise; end if;
  end;

  select balance into v_balance from public.demo_wallets where user_id=v_user;
  select status into v_status from public.deposit_requests where id=v_request_pending;
  if v_balance<>133.00 or v_status<>'pending' then
    raise exception 'Unauthorized deposit request action changed state.';
  end if;

  if has_function_privilege('anon','public.nplus_approve_deposit(uuid)','EXECUTE')
     or has_function_privilege('anon','public.nplus_reject_deposit(uuid)','EXECUTE') then
    raise exception 'Anonymous execute is granted on admin deposit RPCs.';
  end if;
  if not has_function_privilege('authenticated','public.nplus_approve_deposit(uuid)','EXECUTE')
     or not has_function_privilege('authenticated','public.nplus_reject_deposit(uuid)','EXECUTE') then
    raise exception 'Authenticated admin deposit RPC grants are missing.';
  end if;

  perform set_config('request.jwt.claim.sub','',true);
  begin
    perform public.nplus_approve_deposit(v_request_pending);
    raise exception 'TEST_FAILURE: unauthenticated request was allowed.';
  exception when others then
    if sqlerrm not like '%Authentication required%' then raise; end if;
  end;

  raise notice 'N+ ADMIN deposit approval/rejection tests passed.';
end
$tests$;
