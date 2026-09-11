from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent
HTML = ROOT / "stable" / "index.html"
BUILD = ROOT / "stable" / "build.json"
MARKER = "<!-- cv-rank-system-v60: bronze-to-legend HUD + profile + progression feedback -->"

text = HTML.read_text(encoding="utf-8")

STYLE = r'''<style id="cv-rank-system-v60-css">
:root{--cv60-panel:#090d11;--cv60-line:#2b343c;--cv60-text:#f5f7fa;--cv60-muted:#8d99a2}
.cvRankHudV60{--rank:#c47a3a;--rank2:#6e351e;position:relative;display:grid;grid-template-columns:84px minmax(0,1fr);gap:14px;margin:12px 0 16px;padding:16px;border:1px solid color-mix(in srgb,var(--rank) 45%,#263139);border-radius:19px;overflow:hidden;background:radial-gradient(circle at 8% 12%,color-mix(in srgb,var(--rank) 18%,transparent),transparent 38%),linear-gradient(145deg,#0c1216,#070a0d 72%);box-shadow:0 18px 50px rgba(0,0,0,.35),inset 0 0 32px color-mix(in srgb,var(--rank) 5%,transparent)}
.cvRankHudV60:after{content:'';position:absolute;inset:auto -12% -55% 28%;height:150px;background:radial-gradient(ellipse,color-mix(in srgb,var(--rank) 14%,transparent),transparent 65%);pointer-events:none}.cvRankHudV60>*{position:relative;z-index:1}.cvRankEyV60{font-size:8px;font-weight:900;letter-spacing:.18em;color:var(--rank);text-transform:uppercase}.cvRankTitleV60{margin-top:3px;font:900 26px 'Barlow Condensed';line-height:1;color:#fff;text-transform:uppercase}.cvRankTitleV60 span{color:var(--rank)}.cvRankTagV60{margin-top:6px;color:#aab4bb;font-size:10px;line-height:1.4}.cvRankBarV60{height:8px;margin-top:12px;border:1px solid #273039;border-radius:999px;background:#11181d;overflow:hidden}.cvRankBarV60 i{display:block;height:100%;border-radius:inherit;background:linear-gradient(90deg,var(--rank2),var(--rank));box-shadow:0 0 16px color-mix(in srgb,var(--rank) 55%,transparent);transition:width .55s ease}.cvRankMetaV60{display:flex;justify-content:space-between;gap:10px;margin-top:6px;color:#7f8b94;font-size:8px}.cvRankMetaV60 b{color:#dfe6ea}.cvRankNextV60{display:flex;align-items:center;gap:7px;margin-top:11px;padding-top:10px;border-top:1px solid #202a30;color:#aab5bb;font-size:9px}.cvRankNextV60 strong{color:var(--rank);font-size:10px}.cvRankOpenV60{grid-column:1/-1;min-height:40px;border:1px solid color-mix(in srgb,var(--rank) 42%,#2b343c);border-radius:11px;background:linear-gradient(180deg,color-mix(in srgb,var(--rank) 13%,#10161a),#090d10);color:#f6f8f9;font-size:9px;font-weight:900;letter-spacing:.07em}
.cvRankShieldV60{--rank:#c47a3a;--rank2:#6e351e;position:relative;width:76px;height:88px;margin:auto;filter:drop-shadow(0 0 13px color-mix(in srgb,var(--rank) 38%,transparent))}.cvRankShieldV60.large{width:126px;height:148px;filter:drop-shadow(0 0 28px color-mix(in srgb,var(--rank) 54%,transparent))}.cvRankShieldV60:before{content:'';position:absolute;inset:0;clip-path:polygon(50% 0,83% 10%,100% 31%,88% 75%,50% 100%,12% 75%,0 31%,17% 10%);background:linear-gradient(135deg,#f7f9fa 0%,var(--rank) 22%,var(--rank2) 52%,var(--rank) 76%,#e8edf0 100%)}.cvRankShieldV60:after{content:'';position:absolute;inset:7px;clip-path:polygon(50% 0,82% 12%,94% 33%,82% 70%,50% 91%,18% 70%,6% 33%,18% 12%);background:radial-gradient(circle at 50% 36%,color-mix(in srgb,var(--rank) 20%,#10171c),#05080a 63%);border:1px solid rgba(255,255,255,.12)}.cvRankGemV60{position:absolute;z-index:2;left:50%;top:48%;width:29%;aspect-ratio:1;transform:translate(-50%,-50%) rotate(45deg);background:linear-gradient(135deg,#fff,var(--rank) 35%,var(--rank2) 75%);box-shadow:0 0 17px color-mix(in srgb,var(--rank) 65%,transparent);border:1px solid rgba(255,255,255,.65)}.cvRankShieldV60.large .cvRankGemV60{box-shadow:0 0 28px color-mix(in srgb,var(--rank) 70%,transparent)}.cvRankShieldV60.legend:before{background:linear-gradient(135deg,#fff 0%,#cbd5dc 20%,#fff 38%,#ff2037 57%,#f7f9fa 76%,#ff5264 100%);box-shadow:0 0 30px rgba(255,255,255,.26)}.cvRankShieldV60.legend .cvRankGemV60{background:linear-gradient(135deg,#fff,#eaf8ff 38%,#ff2037 72%,#fff);box-shadow:0 0 28px rgba(255,255,255,.55),0 0 42px rgba(255,32,55,.36)}
.cvWorkoutRankChipV60{--rank:#c47a3a;display:inline-flex;align-items:center;gap:6px;margin-top:6px;padding:4px 8px;border:1px solid color-mix(in srgb,var(--rank) 38%,#31404a);border-radius:999px;background:color-mix(in srgb,var(--rank) 7%,#081015);color:#bdc7cd;font-size:7px;font-weight:900;letter-spacing:.06em}.cvWorkoutRankChipV60 b{color:var(--rank)}
.cvRankBackdropV60{position:fixed;inset:0;z-index:250;display:grid;place-items:end center;padding:18px;background:rgba(0,0,0,.78);backdrop-filter:blur(13px)}.cvRankProfileV60{--rank:#c47a3a;--rank2:#6e351e;width:min(520px,100%);max-height:92vh;overflow:auto;padding:20px;border:1px solid color-mix(in srgb,var(--rank) 40%,#303943);border-radius:24px;background:radial-gradient(circle at 50% -5%,color-mix(in srgb,var(--rank) 13%,transparent),transparent 32%),linear-gradient(180deg,#0d1216,#05080a);box-shadow:0 25px 80px rgba(0,0,0,.65)}.cvRankCloseV60{float:right;width:38px;height:38px;border:1px solid #344049;border-radius:11px;background:#091015;color:#fff;font-size:18px}.cvRankProfileHeadV60{text-align:center;padding:18px 0 14px}.cvRankProfileHeadV60 h2{margin-top:9px;font-size:34px}.cvRankProfileHeadV60 h2 span{color:var(--rank)}.cvRankProfileHeadV60 p{margin:7px auto 0;max-width:330px;color:#98a5ad;font-size:10px;line-height:1.5}.cvRankProfileGridV60{display:grid;grid-template-columns:repeat(2,1fr);gap:8px;margin-top:13px}.cvRankMetricV60{padding:12px;border:1px solid #29353d;border-radius:13px;background:#081015}.cvRankMetricV60 small{display:block;color:#7f8b94;font-size:7px;text-transform:uppercase;letter-spacing:.08em}.cvRankMetricV60 b{display:block;margin-top:5px;font-size:20px}.cvPillarsV60{display:grid;gap:7px;margin-top:12px}.cvPillarV60{display:grid;grid-template-columns:105px 1fr auto;align-items:center;gap:8px;padding:9px 10px;border:1px solid #26323a;border-radius:11px;background:#070d11;font-size:9px}.cvPillarV60 .mini{height:5px;border-radius:99px;background:#182128;overflow:hidden}.cvPillarV60 .mini i{display:block;height:100%;background:linear-gradient(90deg,var(--rank2),var(--rank))}.cvRankPathV60{display:flex;gap:6px;overflow:auto;margin-top:12px;padding-bottom:4px;scrollbar-width:none}.cvRankPathV60::-webkit-scrollbar{display:none}.cvRankStepV60{flex:0 0 88px;padding:10px 7px;border:1px solid #27323a;border-radius:12px;background:#070c10;text-align:center;color:#718089;font-size:7px}.cvRankStepV60 strong{display:block;margin-top:5px;color:#aab5bb;font-size:9px}.cvRankStepV60.current{border-color:color-mix(in srgb,var(--rank) 50%,#27323a);box-shadow:inset 0 0 18px color-mix(in srgb,var(--rank) 8%,transparent)}.cvRankStepV60.current strong{color:var(--rank)}.cvRankStepV60.reached{color:#7be8b1}.cvRankDotV60{width:24px;height:28px;margin:auto;clip-path:polygon(50% 0,90% 20%,80% 72%,50% 100%,20% 72%,10% 20%);background:var(--dot,#59636a);box-shadow:0 0 12px var(--dot,#59636a)}
.cvProgressionV60{--rank:#c47a3a;--rank2:#6e351e;width:min(430px,100%);padding:24px 20px 20px;border:1px solid color-mix(in srgb,var(--rank) 55%,#37424a);border-radius:25px;text-align:center;background:radial-gradient(circle at 50% 25%,color-mix(in srgb,var(--rank) 22%,transparent),transparent 31%),linear-gradient(180deg,#0e1216,#040607 78%);box-shadow:0 0 80px color-mix(in srgb,var(--rank) 15%,transparent),0 30px 90px rgba(0,0,0,.75);animation:cvRankEnterV60 .36s ease-out}.cvProgressionV60 .cvOverlineV60{font-size:11px;font-weight:950;letter-spacing:.20em;color:var(--rank)}.cvProgressionV60 h2{margin:8px 0 14px;font-size:48px;line-height:.95}.cvProgressionV60 h3{margin:13px 0 2px;font-size:27px}.cvProgressionV60 p{margin:6px auto 0;max-width:300px;color:#a7b1b7;font-size:10px;line-height:1.5}.cvProgressionV60 .btn{width:100%;margin-top:18px;border-color:color-mix(in srgb,var(--rank) 65%,#3b454c);background:linear-gradient(180deg,color-mix(in srgb,var(--rank) 70%,#111),color-mix(in srgb,var(--rank2) 75%,#050607))}.cvXpBurstV60{position:fixed;z-index:230;left:50%;top:25%;transform:translate(-50%,-50%);padding:8px 12px;border:1px solid #3a4851;border-radius:999px;background:#071015;color:#7eeab4;font:900 17px 'Barlow Condensed';box-shadow:0 15px 40px rgba(0,0,0,.45);animation:cvXpBurstV60 1.35s ease both;pointer-events:none}@keyframes cvXpBurstV60{0%{opacity:0;transform:translate(-50%,0) scale(.8)}18%{opacity:1;transform:translate(-50%,-15px) scale(1.08)}75%{opacity:1}100%{opacity:0;transform:translate(-50%,-55px) scale(.95)}}@keyframes cvRankEnterV60{from{opacity:0;transform:translateY(24px) scale(.92)}to{opacity:1;transform:none}}
@media(max-width:390px){.cvRankHudV60{grid-template-columns:70px minmax(0,1fr);padding:14px;gap:11px}.cvRankShieldV60{width:65px;height:76px}.cvRankTitleV60{font-size:23px}.cvRankProfileV60{padding:17px}.cvPillarV60{grid-template-columns:90px 1fr auto}}
</style>'''

