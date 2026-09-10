from pathlib import Path

path = Path('index.html')
text = path.read_text()

def replace_once(old, new, label):
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one anchor, found {count}')
    text = text.replace(old, new, 1)

replace_once(
    "let suffix=(crypto&&typeof crypto.randomUUID==='function')?crypto.randomUUID():String(Date.now())+'-'+Math.random().toString(36).slice(2);",
    "let suffix=(globalThis.crypto&&typeof globalThis.crypto.randomUUID==='function')?globalThis.crypto.randomUUID():String(Date.now())+'-'+Math.random().toString(36).slice(2);",
    'safe crypto access'
)
replace_once(
    "let effectiveKey=initial?.idempotency_key||communicationNewIdempotency(client.id,messageType);",
    "let effectiveKey=key;",
    'displayed/saved idempotency parity'
)

if "let effectiveKey=key;" not in text:
    raise SystemExit('Idempotency parity marker missing after patch')
if "globalThis.crypto.randomUUID()" not in text:
    raise SystemExit('Safe crypto marker missing after patch')
path.write_text(text)
