from pathlib import Path

path = Path('scripts/autopilot-self-review.sh')
text = path.read_text()
start_marker = 'sensitive_scan_text="$(printf \'%s\' "${context_text}" | python3 -c \'\n'
end_marker = '\ngit fetch origin main "${head_ref}"\n'
start = text.find(start_marker)
end = text.find(end_marker, start)
if start < 0 or end < 0:
    raise SystemExit('Sensitivity guard anchors not found')

replacement = r'''sensitive_scan_text="$(printf '%s' "${context_text}" | python3 -c '
import re, sys
s = sys.stdin.read()
# Strip explicit negative/read-only statements before classifying risk.
negative_patterns = [
    r"(?i)\bno\s+hacer\s+(?:insert|patch|delete)(?:\s*/\s*(?:insert|patch|delete))*\b",
    r"(?i)\b(?:read[- ]?only|solo lectura|sin escrituras?|no mutar|no modificar datos)\b",
    r"(?i)\brls\s+select\s+ya\s+existe\b",
    r"(?i)\bvalidaciones?\b[^.;\n]{0,100}\brls\b",
    r"(?i)\b(?:usar\s+)?solo\s+select\s+bajo\s+rls\b",
    r"(?i)\bselect\s+bajo\s+rls\b",
    r"(?i)\bno\s+(?:crear|procesar|ejecutar|realizar|marcar|modificar|actualizar|borrar|eliminar|anular|cancelar)\b[^.;\n]{0,100}\b(?:pagos?|payment|billing|factur(?:a|ación)?|cobros?|refunds?|reembolsos?|charges?|cargos?)\b",
    r"(?i)\b(?:sin|no\s+realizar|no\s+procesar)\s+(?:pagos?|cobros?|refunds?|reembolsos?|charges?|cargos?)\s+reales?\b",
]
for pattern in negative_patterns:
    s = re.sub(pattern, " ", s)
sys.stdout.write(s)
')"

sensitive=false
# Always-sensitive domains: credentials/secrets, access control, destructive data/schema work,
# or irreversible production/security operations.
if grep -Eiq '(password|contraseñ|credential|credencial|api[ _-]?key|delete|borrar|eliminar|drop table|truncate|rls|permission|permiso|service[_-]?role|security|seguridad|migration|migración|production data|datos de producción|github[ _-]?secret|crear.{0,40}(secret|secreto)|modificar.{0,40}(secret|secreto)|rotar.{0,40}(secret|secreto)|eliminar.{0,40}(secret|secreto))' <<<"${sensitive_scan_text}"; then
  sensitive=true
fi

# Financial vocabulary by itself is not sensitive. A read-only payments report, billing table,
# subscription status view, or analytics UI may auto-merge when the independent review rates it LOW.
# Escalate only when financial terms are paired with an operation that can move money or mutate
# payment/billing state.
if grep -Eiq '(payment|pagos?|billing|factur(?:a|ación)?|cobros?|refunds?|reembolsos?|charges?|cargos?|débitos?|debits?)' <<<"${sensitive_scan_text}" \
  && grep -Eiq '(crear|create|registrar|register|procesar|process|ejecutar|execute|realizar|marcar|mark|cobrar|charge|captur|capture|refund|reembols|debit|débito|anular|void|cancelar|cancel|modificar|modify|actualizar|update|patch|post|write|escribir|settle|liquidar)' <<<"${sensitive_scan_text}"; then
  sensitive=true
fi
'''

text = text[:start] + replacement + text[end:]
path.write_text(text)