SCRIPT = r'''<script id="cv-rank-system-v60-js">
(function(){
  if(window.CVRankV60?.version==='v60')return;
  const ranks=[
    {key:'bronze',name:'BRONCE',min:1,max:4,c1:'#C47A3A',c2:'#6E351E',tag:'El primer paso también cuenta.'},
    {key:'silver',name:'PLATA',min:5,max:9,c1:'#D8E0E6',c2:'#71808A',tag:'La constancia empieza a notarse.'},
    {key:'gold',name:'ORO',min:10,max:19,c1:'#F4B942',c2:'#8A5A12',tag:'Los hábitos generan resultados.'},
    {key:'diamond',name:'DIAMANTE',min:20,max:29,c1:'#38BDF8',c2:'#DDF7FF',tag:'Disciplina en acción.'},
    {key:'master',name:'MAESTRO',min:30,max:39,c1:'#A855F7',c2:'#5B21B6',tag:'Dominas tu proceso.'},
    {key:'grandmaster',name:'GRAN MAESTRO',min:40,max:49,c1:'#FF283F',c2:'#7F0715',tag:'Inspiras con tu ejemplo.'},
    {key:'legend',name:'LEYENDA',min:50,max:50,c1:'#F5F7FA',c2:'#FF2037',tag:'Más que un objetivo: un estilo de vida.',terminal:true}
  ];
  const state={value:null,request:null,lastUser:null,wrapped:false,audio:null};
  const real=()=>{try{return mode==='real'&&!!user?.id}catch(_){return false}};
  const currentView=()=>{try{return String(view||document.body.dataset.cvView||'home')}catch(_){return String(document.body.dataset.cvView||'home')}};
  const safe=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const clone=v=>v?JSON.parse(JSON.stringify(v)):null;
  const rankForLevel=l=>ranks.find(r=>Number(l)>=r.min&&Number(l)<=r.max)||ranks[0];
  const vars=r=>`--rank:${safe(r?.color_primary||r?.c1||'#C47A3A')};--rank2:${safe(r?.color_secondary||r?.c2||'#6E351E')}`;
  const rankClass=r=>String(r?.key||'bronze')==='legend'?' legend':'';
  function demoState(){const level=Math.max(1,Number(data?.cv?.current_level||1)),rank=rankForLevel(level),next=ranks.find(r=>r.min>level)||null,total=Math.max(0,Number(data?.cv?.total_xp||0));return {current_level:level,total_xp:total,credit_balance:Number(data?.cv?.credit_balance||0),cv_score:Number(data?.cv?.current_cv_score||0),rank:{key:rank.key,name:rank.name,min_level:rank.min,max_level:rank.max,color_primary:rank.c1,color_secondary:rank.c2,tagline:rank.tag,terminal:!!rank.terminal},next_rank:next?{key:next.key,name:next.name,min_level:next.min,color_primary:next.c1,color_secondary:next.c2,tagline:next.tag}:null,level_progress_pct:0,rank_progress_pct:0,xp_to_next_level:0,xp_to_next_rank:0,levels_to_next_rank:next?next.min-level:0,pillar_xp:{}}}
  async function load(force=false){
    if(!real()){state.value=demoState();return state.value}
    const uid=user.id;if(state.lastUser!==uid){state.value=null;state.lastUser=uid}
    if(state.value&&!force)return state.value;if(state.request)return state.request;
    state.request=(async()=>{const q=await sb.rpc('get_client_rank_state_backend',{p_actor_id:uid,p_client_id:uid});if(q.error)throw q.error;if(!q.data?.rank)throw new Error('CV Rank no disponible');state.value=q.data;if(typeof data==='object'&&data?.cv){data.cv.current_level=q.data.current_level;data.cv.total_xp=q.data.total_xp;data.cv.credit_balance=q.data.credit_balance}return state.value})().catch(e=>{console.warn('CV Rank V60 load failed',e);state.value=demoState();return state.value}).finally(()=>{state.request=null});
    return state.request
  }
  function shield(s,large=false){const r=s?.rank||s||ranks[0];return `<div class="cvRankShieldV60${large?' large':''}${rankClass(r)}" style="${vars(r)}" aria-hidden="true"><span class="cvRankGemV60"></span></div>`}
  function hud(s){const r=s.rank||{},terminal=!!r.terminal,pct=Math.max(0,Math.min(100,Number(s.level_progress_pct||0))),level=Number(s.current_level||1),next=Number(s.next_level_xp||0);return `<section class="cvRankHudV60" style="${vars(r)}"><div>${shield(s)}</div><div><div class="cvRankEyV60">CV RANK SYSTEM</div><div class="cvRankTitleV60">RANGO <span>${safe(r.name||'BRONCE')}</span> · NIVEL ${level}</div><div class="cvRankTagV60">${safe(r.tagline||'Cada acción suma.')}</div><div class="cvRankBarV60"><i style="width:${pct}%"></i></div><div class="cvRankMetaV60"><b>${Number(s.total_xp||0).toLocaleString('es-CL')} XP</b><span>${terminal?'Rango máximo':Number(s.xp_to_next_level||0).toLocaleString('es-CL')+' XP para Nivel '+(level+1)}</span></div>${terminal?'<div class="cvRankNextV60"><strong>LEYENDA</strong><span>Has alcanzado el rango máximo.</span></div>':`<div class="cvRankNextV60"><strong>CAMINO A ${safe(s.next_rank?.name||'SIGUIENTE RANGO')}</strong><span>${Number(s.xp_to_next_rank||0).toLocaleString('es-CL')} XP · ${Number(s.levels_to_next_rank||0)} niveles</span></div>`}</div><button class="cvRankOpenV60" type="button" onclick="window.CVRankV60.openProfile()">VER MI EVOLUCIÓN</button></section>`}
  function decorateHome(){const c=document.getElementById('content');if(!c||currentView()!=='home'||!state.value)return;c.querySelector('.cvRankHudV60')?.remove();const hero=c.querySelector('.hero');if(hero)hero.insertAdjacentHTML('afterend',hud(state.value));const stats=c.querySelector('.stats');if(stats){const cards=stats.querySelectorAll('.stat');if(cards[0]){cards[0].querySelector('.l').textContent='Rango actual';cards[0].querySelector('.v').textContent=state.value.rank?.name||'—';cards[0].querySelector('.v').style.fontSize='19px'}if(cards[2])cards[2].querySelector('.v').textContent=Number(state.value.total_xp||0).toLocaleString('es-CL')}}}
  function decorateWorkout(){if(currentView()!=='workout'||!state.value)return;const top=document.querySelector('.workoutTop .grow')||document.querySelector('.workoutTop');if(!top||top.querySelector('.cvWorkoutRankChipV60'))return;const chip=document.createElement('div');chip.className='cvWorkoutRankChipV60';chip.style.cssText=`--rank:${state.value.rank?.color_primary||'#C47A3A'}`;chip.innerHTML=`RANGO <b>${safe(state.value.rank?.name||'BRONCE')}</b> · NIVEL ${Number(state.value.current_level||1)}`;top.append(chip)}
  function ladder(s){return ranks.map((r,i)=>{const reached=Number(s.current_level||1)>=r.min,current=s.rank?.key===r.key;return `<div class="cvRankStepV60 ${reached?'reached':''} ${current?'current':''}"><div class="cvRankDotV60" style="--dot:${r.c1}"></div><strong>${safe(r.name)}</strong>Nv. ${r.min}${r.max>r.min?'–'+r.max:''}</div>`}).join('')}
  function profileHTML(s){const p=s.pillar_xp||{},vals={training:Number(p.training||0),nutrition:Number(p.nutrition||0),habits:Number(p.habits||0),progress:Number(p.progress||0)},max=Math.max(1,...Object.values(vals));const pillar=(name,key)=>`<div class="cvPillarV60"><span>${name}</span><div class="mini"><i style="width:${Math.round(vals[key]/max*100)}%"></i></div><b>${vals[key].toLocaleString('es-CL')} XP</b></div>`;return `<button class="cvRankCloseV60" type="button" aria-label="Cerrar">×</button><div class="cvRankProfileHeadV60">${shield(s,true)}<div class="cvRankEyV60">TU IDENTIDAD EN EVOLUCIÓN</div><h2>RANGO <span>${safe(s.rank?.name||'BRONCE')}</span></h2><p>${safe(s.rank?.tagline||'Cada acción construye tu siguiente nivel.')}</p></div><div class="cvRankBarV60"><i style="width:${Math.max(0,Math.min(100,Number(s.level_progress_pct||0)))}%"></i></div><div class="cvRankMetaV60"><b>NIVEL ${Number(s.current_level||1)} · ${Number(s.total_xp||0).toLocaleString('es-CL')} XP</b><span>${s.rank?.terminal?'RANGO MÁXIMO':Number(s.xp_to_next_level||0).toLocaleString('es-CL')+' XP para subir'}</span></div><div class="cvRankProfileGridV60"><div class="cvRankMetricV60"><small>CV Score</small><b>${Math.round(Number(s.cv_score||0))}</b></div><div class="cvRankMetricV60"><small>Créditos CV</small><b>${Number(s.credit_balance||0).toLocaleString('es-CL')}</b></div><div class="cvRankMetricV60"><small>Progreso de rango</small><b>${Math.round(Number(s.rank_progress_pct||0))}%</b></div><div class="cvRankMetricV60"><small>Próximo rango</small><b style="font-size:15px">${safe(s.next_rank?.name||'LEYENDA')}</b></div></div><div class="section"><div class="sectionHead"><h2>XP POR ÁREA</h2></div><div class="cvPillarsV60">${pillar('Entrenamiento','training')}${pillar('Nutrición','nutrition')}${pillar('Hábitos','habits')}${pillar('Progreso','progress')}</div></div><div class="section"><div class="sectionHead"><h2>CAMINO DE RANGOS</h2></div><div class="cvRankPathV60">${ladder(s)}</div></div>`}
  async function openProfile(){const s=await load(true);document.querySelector('.cvRankBackdropV60')?.remove();const back=document.createElement('div');back.className='cvRankBackdropV60';back.innerHTML=`<section class="cvRankProfileV60" style="${vars(s.rank)}" role="dialog" aria-modal="true">${profileHTML(s)}</section>`;document.body.append(back);back.querySelector('.cvRankCloseV60').onclick=()=>back.remove();back.addEventListener('click',e=>{if(e.target===back)back.remove()})}
  function progressionSound(rankUp=false){if(localStorage.getItem('cv_sound_enabled')==='0')return;setTimeout(()=>{try{const C=window.AudioContext||window.webkitAudioContext;if(!C)return;state.audio=state.audio||new C();if(state.audio.state==='suspended')state.audio.resume().catch(()=>{});const t=state.audio.currentTime,notes=rankUp?[392,523,659,784,1047]:[523,659,784];notes.forEach((f,i)=>{const o=state.audio.createOscillator(),g=state.audio.createGain();o.type=i===notes.length-1?'triangle':'sine';o.frequency.value=f;const at=t+i*.085;g.gain.setValueAtTime(.0001,at);g.gain.exponentialRampToValueAtTime(rankUp?.035:.025,at+.015);g.gain.exponentialRampToValueAtTime(.0001,at+.19);o.connect(g).connect(state.audio.destination);o.start(at);o.stop(at+.21)})}catch(_){}},360)}
  function showProgression(before,after,gained=0){const levelUp=Number(after?.current_level||0)>Number(before?.current_level||0),rankUp=before?.rank?.key&&after?.rank?.key&&before.rank.key!==after.rank.key;if(!levelUp&&!rankUp){if(gained>0)showXp(gained);return}document.querySelector('.cvRankBackdropV60')?.remove();const back=document.createElement('div');back.className='cvRankBackdropV60';const title=rankUp?'RANK UP':'LEVEL UP',headline=rankUp?`${safe(before.rank.name)} → ${safe(after.rank.name)}`:`${Number(before.current_level)} → ${Number(after.current_level)}`,sub=rankUp?`Nuevo rango: ${safe(after.rank.name)}`:`Rango ${safe(after.rank.name)} · Nivel ${Number(after.current_level)}`;back.innerHTML=`<section class="cvProgressionV60" style="${vars(after.rank)}" role="dialog" aria-modal="true"><div class="cvOverlineV60">${title}</div><h2>${headline}</h2>${shield(after,true)}<h3>${sub}</h3><p>${safe(after.rank?.tagline||'Tu esfuerzo está construyendo una mejor versión.')}${gained>0?' · +'+Number(gained).toLocaleString('es-CL')+' XP':''}</p><button class="btn primary" type="button">CONTINUAR</button></section>`;document.body.append(back);back.querySelector('button').onclick=()=>back.remove();try{navigator.vibrate?.(rankUp?[90,60,120,60,170]:[70,45,110])}catch(_){}progressionSound(rankUp)}
  function showXp(amount){if(!(Number(amount)>0))return;const el=document.createElement('div');el.className='cvXpBurstV60';el.textContent='+'+Number(amount).toLocaleString('es-CL')+' XP';document.body.append(el);setTimeout(()=>el.remove(),1450)}
  async function afterRender(){await load(false);decorateHome();decorateWorkout()}
  function wrapActions(){if(state.wrapped)return;state.wrapped=true;[['logHabit','habit'],['logNutrition','nutrition']].forEach(([name])=>{const original=window[name];if(typeof original!=='function'||original.__cvRankV60)return;const wrapped=async function(){const before=clone(await load(false)),beforeXp=Number(before?.total_xp||0),result=await original.apply(this,arguments);if(result===false)return result;const after=clone(await load(true)),gained=Math.max(0,Number(after?.total_xp||0)-beforeXp);decorateHome();showProgression(before,after,gained);return result};wrapped.__cvRankV60=true;window[name]=wrapped})}
  document.addEventListener('cv:rendered',()=>{afterRender().catch(()=>{});wrapActions()});
  window.addEventListener('pageshow',()=>{load(true).then(()=>{decorateHome();decorateWorkout()}).catch(()=>{})});
  window.CVRankV60={version:'v60',load,openProfile,showProgression,decorateHome,decorateWorkout,ranks};
  setTimeout(()=>{wrapActions();afterRender().catch(()=>{})},0);
})();
</script>'''

