(()=>{
'use strict';
const CV_CLIENT_PUSH_V101_READY='CV_CLIENT_PUSH_V101_READY';
const SUPABASE_FUNCTIONS='https://fmhcansyxcsqkrivqchr.supabase.co/functions/v1';
const ALLOWED_VIEWS=new Set(['home','routine','progress','missions','achievements','notifications']);
let center=null;
let busy=false;
let pushError='';

function hasRealUser(){
  try{return typeof mode!=='undefined'&&mode==='real'&&typeof user!=='undefined'&&!!user?.id&&typeof sb!=='undefined';}catch(_){return false;}
}
function uid(){try{return user?.id||null}catch(_){return null}}
function notify(message){try{if(typeof toast==='function')toast(message);else console.info(message)}catch(_){console.info(message)}}
function isIOS(){return /iPad|iPhone|iPod/.test(navigator.userAgent)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1)}
function isStandalone(){return navigator.standalone===true||window.matchMedia?.('(display-mode: standalone)')?.matches===true}
function supported(){return 'serviceWorker' in navigator&&'PushManager' in window&&'Notification' in window}
function permission(){return supported()?Notification.permission:'unsupported'}
function htmlEsc(value){return String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function timeValue(value,fallback=''){const raw=String(value??'');const m=raw.match(/^(\d{2}):(\d{2})/);return m?`${m[1]}:${m[2]}`:fallback}
function bool(value,fallback=true){return typeof value==='boolean'?value:fallback}
function urlB64ToBytes(base64String){
  const padding='='.repeat((4-base64String.length%4)%4);
  const base64=(base64String+padding).replace(/-/g,'+').replace(/_/g,'/');
  const raw=atob(base64);
  return Uint8Array.from([...raw].map(ch=>ch.charCodeAt(0)));
}
function deviceLabel(){
  const ua=navigator.userAgent;
  if(isIOS())return /iPad/.test(ua)?'iPad':'iPhone';
  if(/Android/i.test(ua))return 'Android';
  if(/Windows/i.test(ua))return 'Windows';
  if(/Macintosh|Mac OS X/i.test(ua))return 'Mac';
  return 'Dispositivo web';
}
function platformLabel(){return `${navigator.platform||'web'}${isStandalone()?' · PWA':''}`.slice(0,120)}
async function rpc(name,args={}){
  const result=await sb.rpc(name,args);
  if(result.error)throw result.error;
  return result.data;
}
async function loadCenter(force=false){
  if(!hasRealUser())return null;
  if(center&&!force)return center;
  center=await rpc('get_push_center_v101',{p_actor_id:uid()});
  return center;
}
async function currentSubscription(){
  if(!supported())return null;
  const registration=await navigator.serviceWorker.ready;
  return registration.pushManager.getSubscription();
}
function statusModel(){
  const active=Number(center?.subscriptions?.active||0);
  const configured=center?.configured===true;
  const perm=permission();
  if(!supported())return {tone:'bad',title:'No compatible',detail:'Este navegador no expone Web Push.'};
  if(isIOS()&&!isStandalone())return {tone:'warn',title:'Añade CV Coach a inicio',detail:'En iPhone/iPad, abre CV Coach desde el icono de la pantalla de inicio para activar notificaciones.'};
  if(perm==='denied')return {tone:'bad',title:'Permiso bloqueado',detail:'Las notificaciones están bloqueadas en los ajustes del dispositivo/navegador.'};
  if(!configured)return {tone:'bad',title:'Servicio no configurado',detail:'El backend Push no está listo todavía.'};
  if(perm==='granted'&&active>0)return {tone:'ok',title:'Push activado',detail:`${active} dispositivo${active===1?'':'s'} activo${active===1?'':'s'} en tu cuenta.`};
  return {tone:'neutral',title:'Push disponible',detail:'Actívalo para recibir avisos aunque CV Coach esté cerrado.'};
}
function injectStyle(){
  if(document.getElementById('cvPushV101Style'))return;
  const style=document.createElement('style');
  style.id='cvPushV101Style';
  style.textContent=`
  .cvPushV101{margin:14px 0;border:1px solid #334048;background:linear-gradient(180deg,#0d1519,#080d10);border-radius:16px;padding:14px;box-shadow:0 14px 36px rgba(0,0,0,.22)}
  .cvPushV101Head{display:flex;gap:10px;align-items:flex-start}.cvPushV101Head .grow{flex:1}.cvPushV101Title{font:800 22px 'Barlow Condensed',sans-serif}.cvPushV101Detail{font-size:10px;color:#98a4aa;line-height:1.45;margin-top:3px}
  .cvPushV101Badge{font-size:8px;font-weight:900;letter-spacing:.08em;border-radius:999px;padding:5px 8px;border:1px solid #39464d}.cvPushV101Badge.ok{color:#6ce7a3;border-color:#2c6b49}.cvPushV101Badge.warn{color:#ffc77f;border-color:#6e4c1f}.cvPushV101Badge.bad{color:#ff8795;border-color:#6a2630}.cvPushV101Badge.neutral{color:#aac7ff;border-color:#31517e}
  .cvPushV101Actions{display:flex;gap:8px;flex-wrap:wrap;margin-top:12px}.cvPushV101Actions .btn{flex:1;min-width:130px}
  .cvPushV101Prefs{display:grid;grid-template-columns:1fr 1fr;gap:8px;margin-top:12px}.cvPushV101Toggle{display:flex;align-items:center;gap:8px;border:1px solid #253139;border-radius:11px;padding:10px;background:#070c0f;color:#c8d0d4;font-size:10px}.cvPushV101Toggle input{accent-color:#ff2037}
  .cvPushV101Times{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-top:10px}.cvPushV101Times label{margin:0}.cvPushV101Times input{width:100%;min-height:40px;background:#070c0f;border:1px solid #2c383f;border-radius:10px;color:#fff;padding:0 9px}
  .cvPushV101Note{margin-top:10px;font-size:9px;line-height:1.45;color:#849198}.cvPushV101Error{margin-top:8px;color:#ff8795;font-size:10px}.cvPushV101Save{margin-top:10px;width:100%}
  @media(max-width:520px){.cvPushV101Prefs,.cvPushV101Times{grid-template-columns:1fr}.cvPushV101Head{align-items:center}}
  `;
  document.head.append(style);
}
function renderPanel(){
  const content=document.getElementById('content');
  if(!content||!document.getElementById('cvNotificationList'))return;
  injectStyle();
  let panel=document.getElementById('cvPushV101');
  if(!panel){
    panel=document.createElement('section');
    panel.id='cvPushV101';panel.className='cvPushV101';
    const toolbar=document.querySelector('.cvNotificationToolbar');
    if(toolbar)toolbar.insertAdjacentElement('afterend',panel);else content.prepend(panel);
  }
  const s=statusModel(),p=center?.preferences||{},perm=permission();
  const canActivate=supported()&&center?.configured===true&&!(isIOS()&&!isStandalone())&&perm!=='denied';
  const active=perm==='granted'&&Number(center?.subscriptions?.active||0)>0;
  const iosHelp=isIOS()&&!isStandalone()?'<div class="cvPushV101Note"><b>iPhone/iPad:</b> toca Compartir → Añadir a pantalla de inicio, abre CV Coach desde ese icono y vuelve aquí. Apple solo habilita Web Push para la web app instalada.</div>':'';
  panel.innerHTML=`
    <div class="cvPushV101Head"><div class="grow"><div class="cvPushV101Title">🔔 NOTIFICACIONES DEL DISPOSITIVO</div><div class="cvPushV101Detail">Avisos de rutina, seguimiento, progreso y mensajes importantes incluso con CV Coach cerrado.</div></div><span class="cvPushV101Badge ${htmlEsc(s.tone)}">${htmlEsc(s.title)}</span></div>
    <div class="cvPushV101Detail" style="margin-top:8px">${htmlEsc(s.detail)}</div>${iosHelp}
    <div class="cvPushV101Actions"><button id="cvPushEnableV101" class="btn primary" type="button" ${canActivate&&!active&&!busy?'':'disabled'}>${active?'ACTIVADO':'ACTIVAR EN ESTE DISPOSITIVO'}</button><button id="cvPushTestV101" class="btn" type="button" ${active&&!busy?'':'disabled'}>ENVIAR PRUEBA</button><button id="cvPushDisableV101" class="btn" type="button" ${active&&!busy?'':'disabled'}>DESACTIVAR DISPOSITIVO</button></div>
    <div class="cvPushV101Prefs">
      ${toggle('cvPushTrainingV101','Entrenamiento y check-in',bool(p.training_reminders,true))}
      ${toggle('cvPushProgramV101','Rutinas y onboarding',bool(p.program_updates,true))}
      ${toggle('cvPushProgressV101','Progreso, logros y CV Rank',bool(p.progress_updates,true))}
      ${toggle('cvPushCoachV101','Mensajes del coach',bool(p.coach_updates,true))}
      ${toggle('cvPushSystemV101','Sistema CV Coach',bool(p.system_updates,true))}
      ${toggle('cvPushMasterV101','Push habilitado',bool(p.enabled,true))}
    </div>
    <div class="cvPushV101Times"><label>Silencio desde<input id="cvPushQuietStartV101" type="time" value="${htmlEsc(timeValue(p.quiet_hours_start,'21:00'))}"></label><label>Silencio hasta<input id="cvPushQuietEndV101" type="time" value="${htmlEsc(timeValue(p.quiet_hours_end,'08:00'))}"></label><label>Recordatorio gym<input id="cvPushWorkoutTimeV101" type="time" value="${htmlEsc(timeValue(p.workout_reminder_time,''))}"></label></div>
    <div class="cvPushV101Note">El recordatorio del gym solo se genera en los días de entrenamiento que declaraste y únicamente si eliges una hora. Las horas silenciosas no eliminan el aviso: retrasan su entrega.</div>
    <button id="cvPushSaveV101" class="btn cvPushV101Save" type="button" ${busy?'disabled':''}>GUARDAR PREFERENCIAS</button>
    ${pushError?`<div class="cvPushV101Error">${htmlEsc(pushError)}</div>`:''}`;
  bindPanel();
}
function toggle(id,label,checked){return `<label class="cvPushV101Toggle"><input id="${id}" type="checkbox" ${checked?'checked':''}><span>${htmlEsc(label)}</span></label>`}
function bindPanel(){
  document.getElementById('cvPushEnableV101')?.addEventListener('click',enablePush);
  document.getElementById('cvPushDisableV101')?.addEventListener('click',disablePush);
  document.getElementById('cvPushTestV101')?.addEventListener('click',testPush);
  document.getElementById('cvPushSaveV101')?.addEventListener('click',savePreferences);
}
async function enablePush(){
  if(busy||!hasRealUser())return;
  busy=true;pushError='';renderPanel();
  try{
    if(!supported())throw new Error('Este navegador no soporta Web Push.');
    if(isIOS()&&!isStandalone())throw new Error('En iPhone/iPad debes abrir CV Coach desde el icono añadido a la pantalla de inicio.');
    const c=await loadCenter(true);
    if(!c?.configured||!c?.vapid_public_key)throw new Error('El servicio Push todavía no está configurado.');
    // IMPORTANT V101 GUARDRAIL: Notification.requestPermission() is called only inside this explicit click handler.
    const granted=Notification.permission==='granted'?'granted':await Notification.requestPermission();
    if(granted!=='granted')throw new Error(granted==='denied'?'El permiso fue bloqueado. Puedes cambiarlo desde los ajustes del dispositivo.':'No se concedió permiso para notificaciones.');
    const registration=await navigator.serviceWorker.ready;
    let subscription=await registration.pushManager.getSubscription();
    if(!subscription){subscription=await registration.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:urlB64ToBytes(c.vapid_public_key)});}
    const json=subscription.toJSON();
    if(!json.endpoint||!json.keys?.p256dh||!json.keys?.auth)throw new Error('El navegador no devolvió una suscripción Web Push completa.');
    await rpc('register_push_subscription_v101',{
      p_actor_id:uid(),p_endpoint:json.endpoint,p_p256dh:json.keys.p256dh,p_auth_secret:json.keys.auth,
      p_expiration_time:json.expirationTime??null,p_user_agent:navigator.userAgent,p_device_label:deviceLabel(),p_platform:platformLabel()
    });
    center=null;await loadCenter(true);notify('Notificaciones activadas en este dispositivo.');
  }catch(error){pushError=String(error?.message||error);}
  finally{busy=false;renderPanel();}
}
async function disablePush(){
  if(busy||!hasRealUser())return;
  busy=true;pushError='';renderPanel();
  try{
    const subscription=await currentSubscription();
    if(subscription){await rpc('disable_push_subscription_v101',{p_actor_id:uid(),p_endpoint:subscription.endpoint});await subscription.unsubscribe();}
    center=null;await loadCenter(true);notify('Push desactivado en este dispositivo.');
  }catch(error){pushError=String(error?.message||error);}
  finally{busy=false;renderPanel();}
}
async function savePreferences(){
  if(busy||!hasRealUser())return;
  busy=true;pushError='';renderPanel();
  try{
    const v=id=>document.getElementById(id);
    await rpc('set_push_preferences_v101',{
      p_actor_id:uid(),p_enabled:v('cvPushMasterV101').checked,p_training_reminders:v('cvPushTrainingV101').checked,
      p_program_updates:v('cvPushProgramV101').checked,p_progress_updates:v('cvPushProgressV101').checked,
      p_coach_updates:v('cvPushCoachV101').checked,p_system_updates:v('cvPushSystemV101').checked,
      p_quiet_hours_start:v('cvPushQuietStartV101').value||'21:00',p_quiet_hours_end:v('cvPushQuietEndV101').value||'08:00',
      p_timezone:Intl.DateTimeFormat().resolvedOptions().timeZone||'America/Santiago',p_workout_reminder_time:v('cvPushWorkoutTimeV101').value||null
    });
    center=null;await loadCenter(true);notify('Preferencias de notificaciones guardadas.');
  }catch(error){pushError=String(error?.message||error);}
  finally{busy=false;renderPanel();}
}
async function testPush(){
  if(busy||!hasRealUser())return;
  busy=true;pushError='';renderPanel();
  try{
    const subscription=await currentSubscription();
    if(!subscription||Notification.permission!=='granted')throw new Error('Activa primero las notificaciones en este dispositivo.');
    const queued=await rpc('enqueue_push_test_v101',{p_actor_id:uid()});
    const notificationId=queued?.notification_id;
    if(!notificationId)throw new Error('No se pudo crear la notificación de prueba.');
    const sessionResult=await sb.auth.getSession();
    const token=sessionResult?.data?.session?.access_token;
    if(!token)throw new Error('Tu sesión expiró. Vuelve a iniciar sesión.');
    const response=await fetch(`${SUPABASE_FUNCTIONS}/push-dispatch-v101`,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({action:'test',notification_id:notificationId})});
    const data=await response.json().catch(()=>({}));
    if(!response.ok)throw new Error(data?.error||`HTTP ${response.status}`);
    center=null;await loadCenter(true);
    const outcome=data?.result?.outcome||data?.message||'procesada';
    notify(`Prueba Push: ${outcome}.`);
  }catch(error){pushError=String(error?.message||error);}
  finally{busy=false;renderPanel();}
}
function safeView(value){const v=String(value||'');return ALLOWED_VIEWS.has(v)?v:'home'}
function routeToView(v){
  const target=safeView(v);
  try{
    if(target==='notifications'&&typeof window.openNotifications==='function'){window.openNotifications();return;}
    if(typeof nav==='function'){nav(target);return;}
  }catch(_){ }
}
function consumeLaunchParams(){
  try{
    const url=new URL(location.href);const raw=url.searchParams.get('cv_push_view');
    if(!raw)return;
    const view=safeView(raw);url.searchParams.delete('cv_push_view');url.searchParams.delete('cv_push_notification');
    history.replaceState(history.state,'',url.pathname+url.search+url.hash);
    setTimeout(()=>routeToView(view),150);
  }catch(_){ }
}
navigator.serviceWorker?.addEventListener?.('message',event=>{
  const data=event.data&&typeof event.data==='object'?event.data:{};
  if(data.type==='CV_PUSH_OPEN_V101')routeToView(data.view);
});

const baseOpen=window.openNotifications;
if(typeof baseOpen==='function'){
  window.openNotifications=function(){const out=baseOpen.apply(this,arguments);setTimeout(()=>{loadCenter(true).then(renderPanel).catch(error=>{pushError=String(error?.message||error);renderPanel()})},0);return out;};
}
const baseRender=window.render;
if(typeof baseRender==='function'){
  window.render=function(){const out=baseRender.apply(this,arguments);setTimeout(()=>{if(document.getElementById('cvNotificationList')&&hasRealUser()){loadCenter().then(renderPanel).catch(()=>{})}},0);return out;};
}
window.CVPushV101={version:'101',ready:true,supported,enable:enablePush,test:testPush};
window.addEventListener('load',()=>{consumeLaunchParams();if(document.getElementById('cvNotificationList')&&hasRealUser())loadCenter().then(renderPanel).catch(()=>{});});
})();
