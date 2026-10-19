-- Candidate-only hardening patch prepared from a read-only catalog inspection on 2026-10-19.
-- Fails closed when an authenticated account has no profiles row or a NULL role.
-- Review and test in isolated Supabase staging before any production use.
-- Do not run as part of production until the documented rollout gates have passed.
-- No wallet balances are changed by this migration.
BEGIN;

CREATE OR REPLACE FUNCTION public.nplus_admin_clear_wingo_manual(p_duration integer, p_period text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  select lower(coalesce(role, ''))
    into v_role
  from public.profiles
  where id = auth.uid();

  if coalesce(v_role, '') <> 'admin' then
    raise exception 'Admin access required.';
  end if;

  delete from public.wingo_manual_results
  where duration_seconds = p_duration
    and period = trim(p_period);

  return jsonb_build_object(
    'success', true,
    'duration', p_duration,
    'period', trim(p_period)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_admin_commission_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$

declare
  v_user_id uuid;
  v_role text;

  v_total_bets bigint := 0;
  v_total_bet_amount numeric := 0;
  v_total_wins bigint := 0;
  v_total_winning_amount numeric := 0;

  v_today_bets bigint := 0;
  v_today_bet_amount numeric := 0;
  v_today_commission numeric := 0;

  v_all_commission numeric := 0;

  v_games jsonb := '[]'::jsonb;

begin

  /* -----------------------------------------
     VERIFY CURRENT USER
  ----------------------------------------- */

  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'Authentication required.';
  end if;


  /* -----------------------------------------
     VERIFY ADMIN ROLE
  ----------------------------------------- */

  select lower(coalesce(role, ''))
  into v_role
  from public.profiles
  where id = v_user_id;

  if coalesce(v_role, '') <> 'admin' then
    raise exception 'Admin access required.';
  end if;


  /* -----------------------------------------
     ALL-TIME BETS
     GAME_BET transactions are negative
  ----------------------------------------- */

  select
    count(*),
    coalesce(sum(abs(delta)), 0)
  into
    v_total_bets,
    v_total_bet_amount
  from public.demo_wallet_transactions
  where type = 'GAME_BET'
    and delta < 0;


  /* -----------------------------------------
     ALL-TIME WINS
  ----------------------------------------- */

  select
    count(*),
    coalesce(sum(delta), 0)
  into
    v_total_wins,
    v_total_winning_amount
  from public.demo_wallet_transactions
  where type = 'GAME_WIN'
    and delta > 0;


  /* -----------------------------------------
     ALL-TIME COMMISSION
     
     Current demo platform fee:
     2% of GAME_BET amount
  ----------------------------------------- */

  select
    coalesce(sum(abs(delta)) * 0.02, 0)
  into
    v_all_commission
  from public.demo_wallet_transactions
  where type = 'GAME_BET'
    and delta < 0;


  /* -----------------------------------------
     TODAY
  ----------------------------------------- */

  select
    count(*),
    coalesce(sum(abs(delta)), 0)
  into
    v_today_bets,
    v_today_bet_amount
  from public.demo_wallet_transactions
  where type = 'GAME_BET'
    and delta < 0
    and created_at >= date_trunc('day', now());


  v_today_commission :=
    round(v_today_bet_amount * 0.02, 2);


  /* -----------------------------------------
     GAME-WISE REPORT
     
     source = WINGO / K3 / 5D / etc.
  ----------------------------------------- */

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'game',
        game_name,

        'bets',
        bet_count,

        'bet_amount',
        round(bet_amount, 2),

        'commission',
        round(bet_amount * 0.02, 2)
      )
      order by bet_amount desc
    ),
    '[]'::jsonb
  )
  into v_games
  from (
    select
      coalesce(
        nullif(trim(source), ''),
        'UNKNOWN'
      ) as game_name,

      count(*) as bet_count,

      coalesce(
        sum(abs(delta)),
        0
      ) as bet_amount

    from public.demo_wallet_transactions

    where type = 'GAME_BET'
      and delta < 0

    group by
      coalesce(
        nullif(trim(source), ''),
        'UNKNOWN'
      )

  ) g;


  /* -----------------------------------------
     RETURN REPORT
  ----------------------------------------- */

  return jsonb_build_object(

    'total_bets',
    v_total_bets,

    'total_bet_amount',
    round(v_total_bet_amount, 2),

    'total_wins',
    v_total_wins,

    'total_winning_amount',
    round(v_total_winning_amount, 2),

    'today_bets',
    v_today_bets,

    'today_bet_amount',
    round(v_today_bet_amount, 2),

    'today_commission',
    v_today_commission,

    'all_time_commission',
    round(v_all_commission, 2),

    'commission_rate',
    0.02,

    'games',
    v_games

  );

