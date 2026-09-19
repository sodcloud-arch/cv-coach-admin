(function(global){
  'use strict';

  const STATES=Object.freeze({
    UNAUTHENTICATED:'unauthenticated',
    AUTHENTICATED_NO_ORG:'authenticated_no_org',
    AUTHENTICATED_ACTIVE_ORG:'authenticated_active_org',
    REAUTH_REQUIRED:'reauth_required'
  });

  let current={
    state:STATES.UNAUTHENTICATED,
    user_id:null,
    organization_id:null,
    role:null,
    reason:null,
    updated_at:new Date().toISOString()
  };

  function publish(next){
    current={...current,...next,updated_at:new Date().toISOString()};
    try{
      global.dispatchEvent(new CustomEvent('cv:session-context',{detail:{...current}}));
    }catch(_){}
    return {...current};
  }

  function unauthenticated(reason=null){
    return publish({
      state:STATES.UNAUTHENTICATED,
      user_id:null,
      organization_id:null,
      role:null,
      reason
    });
  }

  function authenticatedNoOrg(userId,reason='organization_required'){
    return publish({
      state:STATES.AUTHENTICATED_NO_ORG,
      user_id:userId||null,
      organization_id:null,
      role:null,
      reason
    });
  }

  function active(userId,context,reason='validated'){
    const org=context?.active_organization||null;
    if(!userId||!org?.organization_id){
      return authenticatedNoOrg(userId,'missing_active_organization');
    }
    return publish({
      state:STATES.AUTHENTICATED_ACTIVE_ORG,
      user_id:userId,
      organization_id:org.organization_id,
      role:org.role||null,
      reason
    });
  }

  function reauthRequired(userId,reason='session_invalid'){
    return publish({
      state:STATES.REAUTH_REQUIRED,
      user_id:userId||null,
      organization_id:null,
      role:null,
      reason
    });
  }

  function snapshot(){return {...current}}

  function fromTenantValidation(userId,result){
    if(result?.valid&&result?.context?.active_organization?.organization_id){
      return active(userId,result.context,'membership_revalidated');
    }
    return authenticatedNoOrg(userId,result?.reason||'organization_context_invalid');
  }

  async function logoutRest({base,key,session,scope='local'}){
    const allowed=new Set(['local','global','others']);
    const safeScope=allowed.has(scope)?scope:'local';
    if(session?.access_token){
      try{
        await fetch(base+'/auth/v1/logout?scope='+encodeURIComponent(safeScope),{
          method:'POST',
          headers:{
            apikey:key,
            Authorization:'Bearer '+session.access_token,
            'Content-Type':'application/json'
          }
        });
      }catch(_){}
    }
    return unauthenticated('logout_'+safeScope);
  }

  async function logoutSupabase({sb,scope='local'}){
    const allowed=new Set(['local','global','others']);
    const safeScope=allowed.has(scope)?scope:'local';
    try{
      const result=await sb.auth.signOut({scope:safeScope});
      if(result?.error&&safeScope==='local')await sb.auth.signOut();
    }catch(_){}
    return unauthenticated('logout_'+safeScope);
  }

  global.CVSessionContext={
    version:'F1.M2.S3_SESSION_V1',
    STATES,
    snapshot,
    unauthenticated,
    authenticatedNoOrg,
    active,
    reauthRequired,
    fromTenantValidation,
    logoutRest,
    logoutSupabase
  };
})(window);
