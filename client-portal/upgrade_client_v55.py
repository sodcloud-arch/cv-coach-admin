from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent
HTML = ROOT / "stable" / "index.html"
BUILD = ROOT / "stable" / "build.json"
MARKER = "<!-- cv-workout-sound-language-v55: original set confirm + single 10-1 countdown + distinct ready -->"

text = HTML.read_text(encoding="utf-8")

SOUND_SCRIPT = r'''<script id="cv-workout-sound-v55-js">
(function(){
  if(window.CVWorkoutSoundV55?.version==='v55')return;

  /* V53 introduced a second set-confirmation MP3 on top of the original
     synthesized CV confirmation. Disable that manager at runtime so a saved
     set has one canonical sound again. V55 keeps the same UI sound preference
     used by the header: cv_sound_enabled. */
  try{window.CVSound?.setEnabled(false)}catch(e){}

  let ac=null,lastSecond=null,restFinished=false,pollHandle=null;
  let workoutPlayer=null;
  function enabled(){try{return localStorage.getItem('cv_sound_enabled')!=='0'}catch(e){return true}}
  function ctx(){
    try{
      if(!ac){const C=window.AudioContext||window.webkitAudioContext;if(!C)return null;ac=new C()}
      if(ac.state==='suspended')ac.resume().catch(()=>{});
      return ac
    }catch(e){return null}
  }
  function tone(f,d,delay=0,vol=.018,type='triangle'){
    if(!enabled())return false;const c=ctx();if(!c)return false;
    try{const o=c.createOscillator(),g=c.createGain(),t=c.currentTime+delay;o.type=type;o.frequency.setValueAtTime(f,t);g.gain.setValueAtTime(.0001,t);g.gain.exponentialRampToValueAtTime(Math.max(.001,vol),t+.006);g.gain.exponentialRampToValueAtTime(.0001,t+d);o.connect(g).connect(c.destination);o.start(t);o.stop(t+d+.02);return true}catch(e){return false}
  }
  function countdownTick(sec){
    if(sec>=4){tone(780,.042,0,.012,'square');return}
    if(sec===3){tone(840,.075,0,.026,'square');return}
    if(sec===2){tone(920,.085,0,.029,'square');return}
    if(sec===1){tone(1040,.105,0,.033,'square')}
  }
  function ready(){
    tone(660,.08,0,.025,'triangle');tone(825,.09,.065,.024,'triangle');tone(990,.15,.13,.022,'triangle')
  }
  function workoutComplete(){
    if(!enabled())return false;
    try{
      workoutPlayer=workoutPlayer||new Audio('./assets/sounds/cv-workout-complete-v1.mp3');
      workoutPlayer.pause();workoutPlayer.currentTime=0;workoutPlayer.volume=.48;
      const p=workoutPlayer.play();if(p?.catch)p.catch(()=>{});return true
    }catch(e){return false}
  }
  function resetRest(){lastSecond=null;restFinished=false}
  function syncRest(){
    const dock=document.getElementById('cvRestVisualV32'),time=document.getElementById('cvRestVisualTime');
    if(!dock||!time||dock.classList.contains('hidden')){resetRest();return}
    const raw=String(time.textContent||'').trim();
    if(dock.classList.contains('ready')||raw==='LISTO'){
      if(!restFinished){restFinished=true;lastSecond=0;ready();try{navigator.vibrate?.([90,55,120])}catch(e){}}
      return
    }
    const match=raw.match(/^(\d+):(\d{2})$/);if(!match)return;
    const sec=Number(match[1])*60+Number(match[2]);
    if(sec>10){lastSecond=null;restFinished=false;return}
    if(sec>0&&sec<=10&&sec!==lastSecond){
      lastSecond=sec;restFinished=false;countdownTick(sec);
      try{navigator.vibrate?.(sec<=3?[35,28,35]:18)}catch(e){}
      return
    }
    if(sec===0&&!restFinished){restFinished=true;lastSecond=0;ready();try{navigator.vibrate?.([90,55,120])}catch(e){}}
  }

  const showResult=window.cvShowWorkoutResult;
  if(typeof showResult==='function'&&!showResult.__cvWorkoutSoundV55){
    const wrapped=function(result){const out=showResult.apply(this,arguments);if(String(result?.status||'').toLowerCase()==='completed')workoutComplete();return out};
    wrapped.__cvWorkoutSoundV55=true;window.cvShowWorkoutResult=wrapped
  }

  document.addEventListener('pointerdown',()=>{ctx();try{workoutPlayer=workoutPlayer||new Audio('./assets/sounds/cv-workout-complete-v1.mp3');workoutPlayer.muted=true;const p=workoutPlayer.play();Promise.resolve(p).catch(()=>{}).then(()=>{try{workoutPlayer.pause();workoutPlayer.currentTime=0}catch(e){}workoutPlayer.muted=false})}catch(e){}},{capture:true,once:true});
  document.addEventListener('visibilitychange',()=>{if(!document.hidden)syncRest()});
  window.addEventListener('pageshow',syncRest);
  pollHandle=setInterval(syncRest,120);
  window.CVWorkoutSoundV55={version:'v55',syncRest,countdownTick,ready,workoutComplete,isEnabled:enabled,stop:()=>{clearInterval(pollHandle);pollHandle=null}};
})();
</script>'''

