(function(){
  if(window.CVRankCelebrationV66?.version==='v66')return;
  const rankMap={
    bronze:{name:'BRONCE',asset:'./assets/ranks/cv-rank-bronze-v61.webp',c1:'#C47A3A',c2:'#6E351E'},
    silver:{name:'PLATA',asset:'./assets/ranks/cv-rank-silver-v61.webp',c1:'#D8E0E6',c2:'#71808A'},
    gold:{name:'ORO',asset:'./assets/ranks/cv-rank-gold-v61.webp',c1:'#F4B942',c2:'#8A5A12'},
    platinum:{name:'PLATINO',asset:'./assets/ranks/cv-rank-platinum-v61.webp',c1:'#28D7E9',c2:'#0B7786'},
    diamond:{name:'DIAMANTE',asset:'./assets/ranks/cv-rank-diamond-v61.webp',c1:'#5596FF',c2:'#173F9C'},
    legend:{name:'LEYENDA',asset:'./assets/ranks/cv-rank-legend-v61.webp',c1:'#F5F7FA',c2:'#FF2037'}
  };
  let overlay=null,pending=null,checking=false,audioCtx=null,primed=false,previewTimer=null;
  const safe=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot',"'":'&#39;'}[c]));
  function real(){try{return mode==='real'&&!!user?.id&&!!sb}catch(_){return false}}
  function demo(){try{return mode!=='real'}catch(_){return true}}
  function enabled(){try{return localStorage.getItem('cv_sound_enabled')!=='0'}catch(_){return true}}
  function ctx(){try{if(!audioCtx){const C=window.AudioContext||window.webkitAudioContext;if(!C)return null;audioCtx=new C()}if(audioCtx.state==='suspended')audioCtx.resume().catch(()=>{});return audioCtx}catch(_){return null}}
  function tone(f,d,delay=0,vol=.02,type='triangle'){if(!enabled())return;const c=ctx();if(!c)return;try{const o=c.createOscillator(),g=c.createGain(),t=c.currentTime+delay;o.type=type;o.frequency.setValueAtTime(f,t);g.gain.setValueAtTime(.0001,t);g.gain.exponentialRampToValueAtTime(Math.max(.001,vol),t+.008);g.gain.exponentialRampToValueAtTime(.0001,t+d);o.connect(g).connect(c.destination);o.start(t);o.stop(t+d+.03)}catch(_){}}
  function sfx(kind){
    if(kind==='level_up'){tone(392,.11,0,.018);tone(523,.12,.09,.021);tone(659,.18,.19,.024);return}
    if(kind==='legend_unlock'){tone(220,.15,0,.018,'sine');tone(330,.18,.10,.021,'triangle');tone(494,.18,.20,.024,'triangle');tone(659,.24,.31,.026,'sine');tone(988,.35,.44,.022,'sine');return}
    tone(262,.11,0,.018);tone(392,.13,.08,.021);tone(523,.16,.18,.024);tone(784,.28,.31,.025)
  }
  function haptic(kind){try{navigator.vibrate?.(kind==='level_up'?[45,35,70]:kind==='legend_unlock'?[80,40,120,55,180]:[65,35,95,45,135])}catch(_){}}
  function rank(raw,key){const base=rankMap[key]||rankMap.bronze;return {...base,...(raw||{}),rank_key:key||raw?.rank_key||'bronze',rank_name:raw?.rank_name||base.name,badge_path:raw?.badge_path||base.asset,color_primary:raw?.color_primary||base.c1,color_secondary:raw?.color_secondary||base.c2}}
  function normalize(x){
    if(!x||x.pending===false)return null;
    const dir=String(x.direction||'level_up');
    const fromKey=x.from_rank?.rank_key||x.from_rank_key||'bronze',toKey=x.to_rank?.rank_key||x.to_rank_key||fromKey;
    return {...x,direction:dir,from_rank:rank(x.from_rank,fromKey),to_rank:rank(x.to_rank,toKey),metadata:x.metadata||{}};
  }
  function shardMarkup(){const pts=[[-104,-72,-38],[-72,-122,-12],[-24,-145,14],[43,-138,32],[92,-102,55],[132,-44,78],[139,35,108],[102,92,132],[44,134,158],[-24,145,188],[-88,110,216],[-132,38,248],[-126,-30,286],[-72,-78,324]];return `<div class="cv66Shards">${pts.map(([x,y,r])=>`<i class="cv66Shard" style="--x:${x}px;--y:${y}px;--r:${r}deg"></i>`).join('')}</div>`}
  function headline(e){if(e.direction==='legend_unlock')return ['LEYENDA','DESBLOQUEADA'];if(e.direction==='rank_up')return ['ASCENSO','DE RANGO'];return ['LEVEL','UP']}
  function subtitle(e){if(e.direction==='legend_unlock')return 'La disciplina ya es parte de ti.';if(e.direction==='rank_up')return 'Tu constancia desbloqueó un nuevo rango.';return 'Tu disciplina te hace avanzar.'}
  function stats(e){const m=e.metadata||{},rows=[];if(Number.isFinite(Number(m.discipline_score)))rows.push(['Disciplina',`${Math.round(Number(m.discipline_score))}%`]);if(Number.isFinite(Number(m.rating_change))&&Number(m.rating_change)!==0)rows.push(['CV Rating',`${Number(m.rating_change)>0?'+':''}${Math.round(Number(m.rating_change))} CV`]);return rows.slice(0,2)}
  function html(e){
    const to=e.to_rank,from=e.from_rank,h=headline(e),isLevel=e.direction==='level_up';const r1=to.color_primary||to.c1,r2=to.color_secondary||to.c2;
    const trans=isLevel?`<span>NIVEL ${Number(e.from_level||0)}</span><span class="arrow">→</span><span>NIVEL ${Number(e.to_level||0)}</span>`:`<span>${safe(from.rank_name)}</span><span class="arrow">→</span><span>${safe(to.rank_name)}</span>`;
    const ss=stats(e);
    return `<div class="cv66Ascend ${safe(e.direction)}" style="--cv66:${safe(r1)};--cv66b:${safe(r2)}" role="dialog" aria-modal="true" aria-label="${safe(h.join(' '))}">
      <div class="cv66Beam"></div><div class="cv66Flash"></div><div class="cv66Ring"></div>
      <div class="cv66Content">
        <div class="cv66Brand">CV RANK SYSTEM</div>
        <div class="cv66Kicker">${isLevel?safe(to.rank_name):e.direction==='legend_unlock'?'RANGO MÁXIMO':'NUEVO RANGO'}</div>
        <div class="cv66Title">${safe(h[0])}<br>${safe(h[1])}</div>
        <div class="cv66Stage">
          ${!isLevel?`<img class="cv66Badge from" src="${safe(from.badge_path)}?v=66" alt="${safe(from.rank_name)}">`:''}
          <img class="cv66Badge to" src="${safe(to.badge_path)}?v=66" alt="${safe(to.rank_name)}">
          ${shardMarkup()}
        </div>
        <div class="cv66Transition">${trans}</div>
        <div class="cv66Sub">${safe(subtitle(e))}</div>
        ${ss.length?`<div class="cv66Stats">${ss.map(([a,b],i)=>`<div class="cv66Stat"><small>${safe(a)}</small><b class="${i===1?'accent':''}">${safe(b)}</b></div>`).join('')}</div>`:''}
        <button class="cv66Continue" type="button">CONTINUAR</button>
      </div>
    </div>`
  }
  function close(){if(!overlay)return;overlay.remove();overlay=null;pending=null;document.body.classList.remove('cv66NoScroll');setTimeout(decorateDemoPreview,80)}
  async function acknowledge(){
    const e=pending;if(!e)return close();
    if(e.__preview)return close();
    try{const q=await sb.rpc('ack_rank_transition_v66',{p_actor_id:user.id,p_transition_id:e.transition_id});if(q.error)throw q.error;close();setTimeout(check,260)}catch(err){console.warn('CV Rank V66 ack failed',err)}
  }
  function show(raw,opts={}){
    const e=normalize(raw);if(!e||overlay)return false;e.__preview=!!opts.preview;pending=e;
    document.body.classList.add('cv66NoScroll');document.body.insertAdjacentHTML('beforeend',html(e));overlay=document.querySelector('.cv66Ascend:last-of-type');
    overlay?.querySelector('.cv66Continue')?.addEventListener('click',acknowledge,{once:true});
    setTimeout(()=>{sfx(e.direction);haptic(e.direction)},160);
    return true
  }
  async function check(){
    if(checking||overlay||!real())return;checking=true;
    try{const q=await sb.rpc('get_pending_rank_transition_v66',{p_actor_id:user.id});if(q.error)throw q.error;const e=normalize(q.data);if(e)show(e)}catch(err){console.warn('CV Rank V66 check failed',err)}finally{checking=false}
  }
  function preview(kind='rank_up'){
    kind=String(kind);if(kind==='legend_unlock')return show({pending:true,direction:kind,from_level:25,to_level:26,from_rank:{rank_key:'diamond'},to_rank:{rank_key:'legend'},metadata:{discipline_score:97,rating_change:180}},{preview:true});
    if(kind==='level_up')return show({pending:true,direction:kind,from_level:1,to_level:2,from_rank:{rank_key:'bronze'},to_rank:{rank_key:'bronze'},metadata:{discipline_score:86,rating_change:240}},{preview:true});
    return show({pending:true,direction:'rank_up',from_level:5,to_level:6,from_rank:{rank_key:'bronze'},to_rank:{rank_key:'silver'},metadata:{discipline_score:91,rating_change:310}},{preview:true});
  }
  function decorateDemoPreview(){
    if(!demo()||overlay)return;
    const card=document.querySelector('#content .cv61RankCard.cv64Real');
    if(!card||card.querySelector('.cv66DemoPreview'))return;
    const box=document.createElement('div');box.className='cv66DemoPreview';
    box.style.cssText='grid-column:1/-1;display:flex;align-items:center;justify-content:space-between;gap:8px;margin-top:3px;padding-top:8px;border-top:1px solid rgba(255,255,255,.055)';
    const note=document.createElement('span');note.textContent='Vista demo · no cambia datos';note.style.cssText='color:#69757c;font-size:7px;font-weight:800;letter-spacing:.04em';
    const btn=document.createElement('button');btn.type='button';btn.textContent='PROBAR ASCENSO';btn.style.cssText='min-height:28px;padding:0 10px;border:1px solid rgba(196,122,58,.38);border-radius:9px;background:rgba(196,122,58,.07);color:#d99a63;font:900 7px/1 inherit;letter-spacing:.09em';
    btn.addEventListener('click',()=>preview('rank_up'));
    box.append(note,btn);card.append(box)
  }
  function schedulePreview(){clearTimeout(previewTimer);previewTimer=setTimeout(decorateDemoPreview,80)}
  document.addEventListener('pointerdown',()=>{if(!primed){primed=true;ctx()}},{capture:true});
  document.addEventListener('cv:rendered',()=>{setTimeout(check,160);schedulePreview()});
  window.addEventListener('pageshow',()=>{setTimeout(check,450);schedulePreview()});
  document.addEventListener('visibilitychange',()=>{if(!document.hidden){setTimeout(check,400);schedulePreview()}});
  new MutationObserver(schedulePreview).observe(document.documentElement,{childList:true,subtree:true});
  setTimeout(check,900);schedulePreview();
  window.CVRankCelebrationV66={version:'v66',check,show,preview,close,decorateDemoPreview};
})();
