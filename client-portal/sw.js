const CACHE_NAME='cv-coach-shell-v73';
const APP_SHELL=[
  './','./index.html','./manifest.webmanifest','./icon.svg',
  './assets/cv-rank-v61.js','./assets/cv-rank-v61.css',
  './assets/ranks/cv-rank-tutorial-v61.webp',
  './assets/ranks/cv-rank-bronze-v61.webp','./assets/ranks/cv-rank-silver-v61.webp',
  './assets/ranks/cv-rank-gold-v61.webp','./assets/ranks/cv-rank-platinum-v61.webp',
  './assets/ranks/cv-rank-diamond-v61.webp','./assets/ranks/cv-rank-legend-v61.webp'
];

self.addEventListener('install',event=>{
  event.waitUntil(caches.open(CACHE_NAME).then(cache=>cache.addAll(APP_SHELL)).then(()=>self.skipWaiting()));
});

self.addEventListener('activate',event=>{
  event.waitUntil(Promise.all([
    caches.keys().then(keys=>Promise.all(keys.filter(key=>key!==CACHE_NAME).map(key=>caches.delete(key)))),
    self.clients.claim()
  ]));
});

self.addEventListener('fetch',event=>{
  const request=event.request;
  if(request.method!=='GET')return;
  const url=new URL(request.url);
  if(url.origin!==self.location.origin)return;
  if(request.mode==='navigate'){
    event.respondWith(fetch(request,{cache:'no-store'}).then(response=>response).catch(()=>caches.match('./index.html')));
    return;
  }
  const cacheable=APP_SHELL.some(item=>new URL(item,self.location.origin).pathname===url.pathname);
  if(!cacheable)return;
  event.respondWith(caches.match(request).then(cached=>cached||fetch(request).then(response=>{
    if(response&&response.ok){const copy=response.clone();caches.open(CACHE_NAME).then(cache=>cache.put(request,copy));}
    return response;
  })));
});
