from pathlib import Path
import re

path=Path('client-portal/index.html')
text=path.read_text()

style='''<style id="cv-workout-result-v1">
.cvWorkoutResultBackdrop{position:fixed;inset:0;z-index:220;background:rgba(0,0,0,.82);backdrop-filter:blur(12px);display:grid;place-items:center;padding:18px}
.cvWorkoutResultCard{width:min(520px,100%);max-height:88dvh;overflow:auto;border:1px solid #303942;border-radius:20px;background:linear-gradient(155deg,#121820,#080d10 65%,#05080a);box-shadow:0 32px 100px rgba(0,0,0,.72),0 0 40px rgba(225,29,46,.08);padding:20px}
.cvWorkoutResultCard .cvResultHero{padding:16px;border:1px solid rgba(225,29,46,.34);border-radius:16px;background:radial-gradient(circle at 100% 0,rgba(225,29,46,.12),transparent 38%),#090e12}
.cvWorkoutResultCard .cvResultHero.success{border-color:rgba(88,226,163,.38);background:radial-gradient(circle at 100% 0,rgba(88,226,163,.10),transparent 38%),#090e12}
.cvWorkoutResultCard h2{font-size:32px;margin:4px 0}.cvWorkoutResultCard .cvResultGrid{display:grid;grid-template-columns:repeat(2,1fr);gap:9px;margin:12px 0}
.cvWorkoutResultCard .cvResultMetric{border:1px solid #26313a;border-radius:13px;background:#080d11;padding:12px}.cvWorkoutResultCard .cvResultMetric small{display:block;color:#8f9aa2;font-size:8px;text-transform:uppercase;letter-spacing:.09em}.cvWorkoutResultCard .cvResultMetric b{display:block;margin-top:5px;font-size:22px}
.cvWorkoutResultCard .cvResultLevel{margin:12px 0;padding:14px;border-radius:14px;border:1px solid rgba(255,45,63,.46);background:rgba(225,29,46,.09);text-align:center}.cvWorkoutResultCard .cvResultLevel b{display:block;font-size:28px;color:#fff}.cvWorkoutResultCard .cvResultList{display:grid;gap:7px;margin:10px 0}.cvWorkoutResultCard .cvResultItem{padding:10px;border:1px solid #253039;border-radius:11px;background:#080d10;font-size:11px;color:#d7dde1}
.cvWorkoutResultCard .cvResultClose{width:100%;margin-top:10px}
</style>'''
if 'id="cv-workout-result-v1"' not in text:
    if text.count('</head>')!=1: raise SystemExit('Expected one </head>')
    text=text.replace('</head>',style+'\n</head>',1)

