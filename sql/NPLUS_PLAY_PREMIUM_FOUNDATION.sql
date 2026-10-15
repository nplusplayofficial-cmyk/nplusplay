-- N+ PLAY premium foundation migration. Virtual-credit demo only.
-- Review against the live schema/RLS policies and take a database backup before running.
-- Does NOT secure client-generated game outcomes or arbitrary positive legacy game credits.

begin;

create index if not exists demo_wallet_transactions_user_created_idx
  on public.demo_wallet_transactions(user_id, created_at desc);
create index if not exists demo_wallets_user_id_idx
  on public.demo_wallets(user_id);

alter table public.demo_wallets enable row level security;
alter table public.demo_wallet_transactions enable row level security;

-- Rebuild wallet-table policies to ensure users can read only their own rows.
do $policy_reset$
declare p record;
begin
  for p in select schemaname, tablename, policyname
           from pg_policies
           where schemaname='public'
             and tablename in ('demo_wallets','demo_wallet_transactions')
  loop
    execute format('drop policy if exists %I on %I.%I', p.policyname, p.schemaname, p.tablename);
  end loop;
end;
$policy_reset$;

create policy nplus_users_read_own_demo_wallet
  on public.demo_wallets for select to authenticated using (user_id = auth.uid());
create policy nplus_users_read_own_demo_wallet_transactions
  on public.demo_wallet_transactions for select to authenticated using (user_id = auth.uid());

revoke all on public.demo_wallets from anon, authenticated;
revoke all on public.demo_wallet_transactions from anon, authenticated;
grant select on public.demo_wallets to authenticated;
grant select on public.demo_wallet_transactions to authenticated;

create or replace function public.nplus_admin_user_directory(p_search text default null, p_limit integer default 200)
returns jsonb language plpgsql security definer set search_path = public
as $function$
declare v_role text; v_rows jsonb := '[]'::jsonb; v_count bigint := 0; v_q text := lower(trim(coalesce(p_search,'')));
begin
  if auth.uid() is null then raise exception 'Authentication required.'; end if;
  select lower(coalesce(role,'')) into v_role from public.profiles where id=auth.uid();
  if coalesce(v_role,'') <> 'admin' then raise exception 'Admin access required.'; end if;

  select count(*) into v_count from public.profiles p
  where v_q='' or lower(coalesce(p.uid,'')) like '%'||v_q||'%'
     or lower(coalesce(p.display_name,'')) like '%'||v_q||'%'
     or lower(coalesce(p.email,'')) like '%'||v_q||'%'
     or (regexp_replace(v_q,'[^0-9]','','g')<>'' and regexp_replace(coalesce(p.phone,''),'[^0-9]','','g') like '%'||regexp_replace(v_q,'[^0-9]','','g')||'%');

  select coalesce(jsonb_agg(r.obj order by r.created_at desc),'[]'::jsonb) into v_rows
  from (
    select p.created_at, jsonb_build_object('user_id',p.id,'id',p.id,'uid',coalesce(p.uid,p.id::text),
      'display_name',coalesce(p.display_name,'N+ PLAY User'),'email',p.email,'phone',p.phone,
      'role',coalesce(p.role,'user'),'created_at',p.created_at,'balance',coalesce(w.balance,0)) obj
    from public.profiles p left join public.demo_wallets w on w.user_id=p.id
    where v_q='' or lower(coalesce(p.uid,'')) like '%'||v_q||'%'
       or lower(coalesce(p.display_name,'')) like '%'||v_q||'%'
       or lower(coalesce(p.email,'')) like '%'||v_q||'%'
       or (regexp_replace(v_q,'[^0-9]','','g')<>'' and regexp_replace(coalesce(p.phone,''),'[^0-9]','','g') like '%'||regexp_replace(v_q,'[^0-9]','','g')||'%')
    order by p.created_at desc nulls last limit least(greatest(coalesce(p_limit,200),1),200)
  ) r;
  return jsonb_build_object('count',v_count,'rows',v_rows);
end;
$function$;

create or replace function public.nplus_admin_user_transactions(p_user_id uuid, p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path = public
as $function$
declare v_role text; v_rows jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required.'; end if;
  select lower(coalesce(role,'')) into v_role from public.profiles where id=auth.uid();
  if coalesce(v_role,'') <> 'admin' then raise exception 'Admin access required.'; end if;
  select coalesce(jsonb_agg(x.obj order by x.created_at desc),'[]'::jsonb) into v_rows
  from (
    select t.created_at, jsonb_build_object('id',t.id,'user_id',t.user_id,'delta',t.delta,
      'balance_before',t.balance_before,'balance_after',t.balance_after,'type',t.type,
      'source',t.source,'note',t.note,'created_at',t.created_at) obj
    from public.demo_wallet_transactions t where t.user_id=p_user_id
    order by t.created_at desc limit least(greatest(coalesce(p_limit,100),1),200)
  ) x;
  return jsonb_build_object('rows',v_rows);
end;
$function$;

create or replace function public.nplus_admin_adjust_demo_wallet(p_target_user uuid, p_delta numeric, p_note text)
returns jsonb language plpgsql security definer set search_path = public
as $function$
declare v_role text; v_before numeric; v_after numeric; v_delta numeric := round(coalesce(p_delta,0),2); v_note text := left(trim(coalesce(p_note,'')),180);
begin
  if auth.uid() is null then raise exception 'Authentication required.'; end if;
  select lower(coalesce(role,'')) into v_role from public.profiles where id=auth.uid();
  if coalesce(v_role,'') <> 'admin' then raise exception 'Admin access required.'; end if;
  if p_target_user is null then raise exception 'Target user is required.'; end if;
  if v_delta=0 or abs(v_delta)>100000 then raise exception 'Adjustment must be non-zero and no greater than 100000 credits.'; end if;
  if length(v_note)<4 then raise exception 'A clear audit note is required.'; end if;
  select balance into v_before from public.demo_wallets where user_id=p_target_user for update;
  if not found then raise exception 'Target wallet was not found.'; end if;
  v_after := round(v_before+v_delta,2);
  if v_after<0 then raise exception 'Adjustment would make the wallet negative.'; end if;
  update public.demo_wallets set balance=v_after, updated_at=now() where user_id=p_target_user;
  insert into public.demo_wallet_transactions(user_id,delta,balance_before,balance_after,type,source,note,created_at)
  values(p_target_user,v_delta,v_before,v_after,'ADMIN_ADJUSTMENT','ADMIN',v_note,now());
  return jsonb_build_object('success',true,'user_id',p_target_user,'before',v_before,'after',v_after,'delta',v_delta);
end;
$function$;

revoke all on function public.nplus_admin_user_directory(text,integer) from public, anon;
revoke all on function public.nplus_admin_user_transactions(uuid,integer) from public, anon;
revoke all on function public.nplus_admin_adjust_demo_wallet(uuid,numeric,text) from public, anon;
grant execute on function public.nplus_admin_user_directory(text,integer) to authenticated;
grant execute on function public.nplus_admin_user_transactions(uuid,integer) to authenticated;
grant execute on function public.nplus_admin_adjust_demo_wallet(uuid,numeric,text) to authenticated;

commit;

-- Release blocker: inspect public.nplus_wallet_change and replace client-provided positive game
-- credits with server-authoritative bet/round/result/payout RPCs. Do not claim anti-cheat security yet.
