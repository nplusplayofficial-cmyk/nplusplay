-- Keep server-authoritative settled round history populated even when no browser
-- tab is open. Existing outcomes are reused; no synthetic historical outcomes are created.
-- Wallet credits are only changed by the existing game settlement functions.

BEGIN;

-- Permit the database-owned cron connection (not browser roles) to settle older
-- rounds. Normal signed-in calls remain limited to the recent round window.
CREATE OR REPLACE FUNCTION public.nplus_wingo_demo_settle_round(p_duration_seconds integer, p_round_index bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
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
  if v_user_id is null and session_user <> 'postgres' then
    raise exception 'Authentication required.';
  end if;

  if p_duration_seconds not in (30, 60, 180, 300) then
    raise exception 'Unsupported WINGO duration.';
  end if;

  v_current_index := floor(extract(epoch from v_now) / p_duration_seconds)::bigint;
  if p_round_index is null
     or p_round_index >= v_current_index
     or (v_user_id is not null and p_round_index < v_current_index - 500) then
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

CREATE OR REPLACE FUNCTION public.nplus_moto_demo_settle_round(p_round_index bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $function$
declare
  u uuid := auth.uid();
  now_at timestamptz := clock_timestamp();
  current_idx bigint;
  st timestamptz;
  en timestamptz;
  r public.nplus_moto_demo_rounds%rowtype;
  b public.nplus_moto_demo_bets%rowtype;
  won boolean;
  payout_amt numeric(12,2);
  before_amt numeric(12,2);
  after_amt numeric(12,2);
  mine jsonb;
begin
  if u is null and session_user <> 'postgres' then
    raise exception 'Authentication required.';
  end if;

  current_idx := floor(extract(epoch from now_at)/60)::bigint;
  if p_round_index is null
     or p_round_index >= current_idx
     or (u is not null and p_round_index < current_idx-500) then
    raise exception 'Round index is invalid or too old.';
  end if;

  st := to_timestamp(p_round_index*60);
  en := st+interval '60 seconds';
  insert into public.nplus_moto_demo_rounds(round_index,starts_at,ends_at,outcome)
  values(p_round_index,st,en,public.nplus_moto_demo_make_outcome())
  on conflict(round_index) do nothing;

  select * into r from public.nplus_moto_demo_rounds
  where round_index=p_round_index for update;

  if now_at<r.ends_at then
    raise exception 'MotoRace round has not finished yet.';
  end if;

  if r.status<>'settled' then
    for b in
      select * from public.nplus_moto_demo_bets
      where round_id=r.id and status='pending'
      order by user_id,id for update
    loop
      won := public.nplus_moto_demo_is_win(b.selection,r.outcome);
      if won then
        payout_amt := round(b.stake*2,2);
        select balance into before_amt from public.demo_wallets
        where user_id=b.user_id for update;
        if not found then
          raise exception 'Wallet not found while settling MotoRace bet.';
        end if;
        after_amt := before_amt+payout_amt;
        update public.demo_wallets set balance=after_amt,updated_at=clock_timestamp()
        where user_id=b.user_id;
        insert into public.demo_wallet_transactions(user_id,delta,balance_before,balance_after,type,source,note)
        values(b.user_id,payout_amt,before_amt,after_amt,'GAME_WIN','MOTORACE',
          format('MotoRace server settlement %s round %s',b.id,r.round_index));
        update public.nplus_moto_demo_bets
        set status='won',payout=payout_amt,settled_at=clock_timestamp()
        where id=b.id;
      else
        update public.nplus_moto_demo_bets
        set status='lost',payout=0,settled_at=clock_timestamp()
        where id=b.id;
      end if;
    end loop;
    update public.nplus_moto_demo_rounds
    set status='settled',settled_at=clock_timestamp()
    where id=r.id returning * into r;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'bet_id',b0.id,'selection',b0.selection,'stake',b0.stake,'fee',b0.fee,
    'total',b0.amount_debited,'status',b0.status,'payout',b0.payout,'settled_at',b0.settled_at
  ) order by b0.created_at,b0.id),'[]'::jsonb)
  into mine from public.nplus_moto_demo_bets b0
  where b0.round_id=r.id and b0.user_id=u;

  return jsonb_build_object(
    'round_id',r.id,'round_index',r.round_index,
    'period',to_char(r.starts_at at time zone 'Asia/Kolkata','YYYYMMDDHH24MI'),
    'status',r.status,'outcome',r.outcome,'bets',mine
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.nplus_demo_history_maintenance_tick()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public'
AS $maintenance$
DECLARE
  v_now timestamptz := clock_timestamp();
  v_game text;
  v_seconds integer;
  v_slot bigint;
  v_start timestamptz;
  v_end timestamptz;
  v_period text;
  v_row record;
  v_lottery_settled integer := 0;
  v_wingo_settled integer := 0;
  v_moto_settled integer := 0;
  v_rounds_inserted integer := 0;
  v_settled integer;
  v_inserted integer;
BEGIN
  IF session_user <> 'postgres' THEN
    RAISE EXCEPTION 'This maintenance function is restricted to the postgres scheduler.';
  END IF;

  -- K3 and 5D have 1/3/5/10-minute rounds; TRX WINGO has 1-minute rounds.
  FOR v_game,v_seconds IN
    SELECT * FROM (VALUES
      ('K3',60),('K3',180),('K3',300),('K3',600),
      ('5D',60),('5D',180),('5D',300),('5D',600),
      ('TRX',60)
    ) AS x(game_key,duration_seconds)
  LOOP
    v_settled := public.nplus_demo_lottery_settle_due(v_game,v_seconds);
    v_lottery_settled := v_lottery_settled + coalesce(v_settled,0);

    v_slot := floor(extract(epoch from v_now)/v_seconds)::bigint;
    v_start := to_timestamp(v_slot*v_seconds);
    v_end := v_start+make_interval(secs=>v_seconds);
    v_period := to_char(v_start AT TIME ZONE 'Asia/Kolkata','YYYYMMDDHH24MI')
      || '-' || v_game || '-' || v_seconds || '-' || v_slot::text;

    INSERT INTO public.nplus_demo_lottery_rounds(
      game_key,duration_seconds,round_slot,period,starts_at,ends_at,outcome
    ) VALUES (
      v_game,v_seconds,v_slot,v_period,v_start,v_end,
      public.nplus_demo_lottery_make_outcome(v_game)
    ) ON CONFLICT(game_key,duration_seconds,round_slot) DO NOTHING;
    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    v_rounds_inserted := v_rounds_inserted + v_inserted;
  END LOOP;

  -- WINGO runs four supported durations. Persist the current round and settle
  -- each existing expired server round even if nobody placed a bet.
  FOR v_seconds IN SELECT unnest(ARRAY[30,60,180,300])
  LOOP
    v_slot := floor(extract(epoch from v_now)/v_seconds)::bigint;
    v_start := to_timestamp(v_slot*v_seconds);
    v_end := v_start+make_interval(secs=>v_seconds);

    INSERT INTO public.nplus_wingo_demo_rounds(
      duration_seconds,round_index,starts_at,ends_at,outcome
    ) VALUES (
      v_seconds,v_slot,v_start,v_end,public.nplus_wingo_make_outcome()
    ) ON CONFLICT(duration_seconds,round_index) DO NOTHING;
    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    v_rounds_inserted := v_rounds_inserted + v_inserted;

    FOR v_row IN
      SELECT round_index
      FROM public.nplus_wingo_demo_rounds
      WHERE duration_seconds=v_seconds AND status='open' AND ends_at<=v_now
      ORDER BY round_index
      LIMIT 200
    LOOP
      PERFORM public.nplus_wingo_demo_settle_round(v_seconds,v_row.round_index);
      v_wingo_settled := v_wingo_settled + 1;
    END LOOP;
  END LOOP;

  -- MOTO uses one-minute rounds. Keep a current round and settle all expired
  -- server rounds, including rounds with no bet records.
  v_slot := floor(extract(epoch from v_now)/60)::bigint;
  v_start := to_timestamp(v_slot*60);
  v_end := v_start+interval '60 seconds';
  INSERT INTO public.nplus_moto_demo_rounds(round_index,starts_at,ends_at,outcome)
  VALUES(v_slot,v_start,v_end,public.nplus_moto_demo_make_outcome())
  ON CONFLICT(round_index) DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  v_rounds_inserted := v_rounds_inserted + v_inserted;

  FOR v_row IN
    SELECT round_index
    FROM public.nplus_moto_demo_rounds
    WHERE status='open' AND ends_at<=v_now
    ORDER BY round_index
    LIMIT 200
  LOOP
    PERFORM public.nplus_moto_demo_settle_round(v_row.round_index);
    v_moto_settled := v_moto_settled + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'ok',true,
    'ran_at',clock_timestamp(),
    'lottery_rounds_settled',v_lottery_settled,
    'wingo_rounds_settled',v_wingo_settled,
    'moto_rounds_settled',v_moto_settled,
    'rounds_inserted',v_rounds_inserted
  );
END;
$maintenance$;

REVOKE ALL ON FUNCTION public.nplus_demo_history_maintenance_tick() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.nplus_demo_history_maintenance_tick() TO postgres;

DO $schedule$
DECLARE
  v_jobid bigint;
BEGIN
  FOR v_jobid IN SELECT jobid FROM cron.job WHERE jobname='nplus-demo-history-maintenance'
  LOOP
    PERFORM cron.unschedule(v_jobid);
  END LOOP;
  PERFORM cron.schedule(
    'nplus-demo-history-maintenance',
    '10 seconds',
    'SELECT public.nplus_demo_history_maintenance_tick();'
  );
END;
$schedule$;

-- Run once during deployment so existing expired rounds become visible right away.
SELECT public.nplus_demo_history_maintenance_tick();

COMMIT;
