\set ON_ERROR_STOP on
\ir ../sql/POST_ROLLOUT_BLOCK_GENERIC_WALLET_CREDITS.sql

do $tests$
declare
 u uuid:=gen_random_uuid();
 result jsonb;
 bal numeric(12,2);
 bet_count integer;
begin
 insert into auth.users(id,email) values(u,'wallet-' || replace(u::text, '-', '') || '@example.invalid');
 insert into public.demo_wallets(user_id,balance) values(u,108.00);
 perform set_config('request.jwt.claim.sub',u::text,true);

 result:=public.nplus_wallet_change(-2.00,'ADJUSTMENT','QA','test negative adjustment');
 if (result->>'after')::numeric<>106.00 then
   raise exception 'Negative non-game adjustment should still be allowed.';
 end if;

 begin
   perform public.nplus_wallet_change(-5.00,'GAME_BET','QA','stale client game debit');
   raise exception 'Generic wallet RPC allowed a caller-supplied GAME_BET debit.';
 exception when insufficient_privilege then
   null;
 end;

 begin
   perform public.nplus_wallet_change(5.00,'GAME_WIN','QA','forged credit attempt');
   raise exception 'Generic wallet RPC allowed a caller-supplied positive credit.';
 exception when insufficient_privilege then
   null;
 end;

 select balance into bal from public.demo_wallets where user_id=u;
 select count(*) into bet_count from public.demo_wallet_transactions where user_id=u;
 if bal<>106.00 or bet_count<>1 then
   raise exception 'Positive credit attempt modified wallet/ledger unexpectedly.';
 end if;

 raise notice 'Generic wallet credit and debit guard tests passed.';
end
$tests$;
