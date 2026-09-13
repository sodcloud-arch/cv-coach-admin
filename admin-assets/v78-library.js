/* CV Coach V78 — Exercise Library Control Center */
(() => {
  const STYLE_ID = 'cv-v78-library-style';
  const statusMeta = {
    active: { label: 'ACTIVO', cls: 'v78-green' },
    ready: { label: 'LISTO', cls: 'v78-blue' },
    staging: { label: 'STAGING', cls: 'v78-gray' },
    missing_image: { label: 'FALTA IMAGEN', cls: 'v78-warn' },
    qa_pending: { label: 'QA PENDIENTE', cls: 'v78-warn' },
    blocked: { label: 'BLOQUEADO', cls: 'v78-red' }
  };

  function ensureStyle() {
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = `
      .v78-head{display:flex;gap:18px;align-items:flex-end;justify-content:space-between;flex-wrap:wrap;margin-bottom:16px}
      .v78-title{font-size:clamp(30px,5vw,54px);line-height:.95;margin:6px 0 8px;letter-spacing:-.03em}
      .v78-sub{color:var(--m);max-width:760px}
      .v78-progress-wrap{min-width:min(420px,100%);flex:1;max-width:520px}
      .v78-progress-label{display:flex;justify-content:space-between;gap:12px;font-size:12px;color:var(--m);margin-bottom:7px}
      .v78-progress{height:9px;border-radius:99px;background:#171a20;overflow:hidden;border:1px solid var(--b)}
      .v78-progress>span{display:block;height:100%;background:linear-gradient(90deg,#ff1c32,#ff344a);box-shadow:0 0 18px rgba(255,28,50,.35)}
      .v78-kpis{display:grid;grid-template-columns:repeat(6,minmax(120px,1fr));gap:10px;margin:16px 0}
      .v78-kpi{background:linear-gradient(180deg,#11151a,#0c0f13);border:1px solid var(--b);border-radius:12px;padding:14px;cursor:pointer;transition:.15s}
      .v78-kpi:hover{border-color:#4a4f58;transform:translateY(-1px)}
      .v78-kpi .v78-n{font-size:28px;font-weight:900;line-height:1}.v78-kpi .v78-l{font-size:11px;color:var(--m);margin-top:6px;text-transform:uppercase;letter-spacing:.08em}
      .v78-toolbar{display:grid;grid-template-columns:minmax(220px,1.5fr) repeat(3,minmax(150px,.7fr));gap:9px;margin:14px 0}
      .v78-table-wrap{overflow:auto;border:1px solid var(--b);border-radius:12px;background:#0b0e12}
      .v78-table{width:100%;border-collapse:collapse;min-width:980px}.v78-table th{font-size:10px;text-transform:uppercase;letter-spacing:.08em;color:#aeb4bf;background:#11151a;padding:11px;text-align:left;position:sticky;top:0;z-index:1}.v78-table td{padding:10px 11px;border-top:1px solid #20242b;vertical-align:middle;font-size:12px}.v78-table tr:hover td{background:#0f1318}
      .v78-thumb{width:94px;height:54px;object-fit:cover;border-radius:7px;border:1px solid #303640;background:#111}.v78-thumb-ph{width:94px;height:54px;border-radius:7px;border:1px dashed #4b3b23;display:grid;place-items:center;color:#ba935d;font-size:10px;background:#15120d}
      .v78-pill{display:inline-flex;align-items:center;justify-content:center;border-radius:999px;padding:5px 8px;font-size:9px;font-weight:800;letter-spacing:.06em;white-space:nowrap;border:1px solid currentColor}.v78-green{color:#55e695;background:#0d261a}.v78-red{color:#ff6777;background:#2a0e13}.v78-warn{color:#ffc56b;background:#2a2010}.v78-blue{color:#75b9ff;background:#102238}.v78-gray{color:#9ca4af;background:#181b20}
      .v78-row-title{font-weight:850;font-size:13px}.v78-muted{color:var(--m);font-size:10px;margin-top:3px}.v78-actions{display:flex;gap:6px;justify-content:flex-end}
      .v78-empty{padding:30px;text-align:center;color:var(--m)}
      .v78-detail-grid{display:grid;grid-template-columns:minmax(270px,.9fr) minmax(300px,1.1fr);gap:14px}.v78-preview{width:100%;aspect-ratio:16/9;object-fit:contain;background:#080a0d;border:1px solid var(--b);border-radius:10px}.v78-checks{display:grid;grid-template-columns:repeat(2,minmax(120px,1fr));gap:7px;margin:10px 0}.v78-check{border:1px solid var(--b);border-radius:8px;padding:8px;font-size:10px}.v78-check.ok{border-color:#245b3c;color:#76e5a5}.v78-check.bad{border-color:#65303a;color:#ff8b98}.v78-exposures{display:flex;gap:6px;flex-wrap:wrap;margin-top:7px}.v78-note{white-space:pre-wrap;padding:10px;border-radius:8px;border:1px solid var(--b);background:#0e1115;color:#c5cad2;font-size:11px}
      .v78-mobile-list{display:none}
      @media(max-width:1050px){.v78-kpis{grid-template-columns:repeat(3,1fr)}.v78-toolbar{grid-template-columns:1fr 1fr}.v78-detail-grid{grid-template-columns:1fr}}
      @media(max-width:720px){.v78-kpis{grid-template-columns:repeat(2,1fr)}.v78-toolbar{grid-template-columns:1fr}.v78-table-wrap{display:none}.v78-mobile-list{display:grid;gap:9px}.v78-mobile-card{border:1px solid var(--b);border-radius:12px;background:#0d1014;padding:11px}.v78-mobile-top{display:flex;gap:10px}.v78-mobile-top .v78-thumb,.v78-mobile-top .v78-thumb-ph{width:112px;height:64px;flex:none}.v78-actions{justify-content:flex-start;margin-top:9px}.v78-checks{grid-template-columns:1fr}}
    `;
    document.head.appendChild(style);
  }

  const clean = v => v == null ? '' : String(v).trim();
  function completeness(x) {
    return [
      ['Nombre', clean(x.name)], ['Slug', clean(x.slug)], ['Músculo', clean(x.primary_muscle)],
      ['Equipo', clean(x.equipment)], ['Patrón', clean(x.movement_pattern)], ['Dificultad', clean(x.difficulty)],
      ['Instrucciones', clean(x.instructions)], ['Tempo', clean(x.default_tempo)],
      ['Descanso', x.default_rest_sec !== null && x.default_rest_sec !== undefined],
      ['Imagen', clean(x.image_path)], ['Unidad', ['reps','seconds'].includes(x.prescription_unit)]
    ].map(([label, value]) => ({ label, ok: !!value }));
  }
  function isComplete(x) { return completeness(x).every(i => i.ok); }
  function stateOf(x, review) {
    const qa = review?.qa_status || 'pending';
    if (qa === 'blocked') return 'blocked';
    if (!clean(x.image_path)) return 'missing_image';
    if (x.active) return 'active';
    if (qa === 'approved' && isComplete(x)) return 'ready';
    if (qa === 'pending') return 'qa_pending';
    return 'staging';
  }
  function sp(state) { const m=statusMeta[state]||statusMeta.staging; return `<span class="v78-pill ${m.cls}">${m.label}</span>`; }
  function qaPill(review) {
    const s=review?.qa_status||'pending';
    return s==='approved'?'<span class="v78-pill v78-green">QA OK</span>':s==='blocked'?'<span class="v78-pill v78-red">QA BLOQ.</span>':'<span class="v78-pill v78-warn">QA PEND.</span>';
  }
  function imgHtml(x) {
    if (!clean(x.image_path)) return '<div class="v78-thumb-ph">SIN IMAGEN</div>';
    return `<img class="v78-thumb" src="${esc(x.image_path)}" loading="lazy" referrerpolicy="no-referrer" onerror="this.outerHTML='<div class=&quot;v78-thumb-ph&quot;>ERROR IMAGEN</div>'">`;
  }
  function kpi(label, n, filter, accent='') { return `<button class="v78-kpi v78-filter-kpi" data-filter="${filter}" type="button" ${accent?`style="border-color:${accent}"`:''}><div class="v78-n">${n}</div><div class="v78-l">${esc(label)}</div></button>`; }

  async function action(exercise, actionName, note) {
    const payload = { p_actor_id: me.id, p_exercise_id: exercise.id, p_action: actionName, p_note: note || null };
    return req('/rest/v1/rpc/manage_exercise_library_backend', { method:'POST', body:JSON.stringify(payload) });
  }

  function openDetail(x, review, exposures) {
    const checks=completeness(x), state=stateOf(x,review), staffAdmin=me?.role==='admin';
    const exposureHtml=exposures.length?exposures.map(e=>`<span class="v78-pill v78-blue">${esc(e.constraint_code)} · ${esc(e.exposure_level)}</span>`).join(''):'<span class="v78-muted">Sin exposiciones mecánicas registradas.</span>';
    const preview=clean(x.image_path)?`<img class="v78-preview" src="${esc(x.image_path)}" referrerpolicy="no-referrer">`:'<div class="v78-preview" style="display:grid;place-items:center;color:#a98754">IMAGEN PENDIENTE</div>';
    $('#modal').innerHTML=`<div class="modal"><div class="card" style="width:min(96vw,1100px);max-height:92vh;overflow:auto"><div class="row"><div class="grow"><div class="ey">V78 · EXERCISE LIBRARY CONTROL CENTER</div><h2 style="margin:4px 0">${esc(x.name)}</h2><div class="row" style="flex-wrap:wrap">${sp(state)} ${qaPill(review)} <span class="v78-pill v78-gray">${esc(x.slug)}</span></div></div><button id="v78Close" class="btn small">✕</button></div><div class="v78-detail-grid" style="margin-top:14px"><div>${preview}<div class="card" style="margin-top:10px"><b>Técnica</b><div class="muted" style="margin-top:7px">${esc(x.instructions||'Sin instrucciones')}</div></div><div class="card" style="margin-top:10px"><b>Exposiciones mecánicas</b><div class="v78-exposures">${exposureHtml}</div></div></div><div><div class="metrics nutritionMetrics"><div class="metric"><span>Músculo</span><b>${esc(x.primary_muscle||'—')}</b></div><div class="metric"><span>Equipo</span><b>${esc(x.equipment||'—')}</b></div><div class="metric"><span>Patrón</span><b>${esc(x.movement_pattern||'—')}</b></div><div class="metric"><span>Dificultad</span><b>${esc(x.difficulty||'—')}</b></div><div class="metric"><span>Tempo</span><b>${esc(x.default_tempo||'—')}</b></div><div class="metric"><span>Descanso</span><b>${x.default_rest_sec==null?'—':esc(x.default_rest_sec+' s')}</b></div></div><h3 style="margin:14px 0 6px">Checklist de publicación</h3><div class="v78-checks">${checks.map(c=>`<div class="v78-check ${c.ok?'ok':'bad'}">${c.ok?'✓':'✕'} ${esc(c.label)}</div>`).join('')}</div><div class="card"><b>Revisión QA</b><div style="margin-top:8px">${qaPill(review)}</div>${review?.qa_notes?`<div class="v78-note" style="margin-top:8px">${esc(review.qa_notes)}</div>`:''}${review?.reviewed_at?`<div class="v78-muted">Revisado: ${esc(new Date(review.reviewed_at).toLocaleString('es-CL'))}</div>`:''}</div>${staffAdmin?`<label style="display:block;margin-top:12px">Nota QA</label><textarea id="v78QaNote" class="input" rows="3" maxlength="1000" placeholder="Nota para aprobación o motivo de bloqueo…">${esc(review?.qa_notes||'')}</textarea><div class="row" style="flex-wrap:wrap;margin-top:8px"><button class="btn good small v78Act" data-action="approve_qa">APROBAR QA</button><button class="btn small v78Act" data-action="block">BLOQUEAR</button>${review?.qa_status==='approved'&&!x.active?'<button class="btn primary small v78Act" data-action="activate">ACTIVAR</button>':''}${x.active?'<button class="btn small v78Act" data-action="deactivate">DESACTIVAR</button>':''}${review?.qa_status!=='pending'?'<button class="btn small v78Act" data-action="reset_qa">REABRIR QA</button>':''}</div><div id="v78ActionStatus" class="status muted"></div><div class="muted" style="margin-top:8px">Activar solo cambia la disponibilidad del catálogo. No modifica rutinas publicadas. Desactivar se bloquea si el ejercicio está usado por un programa activo o borrador.</div>`:'<div class="card muted" style="margin-top:12px">Modo de revisión. Las acciones de estado requieren rol administrador.</div>'}</div></div></div></div>`;
    $('#v78Close').onclick=()=>$('#modal').innerHTML='';
    $$('.v78Act').forEach(b=>b.onclick=async()=>{
      const out=$('#v78ActionStatus'), note=$('#v78QaNote')?.value.trim()||'';
      const a=b.dataset.action;
      if(a==='block'&&!note){out.textContent='Para bloquear debes indicar el motivo.';return;}
      if((a==='deactivate'||a==='reset_qa')&&!confirm('¿Confirmas esta acción? El ejercicio dejará de estar disponible para nuevas selecciones si corresponde.'))return;
      try{ $$('.v78Act').forEach(x=>x.disabled=true); out.textContent='Guardando…'; await action(x,a,note); $('#modal').innerHTML=''; cache={}; toast('Estado del ejercicio actualizado.'); await window.library(); }
      catch(e){ out.textContent='No se pudo actualizar: '+String(e?.message||e); $$('.v78Act').forEach(x=>x.disabled=false); }
    });
  }

  window.library = async function libraryV78(){
    ensureStyle();
    try{
      const [all,reviews,exposures]=await Promise.all([
        table('exercises','select=*&order=name'),
        table('exercise_library_reviews','select=*'),
        table('exercise_mechanical_exposures','select=exercise_id,constraint_code,exposure_level,note').catch(()=>[])
      ]);
      const rmap=new Map((reviews||[]).map(r=>[r.exercise_id,r]));
      const emap=new Map();
      (exposures||[]).forEach(e=>{if(!emap.has(e.exercise_id))emap.set(e.exercise_id,[]);emap.get(e.exercise_id).push(e)});
      const rows=(all||[]).map(x=>({x,review:rmap.get(x.id)||{qa_status:'pending'},state:stateOf(x,rmap.get(x.id))}));
      const counts={total:rows.length,active:rows.filter(r=>r.x.active).length,staging:rows.filter(r=>!r.x.active).length,approved:rows.filter(r=>r.review.qa_status==='approved').length,pending:rows.filter(r=>r.review.qa_status==='pending').length,blocked:rows.filter(r=>r.review.qa_status==='blocked').length,missing:rows.filter(r=>!clean(r.x.image_path)).length};
      const reviewed=counts.approved+counts.blocked, progress=counts.total?Math.round(reviewed/counts.total*100):0;
      const muscles=[...new Set(rows.map(r=>r.x.primary_muscle).filter(Boolean))].sort((a,b)=>a.localeCompare(b,'es'));
      const equipments=[...new Set(rows.map(r=>r.x.equipment).filter(Boolean))].sort((a,b)=>a.localeCompare(b,'es'));
      $('#content').innerHTML=`<div class="v78-head"><div><div class="ey">BIBLIOTECA DE EJERCICIOS · V78</div><h1 class="v78-title">Exercise Library<br>Control Center</h1><div class="v78-sub">Catálogo vivo, control de QA y activación segura. Programación continúa usando exclusivamente ejercicios activos.</div></div><div class="v78-progress-wrap"><div class="v78-progress-label"><span>QA REVISADO</span><b>${progress}% · ${reviewed}/${counts.total}</b></div><div class="v78-progress"><span style="width:${progress}%"></span></div><div class="v78-muted" style="margin-top:7px">${counts.pending} pendientes · ${counts.blocked} bloqueados · ${counts.missing} sin imagen</div></div></div><div class="v78-kpis">${kpi('Total catálogo',counts.total,'all')}${kpi('Activos',counts.active,'active','#245b3c')}${kpi('Staging',counts.staging,'staging')}${kpi('QA pendiente',counts.pending,'qa_pending','#62451f')}${kpi('Bloqueados',counts.blocked,'blocked','#64202b')}${kpi('Falta imagen',counts.missing,'missing_image','#62451f')}</div><div class="v78-toolbar"><input id="v78Q" class="input" placeholder="Buscar por ejercicio, músculo, equipo o slug…"><select id="v78Mus" class="input"><option value="">Todos los músculos</option>${muscles.map(v=>`<option value="${esc(v)}">${esc(v)}</option>`).join('')}</select><select id="v78Eq" class="input"><option value="">Todo el equipamiento</option>${equipments.map(v=>`<option value="${esc(v)}">${esc(v)}</option>`).join('')}</select><select id="v78State" class="input"><option value="all">Todos los estados</option><option value="active">Activos</option><option value="ready">Listos para activar</option><option value="staging">Staging</option><option value="qa_pending">QA pendiente</option><option value="blocked">Bloqueados</option><option value="missing_image">Falta imagen</option></select></div><div class="v78-table-wrap"><table class="v78-table"><thead><tr><th>Imagen</th><th>Ejercicio</th><th>Músculo / Equipo</th><th>Patrón</th><th>Estado</th><th>QA</th><th>Ficha</th><th></th></tr></thead><tbody id="v78Rows"></tbody></table></div><div id="v78Mobile" class="v78-mobile-list"></div><div id="v78Result" class="muted" style="margin-top:9px"></div>`;
      let stateFilter='all';
      const draw=()=>{
        const q=$('#v78Q').value.toLowerCase().trim(), m=$('#v78Mus').value, e=$('#v78Eq').value, s=$('#v78State').value;
        const filtered=rows.filter(r=>{const x=r.x, hay=`${x.name||''} ${x.slug||''} ${x.primary_muscle||''} ${x.equipment||''} ${x.movement_pattern||''}`.toLowerCase();const stateMatch=s==='all'||r.state===s||(s==='staging'&&!x.active);return (!q||hay.includes(q))&&(!m||x.primary_muscle===m)&&(!e||x.equipment===e)&&stateMatch});
        $('#v78Rows').innerHTML=filtered.map(r=>{const x=r.x, comp=isComplete(x);return `<tr><td>${imgHtml(x)}</td><td><div class="v78-row-title">${esc(x.name)}</div><div class="v78-muted">${esc(x.slug)}</div></td><td><b>${esc(x.primary_muscle||'—')}</b><div class="v78-muted">${esc(x.equipment||'—')}</div></td><td>${esc(x.movement_pattern||'—')}<div class="v78-muted">${esc(x.difficulty||'—')}</div></td><td>${sp(r.state)}</td><td>${qaPill(r.review)}</td><td>${comp?'<span class="v78-pill v78-green">COMPLETA</span>':'<span class="v78-pill v78-warn">INCOMPLETA</span>'}</td><td><button class="btn small v78Open" data-id="${esc(x.id)}">REVISAR</button></td></tr>`}).join('')||'<tr><td colspan="8" class="v78-empty">No hay ejercicios con estos filtros.</td></tr>';
        $('#v78Mobile').innerHTML=filtered.map(r=>{const x=r.x;return `<div class="v78-mobile-card"><div class="v78-mobile-top">${imgHtml(x)}<div><div class="v78-row-title">${esc(x.name)}</div><div class="v78-muted">${esc(x.primary_muscle||'—')} · ${esc(x.equipment||'—')}</div><div style="margin-top:7px">${sp(r.state)} ${qaPill(r.review)}</div></div></div><div class="v78-actions"><button class="btn small v78Open" data-id="${esc(x.id)}">REVISAR</button></div></div>`}).join('')||'<div class="v78-empty">No hay ejercicios con estos filtros.</div>';
        $('#v78Result').textContent=`Mostrando ${filtered.length} de ${rows.length} ejercicios.`;
        $$('.v78Open').forEach(b=>b.onclick=()=>{const r=rows.find(y=>y.x.id===b.dataset.id);if(r)openDetail(r.x,r.review,emap.get(r.x.id)||[])});
      };
      ['v78Q','v78Mus','v78Eq','v78State'].forEach(id=>$('#'+id).oninput=draw);
      $$('.v78-filter-kpi').forEach(b=>b.onclick=()=>{const f=b.dataset.filter;$('#v78State').value=f==='all'?'all':f;draw();});
      draw();
    }catch(e){
      $('#content').innerHTML=`<div class="card" style="border-color:#64202b"><b>No se pudo abrir Exercise Library Control Center</b><div class="muted" style="margin-top:8px">${esc(String(e?.message||e))}</div></div>`;
    }
  };
})();
