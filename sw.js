const V='onyaonni-v8',SHELL=['./','index.html','manifest.json','icons/icon.svg','icons/icon-192.png','icons/icon-512.png','img/bg.jpg','vendor/supabase.js','vendor/qrcode.js','vendor/jspdf.umd.min.js','fonts/inter-latin.woff2','fonts/inter-latin-ext.woff2','fonts/inter-cyrillic.woff2','fonts/inter-cyrillic-ext.woff2','fonts/playfair-latin.woff2','fonts/DejaVuSans.ttf','fonts/DejaVuSans-Bold.ttf'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(V).then(c=>Promise.all(SHELL.map(u=>c.add(u).catch(()=>{})))));self.skipWaiting()});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==V).map(x=>caches.delete(x)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',e=>{const r=e.request,u=new URL(r.url);if(r.method!=='GET')return;
if(u.hostname.endsWith('supabase.co')){
 if(u.pathname.includes('/storage/v1/object/public/')){e.respondWith(caches.open(V).then(async c=>{const m=await c.match(r);const n=fetch(r).then(res=>{if(res&&(res.ok||res.type==='opaque'))c.put(r,res.clone());return res}).catch(()=>m);return m||n}))}
 return}
if(u.origin!==location.origin)return;
e.respondWith(fetch(r).then(res=>{if(res.ok){const cp=res.clone();caches.open(V).then(c=>c.put(r,cp))}return res}).catch(()=>caches.match(r,{ignoreSearch:true}).then(m=>m||(r.mode==='navigate'?caches.match('index.html'):undefined)||Response.error())))});
