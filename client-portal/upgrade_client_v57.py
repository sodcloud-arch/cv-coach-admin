from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent
HTML = ROOT / "stable" / "index.html"
BUILD = ROOT / "stable" / "build.json"
MARKER = "<!-- cv-client-modules-v57: audited habits missions progress notifications onboarding -->"

text = HTML.read_text(encoding="utf-8")

STYLE = r'''<style id="cv-client-modules-v57-css">
:root{--cv57-blue:#43b8ff;--cv57-blue2:#249fe8;--cv57-green:#5ee3a5;--cv57-red:#e11d2e;--cv57-panel:#0a1117;--cv57-line:#2a3943;--cv57-muted:#91a0a9}
.cvModuleHeroV57{margin:0 0 14px;padding:17px;border:1px solid rgba(67,184,255,.28);border-radius:17px;background:radial-gradient(circle at 100% 0,rgba(67,184,255,.10),transparent 34%),linear-gradient(150deg,#0e171e,#080d12);box-shadow:0 16px 42px rgba(0,0,0,.24)}
.cvModuleHeroV57 h2{font-size:27px;margin:4px 0 5px}.cvModuleHeroV57 p{margin:0;color:#a8b4bb;font-size:12px;line-height:1.5}.cvModuleChipsV57{display:flex;flex-wrap:wrap;gap:6px;margin-top:11px}.cvModuleChipV57{display:inline-flex;align-items:center;min-height:27px;padding:0 9px;border:1px solid #31424d;border-radius:999px;background:#071016;color:#c4d0d6;font-size:8px;font-weight:850}.cvModuleChipV57.good{border-color:rgba(94,227,165,.30);background:rgba(94,227,165,.07);color:#8af0be}.cvModuleChipV57.info{border-color:rgba(67,184,255,.30);background:rgba(67,184,255,.07);color:#89d6ff}
.cvWeeklyHomeV57{margin:10px 0 14px;padding:15px;border:1px solid rgba(67,184,255,.30);border-radius:16px;background:linear-gradient(145deg,rgba(67,184,255,.085),#091116 68%);box-shadow:0 15px 36px rgba(0,0,0,.22)}.cvWeeklyHomeV57 .row{align-items:center}.cvWeeklyHomeV57 strong{font-size:15px}.cvWeeklyHomeV57 p{margin:5px 0 0;color:#9eacb4;font-size:11px;line-height:1.45}.cvWeeklyHomeV57 .btn{margin-left:auto;min-height:40px!important;height:40px!important;font-size:10px!important}
.cvHabitStatusV57{display:inline-flex;align-items:center;gap:5px;margin-top:5px;padding:4px 7px;border:1px solid #34434d;border-radius:999px;color:#8f9ca4;font-size:7px;font-weight:900;letter-spacing:.05em;text-transform:uppercase}.cvHabitStatusV57.done{border-color:rgba(94,227,165,.32);background:rgba(94,227,165,.07);color:#7cebb3}.cvHabitStatusV57.pending{border-color:rgba(67,184,255,.25);background:rgba(67,184,255,.05);color:#7bcfff}.cvHabitStatusV57:before{content:'●';font-size:6px}.cvPositiveActionV57{border-color:rgba(94,227,165,.40)!important;background:rgba(94,227,165,.10)!important;color:#8df2c0!important}
.cvNutritionV57{margin-top:12px;padding-top:12px;border-top:1px solid #223039}.cvNutritionV57 h3{font-size:18px;margin:0 0 3px}.cvNutritionV57 p{margin:0;color:#8f9da5;font-size:10px;line-height:1.45}.cvMealButtonsV57{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:7px;margin-top:11px}.cvMealButtonsV57 button{min-height:43px;border:1px solid #33434d;border-radius:11px;background:#071016;color:#d5dce0;font-size:11px;font-weight:900}.cvMealButtonsV57 button.selected{border-color:rgba(94,227,165,.50);background:rgba(94,227,165,.11);color:#9af3c7;box-shadow:0 0 18px rgba(94,227,165,.07)}.cvNutritionStatusV57{margin-top:9px;color:#90a0aa;font-size:10px}.cvNutritionStatusV57.good{color:#7cebb3}
.cvMissionGroupV57{margin-top:16px}.cvMissionGroupV57>h2{font-size:25px;margin:0 0 9px}.cvMissionGridV57{display:grid;gap:9px}.cvMissionCardV57{padding:14px;border:1px solid #293842;border-radius:15px;background:linear-gradient(150deg,#0d151b,#080d11);box-shadow:0 12px 30px rgba(0,0,0,.20)}.cvMissionCardV57.complete{border-color:rgba(94,227,165,.28);background:linear-gradient(150deg,#0b1713,#07100d)}.cvMissionCardV57.closed{opacity:.72}.cvMissionHeadV57{display:flex;align-items:flex-start;gap:10px}.cvMissionHeadV57 .grow{min-width:0}.cvMissionCardV57 h3{font-size:20px;line-height:1.12;margin:0}.cvMissionCardV57 p{margin:5px 0 0;color:#9daab2;font-size:10.5px;line-height:1.45}.cvMissionBadgeV57{flex:0 0 auto;padding:5px 7px;border:1px solid rgba(67,184,255,.28);border-radius:999px;background:rgba(67,184,255,.06);color:#7fd2ff;font-size:7px;font-weight:900;letter-spacing:.06em}.cvMissionBadgeV57.good{border-color:rgba(94,227,165,.30);background:rgba(94,227,165,.07);color:#7cebb3}.cvMissionProgressV57{height:7px;margin-top:11px;border-radius:999px;background:#18242b;overflow:hidden}.cvMissionProgressV57 i{display:block;height:100%;border-radius:inherit;background:linear-gradient(90deg,#2caaf2,#4ec7d5 55%,#5ee3a5)}.cvMissionMetaV57{display:flex;flex-wrap:wrap;gap:7px;margin-top:9px;color:#819099;font-size:8.5px}.cvMissionMetaV57 b{color:#dce4e8}.cvMissionAutoV57{margin-top:8px;color:#71818b;font-size:8.5px;line-height:1.4}.cvMissionEmptyV57{padding:18px;text-align:center;border:1px dashed #31404a;border-radius:14px;color:#819099;font-size:11px}
.cvProgressQuickV57{display:grid;grid-template-columns:repeat(3,1fr);gap:7px;margin:12px 0}.cvProgressQuickV57 .cvQuickV57{padding:11px;border:1px solid #293841;border-radius:13px;background:#081015}.cvProgressQuickV57 small{display:block;color:#7f8d95;font-size:7.5px;text-transform:uppercase;letter-spacing:.07em}.cvProgressQuickV57 b{display:block;margin-top:5px;font-size:22px}.cvProgressNavV57{display:flex;gap:6px;overflow:auto;margin:-2px 0 12px;padding:2px 0 4px;scrollbar-width:none}.cvProgressNavV57::-webkit-scrollbar{display:none}.cvProgressNavV57 button{flex:0 0 auto;min-height:34px;padding:0 10px;border:1px solid #30404a;border-radius:999px;background:#081015;color:#aebbc2;font-size:8px;font-weight:850}
.cvPhotoCardV57{overflow:hidden;padding:0!important}.cvPhotoCardV57 img{display:block;width:100%;aspect-ratio:1/1;object-fit:cover;background:#05080a}.cvPhotoInfoV57{padding:10px}.cvPhotoInfoV57 strong{display:block;font-size:12px}.cvPhotoInfoV57 small{display:block;margin-top:3px;color:#87959d;font-size:9px}.cvPhotoShareV57{width:100%;min-height:38px;margin-top:9px;border:1px solid #33434d;border-radius:10px;background:#081015;color:#bdc8ce;font-size:8px;font-weight:900}.cvPhotoShareV57.shared{border-color:rgba(94,227,165,.34);background:rgba(94,227,165,.08);color:#89efbc}
.cvOnboardingMetaV57{display:flex;flex-wrap:wrap;gap:6px;margin:10px 0 4px}.cvOnboardingMetaV57 span{padding:5px 8px;border:1px solid rgba(67,184,255,.24);border-radius:999px;background:rgba(67,184,255,.05);color:#83d4ff;font-size:8px;font-weight:850}
.cvDayStatusV57{display:inline-flex;margin-top:7px;padding:4px 7px;border:1px solid #33434d;border-radius:999px;color:#87949c;font-size:7px;font-weight:900}.cvDayStatusV57.live{border-color:rgba(67,184,255,.35);background:rgba(67,184,255,.07);color:#83d4ff}.cvDayStatusV57.done{border-color:rgba(94,227,165,.28);background:rgba(94,227,165,.06);color:#81ecb6}
@media(max-width:767px){
  .top{grid-template-columns:70px minmax(0,1fr) 126px!important}.topRight{width:126px!important;min-width:126px!important;gap:4px!important}.top .cvOfficialHeaderImg{width:58px!important;height:58px!important;max-width:58px!important;max-height:58px!important}.top .cvHeaderIdentity b,.top .topTitle b{font-size:16px!important;letter-spacing:.035em!important}.cvNotificationButton,#cvNotificationButton{display:grid!important;width:34px!important;min-width:34px!important;height:36px!important;min-height:36px!important;border-radius:11px!important}.cvNotificationBadge{display:grid!important}.cvNotificationBadge.hidden{display:none!important}.cvModuleHeroV57{padding:15px}.cvMealButtonsV57{grid-template-columns:repeat(4,minmax(0,1fr))}.cvProgressQuickV57 b{font-size:20px}.cvMissionCardV57{padding:13px}
}
@media(max-width:390px){.top{grid-template-columns:64px minmax(0,1fr) 122px!important}.topRight{width:122px!important;min-width:122px!important}.top .cvOfficialHeaderImg{width:54px!important;height:54px!important;max-width:54px!important;max-height:54px!important}.top .cvHeaderIdentity b,.top .topTitle b{font-size:15px!important}.logout{min-width:44px!important;padding:0 5px!important}.cvMealButtonsV57{grid-template-columns:repeat(3,minmax(0,1fr))}}
@media(min-width:700px){.cvMissionGridV57{grid-template-columns:repeat(2,minmax(0,1fr))}.cvPhotoManagerGridV57{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}}
</style>'''

