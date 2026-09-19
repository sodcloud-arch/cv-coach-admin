(function(global){
  'use strict';

  function normalized(snapshot){
    const caps=Array.isArray(snapshot?.capabilities)?snapshot.capabilities:[];
    return {
      ...snapshot,
      capabilities:caps,
      capabilityMap:new Map(caps.map(item=>[String(item.capability),item]))
    };
  }

  function can(snapshot,capability){
    const s=snapshot?.capabilityMap?snapshot:normalized(snapshot||{});
    return s.capabilityMap.has(String(capability||''));
  }

  function scopes(snapshot,capability){
    const s=snapshot?.capabilityMap?snapshot:normalized(snapshot||{});
    const item=s.capabilityMap.get(String(capability||''));
    return Array.isArray(item?.scopes)?item.scopes:[];
  }

  async function loadRest({base,key,session,organizationId}){
    const r=await fetch(base+'/rest/v1/rpc/get_my_permission_snapshot_v1',{
      method:'POST',
      headers:{
        apikey:key,
        Authorization:'Bearer '+session.access_token,
        'Content-Type':'application/json'
      },
      body:JSON.stringify({p_organization_id:organizationId})
    });
    let payload=null;
    try{payload=await r.json()}catch(_){}
    if(!r.ok)throw new Error(payload?.message||payload?.error||'No se pudo resolver tus permisos.');
    return normalized(payload);
  }

  async function loadSupabase({sb,organizationId}){
    const result=await sb.rpc('get_my_permission_snapshot_v1',{
      p_organization_id:organizationId
    });
    if(result.error)throw result.error;
    return normalized(result.data);
  }

  function apply(root,snapshot){
    const base=root||document;
    base.querySelectorAll('[data-capability]').forEach(el=>{
      const allowed=can(snapshot,el.getAttribute('data-capability'));
      el.hidden=!allowed;
      el.setAttribute('aria-hidden',allowed?'false':'true');
    });
  }

  global.CVPermissionContext={
    version:'F1.M2.S8_PERMISSION_CONTEXT_V1',
    normalized,
    can,
    scopes,
    loadRest,
    loadSupabase,
    apply
  };
})(window);
