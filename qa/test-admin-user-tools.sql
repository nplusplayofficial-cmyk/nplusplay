\set ON_ERROR_STOP on

-- Isolated database only. The earlier QA SQL sets up auth.users, auth.uid(),
-- demo_wallets and demo_wallet_transactions in a disposable PostgreSQL 17 DB.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id),
  uid text not null unique,
  display_name text,
  email text,
  phone text,
  role text not null default 'user',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

\ir ../sql/NPLUS_PLAY_ADMIN_USER_TOOLS.sql

do $tests$
declare
  v_admin uuid := 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
  v_user uuid := 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  v_directory jsonb;
  v_ledger jsonb;
  v_credit jsonb;
  v_debit jsonb;
  v_attempt jsonb;
  v_balance numeric(12,2);
  v_count integer;
begin
  insert into auth.users(id,email)
  values
    (v_admin,'admin-qa@example.invalid'),
    (v_user,'user-qa@example.invalid');

  insert into public.profiles(id,uid,display_name,email,phone,role)
  values
    (v_admin,'QA-ADMIN','N+ Admin QA','admin-qa@example.invalid','9000000001','admin'),
    (v_user,'QA-USER','Demo User QA','user-qa@example.invalid','9000000002','user');

  insert into public.demo_wallets(user_id,balance)
  values (v_admin,108.00),(v_user,108.00);

  perform set_config('request.jwt.claim.sub',v_admin::text,true);

  v_directory := public.nplus_admin_user_directory('QA-ADMIN',200);
  if jsonb_typeof(v_directory->'rows')<>'array'
     or jsonb_array_length(v_directory->'rows')<>1
     or v_directory->'rows'->0->>'user_id'<>v_admin::text
     or v_directory->'rows'->0->>'role'<>'admin' then
    raise exception 'Admin user directory did not find the unique test admin profile.';
  end if;

  v_directory := public.nplus_admin_user_directory('QA-USER',200);
  if jsonb_typeof(v_directory->'rows')<>'array'
     or jsonb_array_length(v_directory->'rows')<>1
     or v_directory->'rows'->0->>'user_id'<>v_user::text
     or v_directory->'rows'->0->>'display_name'<>'Demo User QA'
     or (v_directory->'rows'->0->>'balance')::numeric<>108.00 then
    raise exception 'Admin directory did not return expected test user/wallet fields.';
  end if;

  v_directory := public.nplus_admin_user_directory('Demo User',200);
  if jsonb_array_length(v_directory->'rows')<>1 then
    raise exception 'Admin user search is not filtering results.';
  end if;

  v_credit := public.nplus_admin_adjust_demo_wallet(v_user,25.00,'QA manual demo credit');
  if (v_credit->>'before')::numeric<>108.00 or (v_credit->>'after')::numeric<>133.00 then
    raise exception 'Positive admin adjustment incorrect.';
  end if;

  v_debit := public.nplus_admin_adjust_demo_wallet(v_user,-8.00,'QA manual demo debit');
  if (v_debit->>'before')::numeric<>133.00 or (v_debit->>'after')::numeric<>125.00 then
    raise exception 'Negative admin adjustment incorrect.';
  end if;

  v_ledger := public.nplus_admin_user_transactions(v_user,100);
  if jsonb_typeof(v_ledger->'rows')<>'array'
     or jsonb_array_length(v_ledger->'rows')<>2 then
    raise exception 'Admin user ledger did not return two adjustment rows.';
  end if;
  if v_ledger->'rows'->0->>'type'<>'ADMIN_ADJUSTMENT'
     or coalesce(v_ledger->'rows'->0->>'note','')='' then
    raise exception 'Admin ledger is missing transaction audit details.';
  end if;

  select balance into v_balance from public.demo_wallets where user_id=v_user;
  select count(*) into v_count from public.demo_wallet_transactions
  where user_id=v_user and source='NPLUS_ADMIN';
  if v_balance<>125.00 or v_count<>2 then
    raise exception 'Wallet balance and ledger are inconsistent after adjustment.';
  end if;

  begin
    perform public.nplus_admin_adjust_demo_wallet(v_user,-200.00,'QA below zero');
    raise exception 'TEST_FAILURE: overdraw unexpectedly allowed.';
  exception when others then
    if sqlerrm not like '%Adjustment would make the virtual balance negative%' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub',v_user::text,true);
  begin
    perform public.nplus_admin_user_directory('',200);
    raise exception 'Non-admin user was able to read admin directory.';
  exception when others then
    if sqlerrm <> 'Admin access required.' then raise; end if;
  end;
  begin
    perform public.nplus_admin_user_transactions(v_user,100);
    raise exception 'Non-admin user was able to read admin ledger.';
  exception when others then
    if sqlerrm <> 'Admin access required.' then raise; end if;
  end;
  begin
    perform public.nplus_admin_adjust_demo_wallet(v_user,1.00,'QA unauthorized credit');
    raise exception 'Non-admin user was able to adjust a wallet.';
  exception when others then
    if sqlerrm <> 'Admin access required.' then raise; end if;
  end;

  if has_function_privilege('anon','public.nplus_admin_user_directory(text,integer)','EXECUTE')
     or has_function_privilege('anon','public.nplus_admin_user_transactions(uuid,integer)','EXECUTE')
     or has_function_privilege('anon','public.nplus_admin_adjust_demo_wallet(uuid,numeric,text)','EXECUTE') then
    raise exception 'Anonymous EXECUTE was granted on admin user functions.';
  end if;
  if not has_function_privilege('authenticated','public.nplus_admin_user_directory(text,integer)','EXECUTE')
     or not has_function_privilege('authenticated','public.nplus_admin_user_transactions(uuid,integer)','EXECUTE')
     or not has_function_privilege('authenticated','public.nplus_admin_adjust_demo_wallet(uuid,numeric,text)','EXECUTE') then
    raise exception 'Signed-in EXECUTE grants missing; admin role check must occur in the RPC.';
  end if;

  perform set_config('request.jwt.claim.sub','',true);
  begin
    perform public.nplus_admin_user_directory('',200);
    raise exception 'Unauthenticated call was allowed.';
  exception when others then
    if sqlerrm <> 'Authentication required.' then raise; end if;
  end;

  raise notice 'N+ ADMIN user tools tests passed.';
end
$tests$;
