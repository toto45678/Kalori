// offline shell; API calls always go to the network; the text reader (ocr/) is cached the first time it is used
const C='kalori-v12',FILES=['./','index.html','manifest.webmanifest','icons/icon-192.png'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(C).then(c=>c.addAll(FILES)));self.skipWaiting()});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==C&&k!=='kalori-ocr-1').map(k=>caches.delete(k)))));self.clients.claim()});
self.addEventListener('fetch',e=>{const u=new URL(e.request.url);if(e.request.method!=='GET'||u.origin!==location.origin)return;
 if(u.pathname.includes('/ocr/')){e.respondWith(caches.open('kalori-ocr-1').then(c=>c.match(e.request).then(m=>m||fetch(e.request).then(r=>{if(r.ok)c.put(e.request,r.clone());return r}))));return}
 e.respondWith(fetch(e.request).then(r=>{if(r.ok){const cp=r.clone();caches.open(C).then(c=>c.put(e.request,cp))}return r}).catch(()=>caches.match(e.request,{ignoreSearch:true})))});
