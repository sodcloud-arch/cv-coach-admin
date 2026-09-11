from pathlib import Path
p=Path('index.html')
s=p.read_text(encoding='utf-8')
old='<h1 class="title">47 ejercicios</h1>'
new='<h1 class="title">${all.length} ejercicios</h1>'
if s.count(old)!=1:
    raise SystemExit(f'expected one library count anchor, got {s.count(old)}')
s=s.replace(old,new,1)
p.write_text(s,encoding='utf-8')
print('LIBRARY_DYNAMIC_COUNT_OK')
