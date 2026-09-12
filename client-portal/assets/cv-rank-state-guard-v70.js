(function(){
  if(window.CVRankStateGuardV70)return;
  window.CVRankStateGuardV70=true;

  const floors=[0,0,200,450,750,1100,1500,1950,2450,3000,3600,4250,4950,5700,6500,7350,8250,9200,10200,11250,12350,13500,14700,16000,17400,18900,20500];
  const maintain={bronze:55,silver:60,gold:70,platinum:78,diamond:86,legend:93};
  const progress={bronze:70,silver:75,gold:82,platinum:87,diamond:92,legend:96};
  let timer=null,running=false;

  const real=()=>{try{return mode==='real'&&!!user?.id&&!!sb}catch(_){return false}};
  const cacheKey=()=>real()?`cv_rank_dashboard_v70_${user.id}`:null;
  const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const bounded=(p,ms=6500)=>Promise.race([Promise.resolve(p),new Promise((_,rej)=>setTimeout(()=>rej(new Error('rank dashboard timeout')),ms))]);

  function valid(d){return !!(d&&d.tutorial_completed!=null&&Number(d.current_level)>=0&&d.rank&&d.rank.rank_key)}
  function readCache(){const k=cacheKey();if(!k)return null;try{const x=JSON.parse(localStorage.getItem(k)||'null');return valid(x?.data)?x.data:null}catch(_){return null}}
  function writeCache(d){const k=cacheKey();if(!k||!valid(d))return;try{localStorage.setItem(k,JSON.stringify({at:Date.now(),data:d}))}catch(_){}}
  function normalize(d){
    if(!d)return d;
    const out=JSON.parse(JSON.stringify(d));
    const lvl=Math.max(0,Math.min(26,Number(out.current_level||0)));
    const rating=Number(out.cv_rating||0);
    const nextFloor=lvl<26?Number(floors[lvl+1]||0):rating;
    if(lvl>0&&lvl<26&&Number.isFinite(rating)&&nextFloor>rating){
      const computed=Math.max(0,nextFloor-rating);
      const raw=Number(out.rating_to_next_level);
      if(!Number.isFinite(raw)||raw<=0)out.rating_to_next_level=Math.round(computed*100)/100;
      if(!Number.isFinite(Number(out.level_progress_pct))||Number(out.level_progress_pct)<=0){
        const floor=Number(floors[lvl]||0),span=Math.max(1,nextFloor-floor);
        out.level_progress_pct=Math.max(0,Math.min(100,((rating-floor)/span)*100));
      }
    }
    return out;
  }
  async function direct(){
    if(!real())return null;
    try{await bounded(sb.rpc('sync_rank_tutorial_v61',{p_actor_id:user.id}),3500)}catch(_){}
    const q=await bounded(sb.rpc('get_client_rank_dashboard_v61',{p_actor_id:user.id,p_client_id:user.id}),6500);
    if(q?.error)throw q.error;
    const d=normalize(q?.data);
    if(!valid(d))throw new Error('rank dashboard invalid');
    writeCache(d);return d;
  }
  function rankState(d){
    const key=d?.rank?.rank_key||'bronze';
    const score=Math.round(Number(d?.discipline_preview?.discipline_score??d?.last_discipline_score??0));
    const min=maintain[key]||55,grow=progress[key]||70;
    if(score<min)return {title:'EN RIESGO',msg:`Necesitas ${min}% para proteger tu rango.`,color:'#ff4054',score};
    if(score>=grow)return {title:'EN PROGRESO',msg:`Superas el ${grow}% requerido para avanzar.`,color:'#48db9b',score};
    return {title:'RANGO SEGURO',msg:`Mantienes el mínimo de ${min}% esta semana.`,color:'#42bfff',score};
  }
  function rankAsset(d){return `./assets/ranks/cv-rank-${d?.rank?.rank_key||'bronze'}-v61.webp?v=70`}

  function updateWorkout(d){
    const hud=document.querySelector('#content .cv64WorkoutRankHud');if(!hud)return;
    if(!d){
      hud.classList.add('cv70Syncing');
      const meta=hud.querySelector('.cv64WorkoutMeta');if(meta)meta.innerHTML='<b>— CV</b><span>Sincronizando progreso…</span>';
      const state=hud.querySelector('.cv64WorkoutState');if(state)state.innerHTML='<b>SINCRONIZANDO</b><span>Conectando CV Rank</span>';
      return;
    }
    hud.classList.remove('cv70Syncing');
    const r=d.rank||{},lvl=Number(d.current_level||1),rating=Number(d.cv_rating||0),remaining=Number(d.rating_to_next_level||0),pct=Math.max(0,Math.min(100,Number(d.level_progress_pct||0))),st=rankState(d);
    hud.style.setProperty('--r',r.color_primary||'#c47a3a');hud.style.setProperty('--r2',r.color_secondary||'#6e351e');hud.style.setProperty('--state',st.color);
    const img=hud.querySelector('.cv64WorkoutBadge img');if(img){img.src=rankAsset(d);img.alt=`Insignia ${r.rank_name||'BRONCE'}`}
    const strong=hud.querySelector('.cv64WorkoutCopy strong');if(strong)strong.innerHTML=`${esc(r.rank_name||'BRONCE')} <em>· NIVEL ${lvl}</em>`;
    const fill=hud.querySelector('.cv64WorkoutBar i');if(fill)fill.style.width=pct+'%';
    const meta=hud.querySelector('.cv64WorkoutMeta');if(meta)meta.innerHTML=`<b>${rating.toLocaleString('es-CL',{maximumFractionDigits:2})} CV</b><span>${lvl>=26?'Rango máximo':remaining.toLocaleString('es-CL',{maximumFractionDigits:2})+' CV para Nivel '+(lvl+1)}</span>`;
    const state=hud.querySelector('.cv64WorkoutState');if(state)state.innerHTML=`<b>${st.title}</b><span>Disciplina ${st.score}%</span>`;
  }

  function updateHome(d){
    const card=document.querySelector('#content .cv61RankCard');if(!card||!d?.tutorial_completed)return;
    const r=d.rank||{},lvl=Number(d.current_level||1),rating=Number(d.cv_rating||0),remaining=Number(d.rating_to_next_level||0),pct=Math.max(0,Math.min(100,Number(d.level_progress_pct||0))),st=rankState(d);
    card.style.setProperty('--r',r.color_primary||'#c47a3a');card.style.setProperty('--r2',r.color_secondary||'#6e351e');
    const img=card.querySelector('.cv61Badge img');if(img){img.src=rankAsset(d);img.alt=`Insignia ${r.rank_name||'BRONCE'}`}
    const title=card.querySelector('.cv61Title');if(title)title.innerHTML=`RANGO <b>${esc(r.rank_name||'BRONCE')}</b><span class="cv64TitleLevel">NIVEL ${lvl}</span>`;
    const fill=card.querySelector('.cv61Bar i');if(fill)fill.style.width=pct+'%';
    const meta=card.querySelector('.cv61Meta');if(meta)meta.innerHTML=`<b>${rating.toLocaleString('es-CL',{maximumFractionDigits:2})} CV</b><span>${lvl>=26?'Rango máximo':remaining.toLocaleString('es-CL',{maximumFractionDigits:2})+' CV para Nivel '+(lvl+1)}</span>`;
    const state=card.querySelector('.cv64State');if(state){state.style.setProperty('--state',st.color);state.innerHTML=`<strong>${st.title}</strong><span>${st.msg}</span>`}
    const next=card.querySelector('.cv61Next');if(next&&lvl<26){const nextName=d.next_rank?.rank_name||d.next_rank?.name||'SIGUIENTE';const min=Number(d.next_rank?.min_level||lvl+1),n=Math.max(1,min-lvl);next.innerHTML=`<strong>PRÓXIMO RANGO · ${esc(nextName)}</strong><span>${n} ascenso${n===1?'':'s'} restante${n===1?'':'s'} · Disciplina ${st.score}%</span>`}
  }

  async function refresh(){
    if(running)return;running=true;
    try{
      let d=null;
      if(real()){
        const cached=readCache();
        if(cached){d=normalize(cached);updateWorkout(d);updateHome(d)}
        try{d=await direct()}catch(e){console.warn('CV Rank V70 direct load failed',e);d=d||cached}
      }else if(window.CVRankV61?.load){
        try{d=normalize(await window.CVRankV61.load(false))}catch(_){}
      }
      updateWorkout(d);updateHome(d);
    }finally{running=false}
  }
  function schedule(ms=80){clearTimeout(timer);timer=setTimeout(refresh,ms)}
  document.addEventListener('cv:rendered',()=>schedule(40));
  window.addEventListener('pageshow',()=>schedule(120));
  document.addEventListener('visibilitychange',()=>{if(!document.hidden)schedule(120)});
  new MutationObserver(()=>schedule(90)).observe(document.documentElement,{childList:true,subtree:true});
  schedule(180);
})();