end;

$function$;

CREATE OR REPLACE FUNCTION public.nplus_admin_deposit_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user_id uuid;
  v_role text;
  v_approved_count bigint := 0;
  v_approved_total numeric := 0;
  v_today_count bigint := 0;
  v_today_total numeric := 0;
  v_rows jsonb := '[]'::jsonb;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'Authentication required.';
  end if;

  select lower(coalesce(role, ''))
  into v_role
  from public.profiles
  where id = v_user_id;

  if coalesce(v_role, '') <> 'admin' then
    raise exception 'Admin access required.';
  end if;

  -- Total approved deposits
  select
    count(*),
    coalesce(sum(amount), 0)
  into
    v_approved_count,
    v_approved_total
  from public.deposit_requests
  where lower(coalesce(status, '')) = 'approved';

  -- Today's approved deposits
  select
    count(*),
    coalesce(sum(amount), 0)
  into
    v_today_count,
    v_today_total
  from public.deposit_requests
  where lower(coalesce(status, '')) = 'approved'
    and created_at >= date_trunc('day', now());

  -- Approved deposit history
  select coalesce(
    jsonb_agg(
      x.row_data
      order by x.created_at desc
    ),
    '[]'::jsonb
  )
  into v_rows
  from (
    select
      d.created_at,
      jsonb_build_object(
        'id', d.id,
        'user_id', d.user_id,
        'amount', round(coalesce(d.amount, 0), 2),
        'status', d.status,
        'created_at', d.created_at,
        'display_name',
          coalesce(
            p.display_name,
            'N+ PLAY User'
          ),
        'uid',
          coalesce(
            p.uid,
            d.user_id::text
          ),
        'email',
          p.email
      ) as row_data
    from public.deposit_requests d
    left join public.profiles p
      on p.id = d.user_id
    where lower(coalesce(d.status, '')) = 'approved'
    order by d.created_at desc
    limit 200
  ) x;

  return jsonb_build_object(
    'approved_count',
      v_approved_count,

    'approved_total',
      round(v_approved_total, 2),

    'today_approved_count',
      v_today_count,

    'today_approved_total',
      round(v_today_total, 2),

    'rows',
      v_rows
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_admin_save_wingo_manual(p_duration integer, p_period text, p_color text, p_number integer, p_size text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role text;
  v_color text := upper(trim(coalesce(p_color, '')));
  v_size text := upper(trim(coalesce(p_size, '')));
  v_period text := trim(coalesce(p_period, ''));
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  select lower(coalesce(role, ''))
    into v_role
  from public.profiles
  where id = auth.uid();

  if coalesce(v_role, '') <> 'admin' then
    raise exception 'Admin access required.';
  end if;

  if p_duration not in (30,60,180,300) then
    raise exception 'Invalid WINGO duration.';
  end if;

  if v_period = '' then
    raise exception 'WINGO period is required.';
  end if;

  if v_color not in ('GREEN','VIOLET','RED') then
    raise exception 'Invalid WINGO color.';
  end if;

  if p_number is null or p_number < 0 or p_number > 9 then
    raise exception 'WINGO number must be between 0 and 9.';
  end if;

  if v_size not in ('BIG','SMALL') then
    raise exception 'WINGO size must be BIG or SMALL.';
  end if;

  insert into public.wingo_manual_results (
    duration_seconds,
    period,
    mode,
    color,
    number,
    size,
    created_by
  )
  values (
    p_duration,
    v_period,
    'MANUAL',
    v_color,
    p_number,
    v_size,
    auth.uid()
  )
  on conflict (duration_seconds, period)
  do update set
    mode = 'MANUAL',
    color = excluded.color,
    number = excluded.number,
    size = excluded.size,
    created_by = auth.uid(),
    created_at = now();

  return jsonb_build_object(
    'success', true,
    'duration', p_duration,
    'period', v_period,
    'mode', 'MANUAL',
    'color', v_color,
    'number', p_number,
    'size', v_size,
    'result', v_color || ' ' || p_number::text || ' · ' || v_size
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_admin_set_wingo_demo(p_duration integer, p_mode text, p_color text DEFAULT NULL::text, p_number integer DEFAULT NULL::integer, p_size text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role text;
  v_mode text := upper(trim(coalesce(p_mode, 'AUTO')));
  v_color text := upper(trim(coalesce(p_color, '')));
  v_size text := upper(trim(coalesce(p_size, '')));
begin
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  select lower(coalesce(role, ''))
    into v_role
  from public.profiles
  where id = auth.uid();

  if coalesce(v_role, '') <> 'admin' then
    raise exception 'Admin access required.';
  end if;

  if p_duration not in (30,60,180,300) then
    raise exception 'Invalid WINGO duration.';
  end if;

  if v_mode not in ('AUTO','MANUAL','RANDOM') then
    raise exception 'Invalid WINGO mode.';
  end if;

  if v_mode = 'MANUAL' then
    if v_color not in ('GREEN','VIOLET','RED') then
      raise exception 'Manual WINGO color is required.';
    end if;

    if p_number is null or p_number < 0 or p_number > 9 then
      raise exception 'Manual WINGO number must be between 0 and 9.';
    end if;

    if v_size not in ('BIG','SMALL') then
      raise exception 'Manual WINGO size is required.';
    end if;
  end if;

  insert into public.demo_game_controls (
    game_key,
    duration_seconds,
    mode,
    color,
    number,
    result,
    updated_by,
    updated_at
  )
  values (
    'WINGO',
    p_duration,
    v_mode,
    nullif(v_color, ''),
    p_number,
    case
      when v_mode = 'MANUAL'
        then v_color || ' ' || p_number::text || ' · ' || v_size
      when v_mode = 'RANDOM'
        then 'RANDOM DEMO'
      else
        'AUTO'
    end,
    auth.uid(),
    now()
  )
  on conflict (game_key, duration_seconds)
  do update set
    mode = excluded.mode,
    color = excluded.color,
    number = excluded.number,
    result = excluded.result,
    updated_by = auth.uid(),
    updated_at = now();

  return jsonb_build_object(
    'success', true,
    'duration', p_duration,
    'mode', v_mode,
    'color', nullif(v_color, ''),
    'number', p_number,
    'size', nullif(v_size, ''),
    'result',
      case
        when v_mode = 'MANUAL'
          then v_color || ' ' || p_number::text || ' · ' || v_size
        when v_mode = 'RANDOM'
          then 'RANDOM DEMO'
        else 'AUTO'
      end
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_admin_set_wingo_demo(p_duration integer, p_mode text, p_color text DEFAULT NULL::text, p_number integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$

declare
  v_role text;
  v_mode text;
  v_color text;
  v_result text;
begin

  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  select lower(coalesce(role,''))
  into v_role
  from public.profiles
  where id = auth.uid();

  if coalesce(v_role, '') <> 'admin' then
    raise exception 'Admin access required.';
  end if;

  if p_duration not in (30,60,180,300) then
    raise exception 'Invalid WINGO duration.';
  end if;

  v_mode := upper(trim(coalesce(p_mode,'AUTO')));

  if v_mode not in ('AUTO','MANUAL','RANDOM') then
    raise exception 'Invalid demo mode.';
  end if;

  if v_mode = 'MANUAL' then

    if p_number is null
       or p_number < 0
       or p_number > 9 then
      raise exception 'Number must be between 0 and 9.';
    end if;

    if p_number in (1,3,7,9) then
      v_color := 'GREEN';
    elsif p_number in (2,4,6,8) then
      v_color := 'RED';
    elsif p_number = 0 then
      v_color := 'RED';
    elsif p_number = 5 then
      v_color := 'GREEN';
    end if;

    v_result := v_color || ' ' || p_number;

  else

    v_color := null;

    v_result :=
      case
        when v_mode = 'AUTO' then 'AUTO'
        else 'RANDOM DEMO'
      end;

  end if;

  update public.demo_game_controls
  set
    mode = v_mode,
    color = v_color,
    number =
      case
        when v_mode = 'MANUAL'
          then p_number
        else null
      end,
    result = v_result,
    updated_by = auth.uid(),
    updated_at = now()
  where game_key = 'WINGO'
    and duration_seconds = p_duration;

  return jsonb_build_object(
    'success',true,
    'game','WINGO',
    'duration',p_duration,
    'mode',v_mode,
    'color',v_color,
    'number',
      case
        when v_mode='MANUAL'
          then p_number
        else null
      end,
    'result',v_result
  );

end;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_admin_wingo_live_bets(p_period text)
 RETURNS TABLE(display_name text, uid text, period text, selection text, stake numeric, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role text;
begin
  select lower(coalesce(role, ''))
  into v_role
  from public.profiles
  where id = auth.uid();

  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  if coalesce(v_role, '') <> 'admin' then
    raise exception 'Admin access required.';
  end if;

  return query
  select
    p.display_name,
    p.uid,
    substring(t.note from '^WINGO BET ([^ ]+)') as period,
    concat(
      upper(substring(t.note from 'type=([^ ]+)')),
      ' ',
      substring(t.note from 'value=([^ ]+)')
    ) as selection,
    abs(t.delta) as stake,
    t.created_at
  from public.demo_wallet_transactions t
  join public.profiles p
    on p.id = t.user_id
  where t.type = 'GAME_BET'
    and t.source = 'WINGO'
    and substring(t.note from '^WINGO BET ([^ ]+)') = p_period
  order by t.created_at desc;
end;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_admin_wingo_round_summary(p_period text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role text;
  v_bets jsonb := '[]'::jsonb;
  v_colors jsonb := '{}'::jsonb;
  v_numbers jsonb := '{}'::jsonb;
  v_sizes jsonb := '{}'::jsonb;
  v_bet_count bigint := 0;
  v_total_stake numeric := 0;
begin

  -- Authentication check
  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  -- Admin check
  select lower(coalesce(pr.role, ''))
  into v_role
  from public.profiles pr
  where pr.id = auth.uid();

  if coalesce(v_role, '') <> 'admin' then
    raise exception 'Admin access required.';
  end if;


  -- TOTAL BETS
  select
    count(*),
    coalesce(sum(abs(t.delta)), 0)
  into
    v_bet_count,
    v_total_stake
  from public.demo_wallet_transactions t
  where t.type = 'GAME_BET'
    and t.source = 'WINGO'
    and substring(t.note from '^WINGO BET ([^ ]+)') = p_period;


  -- INDIVIDUAL BET DETAILS
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'display_name', pr.display_name,
        'uid', pr.uid,
        'period', substring(t.note from '^WINGO BET ([^ ]+)'),
        'type', substring(t.note from 'type=([^ ]+)'),
        'value', substring(t.note from 'value=([^ ]+)'),
        'qty', coalesce(
          substring(t.note from 'qty=([^ ]+)'),
          '1'
        ),
        'multi', coalesce(
          substring(t.note from 'multi=([^ ]+)'),
          '1'
        ),
        'stake', abs(t.delta),
        'created_at', t.created_at
      )
      order by t.created_at desc
    ),
    '[]'::jsonb
  )
  into v_bets
  from public.demo_wallet_transactions t
  join public.profiles pr
    on pr.id = t.user_id
  where t.type = 'GAME_BET'
    and t.source = 'WINGO'
    and substring(t.note from '^WINGO BET ([^ ]+)') = p_period;


  -- COLOR BREAKDOWN
  select coalesce(
    jsonb_object_agg(
      c.label,
      jsonb_build_object(
        'count', coalesce(x.cnt, 0),
        'amount', coalesce(x.amount, 0)
      )
    ),
    '{}'::jsonb
  )
  into v_colors
  from (
    values
      ('Green'),
      ('Violet'),
      ('Red')
  ) as c(label)

  left join (
    select
      initcap(
        lower(
          substring(t.note from 'value=([^ ]+)')
        )
      ) as item_label,

      count(*) as cnt,
      sum(abs(t.delta)) as amount

    from public.demo_wallet_transactions t

    where t.type = 'GAME_BET'
      and t.source = 'WINGO'
      and substring(
        t.note
        from '^WINGO BET ([^ ]+)'
      ) = p_period

      and lower(
        substring(t.note from 'type=([^ ]+)')
      ) = 'color'

    group by
      initcap(
        lower(
          substring(t.note from 'value=([^ ]+)')
        )
      )

  ) x

  on lower(x.item_label) = lower(c.label);


  -- NUMBER BREAKDOWN
  select coalesce(
    jsonb_object_agg(
      n.label,
      jsonb_build_object(
        'count', coalesce(x.cnt, 0),
        'amount', coalesce(x.amount, 0)
      )
    ),
    '{}'::jsonb
  )
  into v_numbers

  from (
    values
      ('0'),
      ('1'),
      ('2'),
      ('3'),
      ('4'),
      ('5'),
      ('6'),
      ('7'),
      ('8'),
      ('9')
  ) as n(label)

  left join (
    select
      substring(
        t.note
        from 'value=([^ ]+)'
      ) as item_label,

      count(*) as cnt,
      sum(abs(t.delta)) as amount

    from public.demo_wallet_transactions t

    where t.type = 'GAME_BET'
      and t.source = 'WINGO'
      and substring(
        t.note
        from '^WINGO BET ([^ ]+)'
      ) = p_period

      and lower(
        substring(t.note from 'type=([^ ]+)')
      ) = 'number'

    group by
      substring(
        t.note
        from 'value=([^ ]+)'
      )

  ) x

  on x.item_label = n.label;


  -- BIG / SMALL BREAKDOWN
  select coalesce(
    jsonb_object_agg(
      s.label,
      jsonb_build_object(
        'count', coalesce(x.cnt, 0),
        'amount', coalesce(x.amount, 0)
      )
    ),
    '{}'::jsonb
  )
  into v_sizes

  from (
    values
      ('Big'),
      ('Small')
  ) as s(label)

  left join (
    select
      initcap(
        lower(
          substring(t.note from 'value=([^ ]+)')
        )
      ) as item_label,

      count(*) as cnt,
      sum(abs(t.delta)) as amount

    from public.demo_wallet_transactions t

    where t.type = 'GAME_BET'
      and t.source = 'WINGO'
      and substring(
        t.note
        from '^WINGO BET ([^ ]+)'
      ) = p_period

      and lower(
        substring(t.note from 'type=([^ ]+)')
      ) = 'size'

    group by
      initcap(
        lower(
          substring(t.note from 'value=([^ ]+)')
        )
      )

  ) x

  on lower(x.item_label) = lower(s.label);


  -- FINAL RESULT
  return jsonb_build_object(
    'period', p_period,
    'bet_count', v_bet_count,
    'total_stake', round(v_total_stake, 2),
    'colors', v_colors,
    'numbers', v_numbers,
    'sizes', v_sizes,
    'bets', v_bets
  );

end;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_set_game_status(p_game_key text, p_enabled boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role text;
  v_key text;
  v_name text;
begin

  select lower(coalesce(role, ''))
  into v_role
  from public.profiles
  where id = auth.uid();

  if auth.uid() is null then
    raise exception 'Authentication required.';
  end if;

  if coalesce(v_role, '') <> 'admin' then
    raise exception 'Admin access required.';
  end if;

  v_key := upper(trim(coalesce(p_game_key, '')));

  if v_key not in (
    'WINGO',
    'K3',
    '5D',
    'TRX',
    'AVIATOR',
    'MOTO'
  ) then
    raise exception 'Invalid game.';
  end if;

  update public.game_settings
  set
    enabled = coalesce(p_enabled, true),
    updated_at = now(),
    updated_by = auth.uid()
  where game_key = v_key
  returning game_name
  into v_name;

  if not found then
    raise exception 'Game setting not found.';
  end if;

  return jsonb_build_object(
    'game_key', v_key,
    'game_name', v_name,
    'enabled', p_enabled
  );

end;
$function$;

COMMIT;
