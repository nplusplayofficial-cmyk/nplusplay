-- MotoRace server-owned records. Apply before NPLUS_PLAY_MOTORACE_RPC.sql.
-- Draft only; test in an isolated database. Virtual credits only.
begin;
create table if not exists public.nplus_moto_demo_rounds (
 id uuid primary key default gen_random_uuid(),
 round_index bigint not null unique,
 starts_at timestamptz not null,
 ends_at timestamptz not null,
 status text not null default 'open' check(status in ('open','settled')),
 outcome jsonb not null,
 created_at timestamptz not null default now(),
 settled_at timestamptz,
 check(ends_at>starts_at),
 check((status='open' and settled_at is null) or (status='settled' and settled_at is not null))
);
create table if not exists public.nplus_moto_demo_bets (
 id uuid primary key default gen_random_uuid(),
 round_id uuid not null references public.nplus_moto_demo_rounds(id) on delete restrict,
 user_id uuid not null references auth.users(id) on delete restrict,
 request_id uuid not null,
 selection jsonb not null,
 stake numeric(12,2) not null check(stake>=1 and stake<=100000),
 fee numeric(12,2) not null check(fee>=0),
 amount_debited numeric(12,2) not null check(amount_debited>=stake),
 status text not null default 'pending' check(status in ('pending','won','lost')),
 payout numeric(12,2) not null default 0 check(payout>=0),
 created_at timestamptz not null default now(),
 settled_at timestamptz,
 unique(user_id,request_id),
 check((status='pending' and settled_at is null) or (status in ('won','lost') and settled_at is not null))
);
create index if not exists nplus_moto_bets_round_status_idx on public.nplus_moto_demo_bets(round_id,status);
create index if not exists nplus_moto_bets_user_created_idx on public.nplus_moto_demo_bets(user_id,created_at desc);
alter table public.nplus_moto_demo_rounds enable row level security;
alter table public.nplus_moto_demo_bets enable row level security;
revoke all on table public.nplus_moto_demo_rounds from public,anon,authenticated;
revoke all on table public.nplus_moto_demo_bets from public,anon,authenticated;
commit;
