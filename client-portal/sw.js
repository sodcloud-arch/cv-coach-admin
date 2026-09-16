const CACHE_NAME='cv-coach-shell-v101';
const CV_PUSH_SW_V101_READY='CV_PUSH_SW_V101_READY';
const APP_SHELL=[
  './','./index.html','./manifest.webmanifest','./icon.svg',
  './assets/cv-rank-v61.js','./assets/cv-rank-v61.css',
  './assets/cv-push-v101.js',
  './assets/ranks/cv-rank-tutorial-v61.webp',
  './assets/ranks/cv-rank-bronze-v61.webp','./assets/ranks/cv-rank-silver-v61.webp',
  './assets/ranks/cv-rank-gold-v61.webp','./assets/ranks/cv-rank-platinum-v61.webp',
  './assets/ranks/cv-rank-diamond-v61.webp','./assets/ranks/cv-rank-legend-v61.webp'
];

const PUSH_ROUTE_TO_VIEW={
  '/':'home',
  '/routine':'routine',
  '/progress':'progress',
  '/progress/missions':'missions',
  '/progress/achievements':'achievements'
};
const PUSH_VIEWS=new Set(Object.values(PUSH_ROUTE_TO_VIEW));

function safePushPayload(event){
  try{
    const value=event.data?.json?.();
    return value&&typeof value==='object'&&!Array.isArray(value)?value:{};
  }catch(_){
    try{return {body:event.data?.text?.()||''};}catch(__){return {};}
  }
}
function safePushRoute(value){
  if(typeof value!=='string'||!value.startsWith('/')||value.startsWith('//'))return '/';
  try{
    const url=new URL(value,self.location.origin);
    if(url.origin!==self.location.origin)return '/';
    return Object.prototype.hasOwnProperty.call(PUSH_ROUTE_TO_VIEW,url.pathname)?url.pathname:'/';
  }catch(_){return '/';}
}
function safePushView(value){
  const v=String(value||'');
  return PUSH_VIEWS.has(v)?v:'home';
}

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

self.addEventListener('push',event=>{
  const payload=safePushPayload(event);
  const route=safePushRoute(payload.action_url);
  const view=PUSH_ROUTE_TO_VIEW[route]||'home';
  const notificationId=typeof payload.notification_id==='string'?payload.notification_id:null;
  const title=String(payload.title||'CV Coach').slice(0,160);
  const body=String(payload.body||'').slice(0,600);
  const tag=String(payload.tag||(`cv-${notificationId||Date.now()}`)).slice(0,180);
  event.waitUntil(self.registration.showNotification(title,{
    body,
    icon:'./icon.svg',
    badge:'./icon.svg',
    tag,
    renotify:false,
    data:{
      v:'101',
      view,
      action_url:route,
      notification_id:notificationId
    }
  }));
});

self.addEventListener('notificationclick',event=>{
  event.notification.close();
  const data=event.notification?.data&&typeof event.notification.data==='object'?event.notification.data:{};
  const view=safePushView(data.view||PUSH_ROUTE_TO_VIEW[safePushRoute(data.action_url)]);
  const notificationId=typeof data.notification_id==='string'?data.notification_id:null;
  const target=new URL('./',self.location.href);
  target.searchParams.set('cv_push_view',view);
  if(notificationId)target.searchParams.set('cv_push_notification',notificationId);
  event.waitUntil((async()=>{
    const windows=await self.clients.matchAll({type:'window',includeUncontrolled:true});
    const existing=windows.find(client=>{
      try{return new URL(client.url).origin===self.location.origin;}catch(_){return false;}
    });
    if(existing){
      existing.postMessage({type:'CV_PUSH_OPEN_V101',view,notification_id:notificationId});
      if('focus' in existing)await existing.focus();
      return;
    }
    if(self.clients.openWindow)await self.clients.openWindow(target.href);
  })());
});
