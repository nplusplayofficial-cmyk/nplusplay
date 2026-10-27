'use strict';
const fs = require('node:fs');
const path = require('node:path');
const candidatePath = path.join(__dirname, '..', 'sql/NPLUS_PLAY_FINITE_NUMERIC_RPC_GUARDS_CANDIDATE_2026-10-27.sql');
function fail(s){console.error('FAIL: '+s);process.exitCode=1;}
function fn(sql,name){const m='CREATE OR REPLACE FUNCTION public.'+name+'(';const i=sql.indexOf(m);if(i<0){fail('missing '+name);return '';}const j=sql.indexOf('CREATE OR REPLACE FUNCTION public.',i+m.length);return sql.slice(i,j<0?sql.length:j);}
function before(body,guard,use,label){const g=body.indexOf(guard),u=body.indexOf(use);if(g<0||u<0||g>u)fail(label+': finite guard absent or after cast/write');}
if(!fs.existsSync(candidatePath)){fail('candidate function bundle is missing');process.exit();}
const s=fs.readFileSync(candidatePath,'utf8'),sp="('NaN','Infinity','-Infinity')";
before(fn(s,'nplus_create_demo_deposit_request'),'p_amount::text IN '+sp,'v_amount:=round(p_amount,2)','deposit');
before(fn(s,'nplus_create_demo_withdrawal_request'),'p_amount::text IN '+sp,'v_amount:=round(p_amount,2)','withdrawal');
before(fn(s,'nplus_demo_admin_create_gift_code'),'p_amount::text IN '+sp,'INSERT INTO public.nplus_demo_gift_codes','gift code');
before(fn(s,'nplus_approve_deposit'),'v_request.amount::text IN '+sp,'select w.balance','deposit approval stored amount');
before(fn(s,'nplus_demo_gift_redeem'),'v_amount::text IN '+sp,'INSERT INTO public.nplus_demo_gift_claims','gift redemption stored amount');
before(fn(s,'nplus_aviator_demo_place_bet'),'p_stake::text IN '+sp,'v_stake:=p_stake','Aviator stake');
before(fn(s,'nplus_aviator_demo_place_bet'),'p_auto_cashout::text IN '+sp,'v_stake:=p_stake','Aviator auto-cashout');
before(fn(s,'nplus_moto_demo_place_bet'),'p_stake::text IN '+sp,'stake_amt:=p_stake','Moto stake');
before(fn(s,'nplus_wingo_demo_place_bet'),'p_stake::text IN '+sp,'v_stake := p_stake','WINGO stake');
before(fn(s,'nplus_demo_safe_transfer'),'p_amount::text IN '+sp,'v_amount := p_amount','Safe transfer');
before(fn(s,'nplus_demo_admin_qualify_referral'),'p_verified_virtual_amount::text IN '+sp,'INSERT INTO public.nplus_demo_referral_qualifications','Referral qualification');
if(/\b(?:GRANT|REVOKE|DROP FUNCTION|DROP TABLE|TRUNCATE)\b/i.test(s))fail('unexpected ACL/schema operation');
if((s.match(/CREATE OR REPLACE FUNCTION public\./g)||[]).length!==10)fail('expected exactly ten function replacements');
if(!s.includes("SET search_path TO 'pg_catalog', 'public'"))fail('fixed search_path missing');
if(process.exitCode)console.error('Finite numeric RPC guard source contract failed.');
else console.log('PASS: finite input guards precede casts/writes in ten authenticated RPCs; ACLs/schema unchanged in candidate bundle.');
