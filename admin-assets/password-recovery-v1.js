(function(global){
  'use strict';

  const NEUTRAL_MESSAGE='Si existe una cuenta para ese correo, recibirás instrucciones para restablecer tu contraseña.';

  function cleanEmail(value){
    return String(value||'').trim().toLowerCase();
  }

  function sameOriginRedirect(value){
    const fallback=global.location.origin+global.location.pathname+'?recovery=1';
    try{
      const url=new URL(value||fallback,global.location.origin);
      if(url.origin!==global.location.origin)return fallback;
      url.hash='';
      return url.toString();
    }catch(_){
      return fallback;
    }
  }

  async function jsonResponse(response){
    try{return await response.json()}catch(_){return null}
  }

  async function requestRest({base,key,email,redirectTo}){
    const target=sameOriginRedirect(redirectTo);
    const normalized=cleanEmail(email);
    try{
      await fetch(base+'/auth/v1/recover?redirect_to='+encodeURIComponent(target),{
        method:'POST',
        headers:{apikey:key,'Content-Type':'application/json'},
        body:JSON.stringify({email:normalized})
      });
    }catch(error){
      console.warn('Password recovery request could not be delivered',error);
    }
    return {accepted:true,message:NEUTRAL_MESSAGE};
  }

  function parseRecoveryFragment(){
    try{
      const params=new URLSearchParams(String(global.location.hash||'').replace(/^#/,''));
      if(params.get('type')!=='recovery')return null;
      const accessToken=params.get('access_token');
      if(!accessToken)return null;
      return {
        access_token:accessToken,
        refresh_token:params.get('refresh_token')||null,
        token_type:params.get('token_type')||'bearer',
        expires_in:Number(params.get('expires_in')||0)||null,
        type:'recovery'
      };
    }catch(_){
      return null;
    }
  }

  function recoveryTokenHash(){
    try{
      const params=new URLSearchParams(global.location.search);
      if(params.get('type')!=='recovery')return null;
      const value=params.get('token_hash');
      return value&&value.trim()?value.trim():null;
    }catch(_){
      return null;
    }
  }

  async function verifyRestRecoveryToken({base,key,tokenHash}){
    if(!tokenHash)throw new Error('invalid_or_expired_recovery_link');
    const response=await fetch(base+'/auth/v1/verify',{
      method:'POST',
      headers:{apikey:key,'Content-Type':'application/json'},
      body:JSON.stringify({token_hash:tokenHash,type:'recovery'})
    });
    const payload=await jsonResponse(response);
    if(!response.ok||!payload?.access_token){
      throw new Error('invalid_or_expired_recovery_link');
    }
    return payload;
  }

  async function resolveRestRecoverySession({base,key}){
    const fragment=parseRecoveryFragment();
    if(fragment)return fragment;
    const tokenHash=recoveryTokenHash();
    if(!tokenHash)return null;
    return verifyRestRecoveryToken({base,key,tokenHash});
  }

  async function updateRestPassword({base,key,session,password}){
    if(!session?.access_token)throw new Error('invalid_or_expired_recovery_link');
    const next=String(password||'');
    if(next.length<8)throw new Error('password_too_short');
    const response=await fetch(base+'/auth/v1/user',{
      method:'PUT',
      headers:{
        apikey:key,
        Authorization:'Bearer '+session.access_token,
        'Content-Type':'application/json'
      },
      body:JSON.stringify({password:next})
    });
    const payload=await jsonResponse(response);
    if(!response.ok||!payload?.id){
      throw new Error('invalid_or_expired_recovery_link');
    }
    return payload;
  }

  async function logoutRest({base,key,session}){
    if(!session?.access_token)return;
    try{
      await fetch(base+'/auth/v1/logout?scope=global',{
        method:'POST',
        headers:{
          apikey:key,
          Authorization:'Bearer '+session.access_token,
          'Content-Type':'application/json'
        }
      });
    }catch(_){}
  }

  function scrubRecoveryUrl(){
    try{
      global.history.replaceState(null,'',global.location.origin+global.location.pathname);
    }catch(_){}
  }

  function isRecoveryNavigation(){
    try{
      const query=new URLSearchParams(global.location.search);
      const hash=new URLSearchParams(String(global.location.hash||'').replace(/^#/,''));
      return query.get('recovery')==='1'
        || query.get('type')==='recovery'
        || hash.get('type')==='recovery';
    }catch(_){
      return false;
    }
  }

  global.CVPasswordRecovery={
    version:'F1.M2.S2_RECOVERY_V1',
    neutralMessage:NEUTRAL_MESSAGE,
    cleanEmail,
    sameOriginRedirect,
    requestRest,
    parseRecoveryFragment,
    recoveryTokenHash,
    verifyRestRecoveryToken,
    resolveRestRecoverySession,
    updateRestPassword,
    logoutRest,
    scrubRecoveryUrl,
    isRecoveryNavigation
  };
})(window);
