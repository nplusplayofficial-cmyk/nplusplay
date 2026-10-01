(() => {
"use strict";
const CFG=window.NPlusConfig||{}, ACTIVE_UID="nplus_authenticated_uid_v1", PREFIX="nplus_uidstore_v2__", WALLET="__wallet_balance__";
const TRACKED=new Set(["nplusplay_wingo_ultra_final_v2","nplusplay_k3_wingo_style_v1","nplus_moto_race_clean_v1","nplus_aviator_demo_final_v3","nplus_trxwingo_demo_v2","nplus_5d_final_v5"]);
const g=Storage.prototype.getItem,s=Storage.prototype.setItem,r=Storage.prototype.removeItem;
const uid=()=>localStorage.getItem(ACTIVE_UID)||"";
const key=k=>uid()?PREFIX+encodeURIComponent(uid())+"__"+encodeURIComponent(k):k;
const walletKey=()=>key(WALLET);
const readWallet=()=>{try{const x=JSON.parse(g.call(localStorage,walletKey())||"null");if(x&&Number.isFinite(Number(x.balance)))return Number(x.balance)}catch{}return Number(CFG.initialDemoBalance||1000)};
const writeWallet=v=>{const n=Math.max(0,Number(v)||0);if(uid())s.call(localStorage,walletKey(),JSON.stringify({balance:n,updatedAt:Date.now()}));window.dispatchEvent(new CustomEvent("nplus-wallet-sync",{detail:{balance:n}}));return n};
function migrate(k){if(!uid())return;const nk=key(k);if(g.call(localStorage,nk)!==null)return;const old=g.call(localStorage,k);if(old!==null){s.call(localStorage,nk,old);r.call(localStorage,k)}}
if(uid()) TRACKED.forEach(migrate);

Storage.prototype.getItem=function(k){
  if(!uid()||!TRACKED.has(k)) return g.call(this,k);
  const nk=key(k); let raw=g.call(this,nk);
  if(raw===null){migrate(k);raw=g.call(this,nk)}
  if(raw===null) return k==="nplus_trxwingo_demo_v2"?JSON.stringify({bets:[]}):JSON.stringify({balance:readWallet()});
  try{const o=JSON.parse(raw);if(o&&typeof o==="object"&&"balance" in o){o.balance=readWallet();return JSON.stringify(o)}}catch{}
  return raw;
};

let last=readWallet(), queue=Promise.resolve();
function serverDelta(gameKey,raw){
  if(!window.NPlusAuth?.isSupabase?.()||!window.supabase||!uid()) return;
  try{
    const o=JSON.parse(raw); if(!o||typeof o.balance!=="number") return;
    const next=Number(o.balance), delta=Number((next-last).toFixed(2)); if(!delta)return; last=next;
    const sb=window.supabase.createClient(CFG.supabaseUrl,CFG.supabaseAnonKey);
    queue=queue.then(async()=>{
      const {data,error}=await sb.rpc("change_demo_balance",{p_delta:delta,p_reason:"GAME_SYNC",p_game:gameKey});
      if(!error&&Number.isFinite(Number(data))){writeWallet(Number(data));last=Number(data)}
    }).catch(()=>{});
  }catch{}
}
Storage.prototype.setItem=function(k,v){
  if(!uid()||!TRACKED.has(k)) return s.call(this,k,v);
  const nk=key(k); let out=v;
  try{const o=JSON.parse(v);if(o&&typeof o==="object"&&"balance" in o){const n=Number(o.balance);if(Number.isFinite(n))writeWallet(n);o.balance=readWallet();out=JSON.stringify(o)}}catch{}
  s.call(this,nk,out); serverDelta(k,v);
};
window.NPlusWallet={
  get:readWallet,
  set:writeWallet,
  spend(amount){const n=Math.max(0,Number(amount)||0),b=readWallet();if(n>b)return false;writeWallet(Number((b-n).toFixed(2)));return true},
  credit(amount){const n=Math.max(0,Number(amount)||0);writeWallet(Number((readWallet()+n).toFixed(2)));return true},
  uid
};
if(!uid()&&!/auth\.html$/i.test(location.pathname)){
  const next=encodeURIComponent(location.pathname.split("/").pop()+location.search+location.hash);
  location.replace("auth.html?next="+next); return;
}
})();