SCRIPT = r'''<script id="cv-client-modules-v57-js">
(function(){
  if(window.CVClientModulesV57?.version==='v57')return;
  const state={dailyKey:'',dailyLoaded:false,habitLogs:new Map(),nutritionLog:null,missionsLoaded:false,missions:[],photosLoaded:false,photos:[],badgeBusy:false,actionLocks:new Set()};
  let feedbackAudio=null;
  const real=()=>{try{return mode==='real'&&!!user?.id}catch(_){return false}};
  const currentView=()=>{try{return String(view||document.body.dataset.cvView||'home')}catch(_){return String(document.body.dataset.cvView||'home')}};
  const uid=()=>{try{return user?.id||null}catch(_){return null}};
  const logDay=()=>{try{return typeof today==='function'?today():new Date().toISOString().slice(0,10)}catch(_){return new Date().toISOString().slice(0,10)}};
  const n=v=>{const x=Number(v);return Number.isFinite(x)?x:0};
  function soundOn(){try{return localStorage.getItem('cv_sound_enabled')!=='0'}catch(_){return true}}
  function successFeedback(){
    try{navigator.vibrate?.([28,24,42])}catch(_){}
    if(!soundOn())return;
    try{const C=window.AudioContext||window.webkitAudioContext;if(!C)return;feedbackAudio=feedbackAudio||new C();if(feedbackAudio.state==='suspended')feedbackAudio.resume().catch(()=>{});const now=feedbackAudio.currentTime;[[620,.00,.018],[820,.065,.016]].forEach(([f,d,v])=>{const o=feedbackAudio.createOscillator(),g=feedbackAudio.createGain();o.type='triangle';o.frequency.value=f;g.gain.setValueAtTime(.0001,now+d);g.gain.exponentialRampToValueAtTime(v,now+d+.008);g.gain.exponentialRampToValueAtTime(.0001,now+d+.10);o.connect(g).connect(feedbackAudio.destination);o.start(now+d);o.stop(now+d+.12)})}catch(_){}
  }
  function rewardText(result,base){
    const bits=[base],xp=n(result?.xp_earned),credits=n(result?.credits_earned),missions=n(result?.missions_completed),levelUp=result?.level_up===true;
    if(xp>0)bits.push('+'+xp+' XP');if(credits>0)bits.push('+'+credits+' créditos');if(missions>0)bits.push(missions===1?'misión completada':missions+' misiones completadas');if(levelUp)bits.push('Nivel '+n(result?.current_level));return bits.join(' · ')
  }
  async function loadDaily(force=false){
    if(!real())return false;const key=uid()+'|'+logDay();if(!force&&state.dailyLoaded&&state.dailyKey===key)return true;
    const [habits,nutrition]=await Promise.all([
      sb.from('habit_logs').select('id,client_habit_id,log_date,value,text_value,completed,updated_at').eq('client_id',uid()).eq('log_date',logDay()),
      sb.from('nutrition_daily_logs').select('id,log_date,adherence_pct,meals_completed,meal_target_snapshot,compliant,updated_at').eq('client_id',uid()).eq('log_date',logDay()).maybeSingle()
    ]);
    if(habits.error)throw habits.error;if(nutrition.error)throw nutrition.error;
    state.habitLogs=new Map((habits.data||[]).map(x=>[String(x.client_habit_id),x]));state.nutritionLog=nutrition.data||null;state.dailyKey=key;state.dailyLoaded=true;return true
  }
  async function loadMissions(force=false){
    if(!real())return false;if(state.missionsLoaded&&!force)return true;
    const q=await sb.from('client_missions').select('id,mission_name,mission_description,pillar,generated_reason,xp_reward_snapshot,credit_reward_snapshot,start_at,expires_at,progress,target,status,completed_at,created_at').eq('client_id',uid()).order('created_at',{ascending:false}).limit(50);
    if(q.error)throw q.error;state.missions=q.data||[];state.missionsLoaded=true;return true
  }
  async function syncCvState(){
    if(!real())return;const q=await sb.from('client_cv_state').select('*').eq('client_id',uid()).maybeSingle();if(!q.error&&q.data&&typeof data==='object'&&data)data.cv=q.data;state.missionsLoaded=false;await loadMissions(true).catch(()=>{});try{if(typeof loadAchievements==='function')await loadAchievements(true)}catch(_){}
  }
  async function syncBadge(){
    if(!real()||state.badgeBusy)return;state.badgeBusy=true;try{const q=await sb.from('notifications').select('id',{count:'exact',head:true}).eq('user_id',uid()).is('read_at',null);if(q.error)return;const count=Number(q.count||0),badge=document.getElementById('cvNotificationBadge');if(badge){badge.textContent=count>99?'99+':String(count);badge.classList.toggle('hidden',count===0)}const mobile=document.querySelector('.cvMobileNotifCountV39');if(mobile){mobile.textContent=count>99?'99+':String(count);mobile.classList.toggle('hidden',count===0)}}catch(_){}finally{state.badgeBusy=false}
  }
  window.logHabit=async function(id,value,completed){
    if(!real())return toast?.('Demo: no se escribieron datos.');const key='habit:'+id;if(state.actionLocks.has(key))return false;state.actionLocks.add(key);
    try{const {data:r,error}=await sb.functions.invoke('log-habit',{body:{client_habit_id:id,log_date:logDay(),value,completed}});if(error||r?.error)throw new Error(r?.detail||r?.error||error.message);await Promise.all([loadDaily(true),syncCvState()]);successFeedback();toast?.(rewardText(r,'Hábito registrado'));render();syncBadge();return true}catch(e){toast?.(e?.message||'No pude registrar el hábito.');return false}finally{state.actionLocks.delete(key)}
  };
  window.logNutrition=async function(pct,explicitMeals=null){
    if(!real())return toast?.('Demo: no se escribieron datos.');const key='nutrition:'+logDay();if(state.actionLocks.has(key))return false;state.actionLocks.add(key);
    try{const target=Math.max(1,Number(data?.nutrition?.meal_target||3)),meals=explicitMeals==null?Math.round(target*Number(pct||0)/100):Math.max(0,Math.min(target,Math.round(Number(explicitMeals)||0))),adherence=Math.max(0,Math.min(100,explicitMeals==null?Number(pct||0):(meals/target*100)));
      const {data:r,error}=await sb.functions.invoke('log-nutrition-day',{body:{log_date:logDay(),adherence_pct:adherence,meals_completed:meals,compliant:adherence>=80}});if(error||r?.error)throw new Error(r?.detail||r?.error||error.message);await Promise.all([loadDaily(true),syncCvState()]);successFeedback();toast?.(rewardText(r,'Nutrición registrada'));render();syncBadge();return true}catch(e){toast?.(e?.message||'No pude registrar nutrición.');return false}finally{state.actionLocks.delete(key)}
  };
  window.cvLogNutritionMealsV57=async meals=>window.logNutrition(null,meals);
  function weeklyPending(){try{return real()&&typeof cvWeeklyCurrent==='function'&&!cvWeeklyCurrent()}catch(_){return false}}
  function decorateHome(){
    const c=document.getElementById('content');if(!c||currentView()!=='home')return;
    if(weeklyPending()&&!c.querySelector('.cvWeeklyHomeV57')){const stats=c.querySelector('.stats'),box=document.createElement('div');box.className='cvWeeklyHomeV57';box.innerHTML='<div class="row"><div class="grow"><strong>Check-in semanal pendiente</strong><p>Cuéntame cómo llegas esta semana. Sueño, energía, estrés y molestias ayudan a ajustar tu proceso.</p></div><button class="btn primary" type="button">HACER CHECK-IN</button></div>';box.querySelector('button').onclick=()=>{if(typeof openWeeklyCheckin==='function')openWeeklyCheckin()};stats?.insertAdjacentElement('afterend',box)}
    const habitSection=[...c.querySelectorAll('.section')].find(s=>/HÁBITOS DE HOY/i.test(s.querySelector('h2')?.textContent||''));if(habitSection){[...habitSection.querySelectorAll('.habit')].forEach((row,i)=>{if(row.querySelector('.cvHabitStatusV57'))return;const h=data?.habits?.[i],log=h?state.habitLogs.get(String(h.id)):null,b=document.createElement('span');b.className='cvHabitStatusV57 '+(log?.completed?'done':'pending');b.textContent=log?.completed?'Cumplido':log?'Registrado':'Pendiente';row.querySelector('div')?.appendChild(b)})}
  }
  function decorateHabits(){
    const c=document.getElementById('content');if(!c||currentView()!=='habits')return;
    if(!c.querySelector('.cvModuleHeroV57')){const hero=document.createElement('div');hero.className='cvModuleHeroV57';const total=data?.habits?.length||0,done=[...state.habitLogs.values()].filter(x=>x.completed).length;hero.innerHTML='<div class="ey">ADHERENCIA DIARIA</div><h2>'+done+' / '+total+' hábitos cumplidos</h2><p>Registra lo que realmente hiciste. Los hábitos cumplidos pueden sumar XP y avanzar misiones automáticamente.</p><div class="cvModuleChipsV57"><span class="cvModuleChipV57 info">HOY · '+esc(logDay())+'</span><span class="cvModuleChipV57 '+(done===total&&total?'good':'')+'">'+done+' COMPLETADOS</span></div>';const first=c.querySelector('.section');first?.insertAdjacentElement('beforebegin',hero)}
    const rows=[...c.querySelectorAll('.habit')];rows.forEach((row,i)=>{const h=data?.habits?.[i];if(!h||row.dataset.cv57==='1')return;row.dataset.cv57='1';const log=state.habitLogs.get(String(h.id)),left=row.querySelector('div:first-child'),badge=document.createElement('span');badge.className='cvHabitStatusV57 '+(log?.completed?'done':'pending');badge.textContent=log?.completed?'Cumplido hoy':log?'Registrado':'Pendiente';left?.appendChild(badge);const input=row.querySelector('input[id^="hv_"]');if(input&&log?.value!=null&&document.activeElement!==input)input.value=String(log.value);const button=row.querySelector('button');if(button){if(h.input_type==='boolean'){button.textContent=log?.completed?'✓ CUMPLIDO HOY':'MARCAR CUMPLIDO';button.classList.toggle('cvPositiveActionV57',!!log?.completed)}else button.textContent=log?'ACTUALIZAR':'GUARDAR'}});
    const nutritionSection=[...c.querySelectorAll('.section')].find(s=>/^NUTRICIÓN$/i.test((s.querySelector('h2')?.textContent||'').trim()));if(nutritionSection&&!nutritionSection.querySelector('.cvNutritionV57')){const card=nutritionSection.querySelector('.card'),old=card?.querySelector('.row');old?.remove();const target=Math.max(1,Number(data?.nutrition?.meal_target||3)),log=state.nutritionLog,selected=log?.meals_completed;const box=document.createElement('div');box.className='cvNutritionV57';const values=target<=8?Array.from({length:target+1},(_,i)=>i):[0,Math.round(target*.5),Math.round(target*.75),target].filter((v,i,a)=>a.indexOf(v)===i);box.innerHTML='<h3>Comidas cumplidas hoy</h3><p>Marca cuántas comidas de tu objetivo diario cumpliste. El porcentaje se calcula automáticamente.</p><div class="cvMealButtonsV57">'+values.map(v=>'<button type="button" data-meals="'+v+'" class="'+(Number(selected)===v?'selected':'')+'">'+v+' / '+target+'</button>').join('')+'</div><div class="cvNutritionStatusV57 '+(log?.compliant?'good':'')+'">'+(log?('Registrado: '+Math.round(Number(log.adherence_pct||0))+'% · '+(log.compliant?'objetivo cumplido':'día registrado')):'Aún no registras nutrición hoy.')+'</div>';box.querySelectorAll('button').forEach(b=>b.onclick=()=>window.cvLogNutritionMealsV57(Number(b.dataset.meals)));card?.appendChild(box)}
  }
  const statusLabel=s=>({active:'ACTIVA',completed:'COMPLETADA',expired:'VENCIDA',failed:'NO COMPLETADA',cancelled:'CANCELADA'}[String(s)]||String(s||'').toUpperCase());
  function dateText(v){if(!v)return '';try{return new Intl.DateTimeFormat('es-CL',{dateStyle:'medium'}).format(new Date(v))}catch(_){return ''}}
  function missionCard(m){const target=Math.max(0,n(m.target)),progress=Math.max(0,n(m.progress)),pct=target?Math.min(100,Math.round(progress/target*100)):0,complete=m.status==='completed',closed=!['active','completed'].includes(String(m.status));return '<article class="cvMissionCardV57 '+(complete?'complete':closed?'closed':'')+'"><div class="cvMissionHeadV57"><div class="grow"><h3>'+esc(m.mission_name||'Misión')+'</h3>'+(m.mission_description?'<p>'+esc(m.mission_description)+'</p>':'')+'</div><span class="cvMissionBadgeV57 '+(complete?'good':'')+'">'+esc(statusLabel(m.status))+'</span></div><div class="cvMissionProgressV57"><i style="width:'+pct+'%"></i></div><div class="cvMissionMetaV57"><span><b>'+esc(progress)+'</b> / '+esc(target)+'</span><span><b>+'+esc(m.xp_reward_snapshot||0)+' XP</b></span><span><b>+'+esc(m.credit_reward_snapshot||0)+' créditos</b></span>'+(m.pillar?'<span>'+esc(String(m.pillar).toUpperCase())+'</span>':'')+(m.expires_at&&m.status==='active'?'<span>Hasta '+esc(dateText(m.expires_at))+'</span>':'')+(m.completed_at?'<span>Completada '+esc(dateText(m.completed_at))+'</span>':'')+'</div><div class="cvMissionAutoV57">El progreso se actualiza automáticamente con los registros vinculados a esta misión.</div></article>'}
  function renderMissions(){
    const c=document.getElementById('content');if(!c||currentView()!=='missions'||!state.missionsLoaded)return;const old=c.querySelector('.section');if(!old)return;old.remove();const active=state.missions.filter(x=>x.status==='active').sort((a,b)=>new Date(a.expires_at||'2999-12-31')-new Date(b.expires_at||'2999-12-31')),completed=state.missions.filter(x=>x.status==='completed').sort((a,b)=>new Date(b.completed_at||0)-new Date(a.completed_at||0)),closed=state.missions.filter(x=>!['active','completed'].includes(String(x.status)));const hero=document.createElement('div');hero.className='cvModuleHeroV57';hero.innerHTML='<div class="ey">CV12 LEVELING</div><h2>'+active.length+' misiones activas</h2><p>No necesitas marcar una misión manualmente: CV Coach actualiza su progreso cuando registras la acción que corresponde.</p><div class="cvModuleChipsV57"><span class="cvModuleChipV57 info">'+active.length+' ACTIVAS</span><span class="cvModuleChipV57 good">'+completed.length+' COMPLETADAS</span></div>';const sub=c.querySelector(':scope > .sub');sub?.insertAdjacentElement('afterend',hero);const wrap=document.createElement('div');wrap.innerHTML='<section class="cvMissionGroupV57"><h2>EN CURSO</h2><div class="cvMissionGridV57">'+(active.length?active.map(missionCard).join(''):'<div class="cvMissionEmptyV57">No tienes misiones activas en este momento.</div>')+'</div></section>'+(completed.length?'<section class="cvMissionGroupV57"><h2>COMPLETADAS</h2><div class="cvMissionGridV57">'+completed.slice(0,12).map(missionCard).join('')+'</div></section>':'')+(closed.length?'<section class="cvMissionGroupV57"><h2>HISTORIAL</h2><div class="cvMissionGridV57">'+closed.slice(0,8).map(missionCard).join('')+'</div></section>':'');while(wrap.firstChild)c.appendChild(wrap.firstChild)
  }
  function decorateRoutine(){
    if(currentView()!=='routine')return;const cards=[...document.querySelectorAll('.day')],sessions=data?.sessions||[];cards.forEach((card,i)=>{if(card.querySelector('.cvDayStatusV57'))return;const d=data?.days?.[i];if(!d)return;const latest=sessions.find(s=>String(s.program_day_id)===String(d.id)),badge=document.createElement('span');badge.className='cvDayStatusV57 '+(latest?.status==='in_progress'?'live':['completed','partial'].includes(latest?.status)?'done':'');badge.textContent=latest?.status==='in_progress'?'SESIÓN EN CURSO':latest?.status==='completed'?'ÚLTIMA: COMPLETADA':latest?.status==='partial'?'ÚLTIMA: PARCIAL':latest?.status==='abandoned'?'ÚLTIMA: CERRADA':'SIN REGISTRO';card.querySelector('.dayHead .grow')?.appendChild(badge);const button=card.querySelector('.dayActions .btn');if(button&&latest?.status==='in_progress')button.textContent='CONTINUAR ENTRENAMIENTO'})
  }
  function decorateProgress(){
    const c=document.getElementById('content');if(!c||currentView()!=='progress')return;if(!c.querySelector('.cvProgressQuickV57')){const sub=c.querySelector(':scope > .sub'),quick=document.createElement('div');quick.className='cvProgressQuickV57';quick.innerHTML='<div class="cvQuickV57"><small>Nivel CV12</small><b>'+esc(data?.cv?.current_level??'—')+'</b></div><div class="cvQuickV57"><small>XP total</small><b>'+esc(data?.cv?.total_xp??'—')+'</b></div><div class="cvQuickV57"><small>Créditos</small><b>'+esc(data?.cv?.credit_balance??'—')+'</b></div>';sub?.insertAdjacentElement('afterend',quick);const nav=document.createElement('div');nav.className='cvProgressNavV57';['RECUPERACIÓN','HISTORIAL DE ENTRENAMIENTOS','RÉCORDS PERSONALES','LOGROS','PROGRESO VISUAL'].forEach(label=>{const b=document.createElement('button');b.type='button';b.textContent=label;b.onclick=()=>{const heading=[...c.querySelectorAll('h2')].find(x=>x.textContent.trim().toUpperCase()===label);heading?.scrollIntoView({behavior:'smooth',block:'start'})};nav.appendChild(b)});quick.insertAdjacentElement('afterend',nav)}
  }
  async function loadPhotos(force=false){
    if(!real()||currentView()!=='progress')return false;if(state.photosLoaded&&!force){renderPhotos();return true}const q=await sb.from('progress_photos').select('id,photo_type,storage_path,taken_at,visible_to_coach').eq('client_id',uid()).order('taken_at',{ascending:false});if(q.error)throw q.error;const rows=q.data||[],signed=await Promise.all(rows.map(async row=>{const s=await sb.storage.from('progress-photos').createSignedUrl(row.storage_path,300);return {...row,signedUrl:s.error?'':s.data?.signedUrl||''}}));state.photos=signed;state.photosLoaded=true;renderPhotos();return true
  }
  function renderPhotos(){
    if(currentView()!=='progress'||!state.photosLoaded)return;const gallery=document.getElementById('progressPhotoGallery');if(!gallery)return;if(!state.photos.length){gallery.innerHTML='<div class="empty">Todavía no tienes fotos de progreso.</div>';return}gallery.innerHTML='<div class="cvPhotoManagerGridV57">'+state.photos.filter(x=>x.signedUrl).map(row=>'<article class="card cvPhotoCardV57"><img src="'+esc(row.signedUrl)+'" alt="Foto de progreso"><div class="cvPhotoInfoV57"><strong>'+esc(progressTypes?.[row.photo_type]||row.photo_type||'Foto')+'</strong><small>'+esc(dateText(row.taken_at))+'</small><button type="button" class="cvPhotoShareV57 '+(row.visible_to_coach?'shared':'')+'" data-photo-id="'+esc(row.id)+'" data-next="'+(row.visible_to_coach?'0':'1')+'">'+(row.visible_to_coach?'✓ COMPARTIDA CON TU COACH':'PRIVADA · COMPARTIR CON COACH')+'</button></div></article>').join('')+'</div>';gallery.querySelectorAll('.cvPhotoShareV57').forEach(b=>b.onclick=()=>window.cvTogglePhotoVisibilityV57(b.dataset.photoId,b.dataset.next==='1'))
  }
  window.cvTogglePhotoVisibilityV57=async function(id,next){const key='photo:'+id;if(state.actionLocks.has(key))return;state.actionLocks.add(key);try{const q=await sb.from('progress_photos').update({visible_to_coach:!!next}).eq('id',id).eq('client_id',uid()).select('id,visible_to_coach').maybeSingle();if(q.error||!q.data?.id)throw q.error||new Error('No se confirmó el cambio.');state.photosLoaded=false;await loadPhotos(true);successFeedback();toast?.(next?'Foto compartida con tu coach.':'Foto marcada como privada.')}catch(e){toast?.(e?.message||'No pude cambiar la visibilidad de la foto.')}finally{state.actionLocks.delete(key)}};
  function decorateOnboarding(){const c=document.getElementById('content');if(currentView()!=='onboarding'||!c||c.querySelector('.cvOnboardingMetaV57'))return;const sub=c.querySelector('.onboardingCard>.sub');if(!sub)return;const m=document.createElement('div');m.className='cvOnboardingMetaV57';m.innerHTML='<span>3 PASOS</span><span>DATOS PROTEGIDOS</span><span>PERSONALIZACIÓN DEL PLAN</span>';sub.insertAdjacentElement('afterend',m)}
  const baseNext=window.nextDay;
  window.nextDay=function(){try{const days=data?.days||[],sessions=data?.sessions||[];if(!days.length)return null;const active=sessions.find(s=>s.status==='in_progress'&&days.some(d=>String(d.id)===String(s.program_day_id)));if(active)return days.find(d=>String(d.id)===String(active.program_day_id))||days[0];const latest=sessions.find(s=>['completed','partial','abandoned'].includes(String(s.status))&&days.some(d=>String(d.id)===String(s.program_day_id)));if(!latest)return days[0];const current=days.findIndex(d=>String(d.id)===String(latest.program_day_id));if(latest.status==='abandoned')return days[current]||days[0];return days[(current+1)%days.length]||days[0]}catch(_){return typeof baseNext==='function'?baseNext():null}};
  const baseUpload=window.uploadProgressPhoto;if(typeof baseUpload==='function'&&!baseUpload.__cv57){const wrapped=async function(){const out=await baseUpload.apply(this,arguments);state.photosLoaded=false;if(currentView()==='progress')setTimeout(()=>loadPhotos(true).catch(()=>{}),100);return out};wrapped.__cv57=true;window.uploadProgressPhoto=wrapped}
  function afterRender(){
    const v=currentView();syncBadge();if(v==='routine')decorateRoutine();if(v==='progress'){decorateProgress();loadPhotos().catch(()=>{})}if(v==='onboarding')decorateOnboarding();if(v==='home'||v==='habits'){loadDaily().then(()=>{if(v==='home')decorateHome();else decorateHabits()}).catch(()=>{})}if(v==='missions'){loadMissions().then(renderMissions).catch(()=>{})}
  }
  document.addEventListener('cv:rendered',()=>requestAnimationFrame(afterRender));window.addEventListener('pageshow',afterRender);requestAnimationFrame(afterRender);
  window.CVClientModulesV57={version:'v57',state,loadDaily,loadMissions,loadPhotos,syncBadge,successFeedback,afterRender};
})();
</script>'''