replacement=r'''function cvWorkoutResultNumber(value,fallback=0){const n=Number(value);return Number.isFinite(n)?n:fallback}
function cvWorkoutResultStatus(result){const status=String(result?.status||'').toLowerCase();if(status==='completed')return {title:'ENTRENAMIENTO COMPLETADO',ey:'PROGRESO REGISTRADO',hero:'success',message:'Tu sesión quedó completada y el sistema ya registró tus métricas reales.'};if(status==='partial')return {title:'SESIÓN PARCIAL GUARDADA',ey:'PROGRESO REGISTRADO',hero:'',message:'Guardamos lo que realizaste. Tu coach podrá revisar la sesión antes de ajustar la progresión.'};if(status==='abandoned')return {title:'SESIÓN CERRADA',ey:'DATOS GUARDADOS',hero:'',message:'La sesión quedó cerrada con baja finalización. Se conservaron las series registradas.'};return {title:'SESIÓN GUARDADA',ey:'CV COACH',hero:'',message:'Tus datos fueron guardados correctamente.'}}
function cvShowWorkoutResult(result){
  const old=document.getElementById('cvWorkoutResultModal');if(old)old.remove();
  const meta=cvWorkoutResultStatus(result),completion=Math.max(0,Math.min(100,cvWorkoutResultNumber(result?.completion_pct,0))),volume=Math.max(0,cvWorkoutResultNumber(result?.total_volume,0)),xp=Math.max(0,cvWorkoutResultNumber(result?.xp_earned,0)),credits=cvWorkoutResultNumber(result?.credits_earned,0),missions=Math.max(0,cvWorkoutResultNumber(result?.missions_completed,0)),achievements=Array.isArray(result?.achievements_unlocked)?result.achievements_unlocked:[],levelUp=result?.level_up===true,currentLevel=Math.max(1,cvWorkoutResultNumber(result?.current_level,1));
  const modal=document.createElement('div');modal.id='cvWorkoutResultModal';modal.className='cvWorkoutResultBackdrop';
  const achievementHtml=achievements.map(a=>'<div class="cvResultItem">🏆 '+esc(a?.title||'Logro desbloqueado')+(a?.rarity?' · '+esc(String(a.rarity)):'')+'</div>').join('');
  modal.innerHTML='<div class="cvWorkoutResultCard"><div class="cvResultHero '+meta.hero+'"><div class="ey">'+esc(meta.ey)+'</div><h2>'+esc(meta.title)+'</h2><div class="sub">'+esc(meta.message)+'</div></div>'+
    (levelUp?'<div class="cvResultLevel"><div class="ey">LEVEL UP</div><b>NIVEL '+esc(currentLevel)+'</b><div class="hint">Tu progreso acumulado desbloqueó un nuevo nivel CV12.</div></div>':'')+
    '<div class="cvResultGrid"><div class="cvResultMetric"><small>Finalización</small><b>'+esc(completion.toFixed(completion%1?1:0))+'%</b></div><div class="cvResultMetric"><small>Volumen</small><b>'+esc(Math.round(volume).toLocaleString('es-CL'))+' kg</b></div><div class="cvResultMetric"><small>XP obtenido</small><b>+'+esc(xp)+'</b></div><div class="cvResultMetric"><small>Créditos</small><b>'+esc(credits>=0?('+'+credits):credits)+'</b></div></div>'+
    (missions>0?'<div class="cvResultItem">✓ Misiones completadas en esta sesión: <b>'+esc(missions)+'</b></div>':'')+
    (achievementHtml?'<div class="section" style="margin-top:12px"><div class="ey">NUEVOS LOGROS</div><div class="cvResultList">'+achievementHtml+'</div></div>':'')+
    '<div class="hint" style="margin-top:10px">El análisis de progresión y riesgo continúa en segundo plano. Las recomendaciones se basarán en tus registros reales.</div><button id="cvWorkoutResultClose" class="btn primary cvResultClose" type="button">CONTINUAR</button></div>';
  document.body.appendChild(modal);document.getElementById('cvWorkoutResultClose').onclick=()=>modal.remove();
}
window.finishWorkout=async()=>{if(mode==='demo'){toast('Demo finalizada. No se escribieron datos.');workout=null;view='home';render();return}if(!workout.sessionId)return toast('Primero inicia el entrenamiento.');try{const {data:r,error}=await sb.functions.invoke('complete-workout',{body:{session_id:workout.sessionId}});if(error||r?.error)throw new Error(r?.detail||r?.error||error.message);clearInterval(timerHandle);workout=null;await loadReal();view='home';render();cvShowWorkoutResult(r||{})}catch(e){toast(e.message)}}

function habits()'''
pattern=r"window\.finishWorkout=async\(\)=>\{.*?\}\n\nfunction habits\(\)"
text,count=re.subn(pattern,replacement,text,count=1,flags=re.S)
if count!=1: raise SystemExit(f'finishWorkout anchor count={count}')

required=['cvShowWorkoutResult(result)','ENTRENAMIENTO COMPLETADO','SESIÓN PARCIAL GUARDADA','completion_pct','total_volume','xp_earned','credits_earned','missions_completed','achievements_unlocked','level_up',"sb.functions.invoke('complete-workout'",'El análisis de progresión y riesgo continúa en segundo plano.']
missing=[x for x in required if x not in text]
if missing: raise SystemExit('Missing result markers: '+', '.join(missing))
path.write_text(text)
