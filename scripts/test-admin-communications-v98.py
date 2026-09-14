from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
html=(ROOT/'index.html').read_text(encoding='utf-8')
js=(ROOT/'admin-assets'/'cv-communications-adherence-v98.js').read_text(encoding='utf-8')
sql0=(ROOT/'supabase'/'migrations'/'202609141735_communications_adherence_intelligence_v98.sql').read_text(encoding='utf-8')
sql1=(ROOT/'supabase'/'migrations'/'202609141745_communications_adherence_intelligence_v98_1.sql').read_text(encoding='utf-8')
sql2=(ROOT/'supabase'/'migrations'/'202609141755_communications_adherence_intelligence_v98_2.sql').read_text(encoding='utf-8')
all_sql='\n'.join([sql0,sql1,sql2])

checks={
  'html_marker':'<!-- cv-admin-communications-adherence-v98 -->' in html,
  'html_asset':'/admin-assets/cv-communications-adherence-v98.js' in html,
  'js_ready':'CV_ADMIN_COMMUNICATIONS_ADHERENCE_V98_READY' in js,
  'js_view':"const VIEW='adherence-v98'" in js and '🎯 Adherencia V98' in js,
  'js_rpcs':all(x in js for x in ['get_adherence_communication_center_v98','prepare_adherence_followup_v98','mark_adherence_followup_contacted_v98','refresh_adherence_followup_outcomes_v98']),
  'js_manual_confirmation':'YA LO ENVIÉ · REGISTRAR CONTACTO' in js and 'mensaje ya fue enviado realmente' in js,
  'js_guardrails':all(x in js for x in ['autoenvío OFF','borrador ≠ contacto','quiet hours','abandoned']),
  'sql_table':'private.adherence_followup_events_v98' in all_sql,
  'sql_meaningful_workouts':"ws.status in ('completed','partial')" in sql2,
  'sql_abandoned_guard':"'abandoned_sessions_reset_clock',false" in sql2,
  'sql_quiet_hours':'quiet_hours_start' in sql1 and 'quiet_hours_end' in sql1 and 'quiet_hours_checked' in sql2,
  'sql_future_timestamp_guard':'future_workout_timestamps_excluded' in sql1,
  'sql_outcome_window':"interval '7 days'" in all_sql,
  'sql_learning_gate':"'learning_ready',r.sample_size>=3" in sql0,
  'sql_no_auto_send':"'auto_send',false" in sql0 and "'auto_sent',false" in sql0,
  'sql_draft_not_contact':"'draft_creation_is_not_contact',true" in sql0,
  'sql_manual_contact':'manual_contact_confirmation_required' in sql0 and 'recorded_manual_external_contact' in sql1,
  'sql_safety_suppression':"upper(coalesce(p.risk_level,'GREEN')) <> 'RED'" in sql0,
  'sql_e164_contract':'[1-9][0-9]{7,14}' in sql2 and 'phone_ready' in sql2,
}
failed=[k for k,v in checks.items() if not v]
if failed:
    raise SystemExit('V98 contract failed: '+', '.join(failed))
print('CV_ADMIN_COMMUNICATIONS_ADHERENCE_V98_OK')