if MARKER not in text:
    prerequisites = [
        "cv-set-toggle-runtime-v56",
        "function habits()",
        "function missions()",
        "function progress()",
        "function cvWeeklyCurrent()",
        "window.logHabit=async",
        "window.logNutrition=async",
        "progress_photos",
        "notifications",
        "client_missions",
        "cv-client-header-v39",
    ]
    for prerequisite in prerequisites:
        if prerequisite not in text:
            raise SystemExit(f"client modules v57 prerequisite missing: {prerequisite}")
    if "</body>" not in text:
        raise SystemExit("client modules v57: </body> missing")
    text = text.replace("</body>", STYLE + "\n" + SCRIPT + "\n" + MARKER + "\n</body>", 1)

required = [
    MARKER,
    'cv-client-modules-v57-css',
    'cv-client-modules-v57-js',
    "window.CVClientModulesV57={version:'v57'",
    "sb.from('habit_logs')",
    "sb.from('nutrition_daily_logs')",
    "sb.from('client_missions')",
    "sb.from('notifications')",
    "sb.from('progress_photos')",
    "window.cvLogNutritionMealsV57",
    "window.cvTogglePhotoVisibilityV57",
    "Check-in semanal pendiente",
    "El progreso se actualiza automáticamente",
    "SESIÓN EN CURSO",
    "cvNotificationButton,#cvNotificationButton{display:grid!important",
]
for item in required:
    if item not in text:
        raise SystemExit(f"client modules v57 required contract missing: {item}")

HTML.write_text(text, encoding="utf-8")
sha = hashlib.sha256(text.encode("utf-8")).hexdigest()
metadata = {}
if BUILD.exists():
    try:
        metadata = json.loads(BUILD.read_text(encoding="utf-8"))
    except Exception:
        metadata = {}
metadata["bytes"] = len(text.encode("utf-8"))
metadata["sha256"] = sha
patches = list(metadata.get("patches") or [])
for patch in [
    "client module audit v57",
    "daily habit state hydration v57",
    "meal-based nutrition logging v57",
    "mission lifecycle visibility v57",
    "weekly check-in home discovery v57",
    "global mobile notification access v57",
    "progress photo coach-visibility controls v57",
    "routine status and next-session sequencing v57",
    "confirmed module success feedback v57",
]:
    if patch not in patches:
        patches.append(patch)
metadata["patches"] = patches
BUILD.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"sha256": sha, "bytes": metadata["bytes"], "patches": metadata["patches"][-9:]}, ensure_ascii=False))
