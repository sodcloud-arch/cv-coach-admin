from pathlib import Path

path = Path('supabase/functions/generate-ai-program/index.ts')
text = path.read_text(encoding='utf-8')

def replace_once(old, new, label):
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected 1 marker, found {count}')
    text = text.replace(old, new, 1)

old = '''  const weekly = compactRecord(root.latest_weekly_checkin, [
'''
new = '''  const trainingPreferences = compactRecord(root.training_preferences, [
    "muscle_focus",
  ]);
  const weekly = compactRecord(root.latest_weekly_checkin, [
'''
replace_once(old, new, 'training preferences sanitizer')

old = '''    client_training_context: {
      profile,
      onboarding,
      latest_weekly_checkin: weekly,
    },
'''
new = '''    client_training_context: {
      profile,
      onboarding,
      training_preferences: trainingPreferences,
      latest_weekly_checkin: weekly,
    },
'''
replace_once(old, new, 'training preferences output')

old = '''3. Respeta equipamiento, disponibilidad, duración de sesión, experiencia y objetivo cuando estén presentes.
4. Considera dolor/lesiones/limitaciones de forma conservadora.'''
new = '''3. Respeta equipamiento, disponibilidad, duración de sesión, experiencia y objetivo cuando estén presentes.
3A. Si client_training_context.training_preferences.muscle_focus contiene grupos específicos, trátalos como la prioridad muscular VIGENTE: dales énfasis razonable en selección de ejercicios, distribución semanal y volumen, manteniendo equilibrio general, patrones básicos y todas las restricciones. Si contiene full_body, programa un desarrollo equilibrado sin priorizar una región concreta. La prioridad muscular no autoriza ignorar dolor, lesiones, limitaciones, equipamiento ni disponibilidad.
4. Considera dolor/lesiones/limitaciones de forma conservadora.'''
replace_once(old, new, 'training focus prompt')

path.write_text(text, encoding='utf-8')
print('AI training focus context patch applied')
