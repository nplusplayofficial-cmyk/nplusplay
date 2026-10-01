(() => {
"use strict";
const CFG=window.NPlusConfig||{};
const SESSION_KEY="nplus_session_v1", ACCOUNTS_KEY="nplus_demo_accounts_v1", UID_MARKER="nplus_authenticated_uid_v1";
const USE_SUPABASE=!!window.supabase && typeof CFG.supabaseUrl==="string" && CFG.supabaseUrl.startsWith("https://") && CFG.supabaseAnonKey && CFG.supabaseAnonKey!=="YOUR_SUPABASE_ANON_KEY";
const sb=USE_SUPABASE?window.supabase.createClient(CFG.supabaseUrl,CFG.supabaseAnonKey):null;
const emailClean=v=>String(v||"").trim().toLowerCase();
const uidFromAuth=id=>"NPLUS-"+String(id||"").replace(/-/g,"").slice(0,8).toUpperCase();
async function hash(v){const b=new TextEncoder().encode(v);if(crypto?.subtle){const h=await crypto.subtle.digest("SHA-256",b);return [...new Uint8Array(h)].map(x=>x.toString(16).padStart(2,"0")).join("")}return btoa(unescape(encodeURIComponent(v)))}
function accounts(){try{const x=JSON.parse(localStorage.getItem(ACCOUNTS_KEY)||"[]");return Array.isArray(x)?x:[]}catch{return[]}}
function saveAccounts(x){localStorage.setItem(ACCOUNTS_KEY,JSON.stringify(x))}
function setSession(s){localStorage.setItem(SESSION_KEY,JSON.stringify(s));localStorage.setItem(UID_MARKER,s.uid);return s}
async function signUp({name,email,password}){
  const e=emailClean(email), n=String(name||"").trim();
  if(!n) throw new Error("Enter your name.");
  if(!e.includes("@")) throw new Error("Enter a valid email.");
  if(!password || password.length<6) throw new Error("Password must be at least 6 characters.");
  if(USE_SUPABASE){
    const {data,error}=await sb.auth.signUp({email:e,password,options:{data:{full_name:n}}});
    if(error) throw error;
    if(!data.user) throw new Error("Account could not be created.");
    const s={mode:"supabase",uid:uidFromAuth(data.user.id),authId:data.user.id,email:data.user.email||e,name:n};
    if(data.session) setSession(s); else localStorage.setItem("nplus_pending_signup_email_v1",e);
    return {...s,needsEmailConfirmation:!data.session};
  }
  const rows=accounts();
  if(rows.some(x=>x.email===e)) throw new Error("Account already exists.");
  const uid="NPLUS-"+crypto.randomUUID().replace(/-/g,"").slice(0,8).toUpperCase();
  const row={uid,email:e,name:n,passwordHash:await hash(password),createdAt:Date.now()};
  rows.push(row); saveAccounts(rows); return setSession({mode:"demo",...row});
}
async function signIn({email,password}){
  const e=emailClean(email);
  if(!e||!password) throw new Error("Enter email and password.");
  if(USE_SUPABASE){
    const {data,error}=await sb.auth.signInWithPassword({email:e,password});
    if(error) throw error;
    const u=data.user;
    if(!u) throw new Error("Login failed.");
    return setSession({mode:"supabase",uid:uidFromAuth(u.id),authId:u.id,email:u.email||e,name:u.user_metadata?.full_name||u.user_metadata?.name||"N+ Member"});
  }
  const row=accounts().find(x=>x.email===e);
  if(!row || row.passwordHash!==(await hash(password))) throw new Error("Incorrect email or password.");
  return setSession({mode:"demo",...row});
}
async function signOut(){
  if(USE_SUPABASE){try{await sb.auth.signOut()}catch{}}
  localStorage.removeItem(SESSION_KEY); localStorage.removeItem(UID_MARKER);
}
async function current(){
  if(USE_SUPABASE){
    const {data}=await sb.auth.getUser();
    if(!data?.user) return null;
    const u=data.user, s={mode:"supabase",uid:uidFromAuth(u.id),authId:u.id,email:u.email||"",name:u.user_metadata?.full_name||u.user_metadata?.name||"N+ Member"};
    localStorage.setItem(SESSION_KEY,JSON.stringify(s)); localStorage.setItem(UID_MARKER,s.uid); return s;
  }
  try{const x=JSON.parse(localStorage.getItem(SESSION_KEY)||"null");return x?.uid?x:null}catch{return null}
}
window.NPlusAuth={isSupabase:()=>USE_SUPABASE,configMode:()=>USE_SUPABASE?"SUPABASE":"LOCAL DEMO",signUp,signIn,signOut,current};
})();
