from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parent
HTML=ROOT/'stable'/'index.html'
ASSET=ROOT/'assets'/'cv-session-recovery-v107.js'
MARKER='<!-- cv-session-recovery-v107: interrupted-session recovery + reload protection -->'
START='<!-- cv-session-recovery-v107-inline-start -->'
END='<!-- cv-session-recovery-v107-inline-end -->'

for path in [HTML,ASSET]:
    if not path.exists() or path.stat().st_size<500:
        raise SystemExit(f'CV V107 source missing: {path}')

subprocess.run(['node','--check',str(ASSET)],check=True)
asset=ASSET.read_text(encoding='utf-8').strip()
text=HTML.read_text(encoding='utf-8')

# Expose an explicit runtime context bridge from the same lexical scope that
# owns mode/user/workout. V107 must not depend on implicit cross-script lexical access.
context_decl="let mode='demo',user=null,view='home',data=null,workout=null,timerHandle=null;"
context_bridge="window.CVWorkoutContextV107=()=>({mode,user,view,data,workout});"
if context_bridge not in text:
    if context_decl not in text:
        raise SystemExit('V107 workout context declaration missing')
    text=text.replace(context_decl,context_decl+"\\n"+context_bridge,1)
if context_bridge not in text:
    raise SystemExit('V107 workout context bridge injection failed')

# V107 hardens the legacy V35 title-wrapper against V103 ownership.
# V35 used to assume the h3 remained a direct child of .grow. Once V103
# wraps that title, insertBefore(row,title) can throw repeatedly from its
# MutationObserver. Do not mutate if a newer layer already owns the title.
legacy_v35="grow.insertBefore(row,title);row.appendChild(title);"
safe_v35="if(title.parentNode!==grow)return;grow.insertBefore(row,title);row.appendChild(title);"
if legacy_v35 in text:
    text=text.replace(legacy_v35,safe_v35)
if legacy_v35 in text:
    raise SystemExit('V107 failed to harden legacy V35 title insertion')
if safe_v35 not in text:
    raise SystemExit('V107 safe V35 title insertion contract missing')

text=re.sub(rf'\s*{re.escape(START)}.*?{re.escape(END)}\s*','\n',text,flags=re.S)
text=text.replace(MARKER,'')

for token in [
    'CV_FINISH_GUARD_V106_READY',
    'CVFinishGuardV106',
    'CV_GUIDED_SET_LOGGING_V105_READY',
    'cvWorkoutActiveV40',
    'cvSetRow',
]:
    if token not in text:
        raise SystemExit(f'V107 base contract missing: {token}')

for token in [
    'CV_SESSION_RECOVERY_V107_READY',
    "const VERSION='107'",
    'cv_workout_recovery_v107',
    'cvSessionRecoveryV107',
    'REANUDAR SESIÓN',
    'SESIÓN INTERRUMPIDA',
    'beforeunload',
]:
    if token not in asset:
        raise SystemExit(f'V107 asset contract missing: {token}')

payload=f'\n{MARKER}\n{START}\n<script>\n{asset}\n</script>\n{END}\n'
if '</body>' not in text:
    raise SystemExit('V107 body injection target missing')
text=text.replace('</body>',payload+'</body>',1)

for token in [MARKER,START,END,'CV_SESSION_RECOVERY_V107_READY','CVSessionRecoveryV107']:
    if token not in text:
        raise SystemExit(f'V107 client contract missing: {token}')
if text.count(START)!=1 or text.count(END)!=1:
    raise SystemExit('V107 runtime must be injected exactly once')
if text.index('CV_FINISH_GUARD_V106_READY') > text.index('CV_SESSION_RECOVERY_V107_READY'):
    raise SystemExit('V107 must load after V106')

HTML.write_text(text,encoding='utf-8')
print('CV_CLIENT_SESSION_RECOVERY_V107_PATCHED')
