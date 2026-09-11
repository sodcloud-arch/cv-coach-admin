(function(){
  if(window.CVRankRealUIV63)return;
  window.CVRankRealUIV63=true;

  const earned=[
    ['bronze','BRONCE',1,5],
    ['silver','PLATA',6,10],
    ['gold','ORO',11,15],
    ['platinum','PLATINO',16,20],
    ['diamond','DIAMANTE',21,25],
    ['legend','LEYENDA',26,26]
  ];
  const maintain={bronze:55,silver:60,gold:70,platinum:78,diamond:86,legend:93};
  const progress={bronze:70,silver:75,gold:82,platinum:87,diamond:92,legend:96};
  const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const row=l=>earned.find(r=>l>=r[2]&&l<=r[3])||earned[0];
  const asset=k=>`./assets/ranks/cv-rank-${k}-v61.webp`;

  function rankState(d){
    if(!d?.tutorial_completed)return {t:'INICIACIÓN',m:'Completa el tutorial para ganar Bronce.',c:'#a5b1b8'};
    const r=d.rank?.rank_key||row(+d.current_level)[0];
    const score=+(d.discipline_preview?.discipline_score||d.last_discipline_score||0);
    const min=maintain[r]||55;
    const grow=progress[r]||70;
    if(score<min)return {t:'EN RIESGO',m:`Necesitas ${min}% para proteger tu rango.`,c:'#ff4054'};
    if(score>=grow)return {t:'EN PROGRESO',m:`Superas el ${grow}% requerido para avanzar.`,c:'#48db9b'};
    return {t:'RANGO SEGURO',m:`Mantienes el mínimo de ${min}% esta semana.`,c:'#42bfff'};
  }

  function inLeague(d){
    if(!d?.tutorial_completed)return 0;
    const r=row(+d.current_level);
    return r[2]===r[3]?1:(+d.current_level-r[2]+1);
  }

  function compactPath(d){
    const lvl=+d?.current_level||0;
    const cur=d?.rank?.rank_key||row(Math.max(1,lvl))[0];
    const tutorial=`<div class="cv63Step ${!d?.tutorial_completed?'current':'reached'}"><img src="${asset('tutorial')}" alt="Tutorial"><b>Tutorial</b></div>`;
    const leagues=earned.map(r=>{
      const reached=d?.tutorial_completed&&lvl>=r[2];
      const current=d?.tutorial_completed&&cur===r[0];
      return `<div class="cv63Step ${reached?'reached':''} ${current?'current':''}"><img src="${asset(r[0])}" alt="${r[1]}"><b>${r[1]}</b></div>`;
    }).join('');
    return `<div class="cv63CompactPath">${tutorial}${leagues}</div>`;
  }

  function levelPips(d){
    if(!d?.tutorial_completed||+d.current_level===26)return '';
    const n=inLeague(d);
    return `<div class="cv63LevelPips">${[1,2,3,4,5].map(i=>`<i class="${i<=n?'on':''}"></i>`).join('')}</div>`;
  }

  async function activeChallenge(){
    try{
      if(typeof mode==='undefined'||mode!=='real'||typeof sb==='undefined'||typeof user==='undefined'||!user?.id)return null;
      const q=await sb.rpc('get_client_challenges_v61',{p_actor_id:user.id,p_client_id:user.id});
      if(q.error)return null;
      return (q.data?.rows||[]).find(x=>x.status==='active')||null;
    }catch(_){return null;}
  }

  async function decorateHome(d){
    const c=document.getElementById('content');
    if(!c||String(document.body.dataset.cvView||'home')!=='home')return;
    const card=c.querySelector('.cv61RankCard');
    if(card&&!card.classList.contains('cv63Real')){
      card.classList.add('cv63Real');
      const badge=card.querySelector('.cv61Badge');
      if(badge){
        badge.style.setProperty('--cv63-aura',`${5+inLeague(d)*3}px`);
        badge.insertAdjacentHTML('beforeend',levelPips(d));
      }
      const st=rankState(d);
      const next=card.querySelector('.cv61Next');
      if(next&&!card.querySelector('.cv63State')){
        next.insertAdjacentHTML('afterend',`<div class="cv63State" style="--state:${st.c}"><strong>${st.t}</strong><span>${st.m}</span></div>`);
      }
      const open=card.querySelector('.cv61Open');
      if(open&&!card.querySelector('.cv63CompactPath'))open.insertAdjacentHTML('beforebegin',compactPath(d));
    }

    if(d?.tutorial_completed&&!c.querySelector('.cv63ChallengeTeaser')){
      const ch=await activeChallenge();
      if(ch){
        const target=c.querySelector('.cv61MiniStats');
        if(target){
          target.insertAdjacentHTML('afterend',`<div class="cv63ChallengeTeaser" role="button" tabindex="0"><div class="row"><div class="ico">🎯</div><div class="grow"><small>DESAFÍO ACTIVO</small><b>${esc(ch.name||'Competencia CV')}</b><em>${esc(ch.reward_title||'Revisa tus requisitos y sigue avanzando.')}</em></div><div class="go">›</div></div></div>`);
          const teaser=c.querySelector('.cv63ChallengeTeaser');
          if(teaser){
            const go=()=>window.CVRankV61?.open?.('challenges');
            teaser.onclick=go;
            teaser.onkeydown=e=>{if(e.key==='Enter'||e.key===' ')go();};
          }
        }
      }
    }
  }

  function decorateModal(d){
    const sheet=document.querySelector('.cv61Sheet');
    if(!sheet)return;
    const body=sheet.querySelector('.cv61Body');
    if(!body||body.querySelector('.cv63EvoState'))return;
    const active=sheet.querySelector('[data-tab].active')?.dataset.tab;
    if(active!=='evolution')return;
    const st=rankState(d);
    const hero=body.querySelector('.cv61Hero');
    if(hero){
      hero.insertAdjacentHTML('afterend',`<div class="cv63EvoState" style="--state:${st.c}"><small>ESTADO DEL RANGO</small><b>${st.t}</b><p>${st.m}</p></div>${compactPath(d)}`);
    }
  }

  async function run(){
    try{
      if(!window.CVRankV61)return;
      const d=await window.CVRankV61.load(false);
      await decorateHome(d);
      decorateModal(d);
    }catch(e){console.warn('CV Rank real UI V63',e);}
  }

  document.addEventListener('cv:rendered',()=>setTimeout(run,20));
  window.addEventListener('pageshow',()=>setTimeout(run,80));
  new MutationObserver(()=>setTimeout(run,20)).observe(document.documentElement,{childList:true,subtree:true});
  setTimeout(run,120);
})();
