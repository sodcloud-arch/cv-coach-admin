import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const CORS={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Methods":"GET,HEAD,OPTIONS","Access-Control-Allow-Headers":"content-type","X-Content-Type-Options":"nosniff"};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...CORS,"Content-Type":"application/json; charset=utf-8","Cache-Control":"no-store"}});

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS") return new Response(null,{status:204,headers:CORS});
  if(req.method!=="GET"&&req.method!=="HEAD") return json({error:"method_not_allowed"},405);
  const id=new URL(req.url).searchParams.get("id")?.trim()||"";
  if(!/^[A-Za-z0-9_-]{20,100}$/.test(id)) return json({error:"invalid_asset_id"},400);

  const supabaseUrl=Deno.env.get("SUPABASE_URL")||"";
  const anonKey=Deno.env.get("SUPABASE_ANON_KEY")||"";
  if(!supabaseUrl||!anonKey) return json({error:"proxy_not_configured"},500);

  const authRes=await fetch(`${supabaseUrl}/rest/v1/rpc/is_exercise_drive_asset_approved_v100`,{
    method:"POST",
    headers:{Authorization:`Bearer ${anonKey}`,apikey:anonKey,"Content-Type":"application/json"},
    body:JSON.stringify({p_drive_id:id}),
  });
  if(!authRes.ok) return json({error:"asset_authorization_failed",status:authRes.status},502);
  const approved=await authRes.json();
  if(approved!==true) return json({error:"asset_not_in_library"},404);

  const candidates=[
    `https://drive.google.com/thumbnail?id=${encodeURIComponent(id)}&sz=w1600`,
    `https://lh3.googleusercontent.com/d/${encodeURIComponent(id)}=w1600`,
    `https://drive.usercontent.google.com/download?id=${encodeURIComponent(id)}&export=view&authuser=0`,
  ];
  let lastStatus=0;
  for(const source of candidates){
    try{
      const upstream=await fetch(source,{redirect:"follow",headers:{"User-Agent":"Mozilla/5.0 CV-Coach-Asset-Proxy/3.0",Accept:"image/avif,image/webp,image/png,image/jpeg,image/*,*/*;q=0.8"}});
      lastStatus=upstream.status;
      const type=upstream.headers.get("content-type")||"";
      if(!upstream.ok||!type.toLowerCase().startsWith("image/")) continue;
      const headers=new Headers(CORS);
      headers.set("Content-Type",type);
      headers.set("Cache-Control","public, max-age=86400, s-maxage=86400, stale-while-revalidate=604800");
      headers.set("X-CV-Asset-Proxy","drive-v3");
      const len=upstream.headers.get("content-length"); if(len) headers.set("Content-Length",len);
      return req.method==="HEAD"?new Response(null,{status:200,headers}):new Response(upstream.body,{status:200,headers});
    }catch(_){continue;}
  }
  return json({error:"asset_unavailable",upstream_status:lastStatus},502);
});
