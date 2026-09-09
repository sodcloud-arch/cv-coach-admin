from pathlib import Path

path = Path('scripts/autopilot-self-review.sh')
text = path.read_text()

old = '''context_text="${action_title} ${action_instructions} ${request_payload} ${action_payload}"
sensitive=false
if grep -Eiq '(password|contraseñ|credential|credencial|api[ _-]?key|payment|pago|billing|factur|delete|borrar|eliminar|drop table|rls|permission|permiso|service[_-]?role|security|seguridad|migration|migración|production data|datos de producción|github[ _-]?secret|crear.{0,40}(secret|secreto)|modificar.{0,40}(secret|secreto)|rotar.{0,40}(secret|secreto)|eliminar.{0,40}(secret|secreto))' <<<"${context_text}"; then
  sensitive=true
fi'''

new = '''context_text="${action_title} ${action_instructions} ${request_payload} ${action_payload}"
# Remove explicit negative/read-only safety phrases before sensitivity classification.
# This prevents phrases such as "No hacer INSERT/PATCH/DELETE" or "RLS SELECT ya existe"
# from being mistaken for requested sensitive operations, while positive destructive/access
# instructions remain visible to the guard.
sensitive_scan_text="$(printf '%s' "${context_text}" | python3 -c '
import re, sys
s = sys.stdin.read()
s = re.sub(r"(?i)\\bno\\s+hacer\\s+(?:insert|patch|delete)(?:\\s*/\\s*(?:insert|patch|delete))*\\b", " ", s)
s = re.sub(r"(?i)\\b(?:read[- ]?only|solo lectura|sin escrituras?|no mutar|no modificar datos)\\b", " ", s)
s = re.sub(r"(?i)\\brls\\s+select\\s+ya\\s+existe\\b", " ", s)
s = re.sub(r"(?i)\\bvalidaciones?\\b[^.;\\n]{0,100}\\brls\\b", " ", s)
sys.stdout.write(s)
')"
sensitive=false
if grep -Eiq '(password|contraseñ|credential|credencial|api[ _-]?key|payment|pago|billing|factur|delete|borrar|eliminar|drop table|rls|permission|permiso|service[_-]?role|security|seguridad|migration|migración|production data|datos de producción|github[ _-]?secret|crear.{0,40}(secret|secreto)|modificar.{0,40}(secret|secreto)|rotar.{0,40}(secret|secreto)|eliminar.{0,40}(secret|secreto))' <<<"${sensitive_scan_text}"; then
  sensitive=true
fi'''

if old in text:
    text = text.replace(old, new, 1)
elif 'sensitive_scan_text=' not in text:
    raise SystemExit('sensitive classification block not found')

path.write_text(text)
