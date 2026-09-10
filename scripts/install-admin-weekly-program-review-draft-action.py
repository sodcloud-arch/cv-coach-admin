from pathlib import Path

path=Path('index.html')
text=path.read_text()

def replace_once(old,new,label):
    global text
    count=text.count(old)
    if count!=1:
        raise SystemExit(f'{label}: expected exactly one anchor, found {count}')
    text=text.replace(old,new,1)

old = '''+(r.coach_notes?'<div class="muted" style="margin-top:7px"><b>Nota coach:</b> '+esc(r.coach_notes)+'</div>':'')+(status==='pending'?'<textarea class="input weeklyProgramReviewNote"'''
new = '''+(r.coach_notes?'<div class="muted" style="margin-top:7px"><b>Nota coach:</b> '+esc(r.coach_notes)+'</div>':'')+((status==='pending'||status==='reviewed')?'<button class="btn primary small weeklyProgramReviewDraft" data-program="'+esc(r.program_id)+'" data-client="'+esc(r.client_id)+'" style="margin-top:10px">PREPARAR AJUSTE</button><div class="muted" style="margin-top:6px">Crea o abre un borrador. El programa activo no cambia hasta publicar una nueva versión.</div>':'')+(status==='pending'?'<textarea class="input weeklyProgramReviewNote"'''
replace_once(old,new,'draft button placement')

old_action = "$$('.weeklyProgramReviewAction').forEach(b=>b.onclick=async()=>{"
new_action = "$$('.weeklyProgramReviewDraft').forEach(b=>b.onclick=()=>confirmCloneVersion(b.dataset.program,b.dataset.client));" + old_action
replace_once(old_action,new_action,'draft action binding')

required=['weeklyProgramReviewDraft','PREPARAR AJUSTE','El programa activo no cambia hasta publicar una nueva versión.','confirmCloneVersion(b.dataset.program,b.dataset.client)']
missing=[x for x in required if x not in text]
if missing:
    raise SystemExit('Missing draft-action markers: '+', '.join(missing))

start=text.index('function weeklyProgramReviewReasonLabel')
end=text.index('async function programs(){',start)
block=text[start:end]
if block.count('weeklyProgramReviewDraft') != 2:
    raise SystemExit('Expected one rendered draft control and one event binding')
if block.count('confirmCloneVersion(b.dataset.program,b.dataset.client)') != 1:
    raise SystemExit('Expected exactly one safe draft handoff')
for forbidden in ["weekly_program_reviews',{method:'POST'","weekly_program_reviews',{method:'PATCH'","weekly_program_reviews',{method:'DELETE'",'SUPABASE_SERVICE_ROLE_KEY','service_role']:
    if forbidden in block:
        raise SystemExit('Unsafe weekly program review draft implementation: '+forbidden)
path.write_text(text)