if MARKER not in text:
    for prerequisite in [
        "cv-client-sound-v53",
        "cv-mobile-workout-reliability-v54",
        "cvRestVisualV32",
        "function sfx(k)",
        "if(event.detail?.completed)sfx('confirm')",
    ]:
        if prerequisite not in text:
            raise SystemExit(f"sound v55 prerequisite missing: {prerequisite}")
    if "</body>" not in text:
        raise SystemExit("sound v55: </body> missing")
    text = text.replace("</body>", SOUND_SCRIPT + "\n" + MARKER + "\n</body>", 1)

required = [
    MARKER,
    'cv-workout-sound-v55-js',
    "window.CVSound?.setEnabled(false)",
    "localStorage.getItem('cv_sound_enabled')",
    "tone(780,.042,0,.012,'square')",
    "tone(840,.075,0,.026,'square')",
    "tone(920,.085,0,.029,'square')",
    "tone(1040,.105,0,.033,'square')",
    "tone(660,.08,0,.025,'triangle')",
    "tone(825,.09,.065,.024,'triangle')",
    "tone(990,.15,.13,.022,'triangle')",
    "navigator.vibrate?.(sec<=3?[35,28,35]:18)",
    "./assets/sounds/cv-workout-complete-v1.mp3",
    "window.CVWorkoutSoundV55={version:'v55'",
]
for item in required:
    if item not in text:
        raise SystemExit(f"sound v55 required contract missing: {item}")

# The original set confirmation remains the single set-complete sound after
# V53 is disabled. 3-2-1 use one stronger note each; they must never be built
# from two overlapping tones because that sounds like a duplicate beep.
for original in [
    "tone(c,523,.065,0,.027,'triangle')",
    "tone(c,659,.07,.045,.025,'triangle')",
    "tone(c,784,.10,.09,.022,'triangle')",
    "if(event.detail?.completed)sfx('confirm')",
]:
    if original not in text:
        raise SystemExit(f"sound v55 original set-confirm contract missing: {original}")

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
    "original set-confirm sound restored v55",
    "single countdown ticks 10-to-4 v55",
    "single emphasized notes 3-2-1 v55",
    "distinct rest-ready chime v55",
    "single sound preference cv_sound_enabled v55",
]:
    if patch not in patches:
        patches.append(patch)
metadata["patches"] = patches
BUILD.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"sha256": sha, "bytes": metadata["bytes"], "patches": metadata["patches"][-5:]}, ensure_ascii=False))
