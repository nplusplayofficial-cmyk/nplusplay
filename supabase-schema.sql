-- N+ PLAY CORE SCHEMA
-- Virtual-credit/demo platform only.
-- Do not use these tables as a real-money payment/wagering ledger.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  uid text unique not null,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.demo_wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  balance numeric(18,2) not null default 1000.00,
  updated_at timestamptz not null default now()
);

create table if not exists public.demo_wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  delta numeric(18,2) not null,
  balance_before numeric(18,2) not null,
  balance_after numeric(18,2) not null,
  type text not null,
  source text,
  note text,
  created_at timestamptz not null default now()
);

create index if not exists demo_wallet_transactions_user_created_idx
on public.demo_wallet_transactions(user_id, created_at desc);

alter table public.profiles enable row level security;
alter table public.demo_wallets enable row level security;
alter table public.demo_wallet_transactions enable row level security;

create policy "profiles own row"
on public.profiles for select
using (auth.uid() = id);

create policy "wallet own row"
on public.demo_wallets for select
using (auth.uid() = user_id);

create policy "wallet tx own rows"
on public.demo_wallet_transactions for select
using (auth.uid() = user_id);

create or replace function public.create_nplus_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  generated_uid text;
begin
  generated_uid := 'NPLUS-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 16));

  insert into public.profiles(id, uid, display_name)
  values (
    new.id,
    generated_uid,
    coalesce(new.raw_user_meta_data->>'display_name', '')
  );

  insert into public.demo_wallets(user_id, balance)
  values (new.id, 1000.00);

  return new;
end;
$$;

drop trigger if exists on_auth_user_created_nplus on auth.users;

create trigger on_auth_user_created_nplus
after insert on auth.users
for each row execute function public.create_nplus_profile();
