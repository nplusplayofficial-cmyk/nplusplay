-- N+ PLAY server-authoritative WINGO demo settlement foundation.
-- Draft only: review and test in an isolated database before applying anywhere.
-- Never execute this file directly against production without explicit review.
-- Virtual credits only. This does not implement cash deposits or withdrawals.

begin;

create table if not exists public.nplus_wingo_demo_rounds (
  id uuid primary key default gen_random_uuid(),
  duration_seconds integer not null check (duration_seconds in (30, 60, 180, 300)),
  round_index bigint not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'open' check (status in ('open', 'settled')),
  outcome jsonb not null,
  created_at timestamptz not null default now(),
  settled_at timestamptz,
  unique (duration_seconds, round_index),
  check (ends_at > starts_at),
  check (
    (status = 'open' and settled_at is null)
    or (status = 'settled' and settled_at is not null)
  )
);

create table if not exists public.nplus_wingo_demo_bets (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.nplus_wingo_demo_rounds(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  request_id uuid not null,
  selection jsonb not null,
  stake numeric(12,2) not null check (stake >= 1 and stake <= 100000),
  status text not null default 'pending' check (status in ('pending', 'won', 'lost')),
  payout numeric(12,2) not null default 0 check (payout >= 0),
  created_at timestamptz not null default now(),
  settled_at timestamptz,
  unique (user_id, request_id),
  check (
    (status = 'pending' and settled_at is null)
    or (status in ('won', 'lost') and settled_at is not null)
  )
);

create index if not exists nplus_wingo_bets_round_status_idx
  on public.nplus_wingo_demo_bets (round_id, status);
create index if not exists nplus_wingo_bets_user_created_idx
  on public.nplus_wingo_demo_bets (user_id, created_at desc);

alter table public.nplus_wingo_demo_rounds enable row level security;
alter table public.nplus_wingo_demo_bets enable row level security;
revoke all on table public.nplus_wingo_demo_rounds from public, anon, authenticated;
revoke all on table public.nplus_wingo_demo_bets from public, anon, authenticated;

-- This helper is intentionally not directly executable through the client API.
create or replace function public.nplus_wingo_make_outcome()
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_number integer;
  v_color text;
  v_colors jsonb;
  v_size text;
begin
  v_number := floor(random() * 10)::integer;

  if v_number in (0, 5) then
    v_color := 'VIOLET';
  elsif v_number in (1, 3, 7, 9) then
    v_color := 'GREEN';
  else
    v_color := 'RED';
  end if;

  v_colors := case
    when v_number = 0 then jsonb_build_array('RED', 'VIOLET')
    when v_number = 5 then jsonb_build_array('GREEN', 'VIOLET')
    when v_color = 'GREEN' then jsonb_build_array('GREEN')
    else jsonb_build_array('RED')
  end;

  v_size := case when v_number >= 5 then 'Big' else 'Small' end;

  return jsonb_build_object(
    'number', v_number,
    'color', lower(v_color),
    'colorName', v_color,
    'colors', v_colors,
    'size', v_size
  );
end;
$function$;

create or replace function public.nplus_wingo_payout_multiplier(
  p_selection jsonb,
  p_outcome jsonb
)
returns numeric
language plpgsql
immutable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_type text;
  v_value text;
  v_number integer;
  v_color text;
  v_size text;
begin
  if jsonb_typeof(p_selection) <> 'object' then
    return 0;
  end if;

  v_type := lower(coalesce(p_selection->>'type', ''));
  v_value := coalesce(p_selection->>'value', '');
  v_number := (p_outcome->>'number')::integer;
  v_color := upper(coalesce(p_outcome->>'colorName', ''));
  v_size := upper(coalesce(p_outcome->>'size', ''));

  if v_type = 'number' then
    if v_value ~ '^[0-9]$' and v_value::integer = v_number then
      return 9;
    end if;
    return 0;
  elsif v_type = 'size' then
    if upper(v_value) = v_size then
      return 2;
    end if;
    return 0;
  elsif v_type = 'color' then
    if upper(v_value) = 'VIOLET' and v_number in (0, 5) then
      return 4.5;
    elsif upper(v_value) = 'GREEN' and v_number in (1, 3, 7, 9) then
      return 2;
    elsif upper(v_value) = 'GREEN' and v_number = 5 then
      return 1.5;
    elsif upper(v_value) = 'RED' and v_number in (2, 4, 6, 8) then
      return 2;
    elsif upper(v_value) = 'RED' and v_number = 0 then
      return 1.5;
    end if;
    return 0;
  end if;

  return 0;
exception when others then
  return 0;
end;
$function$;

-- Return the server's current WINGO round. The outcome is not returned to clients.
create or replace function public.nplus_wingo_demo_current_round(
  p_duration_seconds integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_now timestamptz := clock_timestamp();
  v_epoch numeric;
  v_index bigint;
  v_start timestamptz;
  v_end timestamptz;
  v_round public.nplus_wingo_demo_rounds%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  if p_duration_seconds not in (30, 60, 180, 300) then
    raise exception 'Unsupported WINGO duration.';
  end if;

  v_epoch := extract(epoch from v_now);
  v_index := floor(v_epoch / p_duration_seconds)::bigint;
  v_start := to_timestamp(v_index * p_duration_seconds);
  v_end := v_start + make_interval(secs => p_duration_seconds);

  insert into public.nplus_wingo_demo_rounds (
    duration_seconds, round_index, starts_at, ends_at, outcome
  )
  values (
    p_duration_seconds, v_index, v_start, v_end,
    public.nplus_wingo_make_outcome()
  )
  on conflict (duration_seconds, round_index) do nothing;

  select * into v_round
  from public.nplus_wingo_demo_rounds
  where duration_seconds = p_duration_seconds
    and round_index = v_index;

  return jsonb_build_object(
    'round_id', v_round.id,
    'duration_seconds', v_round.duration_seconds,
    'round_index', v_round.round_index,
    'starts_at', v_round.starts_at,
    'ends_at', v_round.ends_at,
    'status', v_round.status,
    'server_time', v_now
  );
end;
$function$;

-- Atomically records a bet and debits virtual credits. Retries using the same
-- request_id are idempotent and never debit the wallet twice.
create or replace function public.nplus_wingo_demo_place_bet(
  p_duration_seconds integer,
  p_selection jsonb,
  p_stake numeric,
  p_request_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := clock_timestamp();
  v_epoch numeric;
  v_index bigint;
  v_start timestamptz;
  v_end timestamptz;
  v_round public.nplus_wingo_demo_rounds%rowtype;
  v_bet public.nplus_wingo_demo_bets%rowtype;
  v_inserted_id uuid;
  v_stake numeric(12,2);
  v_unit_amount numeric(12,2);
  v_balance_before numeric(12,2);
  v_balance_after numeric(12,2);
  v_type text;
  v_value text;
  v_qty integer;
  v_multi integer;
  v_code text;
  v_period text;
begin
  if v_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if p_duration_seconds not in (30, 60, 180, 300) then
    raise exception 'Unsupported WINGO duration.';
  end if;
  if p_request_id is null then
    raise exception 'Request id is required.';
  end if;
  if p_selection is null or jsonb_typeof(p_selection) <> 'object' then
    raise exception 'Invalid selection.';
  end if;

  v_type := lower(coalesce(p_selection->>'type', ''));
  v_value := coalesce(p_selection->>'value', '');

  if v_type not in ('number', 'color', 'size') then
    raise exception 'Unsupported WINGO selection type.';
  end if;
  if v_type = 'number' and not (v_value ~ '^[0-9]$') then
    raise exception 'Number selection must be from 0 to 9.';
  elsif v_type = 'color' and upper(v_value) not in ('RED', 'GREEN', 'VIOLET') then
    raise exception 'Unsupported color selection.';
  elsif v_type = 'size' and upper(v_value) not in ('BIG', 'SMALL') then
    raise exception 'Unsupported size selection.';
  end if;

  if coalesce(p_selection->>'qty', '') <> ''
     and (p_selection->>'qty') !~ '^[0-9]{1,3}$' then
    raise exception 'WINGO quantity must be between 1 and 100.';
  end if;
  if coalesce(p_selection->>'multi', '') <> ''
     and (p_selection->>'multi') !~ '^[0-9]{1,3}$' then
    raise exception 'Unsupported WINGO multiplier.';
  end if;

  v_qty := coalesce(nullif(p_selection->>'qty', '')::integer, 1);
  v_multi := coalesce(nullif(p_selection->>'multi', '')::integer, 1);
  if v_qty not between 1 and 100 then
    raise exception 'WINGO quantity must be between 1 and 100.';
  end if;
  if v_multi not in (1,5,10,20,50,100) then
    raise exception 'Unsupported WINGO multiplier.';
  end if;

  if coalesce(p_selection->>'amount', '') <> '' then
    if (p_selection->>'amount') !~ '^[0-9]+([.][0-9]{1,2})?$' then
      raise exception 'Invalid WINGO unit amount.';
    end if;
    v_unit_amount := (p_selection->>'amount')::numeric(12,2);
    if v_unit_amount <= 0
       or round(v_unit_amount * v_qty * v_multi, 2) <> round(p_stake, 2) then
      raise exception 'WINGO amount, quantity and multiplier do not match the total stake.';
    end if;
  end if;

  if p_stake is null or p_stake < 1 or p_stake > 100000
     or p_stake <> round(p_stake, 2) then
    raise exception 'Demo stake must be between 1 and 100000 credits.';
  end if;
  v_stake := p_stake;

  -- Resolve retries first, including those arriving after the betting cutoff.
  select * into v_bet
  from public.nplus_wingo_demo_bets
  where user_id = v_user_id and request_id = p_request_id;

  if found then
    if v_bet.selection <> p_selection or v_bet.stake <> v_stake then
      raise exception 'Request id was already used for a different bet.';
    end if;

    select balance into v_balance_after
    from public.demo_wallets
    where user_id = v_user_id;

    return jsonb_build_object(
      'bet_id', v_bet.id,
      'round_id', v_bet.round_id,
      'round_index', (select r.round_index from public.nplus_wingo_demo_rounds r where r.id = v_bet.round_id),
      'stake', v_bet.stake,
      'balance', v_balance_after,
      'status', v_bet.status,
      'duplicate_request', true
    );
  end if;

  if not exists (
    select 1 from public.game_settings
    where game_key = 'WINGO' and enabled = true
  ) then
    raise exception 'WINGO betting is disabled by admin.';
  end if;

  v_epoch := extract(epoch from v_now);
  v_index := floor(v_epoch / p_duration_seconds)::bigint;
  v_start := to_timestamp(v_index * p_duration_seconds);
  v_end := v_start + make_interval(secs => p_duration_seconds);

  if v_now >= v_end - interval '5 seconds' then
    raise exception 'Betting is closed for this round.';
  end if;

  insert into public.nplus_wingo_demo_rounds (
    duration_seconds, round_index, starts_at, ends_at, outcome
  )
  values (
    p_duration_seconds, v_index, v_start, v_end,
    public.nplus_wingo_make_outcome()
  )
  on conflict (duration_seconds, round_index) do nothing;

  select * into v_round
  from public.nplus_wingo_demo_rounds
  where duration_seconds = p_duration_seconds
    and round_index = v_index
  for update;

  if v_round.status <> 'open' or v_now >= v_round.ends_at - interval '5 seconds' then
    raise exception 'Betting is closed for this round.';
  end if;

  insert into public.nplus_wingo_demo_bets (
    round_id, user_id, request_id, selection, stake
  )
  values (
    v_round.id, v_user_id, p_request_id, p_selection, v_stake
  )
  on conflict (user_id, request_id) do nothing
  returning id into v_inserted_id;

  if v_inserted_id is null then
    select * into v_bet
    from public.nplus_wingo_demo_bets
    where user_id = v_user_id and request_id = p_request_id;

    if v_bet.round_id <> v_round.id
       or v_bet.selection <> p_selection
       or v_bet.stake <> v_stake then
      raise exception 'Request id was already used for a different bet.';
    end if;

    select balance into v_balance_after
    from public.demo_wallets
    where user_id = v_user_id;

    return jsonb_build_object(
      'bet_id', v_bet.id,
      'round_id', v_round.id,
      'round_index', v_round.round_index,
      'stake', v_bet.stake,
      'balance', v_balance_after,
      'status', v_bet.status,
      'duplicate_request', true
    );
  end if;

  select balance into v_balance_before
  from public.demo_wallets
  where user_id = v_user_id
  for update;

  if not found then
    raise exception 'Wallet not found.';
  end if;
  if v_balance_before < v_stake then
    raise exception 'Insufficient virtual balance.';
  end if;

  v_balance_after := v_balance_before - v_stake;
  update public.demo_wallets
  set balance = v_balance_after,
      updated_at = clock_timestamp()
  where user_id = v_user_id;

  -- Preserve the existing N+ ADMIN WINGO round-report ledger format.
  v_code := case p_duration_seconds
    when 30 then '1000'
    when 60 then '2000'
    when 180 then '3000'
    when 300 then '4000'
  end;
  v_period :=
    to_char(v_round.starts_at at time zone 'Asia/Kolkata', 'YYYYMMDD')
    || v_code
    || lpad(mod(v_round.round_index, 100000)::text, 5, '0');

  insert into public.demo_wallet_transactions (
    user_id, delta, balance_before, balance_after, type, source, note
  )
  values (
    v_user_id, -v_stake, v_balance_before, v_balance_after,
    'GAME_BET', 'WINGO',
    format(
      'WINGO BET %s type=%s value=%s qty=%s multi=%s bet_id=%s',
      v_period, v_type, v_value, v_qty, v_multi, v_inserted_id
    )
  );

  return jsonb_build_object(
    'bet_id', v_inserted_id,
    'round_id', v_round.id,
    'round_index', v_round.round_index,
    'stake', v_stake,
    'balance', v_balance_after,
    'status', 'pending',
    'duplicate_request', false
  );
end;
$function$;

create or replace function public.nplus_wingo_demo_settle_round(
  p_duration_seconds integer,
  p_round_index bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := clock_timestamp();
  v_current_index bigint;
  v_start timestamptz;
  v_end timestamptz;
  v_round public.nplus_wingo_demo_rounds%rowtype;
  v_bet public.nplus_wingo_demo_bets%rowtype;
  v_multiplier numeric;
  v_credit numeric(12,2);
  v_before numeric(12,2);
  v_after numeric(12,2);
  v_result_bets jsonb := '[]'::jsonb;
  v_period text;
  v_code text;
  v_manual public.wingo_manual_results%rowtype;
  v_has_manual boolean := false;
begin
  if v_user_id is null then
    raise exception 'Authentication required.';
  end if;

  if p_duration_seconds not in (30, 60, 180, 300) then
    raise exception 'Unsupported WINGO duration.';
  end if;

  v_current_index := floor(extract(epoch from v_now) / p_duration_seconds)::bigint;
  if p_round_index is null
     or p_round_index >= v_current_index
     or p_round_index < v_current_index - 500 then
    raise exception 'Round index is invalid or outside the recent history window.';
  end if;

  v_start := to_timestamp(p_round_index * p_duration_seconds);
  v_end := v_start + make_interval(secs => p_duration_seconds);

  insert into public.nplus_wingo_demo_rounds (
    duration_seconds, round_index, starts_at, ends_at, outcome
  )
  values (
    p_duration_seconds, p_round_index, v_start, v_end,
    public.nplus_wingo_make_outcome()
  )
  on conflict (duration_seconds, round_index) do nothing;

  select * into v_round
  from public.nplus_wingo_demo_rounds
  where duration_seconds = p_duration_seconds
    and round_index = p_round_index
  for update;

  if v_now < v_round.ends_at then
    raise exception 'Round has not finished yet.';
  end if;

  if v_round.status <> 'settled' then
    -- Preserve the existing admin-controlled result feature, but resolve it
    -- inside the trusted database function rather than in browser code.
    v_code := case p_duration_seconds
      when 30 then '1000'
      when 60 then '2000'
      when 180 then '3000'
      when 300 then '4000'
    end;
    v_period :=
      to_char(v_round.starts_at at time zone 'Asia/Kolkata', 'YYYYMMDD')
      || v_code
      || lpad(mod(v_round.round_index, 100000)::text, 5, '0');

    select * into v_manual
    from public.wingo_manual_results
    where duration_seconds = p_duration_seconds
      and period = v_period
      and mode = 'MANUAL'
    order by created_at desc
    limit 1;
    v_has_manual := found;

    if v_has_manual
       and v_manual.number between 0 and 9
       and upper(coalesce(v_manual.color, '')) in ('RED', 'GREEN', 'VIOLET')
       and upper(coalesce(v_manual.size, '')) in ('BIG', 'SMALL') then
      v_round.outcome := jsonb_build_object(
        'number', v_manual.number,
        'color', lower(v_manual.color),
        'colorName', upper(v_manual.color),
        'colors', jsonb_build_array(upper(v_manual.color)),
        'size', case when upper(v_manual.size) = 'BIG' then 'Big' else 'Small' end
      );
      update public.nplus_wingo_demo_rounds
      set outcome = v_round.outcome
      where id = v_round.id;
    end if;

    for v_bet in
      select * from public.nplus_wingo_demo_bets
      where round_id = v_round.id and status = 'pending'
      order by user_id, id
      for update
    loop
      v_multiplier := public.nplus_wingo_payout_multiplier(
        v_bet.selection, v_round.outcome
      );

      if v_multiplier > 0 then
        v_credit := round(v_bet.stake * 0.98 * v_multiplier, 2);

        select balance into v_before
        from public.demo_wallets
        where user_id = v_bet.user_id
        for update;

        if not found then
          raise exception 'Wallet not found while settling bet.';
        end if;

        v_after := v_before + v_credit;

        update public.demo_wallets
        set balance = v_after, updated_at = clock_timestamp()
        where user_id = v_bet.user_id;

        insert into public.demo_wallet_transactions (
          user_id, delta, balance_before, balance_after, type, source, note
        )
        values (
          v_bet.user_id, v_credit, v_before, v_after, 'GAME_WIN', 'WINGO',
          format('WINGO server settlement %s round %s', v_bet.id, v_round.round_index)
        );

        update public.nplus_wingo_demo_bets
        set status = 'won', payout = v_credit, settled_at = clock_timestamp()
        where id = v_bet.id;
      else
        update public.nplus_wingo_demo_bets
        set status = 'lost', payout = 0, settled_at = clock_timestamp()
        where id = v_bet.id;
      end if;
    end loop;

    update public.nplus_wingo_demo_rounds
    set status = 'settled', settled_at = clock_timestamp()
    where id = v_round.id
    returning * into v_round;
  end if;

  select coalesce(
    jsonb_agg(jsonb_build_object(
      'bet_id', b.id,
      'selection', b.selection,
      'stake', b.stake,
      'status', b.status,
      'payout', b.payout,
      'settled_at', b.settled_at
    ) order by b.created_at, b.id),
    '[]'::jsonb
  )
  into v_result_bets
  from public.nplus_wingo_demo_bets b
  where b.round_id = v_round.id and b.user_id = v_user_id;

  return jsonb_build_object(
    'round_id', v_round.id,
    'duration_seconds', v_round.duration_seconds,
    'round_index', v_round.round_index,
    'status', v_round.status,
    'outcome', v_round.outcome,
    'bets', v_result_bets
  );
end;
$function$;

create or replace function public.nplus_wingo_demo_my_bets(
  p_duration_seconds integer,
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user_id uuid := auth.uid();
  v_rows jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required.';
  end if;
  if p_duration_seconds not in (30, 60, 180, 300) then
    raise exception 'Unsupported WINGO duration.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'bet_id', b.id,
    'request_id', b.request_id,
    'round_id', r.id,
    'round_index', r.round_index,
    'period', (
      to_char(r.starts_at at time zone 'Asia/Kolkata', 'YYYYMMDD')
      || case r.duration_seconds
        when 30 then '1000'
        when 60 then '2000'
        when 180 then '3000'
        when 300 then '4000'
      end
      || lpad(mod(r.round_index, 100000)::text, 5, '0')
    ),
    'starts_at', r.starts_at,
    'ends_at', r.ends_at,
    'selection', b.selection,
    'stake', b.stake,
    'status', b.status,
    'payout', b.payout,
    'created_at', b.created_at,
    'settled_at', b.settled_at,
    'outcome', case when r.status = 'settled' then r.outcome else null end
  ) order by b.created_at desc), '[]'::jsonb)
  into v_rows
  from (
    select b0.*
    from public.nplus_wingo_demo_bets b0
    join public.nplus_wingo_demo_rounds r0 on r0.id = b0.round_id
    where b0.user_id = v_user_id
      and r0.duration_seconds = p_duration_seconds
    order by b0.created_at desc
    limit least(greatest(coalesce(p_limit, 100), 1), 200)
  ) b
  join public.nplus_wingo_demo_rounds r on r.id = b.round_id;

  return v_rows;
end;
$function$;

create or replace function public.nplus_wingo_demo_history(
  p_duration_seconds integer,
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_user_id uuid := auth.uid();
  v_rows jsonb;
begin
  if v_user_id is null then
    raise exception 'Authentication required.';
  end if;
  if p_duration_seconds not in (30, 60, 180, 300) then
    raise exception 'Unsupported WINGO duration.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'round_id', q.id,
    'duration_seconds', q.duration_seconds,
    'round_index', q.round_index,
    'period', q.period,
    'starts_at', q.starts_at,
    'ends_at', q.ends_at,
    'status', q.status,
    'outcome', q.outcome,
    'settled_at', q.settled_at
  ) order by q.starts_at desc), '[]'::jsonb)
  into v_rows
  from (
    select r.*,
      (
        to_char(r.starts_at at time zone 'Asia/Kolkata', 'YYYYMMDD')
        || case r.duration_seconds
          when 30 then '1000'
          when 60 then '2000'
          when 180 then '3000'
          when 300 then '4000'
        end
        || lpad(mod(r.round_index, 100000)::text, 5, '0')
      ) as period
    from public.nplus_wingo_demo_rounds r
    where r.duration_seconds = p_duration_seconds
      and r.status = 'settled'
      and r.ends_at <= clock_timestamp()
    order by r.starts_at desc
    limit least(greatest(coalesce(p_limit, 100), 1), 500)
  ) q;

  return v_rows;
end;
$function$;

revoke all on function public.nplus_wingo_make_outcome() from public, anon, authenticated;
revoke all on function public.nplus_wingo_payout_multiplier(jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.nplus_wingo_demo_current_round(integer) from public, anon;
revoke all on function public.nplus_wingo_demo_place_bet(integer, jsonb, numeric, uuid) from public, anon;
revoke all on function public.nplus_wingo_demo_settle_round(integer, bigint) from public, anon;
revoke all on function public.nplus_wingo_demo_my_bets(integer, integer) from public, anon;
grant execute on function public.nplus_wingo_demo_current_round(integer) to authenticated;
grant execute on function public.nplus_wingo_demo_place_bet(integer, jsonb, numeric, uuid) to authenticated;
grant execute on function public.nplus_wingo_demo_settle_round(integer, bigint) to authenticated;
grant execute on function public.nplus_wingo_demo_my_bets(integer, integer) to authenticated;
revoke all on function public.nplus_wingo_demo_history(integer, integer) from public, anon, authenticated;
grant execute on function public.nplus_wingo_demo_history(integer, integer) to authenticated;

commit;
