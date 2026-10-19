-- N+ PLAY account/profile preferences.
-- Candidate migration: test locally and in an isolated database before rollout.
-- Does not touch balances, wallet transactions, game tables, deposits or withdrawals.
begin;

-- Users may update only their display name in their own profile row.
-- Keep role, email, phone and other sensitive columns unavailable for client-side edits.
revoke update on table public.profiles from public, anon, authenticated;
grant update (display_name) on table public.profiles to authenticated;
drop policy if exists profiles_update_own_display_name on public.profiles;
create policy profiles_update_own_display_name
  on public.profiles
  for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

create table if not exists public.user_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  notification_game_results boolean not null default true,
  notification_rewards boolean not null default true,
  notification_promotions boolean not null default false,
  reduce_motion boolean not null default false,
  compact_layout boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.user_preferences enable row level security;
revoke all on table public.user_preferences from public, anon, authenticated;
grant select, insert, update on table public.user_preferences to authenticated;

drop policy if exists user_preferences_select_own on public.user_preferences;
create policy user_preferences_select_own
  on public.user_preferences
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists user_preferences_insert_own on public.user_preferences;
create policy user_preferences_insert_own
  on public.user_preferences
  for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists user_preferences_update_own on public.user_preferences;
create policy user_preferences_update_own
  on public.user_preferences
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

commit;
