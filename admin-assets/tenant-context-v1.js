(function(global){
  'use strict';

  function slugHint(){
    try{
      const q=new URLSearchParams(global.location.search);
      const raw=q.get('org')||q.get('tenant')||q.get('organization')||'';
      return String(raw).trim().toLowerCase()||null;
    }catch(_){return null}
  }

  function storageKey(userId){
    return 'cv_active_org_v1:'+String(userId||'anonymous');
  }

  function savedSelection(userId){
    try{return localStorage.getItem(storageKey(userId))||null}catch(_){return null}
  }

  function persistSelection(userId,organizationId){
    try{
      if(organizationId)localStorage.setItem(storageKey(userId),String(organizationId));
      else localStorage.removeItem(storageKey(userId));
    }catch(_){}
  }

  function clear(userId){persistSelection(userId,null)}

  async function restRpc({base,key,session,selectedId,suggestedSlug}){
    const response=await fetch(base+'/rest/v1/rpc/resolve_active_organization_context_v1',{
      method:'POST',
      headers:{
        apikey:key,
        Authorization:'Bearer '+session.access_token,
        'Content-Type':'application/json'
      },
      body:JSON.stringify({
        p_selected_organization_id:selectedId||null,
        p_suggested_slug:suggestedSlug||null
      })
    });
    let payload=null;
    try{payload=await response.json()}catch(_){}
    if(!response.ok)throw new Error(payload?.message||payload?.error||'No se pudo resolver tu organización.');
    return payload;
  }

  async function supabaseRpc({sb,selectedId,suggestedSlug}){
    const result=await sb.rpc('resolve_active_organization_context_v1',{
      p_selected_organization_id:selectedId||null,
      p_suggested_slug:suggestedSlug||null
    });
    if(result.error)throw result.error;
    return result.data;
  }

  function chooseOrganization(options){
    return new Promise(resolve=>{
      const existing=document.getElementById('cvTenantChooserV1');
      if(existing)existing.remove();

      const overlay=document.createElement('div');
      overlay.id='cvTenantChooserV1';
      overlay.style.cssText='position:fixed;inset:0;z-index:2147483000;background:rgba(2,5,7,.94);display:grid;place-items:center;padding:20px;font-family:Inter,system-ui,sans-serif;color:#fff';
      const card=document.createElement('div');
      card.style.cssText='width:min(460px,100%);border:1px solid #2b363d;background:#081014;border-radius:18px;padding:20px;box-shadow:0 24px 70px rgba(0,0,0,.5)';
      const title=document.createElement('h2');
      title.textContent='ELIGE TU ORGANIZACIÓN';
      title.style.cssText='margin:0 0 8px;font-size:24px';
      const sub=document.createElement('p');
      sub.textContent='Tu cuenta pertenece a más de una organización. Elige dónde quieres entrar.';
      sub.style.cssText='margin:0 0 16px;color:#9aa6ad;font-size:13px;line-height:1.5';
      card.append(title,sub);

      (options||[]).forEach(item=>{
        const button=document.createElement('button');
        button.type='button';
        button.style.cssText='width:100%;text-align:left;margin:7px 0;padding:13px 14px;border-radius:12px;border:1px solid #344149;background:#0d1519;color:#fff;cursor:pointer';
        const name=document.createElement('strong');
        name.textContent=item.display_name||item.slug||'Organización';
        name.style.cssText='display:block;font-size:14px';
        const meta=document.createElement('span');
        meta.textContent=(item.role||'miembro')+' · '+(item.slug||'');
        meta.style.cssText='display:block;margin-top:4px;color:#8f9ba2;font-size:11px';
        button.append(name,meta);
        button.onclick=()=>{overlay.remove();resolve(item.organization_id)};
        card.append(button);
      });

      overlay.append(card);
      document.body.append(overlay);
    });
  }

  async function ensureCommon({userId,resolver}){
    let context=await resolver(savedSelection(userId),slugHint());

    if(context?.resolution==='selection_required'){
      const chosen=await chooseOrganization(context.memberships||[]);
      context=await resolver(chosen,slugHint());
    }

    if(context?.resolution==='no_membership'){
      clear(userId);
      throw new Error('Tu cuenta no tiene una organización activa. Necesitas una invitación o activación.');
    }

    const orgId=context?.active_organization?.organization_id;
    if(!orgId){
      clear(userId);
      throw new Error('No se pudo establecer una organización activa.');
    }

    persistSelection(userId,orgId);
    return context;
  }

  async function ensureRest({base,key,session,userId}){
    return ensureCommon({
      userId,
      resolver:(selectedId,suggestedSlug)=>restRpc({base,key,session,selectedId,suggestedSlug})
    });
  }

  async function ensureSupabase({sb,userId}){
    return ensureCommon({
      userId,
      resolver:(selectedId,suggestedSlug)=>supabaseRpc({sb,selectedId,suggestedSlug})
    });
  }

  global.CVTenantContext={
    version:'1.0',
    slugHint,
    clear,
    ensureRest,
    ensureSupabase
  };
})(window);
