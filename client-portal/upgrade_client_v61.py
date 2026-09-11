from pathlib import Path
import hashlib,json,re
ROOT=Path(__file__).resolve().parent
HTML=ROOT/'stable'/'index.html';BUILD=ROOT/'stable'/'build.json'
MARKER='<!-- cv-rank-engine-v61: tutorial-empty + 5-level leagues + legend + global-ranking + challenges -->'
V63='<!-- cv-rank-real-ui-v63: approved-transparent-badges + premium-home + rank-state + challenge-teaser -->'
CSS=r'''<style id="cv-rank-real-ui-v63-css">
.cv61TutorialBadge{background:transparent!important;clip-path:none!important;padding:0!important;filter:drop-shadow(0 0 14px rgba(160,180,190,.18))!important;background-image:url('./assets/ranks/cv-rank-tutorial-v61.webp')!important;background-position:center!important;background-repeat:no-repeat!important;background-size:contain!important}
.cv61TutorialBadge:after{display:none!important}.cv61EmptyPath{opacity:.72!important}
.cv61RankCard.cv63Real{grid-template-columns:112px minmax(0,1fr);padding:18px;gap:16px;border-radius:22px;background:radial-gradient(circle at 12% 18%,color-mix(in srgb,var(--r) 19%,transparent),transparent 33%),linear-gradient(145deg,#0c1115,#030507 78%);box-shadow:0 22px 60px rgba(0,0,0,.48),inset 0 0 42px color-mix(in srgb,var(--r) 5%,transparent)}
.cv61RankCard.cv63Real .cv61Badge img{width:108px;filter:drop-shadow(0 0 calc(10px + var(--cv63-aura,8px)) color-mix(in srgb,var(--r) 56%,transparent))}.cv61RankCard.cv63Real .cv61Title{font-size:30px}.cv61RankCard.cv63Real .cv61Sub{font-size:11px}.cv61RankCard.cv63Real .cv61Open{margin-top:2px}
.cv63LevelPips{display:flex;justify-content:center;gap:4px;margin-top:5px}.cv63LevelPips i{width:5px;height:5px;border-radius:50%;border:1px solid color-mix(in srgb,var(--r) 60%,#27323a);background:#11181c}.cv63LevelPips i.on{background:var(--r);box-shadow:0 0 7px color-mix(in srgb,var(--r) 70%,transparent)}
.cv63State{display:flex;align-items:center;justify-content:space-between;gap:8px;margin-top:10px;padding:8px 10px;border:1px solid color-mix(in srgb,var(--state,#45d79a) 42%,#27343b);border-radius:10px;background:color-mix(in srgb,var(--state,#45d79a) 8%,#071014);font-size:8px}.cv63State strong{color:var(--state,#45d79a);letter-spacing:.06em}.cv63State span{color:#8e9ba2;text-align:right}
.cv63CompactPath{grid-column:1/-1;display:grid;grid-template-columns:repeat(7,1fr);gap:4px;margin-top:3px;padding:8px 5px;border:1px solid #26333b;border-radius:12px;background:#05090c}.cv63Step{text-align:center;color:#67747c;font-size:6px;min-width:0}.cv63Step img{display:block;width:42px;height:42px;object-fit:contain;margin:auto;filter:saturate(.15) brightness(.45)}.cv63Step.reached img,.cv63Step.current img{filter:none}.cv63Step.current{color:#fff}.cv63Step.current img{filter:drop-shadow(0 0 8px color-mix(in srgb,var(--r) 65%,transparent))}.cv63Step b{display:block;margin-top:2px;font-size:6px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.cv63Step.current b{color:var(--r)}
.cv63ChallengeTeaser{margin:0 0 14px;padding:13px 14px;border:1px solid rgba(255,48,71,.48);border-radius:15px;background:radial-gradient(circle at 4% 50%,rgba(255,48,71,.15),transparent 36%),linear-gradient(145deg,#0c1216,#06090b);cursor:pointer}.cv63ChallengeTeaser .row{display:flex;align-items:center;gap:10px}.cv63ChallengeTeaser .ico{font-size:25px}.cv63ChallengeTeaser .grow{min-width:0;flex:1}.cv63ChallengeTeaser small{display:block;color:#ff6f80;font-size:7px;font-weight:900;letter-spacing:.13em}.cv63ChallengeTeaser b{display:block;margin-top:2px;font:850 18px 'Barlow Condensed';white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.cv63ChallengeTeaser em{font-style:normal;color:#8f9ba2;font-size:8px}.cv63ChallengeTeaser .go{color:#fff;font-size:20px}
.cv63EvoState{margin:13px 0 2px;padding:12px;border:1px solid color-mix(in srgb,var(--state,#45d79a) 44%,#29353d);border-radius:13px;background:color-mix(in srgb,var(--state,#45d79a) 7%,#071014)}.cv63EvoState small{display:block;color:#7f8c94;font-size:7px;text-transform:uppercase;letter-spacing:.1em}.cv63EvoState b{display:block;margin-top:4px;color:var(--state,#45d79a);font-size:23px}.cv63EvoState p{margin:4px 0 0;color:#9aa6ad;font-size:9px;line-height:1.4}
.cv61Feedback.cv63RankChanged{width:min(470px,100%);overflow:hidden}.cv63Transition{display:grid;grid-template-columns:1fr auto 1fr;align-items:center;gap:9px;margin:8px 0 4px}.cv63Transition .cv61Badge img{width:118px}.cv63Transition .arrow{font-size:30px;color:#fff;opacity:.82}
@media(max-width:390px){.cv61RankCard.cv63Real{grid-template-columns:86px minmax(0,1fr);padding:14px;gap:11px}.cv61RankCard.cv63Real .cv61Badge img{width:84px}.cv61RankCard.cv63Real .cv61Title{font-size:23px}.cv63Step img{width:34px;height:34px}.cv63Step b{font-size:5.5px}.cv63CompactPath{gap:2px;padding:7px 3px}}
</style>'''
JS=r'''<script id="cv-rank-real-ui-v63-js">
(function(){
 if(window.CVRankRealUIV63)return;window.CVRankRealUIV63=true;
 const earned=[['bronze','BRONCE',1,5],['silver','PLATA',6,10],['gold','ORO',11,15],['platinum','PLATINO',16,20],['diamond','DIAMANTE',21,25],['legend','LEYENDA',26,26]];
 const maintain={bronze:55,silver:60,gold:70,platinum:78,diamond:86,legend:93};
 const progress={bronze:70,silver:75,gold:82,platinum:87,diamond:92,legend:96};
 const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const row=l=>earned.find(r=>l>=r[2]&&l<=r[3])||earned[0];
 const asset=k=>`./assets/ranks/cv-rank-${k}-v61.webp`;
 function state(d){if(!d?.tutorial_completed)return {t:'INICIACIÓN',m:'Completa el tutorial para ganar Bronce.',c:'#a5b1b8'};const r=d.rank?.rank_key||row(+d.current_level)[0],s=+(d.discipline_preview?.discipline_score||d.last_discipline_score||0),mn=maintain[r]||55,pg=progress[r]||70;if(s<mn)return {t:'EN RIESGO',m:`Necesitas ${mn}% para proteger tu rango.`,c:'#ff4054'};if(s>=pg)return {t:'EN PROGRESO',m:`Superas el ${pg}% requerido para avanzar.`,c:'#48db9b'};return {t:'RANGO SEGURO',m:`Mantienes el mínimo de ${mn}% esta semana.`,c:'#42bfff'}}
 function inLeague(d){if(!d?.tutorial_completed)return 0;const r=row(+d.current_level);return r[2]===r[3]?1:(+d.current_level-r[2]+1)}
 function path(d){const lvl=+d?.current_level||0,cur=d?.rank?.rank_key||row(Math.max(1,lvl))[0],tutorial=`<div class="cv63Step ${!d?.tutorial_completed?'current':'reached'}"><img src="${asset('tutorial')}" alt="Tutorial"><b>Tutorial</b></div>`;return `<div class="cv63CompactPath">${tutorial}${earned.map(r=>{const reached=d?.tutorial_completed&&lvl>=r[2],current=d?.tutorial_completed&&cur===r[0];return `<div class="cv63Step ${reached?'reached':''} ${current?'current':''}"><img src="${asset(r[0])}" alt="${r[1]}"><b>${r[1]}</b></div>`}).join('')}</div>`}
 function pips(d){if(!d?.tutorial_completed||+d.current_level===26)return '';const n=inLeague(d);return `<div class="cv63LevelPips">${[1,2,3,4,5].map(i=>`<i class="${i<=n?'on':''}"></i>`).join('')}</div>`}
 async function challenge(){try{if(typeof mode==='undefined'||mode!=='real'||typeof sb==='undefined'||typeof user==='undefined'||!user?.id)return null;const q=await sb.rpc('get_client_challenges_v61',{p_actor_id:user.id,p_client_id:user.id});if(q.error)return null;return (q.data?.rows||[]).find(x=>x.status==='active')||null}catch(_){return null}}
 async function home(d){const c=document.getElementById('content');if(!c||String(document.body.dataset.cvView||'home')!=='home')return;const card=c.querySelector('.cv61RankCard');if(card&&!card.classList.contains('cv63Real')){card.classList.add('cv63Real');const b=card.querySelector('.cv61Badge');if(b){b.style.setProperty('--cv63-aura',`${5+inLeague(d)*3}px`);b.insertAdjacentHTML('beforeend',pips(d))}const st=state(d);const meta=card.querySelector('.cv61Next');if(meta&&!card.querySelector('.cv63State'))meta.insertAdjacentHTML('afterend',`<div class="cv63State" style="--state:${st.c}"><strong>${st.t}</strong><span>${st.m}</span></div>`);const open=card.querySelector('.cv61Open');if(open&&!card.querySelector('.cv63CompactPath'))open.insertAdjacentHTML('beforebegin',path(d))}
 if(d?.tutorial_completed&&!c.querySelector('.cv63ChallengeTeaser')){const ch=await challenge();if(ch){const target=c.querySelector('.cv61MiniStats');if(target)target.insertAdjacentHTML('afterend',`<div class="cv63ChallengeTeaser" role="button" tabindex="0"><div class="row"><div class="ico">🎯</div><div class="grow"><small>DESAFÍO ACTIVO</small><b>${esc(ch.name||'Competencia CV')}</b><em>${esc(ch.reward_title||'Revisa tus requisitos y sigue avanzando.')}</em></div><div class="go">›</div></div></div>`);const x=c.querySelector('.cv63ChallengeTeaser');if(x){const go=()=>window.CVRankV61?.open?.('challenges');x.onclick=go;x.onkeydown=e=>{if(e.key==='Enter'||e.key===' ')go()}}}}}
 }
 function modal(d){const sheet=document.querySelector('.cv61Sheet');if(!sheet)return;const body=sheet.querySelector('.cv61Body');if(!body||body.querySelector('.cv63EvoState'))return;const active=sheet.querySelector('[data-tab].active')?.dataset.tab;if(active!=='evolution')return;const st=state(d),hero=body.querySelector('.cv61Hero');if(hero){hero.insertAdjacentHTML('afterend',`<div class="cv63EvoState" style="--state:${st.c}"><small>ESTADO DEL RANGO</small><b>${st.t}</b><p>${st.m}</p></div>${path(d)}`)}}
 async function run(){try{if(!window.CVRankV61)return;const d=await window.CVRankV61.load(false);await home(d);modal(d)}catch(e){console.warn('CV Rank real UI V63',e)}}
 document.addEventListener('cv:rendered',()=>setTimeout(run,20));window.addEventListener('pageshow',()=>setTimeout(run,80));
 new MutationObserver(()=>setTimeout(run,20)).observe(document.documentElement,{childList:true,subtree:true});setTimeout(run,120);
})();
</script>'''
text=HTML.read_text(encoding='utf-8')
text=re.sub(r'<style id="cv-rank-system-v60-css">.*?</style>','',text,flags=re.S)
text=re.sub(r'<script id="cv-rank-system-v60-js">.*?</script>','',text,flags=re.S)
text=re.sub(r'<style id="cv-rank-real-ui-v63-css">.*?</style>','',text,flags=re.S)
text=re.sub(r'<script id="cv-rank-real-ui-v63-js">.*?</script>','',text,flags=re.S)
text=text.replace(V63,'')
if MARKER not in text:
    for prerequisite in ['cv-rank-system-v60','cv-client-e2e-v58','cv-coach-client-loop-v59']:
        if prerequisite not in text: raise SystemExit(f'CV Rank V61 prerequisite missing: {prerequisite}')
    if '</head>' not in text or '</body>' not in text: raise SystemExit('CV Rank V61 HTML anchors missing')
    text=text.replace('</head>','<link rel="stylesheet" href="./assets/cv-rank-v61.css">\n</head>',1)
    text=text.replace('</body>','<script src="./assets/cv-rank-v61.js"></script>\n'+MARKER+'\n</body>',1)
