from pathlib import Path
import hashlib
import json
import runpy

ROOT = Path(__file__).resolve().parent
HTML = ROOT / "stable" / "index.html"
BUILD = ROOT / "stable" / "build.json"
MARKER = "<!-- cv-client-sound-v53: verified set + completed workout sonic feedback -->"

text = HTML.read_text(encoding="utf-8")

SOUND_SCRIPT = r'''<script id="cv-sound-manager-v53-js">
(function(){
  if(window.CVSound?.version==='v53')return;
  const sources={
    set_confirmed:'./assets/sounds/cv-set-confirmed-v1.mp3',
    workout_complete:'./assets/sounds/cv-workout-complete-v1.mp3'
  };
  const volumes={set_confirmed:.28,workout_complete:.48};
  const players={};
  let enabled=true;
  try{enabled=localStorage.getItem('cvSoundEnabledV53')!=='0'}catch(e){}
  function player(name){
    if(players[name])return players[name];
    const audio=new Audio(sources[name]);audio.preload='auto';audio.volume=volumes[name]??.35;players[name]=audio;return audio
  }
  function unlock(){
    const pending=[];
    for(const name of Object.keys(sources)){
      const audio=player(name);
      try{
        audio.muted=true;
        const attempt=audio.play();
        pending.push(Promise.resolve(attempt).catch(()=>{}).then(()=>{try{audio.pause();audio.currentTime=0}catch(e){}audio.muted=false}));
      }catch(e){audio.muted=false}
    }
    return Promise.allSettled(pending)
  }
  function play(name){
    if(!enabled||!sources[name])return false;
    const audio=player(name);
    try{audio.pause();audio.currentTime=0;audio.volume=volumes[name]??.35;const p=audio.play();if(p?.catch)p.catch(()=>{});return true}catch(e){return false}
  }
  function setEnabled(value){enabled=!!value;try{localStorage.setItem('cvSoundEnabledV53',enabled?'1':'0')}catch(e){}return enabled}
  window.CVSound={version:'v53',play,setEnabled,isEnabled:()=>enabled,unlock};
  document.addEventListener('pointerdown',()=>{unlock()},{capture:true,once:true});
  document.addEventListener('cv:set-state',event=>{if(event.detail?.completed===true)play('set_confirmed')});
  const showResult=window.cvShowWorkoutResult;
  if(typeof showResult==='function')window.cvShowWorkoutResult=function(result){const out=showResult.apply(this,arguments);if(String(result?.status||'').toLowerCase()==='completed')play('workout_complete');return out};
})();
</script>'''

if MARKER not in text:
    if "cv-client-runtime-v51" not in text or "cv-workout-regression-guard-v52" not in text:
        raise SystemExit("sound v53 requires V51 runtime and V52 regression guard")
    if "</body>" not in text:
        raise SystemExit("sound v53: </body> missing")
    text = text.replace("</body>", SOUND_SCRIPT + "\n" + MARKER + "\n</body>", 1)

required = [
    MARKER,
    'cv-sound-manager-v53-js',
    "version:'v53'",
    "event.detail?.completed===true",
    "play('set_confirmed')",
    "play('workout_complete')",
    "cvSoundEnabledV53",
    "Promise.allSettled(pending)",
    "./assets/sounds/cv-set-confirmed-v1.mp3",
    "./assets/sounds/cv-workout-complete-v1.mp3",
]
for item in required:
    if item not in text:
        raise SystemExit(f"sound v53 required contract missing: {item}")

HTML.write_text(text, encoding="utf-8")
sha = hashlib.sha256(text.encode("utf-8")).hexdigest()
metadata = {}
if BUILD.exists():
    try:
        metadata = json.loads(BUILD.read_text(encoding="utf-8"))
    except Exception:
        metadata = {}
metadata["bytes"] = len(text.encode("utf-8"))
metadata["sha256"] = sha
patches = list(metadata.get("patches") or [])
for patch in [
    "verified-set sonic confirmation v53",
    "completed-workout sonic reward v53",
    "iOS audio unlock v53",
    "central sound manager v53",
]:
    if patch not in patches:
        patches.append(patch)
metadata["patches"] = patches
BUILD.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"sha256": sha, "bytes": metadata["bytes"], "patches": metadata["patches"][-4:]}, ensure_ascii=False))

# Current production chain: V54 hardens mobile start/persistence UX, then V55
# restores the approved workout sound language and guards it as one runtime.
runpy.run_path(str(ROOT / "upgrade_client_v54.py"), run_name="__main__")
runpy.run_path(str(ROOT.parent / "scripts" / "test-mobile-workout-v54.py"), run_name="__main__")
runpy.run_path(str(ROOT / "upgrade_client_v55.py"), run_name="__main__")
runpy.run_path(str(ROOT.parent / "scripts" / "test-workout-sound-v55.py"), run_name="__main__")
