/* CV Coach V92 — CV12 Migrations & Operations Admin */
(() => {
  const STYLE_ID = 'cv-v92-cutover-style';
  const VIEW = 'cv12';
  const resolved = new Map();

  const clean = value => value == null ? '' : String(value).trim();
  const fmtDate = value => {
    if (!value) return '—';
    const d = new Date(value);
    return Number.isNaN(d.getTime()) ? '—' : d.toLocaleString('es-CL');
  };
  const shortId = value => clean(value) ? clean(value).slice(0, 8) + '…' : '—';
  const bool = value => value === true;

  function ensureStyle() {
    if (document.getElementById(STYLE_ID)) return;
    const style = document.createElement('style');
    style.id = STYLE_ID;
    style.textContent = `
      .v92-head{display:flex;gap:16px;align-items:flex-end;justify-content:space-between;flex-wrap:wrap;margin-bottom:16px}
      .v92-title{font-size:clamp(30px,5vw,52px);line-height:.95;margin:6px 0 8px;letter-spacing:-.03em}
      .v92-sub{color:var(--m);max-width:780px;line-height:1.5}
      .v92-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}
      .v92-card{background:linear-gradient(180deg,#15191d,#0e1114);border:1px solid var(--b);border-radius:15px;padding:16px}
      .v92-card.ready{border-color:#245b3c}.v92-card.blocked{border-color:#62451f}.v92-card.linked{border-color:#274a73}
      .v92-kpis{display:grid;grid-template-columns:repeat(5,minmax(105px,1fr));gap:8px;margin:12px 0}
      .v92-kpi{background:#0c0f12;border:1px solid var(--b);border-radius:11px;padding:11px}.v92-kpi b{display:block;font-size:22px}.v92-kpi span{font-size:9px;color:var(--m);text-transform:uppercase;letter-spacing:.07em}
      .v92-pill{display:inline-flex;align-items:center;border:1px solid currentColor;border-radius:999px;padding:5px 8px;font-size:9px;font-weight:900;letter-spacing:.05em;text-transform:uppercase}.v92-green{color:#7de6a6;background:#0d261a}.v92-warn{color:#ffc480;background:#2a2010}.v92-red{color:#ff8f9d;background:#2a0e13}.v92-blue{color:#9cc4ff;background:#102238}.v92-gray{color:#aab0b8;background:#181b20}
      .v92-status-line{display:flex;gap:7px;flex-wrap:wrap;margin:10px 0}.v92-meta{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px;margin:12px 0}.v92-meta>div{background:#0c0f12;border:1px solid var(--b);border-radius:10px;padding:10px}.v92-meta span{display:block;color:var(--m);font-size:9px;text-transform:uppercase}.v92-meta b{font-size:12px;word-break:break-word}
      .v92-warnings{display:grid;gap:7px;margin:10px 0}.v92-warning{border:1px solid #62451f;background:#21180d;color:#ffc480;border-radius:9px;padding:9px;font-size:11px}.v92-ok{border:1px solid #245b3c;background:#0d2016;color:#8be7ae;border-radius:9px;padding:9px;font-size:11px}
      .v92-resolver{margin-top:14px;border-top:1px solid var(--b);padding-top:14px}.v92-resolver-row{display:grid;grid-template-columns:minmax(180px,1fr) auto;gap:8px}.v92-result{margin-top:9px}.v92-actions{display:flex;gap:7px;flex-wrap:wrap;margin-top:10px}.v92-danger{border-color:#64202b!important;background:#271014!important;color:#ff9cab!important}
      .v92-audit{margin-top:16px}.v92-audit-row{display:grid;grid-template-columns:110px 1fr 160px;gap:10px;padding:10px 0;border-top:1px solid var(--b);font-size:11px}.v92-audit-row:first-child{border-top:0}.v92-audit-action{font-weight:900}.v92-empty{padding:20px;text-align:center;color:var(--m)}
      .v92-modal-copy{background:#0c0f12;border:1px solid var(--b);border-radius:10px;padding:10px;margin:10px 0;font-size:12px;line-height:1.5}.v92-confirm{font-weight:900;color:#fff}
      @media(max-width:1050px){.v92-grid{grid-template-columns:1fr}.v92-kpis{grid-template-columns:repeat(3,1fr)}}
      @media(max-width:720px){.v92-kpis{grid-template-columns:repeat(2,1fr)}.v92-meta{grid-template-columns:1fr}.v92-resolver-row{grid-template-columns:1fr}.v92-audit-row{grid-template-columns:1fr;gap:3px}.v92-actions .btn{flex:1}}
    `;
    document.head.appendChild(style);
  }

  function pill(label, cls) {
    return `<span class="v92-pill ${cls}">${esc(label)}</span>`;
  }

  async function rpc(name, payload = {}) {
    return req('/rest/v1/rpc/' + name, {
      method: 'POST',
      body: JSON.stringify(payload)
    });
  }

  function readiness(item) {
    const r = item?.readiness?.readiness || {};
    const legacy = item?.readiness?.legacy_history || {};
    const identity = item?.readiness?.native_identity || {};
    return { r, legacy, identity };
  }

  function warningHtml(item) {
    const w = item?.readiness?.warnings || {};
    const rows = [];
    if (Number(w.unresolved_exercise_mappings || 0) > 0) {
      rows.push(`${Number(w.unresolved_exercise_mappings)} ejercicios históricos permanecen sin equivalencia canónica segura. No bloquean el acceso.`);
    }
    if (w.baseline_insufficient_for_longitudinal_ai === true) {
      rows.push('La IA longitudinal sigue en recopilación de baseline. Esto no bloquea el cutover de cuenta.');
    }
    return rows.length
      ? `<div class="v92-warnings">${rows.map(x => `<div class="v92-warning">⚠ ${esc(x)}</div>`).join('')}</div>`
      : '<div class="v92-ok">✓ Sin advertencias operativas.</div>';
  }

  function resolverResultHtml(pilot) {
    const x = resolved.get(pilot.pilot_id);
    if (!x) return '';
    if (x.error) return `<div class="v92-warning">${esc(x.error)}</div>`;
    if (x.resolution === 'identity_not_found') {
      return `<div class="v92-result"><div class="v92-warning">No existe una identidad cliente real para <b>${esc(x.email)}</b>. Debe provisionarse mediante el flujo oficial de Clientes antes del cutover.</div><div class="v92-actions"><button class="btn small v92CreateClient" data-pilot="${esc(pilot.pilot_id)}">+ CREAR CLIENTE</button></div></div>`;
    }
    if (x.resolution === 'identity_found') {
      const ready = x.ready_for_v90 === true;
      return `<div class="v92-result"><div class="${ready ? 'v92-ok' : 'v92-warning'}"><b>${esc(x.client_name || 'Cliente')}</b> · ${esc(x.email || '')}<br>Perfil: ${esc(x.profile_status || '—')} · Onboarding: ${esc(x.onboarding_status || '—')} · Relación coach: ${esc(x.coach_relationship_status || '—')}</div>${ready ? `<div class="v92-actions"><button class="btn primary small v92Execute" data-pilot="${esc(pilot.pilot_id)}">EJECUTAR CUTOVER V90</button></div>` : ''}</div>`;
    }
    return `<div class="v92-warning">Respuesta de resolución no reconocida.</div>`;
  }

  function pilotCard(item) {
    const { r, legacy, identity } = readiness(item);
    const technical = bool(r.technical_ready_for_native_identity);
    const linked = !!item.client_id && !!item.linked_at;
    const cutoverReady = bool(r.ready_for_real_cutover);
    const aiReady = bool(r.longitudinal_ai_ready);
    const cls = linked ? 'linked' : technical ? 'ready' : 'blocked';
    const nextLabel = {
      provide_real_client_email: 'Falta correo real',
      execute_v90: 'Listo para V90',
      linked: 'Vinculado'
    }[item.next_action] || item.next_action || 'Revisar';

    return `<article class="v92-card ${cls}" data-pilot-card="${esc(item.pilot_id)}">
      <div class="row"><div class="grow"><div class="ey">CV12 · ${esc(item.source_system || 'legacy')}</div><h2 style="margin:4px 0 2px">${esc(item.subject_label || 'Piloto')}</h2><div class="muted">Piloto ${esc(shortId(item.pilot_id))}</div></div>${linked ? pill('Vinculado','v92-blue') : technical ? pill('Técnicamente listo','v92-green') : pill('Bloqueado','v92-warn')}</div>
      <div class="v92-status-line">${pill(nextLabel, linked ? 'v92-blue' : technical ? 'v92-green' : 'v92-warn')} ${aiReady ? pill('IA longitudinal lista','v92-green') : pill('IA recopilando baseline','v92-gray')}</div>
      <div class="v92-kpis">
        <div class="v92-kpi"><span>Sesiones legacy</span><b>${Number(legacy.sessions || 0)}</b></div>
        <div class="v92-kpi"><span>Logs ejercicio</span><b>${Number(legacy.exercise_logs || 0)}</b></div>
        <div class="v92-kpi"><span>Mapeados</span><b>${Number(legacy.linked_exercise_logs || 0)}</b></div>
        <div class="v92-kpi"><span>Sin mapear</span><b>${Number(legacy.unresolved_exercise_logs || 0)}</b></div>
        <div class="v92-kpi"><span>Evidencia repetida</span><b>${Number(r.evidence_exercises || 0)}</b></div>
      </div>
      <div class="v92-meta">
        <div><span>Modo</span><b>${esc(item.mode || '—')}</b></div>
        <div><span>Sync</span><b>${esc(item.readiness?.sync_state || '—')}</b></div>
        <div><span>Identidad nativa</span><b>${identity.client_id ? esc(shortId(identity.client_id)) : 'Pendiente'}</b></div>
        <div><span>Vinculado</span><b>${fmtDate(item.linked_at)}</b></div>
      </div>
      ${warningHtml(item)}
      ${linked ? `<div class="v92-actions"><button class="btn small v92Rollback v92-danger" data-pilot="${esc(item.pilot_id)}" data-client="${esc(item.client_id)}">ROLLBACK / DESVINCULAR</button></div>` : `<div class="v92-resolver"><b>Resolver identidad real</b><div class="muted" style="margin:4px 0 8px">Solo valida. No crea ni vincula nada automáticamente.</div><div class="v92-resolver-row"><input class="input v92Email" data-pilot="${esc(item.pilot_id)}" type="email" placeholder="correo.real@cliente.com" style="margin:0"><button class="btn small v92Resolve" data-pilot="${esc(item.pilot_id)}">VALIDAR IDENTIDAD</button></div>${resolverResultHtml(item)}</div>`}
      <div class="muted" style="margin-top:12px">Guardrails: historial legacy preservado · auto-publicación OFF · autoedición OFF · identidad sintética prohibida.</div>
    </article>`;
  }

  function auditHtml(audit, itemsByPilot) {
    const rows = Array.isArray(audit?.items) ? audit.items : [];
    return `<section class="v92-card v92-audit"><div class="row"><div class="grow"><div class="ey">AUDITORÍA V90</div><h2 style="margin:4px 0">Operaciones de cutover</h2></div>${pill(`${rows.length} registros`,'v92-gray')}</div>${rows.length ? rows.map(a => {
      const p = itemsByPilot.get(a.pilot_id);
      const label = p?.subject_label || shortId(a.pilot_id);
      const action = clean(a.action).toLowerCase();
      const actionLabel = action.includes('rollback') || action.includes('unlink') ? 'ROLLBACK' : 'CUTOVER';
      const cls = actionLabel === 'ROLLBACK' ? 'v92-warn' : 'v92-blue';
      return `<div class="v92-audit-row"><div>${pill(actionLabel,cls)}</div><div><div class="v92-audit-action">${esc(label)}</div><div class="muted">Cliente ${esc(shortId(a.client_id))} · Actor ${esc(shortId(a.actor_id))}</div></div><div class="muted">${fmtDate(a.created_at)}</div></div>`;
    }).join('') : '<div class="v92-empty">Sin operaciones persistidas. El entorno está limpio.</div>'}</section>`;
  }

  function bindActions(items) {
    const byId = new Map(items.map(x => [x.pilot_id, x]));
    $$('.v92Resolve').forEach(btn => btn.onclick = async () => {
      const pilotId = btn.dataset.pilot;
      const emailInput = document.querySelector(`.v92Email[data-pilot="${CSS.escape(pilotId)}"]`);
      const email = clean(emailInput?.value).toLowerCase();
      if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return toast('Ingresa un correo válido.');
      btn.disabled = true;
      try {
        const out = await rpc('resolve_cv12_native_client_v91', { p_email: email });
        resolved.set(pilotId, out);
        await renderControl();
      } catch (e) {
        resolved.set(pilotId, { error: 'No se pudo validar la identidad: ' + String(e?.message || e) });
        await renderControl();
      } finally {
        btn.disabled = false;
      }
    });

    $$('.v92CreateClient').forEach(btn => btn.onclick = () => {
      const pilotId = btn.dataset.pilot;
      const x = resolved.get(pilotId);
      if (typeof newClient !== 'function') return toast('El flujo de alta no está disponible.');
      newClient();
      const email = clean(x?.email);
      setTimeout(() => {
        const input = $('#ne');
        if (input && email) input.value = email;
      }, 0);
    });

    $$('.v92Execute').forEach(btn => btn.onclick = async () => {
      const pilotId = btn.dataset.pilot;
      const pilot = byId.get(pilotId);
      const x = resolved.get(pilotId);
      if (!pilot || !x?.ready_for_v90 || !x?.client_id) return toast('Primero valida una identidad apta para V90.');
      openConfirm({
        title: 'Ejecutar cutover V90',
        copy: `Vincularás ${pilot.subject_label || 'este piloto'} con ${x.client_name || 'el cliente'} (${x.email || ''}). El historial legacy se conservará y no se publicará ninguna rutina automáticamente.`,
        word: 'VINCULAR',
        button: 'EJECUTAR CUTOVER',
        danger: false,
        onConfirm: async out => {
          const latest = await rpc('resolve_cv12_native_client_v91', { p_email: x.email });
          if (latest?.client_id !== x.client_id || latest?.ready_for_v90 !== true) throw Error('La identidad cambió o dejó de estar lista. Vuelve a validarla.');
          out.textContent = 'Ejecutando V90…';
          await rpc('execute_cv12_native_cutover_v90', { p_pilot_id: pilotId, p_client_id: x.client_id, p_actor_id: me.id });
          resolved.delete(pilotId);
          $('#modal').innerHTML = '';
          cache = {};
          toast('Cutover V90 ejecutado y auditado.');
          await renderControl();
        }
      });
    });

    $$('.v92Rollback').forEach(btn => btn.onclick = () => {
      const pilotId = btn.dataset.pilot;
      const clientId = btn.dataset.client;
      const pilot = byId.get(pilotId);
      openConfirm({
        title: 'Rollback de vínculo',
        copy: `Desvincularás ${pilot?.subject_label || 'este piloto'} de la identidad nativa actual. No se borrará el historial legacy ni datos nativos del cliente.`,
        word: 'DESVINCULAR',
        button: 'CONFIRMAR ROLLBACK',
        danger: true,
        onConfirm: async out => {
          out.textContent = 'Ejecutando rollback…';
          await rpc('rollback_cv12_native_cutover_v90', { p_pilot_id: pilotId, p_expected_client_id: clientId, p_actor_id: me.id });
          resolved.delete(pilotId);
          $('#modal').innerHTML = '';
          cache = {};
          toast('Rollback V90 completado.');
          await renderControl();
        }
      });
    });
  }

  function openConfirm({ title, copy, word, button, danger, onConfirm }) {
    $('#modal').innerHTML = `<div class="modal"><div class="card" style="width:min(96vw,620px)"><div class="row"><div class="grow"><div class="ey">OPERACIÓN PROTEGIDA · V92</div><h2>${esc(title)}</h2></div><button id="v92Close" class="btn small">✕</button></div><div class="v92-modal-copy">${esc(copy)}</div><label>Escribe <span class="v92-confirm">${esc(word)}</span> para confirmar</label><input id="v92ConfirmWord" class="input" autocomplete="off"><button id="v92ConfirmBtn" class="btn ${danger ? 'v92-danger' : 'primary'}" style="width:100%">${esc(button)}</button><div id="v92ConfirmStatus" class="status muted"></div></div></div>`;
    $('#v92Close').onclick = () => $('#modal').innerHTML = '';
    $('#v92ConfirmBtn').onclick = async () => {
      const input = clean($('#v92ConfirmWord')?.value).toUpperCase();
      const out = $('#v92ConfirmStatus');
      if (input !== word) return out.textContent = `Debes escribir ${word} exactamente.`;
      const buttonEl = $('#v92ConfirmBtn');
      buttonEl.disabled = true;
      try {
        await onConfirm(out);
      } catch (e) {
        out.style.color = '#ff93a1';
        out.textContent = 'Operación rechazada: ' + String(e?.message || e);
        buttonEl.disabled = false;
      }
    };
  }

  async function renderControl() {
    ensureStyle();
    const content = $('#content');
    if (!content) return;
    content.innerHTML = '<div class="card muted">Cargando control de migraciones CV12…</div>';
    try {
      const [control, audit] = await Promise.all([
        rpc('get_cv12_cutover_control_v91', { p_pilot_id: null }),
        rpc('get_cv12_cutover_audit_v92', { p_pilot_id: null })
      ]);
      const items = Array.isArray(control?.items) ? control.items : [];
      const itemMap = new Map(items.map(x => [x.pilot_id, x]));
      const technical = items.filter(x => bool(x?.readiness?.readiness?.technical_ready_for_native_identity)).length;
      const linked = items.filter(x => !!x.client_id && !!x.linked_at).length;
      const aiReady = items.filter(x => bool(x?.readiness?.readiness?.longitudinal_ai_ready)).length;
      const unresolved = items.reduce((sum, x) => sum + Number(x?.readiness?.legacy_history?.unresolved_exercise_logs || 0), 0);
      content.innerHTML = `<div class="v92-head"><div><div class="ey">V92 · MIGRATIONS & OPERATIONS</div><h1 class="v92-title">MIGRACIONES CV12</h1><p class="v92-sub">Control operativo sobre V89/V90/V91. La pantalla valida readiness e identidad antes de permitir cualquier mutación; ninguna acción se ejecuta automáticamente.</p></div><button id="v92Refresh" class="btn">↻ ACTUALIZAR</button></div><div class="v92-kpis"><div class="v92-kpi"><span>Pilotos</span><b>${items.length}</b></div><div class="v92-kpi"><span>Técnicamente listos</span><b>${technical}</b></div><div class="v92-kpi"><span>Vinculados</span><b>${linked}</b></div><div class="v92-kpi"><span>IA longitudinal lista</span><b>${aiReady}</b></div><div class="v92-kpi"><span>Mapeos pendientes</span><b>${unresolved}</b></div></div>${items.length ? `<div class="v92-grid">${items.map(pilotCard).join('')}</div>` : '<div class="v92-card v92-empty">No hay pilotos CV12 registrados.</div>'}${auditHtml(audit, itemMap)}`;
      $('#v92Refresh').onclick = () => renderControl();
      bindActions(items);
    } catch (e) {
      content.innerHTML = `<div class="v92-card" style="border-color:#64202b"><b>No se pudo cargar V92</b><div class="muted" style="margin-top:7px">${esc(String(e?.message || e))}</div></div>`;
    }
  }

  function installNavigation() {
    const nav = document.querySelector('.nav');
    if (!nav || nav.querySelector('[data-v="cv12"]')) return;
    const button = document.createElement('button');
    button.dataset.v = VIEW;
    button.textContent = '⇄ Migraciones CV12';
    const account = nav.querySelector('[data-v="account"]');
    nav.insertBefore(button, account || null);
    button.onclick = () => setView(VIEW);
  }

  if (typeof render !== 'function' || typeof setView !== 'function' || typeof req !== 'function') {
    console.error('CV Coach V92: admin host contract unavailable');
    return;
  }

  const baseRender = render;
  const baseSetView = setView;

  render = async function renderV92Aware() {
    if (view === VIEW) return renderControl();
    return baseRender();
  };

  setView = function setViewV92Aware(nextView) {
    if (nextView !== VIEW) return baseSetView(nextView);
    clientDetailToken++;
    view = VIEW;
    $$('.nav button').forEach(b => b.classList.toggle('on', b.dataset.v === VIEW));
    $('#topTitle').textContent = 'Migraciones CV12';
    return render();
  };

  installNavigation();
  window.cv12CutoverV92 = { render: renderControl, version: 'V92' };
})();