if '</head>' not in text or '</body>' not in text: raise SystemExit('CV Rank V63 HTML anchors missing')
text=text.replace('</head>',CSS+'\n</head>',1)
text=text.replace('</body>',JS+'\n'+V63+'\n</body>',1)
required=[MARKER,'./assets/cv-rank-v61.css','./assets/cv-rank-v61.js',V63,'cv-rank-tutorial-v61.webp','cv63CompactPath']
for item in required:
    if item not in text: raise SystemExit(f'CV Rank contract missing: {item}')
if 'cv-rank-system-v60-js' in text or 'cv-rank-system-v60-css' in text: raise SystemExit('CV Rank V61 failed to retire active V60 runtime')
HTML.write_text(text,encoding='utf-8')
sha=hashlib.sha256(text.encode()).hexdigest();meta={}
if BUILD.exists():
    try: meta=json.loads(BUILD.read_text(encoding='utf-8'))
    except Exception: meta={}
meta['bytes']=len(text.encode());meta['sha256']=sha
patches=list(meta.get('patches') or [])
for patch in ['CV Rank Engine v61','Tutorial empty badge slot v61','5-level leagues + Legend v61','Global/league/season ranking UI v61','Challenges + Trophy Room client UI v61','Approved transparent rank badge assets v63','Premium real rank UI v63']:
    if patch not in patches: patches.append(patch)
meta['patches']=patches;BUILD.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'sha256':sha,'bytes':meta['bytes'],'patches':patches[-7:]},ensure_ascii=False))
