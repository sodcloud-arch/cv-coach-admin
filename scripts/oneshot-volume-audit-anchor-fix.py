from pathlib import Path

p = Path("scripts/oneshot-volume-audit-v1.py")
s = p.read_text(encoding="utf-8")
start = s.index('comparison_anchor = ')
end = s.index('\n\nif "aiReviewExplanations(generation.explanations)"', start)
replacement = '''comparison_anchor = "+aiReviewWarnings(g.warnings)+aiReviewConflicts(g.conflicts)"
comparison_replacement = "+aiVolumeAuditHtml(g?.explanations?.volume_audit)+aiReviewWarnings(g.warnings)+aiReviewConflicts(g.conflicts)"
admin = replace_once(admin, comparison_anchor, comparison_replacement, "admin comparison volume audit")'''
s = s[:start] + replacement + s[end:]
p.write_text(s, encoding="utf-8")
print("VOLUME_AUDIT_ANCHOR_FIXED")