if MARKER not in text:
    for prerequisite in [
        "cv-coach-client-loop-v59",
        "cv-client-modules-v57",
        "cv-client-e2e-v58",
        "cv-render-bus-v51-js",
    ]:
        if prerequisite not in text:
            raise SystemExit(f"rank system v60 prerequisite missing: {prerequisite}")

    old_types = "const notificationTypes={onboarding_approved:'Onboarding aprobado',onboarding_changes_requested:'Cambios solicitados',adaptive_mission:'Misión adaptativa',mission_completed:'Misión completada',achievement_unlocked:'Logro desbloqueado',level_up:'Subida de nivel',program_published:'Rutina actualizada'};"
    new_types = "const notificationTypes={onboarding_approved:'Onboarding aprobado',onboarding_changes_requested:'Cambios solicitados',adaptive_mission:'Misión adaptativa',mission_completed:'Misión completada',achievement_unlocked:'Logro desbloqueado',level_up:'Subida de nivel',program_published:'Rutina actualizada',rank_up:'Nuevo rango'};"
    if old_types not in text:
        raise SystemExit("rank system v60 notification type map not found")
    text = text.replace(old_types, new_types, 1)

    if "</body>" not in text:
        raise SystemExit("rank system v60: </body> missing")
    text = text.replace("</body>", STYLE + "\n" + SCRIPT + "\n" + MARKER + "\n</body>", 1)

required = [
    MARKER,
    'cv-rank-system-v60-css',
    'cv-rank-system-v60-js',
    "rank_up:'Nuevo rango'",
    "get_client_rank_state_backend",
    "BRONCE",
    "PLATA",
    "ORO",
    "DIAMANTE",
    "MAESTRO",
    "GRAN MAESTRO",
    "LEYENDA",
    "CV RANK SYSTEM",
    "RANK UP",
    "LEVEL UP",
    "VER MI EVOLUCIÓN",
    "cvRankShieldV60",
    "cvWorkoutRankChipV60",
    "window.CVRankV60={version:'v60'",
]
for item in required:
    if item not in text:
        raise SystemExit(f"rank system v60 required contract missing: {item}")

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
    "CV Rank System HUD v60",
    "Bronze-to-Legend rank identity v60",
    "rank profile and pillar XP v60",
    "level-up and rank-up feedback v60",
    "workout level chip without workout runtime rewrite v60",
]:
    if patch not in patches:
        patches.append(patch)
metadata["patches"] = patches
BUILD.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"sha256": sha, "bytes": metadata["bytes"], "patches": metadata["patches"][-5:]}, ensure_ascii=False))
