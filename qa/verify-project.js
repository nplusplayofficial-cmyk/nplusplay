#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const cp = require('child_process');
const root = path.resolve(__dirname, '..');
const htmls = fs.readdirSync(root).filter(f => f.endsWith('.html'));
let errors = 0;
for (const file of htmls) {
  const html = fs.readFileSync(path.join(root,file),'utf8');
  const scripts = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script\s*>/gi)];
  let scriptIndex = 0;
  for (const m of scripts) {
    if (!m[1].trim()) { scriptIndex++; continue; }
    const temp = path.join(require('os').tmpdir(),`nplus-${process.pid}-${scriptIndex}.js`);
    fs.writeFileSync(temp,m[1]);
    const r = cp.spawnSync('node',['--check',temp],{encoding:'utf8'});
    fs.unlinkSync(temp);
    if (r.status !== 0) { errors++; console.error(`FAIL JS ${file} script ${scriptIndex}: ${r.stderr}`); }
    scriptIndex++;
  }
  const markupOnly = html.replace(/<script\b[^>]*>[\s\S]*?<\/script\s*>/gi, "").replace(/<style\b[^>]*>[\s\S]*?<\/style\s*>/gi, "");
  const ids = [...markupOnly.matchAll(/\bid=["']([^"']+)["']/gi)].map(x=>x[1]);
  const dup = [...new Set(ids.filter((id,i)=>ids.indexOf(id)!==i))];
  if (dup.length) console.warn(`WARN duplicate IDs ${file}: ${dup.join(', ')}`);
  if (!html.includes('manifest.webmanifest')) console.warn(`WARN no PWA manifest link: ${file}`);
}
for (const rel of ['manifest.webmanifest','sw.js','offline.html','assets/nplus-icon.svg','core/README-PRESERVE-EXISTING-CORE.txt','sql/NPLUS_PLAY_PREMIUM_FOUNDATION.sql']) {
  if (!fs.existsSync(path.join(root,rel))) { errors++; console.error('FAIL missing '+rel); }
}
for (const file of ['sw.js']) {
  const r = cp.spawnSync('node',['--check',path.join(root,file)],{encoding:'utf8'});
  if (r.status !== 0) { errors++; console.error(`FAIL JS ${file}: ${r.stderr}`); }
}
console.log(`HTML pages: ${htmls.length}`);
console.log(`Inline/external JavaScript syntax errors: ${errors}`);
console.log(`PWA/core/SQL assets: ${errors===0?'present':'check failures above'}`);
process.exit(errors?1:0);
