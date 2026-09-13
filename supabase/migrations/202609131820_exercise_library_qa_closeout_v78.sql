-- CV Coach V78 — cierre reproducible de QA de biblioteca
-- Conserva activos los 63 ejercicios aprobados y bloquea únicamente filas aún pendientes.
-- No publica ejercicios, no modifica programas y no depende de UUIDs generados.

begin;

with decisions(slug, note) as (
  values
    ('aperturas-polea', 'V78 QA: imagen reutilizada de Aperturas en peck deck. Variante en polea requiere demostración visual dedicada antes de publicar.'),
    ('curl-femoral-sentado', 'V78 QA: imagen reutilizada de Curl femoral tumbado. La variante sentada requiere demostración visual dedicada antes de publicar.'),
    ('dead-bug', 'V78 QA: imagen reutilizada de Plancha frontal. Dead bug requiere demostración visual dedicada antes de publicar.'),
    ('dominadas-asistidas', 'V78 QA: imagen reutilizada de Jalón al pecho. Dominadas asistidas requiere demostración visual dedicada antes de publicar.'),
    ('triceps-sobre-cabeza-polea', 'V78 QA: imagen reutilizada de Press francés. La variante sobre cabeza con cuerda en polea requiere demostración visual dedicada antes de publicar.'),
    ('farmer-carry', 'V78 QA: imagen reutilizada de Sentadilla más press. Farmer carry requiere demostración visual dedicada antes de publicar.'),
    ('hack-squat', 'V78 QA: imagen reutilizada de Prensa 45°. Hack squat requiere demostración visual dedicada antes de publicar.'),
    ('hip-thrust-barra', 'V78 QA: ejercicio redundante con el Hip Thrust con barra activo (slug hip-thrust) y misma imagen. Mantener una sola versión canónica.'),
    ('jalon-pecho-ancho', 'V78 QA: imagen reutilizada del Jalón al pecho genérico. El agarre ancho requiere demostración visual dedicada antes de publicar.'),
    ('jalon-pecho-neutro', 'V78 QA: imagen reutilizada del Jalón al pecho genérico. El agarre neutro requiere demostración visual dedicada antes de publicar.'),
    ('pallof-press', 'V78 QA: imagen reutilizada de Woodchopper en polea. Pallof press requiere demostración visual dedicada antes de publicar.'),
    ('peso-muerto-rumano-barra', 'V78 QA: variante redundante con el Peso muerto rumano activo, cuyo catálogo ya contempla barra o mancuernas. No publicar duplicado hasta definir necesidad específica.'),
    ('press-banca-barra', 'V78 QA: imagen reutilizada de Press de pecho en máquina. Press banca con barra requiere demostración visual dedicada antes de publicar.'),
    ('press-inclinado-mancuernas', 'V78 QA: ejercicio redundante con el Press inclinado con mancuernas activo (slug press-pecho-mancuernas) y misma imagen. Mantener una sola versión canónica.'),
    ('press-militar-mancuernas', 'V78 QA: imagen reutilizada del Press militar sentado. La variante actual no especifica banco/sentado y requiere imagen dedicada o normalización antes de publicar.'),
    ('puente-gluteos', 'V78 QA: imagen reutilizada de Hip Thrust con barra. Puente de glúteos requiere demostración visual dedicada antes de publicar.'),
    ('remo-pecho-apoyado', 'V78 QA: imagen reutilizada de Remo en máquina. Remo pecho apoyado con mancuernas y banco requiere demostración visual dedicada antes de publicar.'),
    ('remo-polea-sentado', 'V78 QA: ejercicio redundante con el Remo sentado en polea activo (slug remo-sentado-polea) y misma imagen. Mantener una sola versión canónica.'),
    ('sentadilla-barra-alta', 'V78 QA: imagen reutilizada de Sentadilla Goblet. Sentadilla con barra alta requiere demostración visual dedicada antes de publicar.'),
    ('zancada-atras', 'V78 QA: imagen reutilizada de Zancadas caminando. Zancada reversa requiere demostración visual dedicada antes de publicar.')
), reviewer as (
  select id
  from public.profiles
  where role = 'admin'::public.app_role
  order by created_at asc
  limit 1
), targets as (
  select e.id, d.note
  from public.exercises e
  join decisions d on d.slug = e.slug
)
update public.exercise_library_reviews r
set qa_status = 'blocked',
    qa_notes = t.note,
    reviewed_by = coalesce(r.reviewed_by, (select id from reviewer)),
    reviewed_at = coalesce(r.reviewed_at, now()),
    updated_at = now()
from targets t
where r.exercise_id = t.id
  and r.qa_status = 'pending';

update public.exercises e
set active = false,
    updated_at = now()
where e.slug in (
  'aperturas-polea','curl-femoral-sentado','dead-bug','dominadas-asistidas',
  'triceps-sobre-cabeza-polea','farmer-carry','hack-squat','hip-thrust-barra',
  'jalon-pecho-ancho','jalon-pecho-neutro','pallof-press','peso-muerto-rumano-barra',
  'press-banca-barra','press-inclinado-mancuernas','press-militar-mancuernas',
  'puente-gluteos','remo-pecho-apoyado','remo-polea-sentado','sentadilla-barra-alta',
  'zancada-atras'
);

commit;
