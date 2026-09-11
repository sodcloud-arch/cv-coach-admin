(function(){
  if(window.CVRankRealUIV65)return;
  window.CVRankRealUIV65=true;

  const earned=[
    ['bronze','BRONCE',1,5],
    ['silver','PLATA',6,10],
    ['gold','ORO',11,15],
    ['platinum','PLATINO',16,20],
    ['diamond','DIAMANTE',21,25],
    ['legend','LEYENDA',26,26]
  ];
  let timer=null,running=false;

  function row(level){return earned.find(r=>Number(level)>=r[2]&&Number(level)<=r[3])||earned[0]}
  function currentView(){try{return String(document.body.dataset.cvView||view||'')}catch(_){return String(document.body.dataset.cvView||'')}}
  function score(d){return Math.round(Number(d?.discipline_preview?.discipline_score||d?.last_discipline_score||0))}

  function decorateHome(d){
    if(currentView()!=='home'||!d?.tutorial_completed)return;
    const card=document.querySelector('#content .cv61RankCard.cv64Real');
    if(!card)return;
    const r=row(d.current_level||1);
    const inLeague=r[2]===r[3]?1:(Number(d.current_level||1)-r[2]+1);

    const sub=card.querySelector('.cv61Sub');
    if(sub&&!card.querySelector('.cv65LeagueProgress')){
      sub.insertAdjacentHTML('afterend',`<div class="cv65LeagueProgress">${r[1]} · ${inLeague}/${r[2]===r[3]?1:5}</div>`);
    }

    const next=card.querySelector('.cv61Next');
    if(next&&!next.dataset.cv65){
      next.dataset.cv65='1';
      next.classList.add('cv65Next');
      if(Number(d.current_level||0)>=26){
        next.innerHTML='<strong>LEYENDA</strong><span>Mantén ≥93% para conservar tu rango.</span>';
      }else{
        const nextRank=d.next_rank?.rank_name||d.next_rank?.name||earned.find(x=>x[2]>Number(d.current_level||1))?.[1]||'SIGUIENTE';
        const nextMin=Number(d.next_rank?.min_level||earned.find(x=>x[1]===nextRank)?.[2]||Number(d.current_level||1)+1);
        const remaining=Math.max(1,nextMin-Number(d.current_level||1));
        next.innerHTML=`<strong>PRÓXIMO RANGO · ${String(nextRank)}</strong><span>${remaining} ascenso${remaining===1?'':'s'} restante${remaining===1?'':'s'} · Disciplina ${score(d)}%</span>`;
      }
    }

    const st=card.querySelector('.cv64State');
    if(st)st.classList.add('cv65CompactState');
  }

  async function run(){
    if(running)return;
    running=true;
    try{
      if(!window.CVRankV61)return;
      const d=await window.CVRankV61.load(false);
      decorateHome(d);
    }catch(e){console.warn('CV Rank V65',e)}finally{running=false}
  }
  function schedule(delay=25){clearTimeout(timer);timer=setTimeout(run,delay)}
  document.addEventListener('cv:rendered',()=>schedule(10));
  window.addEventListener('pageshow',()=>schedule(60));
  new MutationObserver(()=>schedule(25)).observe(document.documentElement,{childList:true,subtree:true});
  schedule(90);
})();
