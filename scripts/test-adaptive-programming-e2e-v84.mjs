const BASE='https://fmhcansyxcsqkrivqchr.supabase.co';
const EDGE=`${BASE}/functions/v1/cv-adaptive-canary-v84`;
const AUDIENCE='cv-coach-production-canary-v76';
const RUN_ID=`${process.env.GITHUB_RUN_ID||'local'}-${process.env.GITHUB_RUN_ATTEMPT||'1'}-v84`;

function required(name){
  const value=process.env[name];
  if(!value)throw new Error(`Missing ${name}`);
  return value;
}

async function oidcToken(){
  const requestToken=required('ACTIONS_ID_TOKEN_REQUEST_TOKEN');
  const rawUrl=required('ACTIONS_ID_TOKEN_REQUEST_URL');
  const url=new URL(rawUrl);
  url.searchParams.set('audience',AUDIENCE);
  const response=await fetch(url,{headers:{Authorization:`Bearer ${requestToken}`}});
  if(!response.ok)throw new Error(`OIDC ${response.status}: ${await response.text()}`);
  const body=await response.json();
  if(!body?.value)throw new Error('OIDC token missing');
  return body.value;
}

const token=await oidcToken();
const response=await fetch(EDGE,{
  method:'POST',
  headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},
  body:JSON.stringify({run_id:RUN_ID}),
});
const text=await response.text();
let body;
try{body=JSON.parse(text)}catch{throw new Error(`V84 canary invalid JSON (${response.status})`)}
if(!response.ok||body?.error)throw new Error(`V84 canary failed: ${body?.error||response.status}`);

const expected={
  ok:true,
  contract:'CV_V84_ADAPTIVE_PROGRAMMING_E2E_OK',
  recommendation_action:'build_time',
  review_status:'modified',
  next_session_progression_status:'applied',
  suggested_duration_seconds:35,
  history_visible:true,
  rollback_isolated:true,
};
for(const [key,value] of Object.entries(expected)){
  if(body?.[key]!==value)throw new Error(`V84 contract mismatch ${key}: expected ${JSON.stringify(value)}, got ${JSON.stringify(body?.[key])}`);
}
console.log('CV_V84_ADAPTIVE_PROGRAMMING_E2E_OK',JSON.stringify({run_id:RUN_ID,target:body.suggested_duration_seconds}));
