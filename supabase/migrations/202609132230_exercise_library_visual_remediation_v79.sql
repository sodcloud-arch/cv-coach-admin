-- CV Coach V79 — Exercise Library visual remediation closeout
-- 19 exercises receive dedicated two-phase visual assets, QA approval, and safe activation.
-- The 4 redundant canonical duplicates remain blocked/inactive from V78.
-- Idempotent by slug. No generated exercise UUIDs are hardcoded.

begin;

with media(slug, drive_id) as (
  values
    ('aperturas-polea','17Si9bJvQGnI20i0t0UR9NjjmC0Hum_Hw'),
    ('curl-femoral-sentado','1mUeGIbrTG2i37vZbyWNwWxyf46wNwBn3'),
    ('curl-femoral-unilateral-maquina','1KhxTgJflOFCLdxF0pArms8jvL4hL6-pN'),
    ('dead-bug','1scG2FgRNPraoFVw8LS_5JbQ3rA-xhBQy'),
    ('dominadas-asistidas','1vmf_ZJJZny5S8mXa8yNyzQhiKywQVDY8'),
    ('triceps-sobre-cabeza-polea','1CSjXyKs2zbGySxhFWSOK1yNFt9G8-G1r'),
    ('extension-triceps-unilateral-polea','1uigz0acMaEFEGwSOXOcIQOCcSDLVF9Dw'),
    ('farmer-carry','1BUMqmTZhN6l_9c_C0jUZYKtUhtrwP00I'),
    ('hack-squat','1VbI5KSxR_b9NpuEdWWuKxz4xlDbHhygw'),
    ('jalon-pecho-ancho','1hfJ3BWl5wPy4Ev4D40CvysePnh6ry24U'),
    ('jalon-pecho-neutro','1eJNzDRpWluZx0PvCNC68aOfK1suT0Hg2'),
    ('pallof-press','1xFGcKpC4nEgKDGE20viMzmL0n4ZXK_R3'),
    ('prensa-horizontal','11DR3YzlHMUE4zGDUsCzdMHL5Vr31C0nS'),
    ('press-banca-barra','161Sohw0EDzuk0G3uCwiFjsELJ8PZzp4i'),
    ('press-militar-mancuernas','1r3oTXGymVOSJZ04FZzY6rbkFFrpQQTIC'),
    ('puente-gluteos','1sYnUHDASU-7rCY0wOU7EVaufroYZYsYZ'),
    ('remo-pecho-apoyado','1c0oUKNLpWRhAz3JFzagqrZgQ3bvBn4j_'),
    ('sentadilla-barra-alta','1mJRJ6UY7I9ySDkc372_NDKGoAiAU4DDw'),
    ('zancada-atras','1M8Uxi1frQcavuJm0TXqHEOLfv_dwXhbr')
)
update public.exercises e
set image_path = 'https://drive.google.com/uc?export=view&id=' || m.drive_id,
    updated_at = now()
from media m
where e.slug = m.slug
  and e.image_path is distinct from 'https://drive.google.com/uc?export=view&id=' || m.drive_id;

with targets(slug) as (
  values
    ('aperturas-polea'),('curl-femoral-sentado'),('curl-femoral-unilateral-maquina'),
    ('dead-bug'),('dominadas-asistidas'),('triceps-sobre-cabeza-polea'),
    ('extension-triceps-unilateral-polea'),('farmer-carry'),('hack-squat'),
    ('jalon-pecho-ancho'),('jalon-pecho-neutro'),('pallof-press'),
    ('prensa-horizontal'),('press-banca-barra'),('press-militar-mancuernas'),
    ('puente-gluteos'),('remo-pecho-apoyado'),('sentadilla-barra-alta'),('zancada-atras')
)
update public.exercise_library_reviews r
set qa_status = 'approved',
    qa_notes = 'V79 QA: remediación visual dedicada revisada. La imagen corresponde al ejercicio y su fase inicial/ejecución; ficha técnica completa. Aprobado para catálogo.',
    reviewed_at = coalesce(r.reviewed_at, now()),
    updated_at = now()
from public.exercises e
join targets t on t.slug = e.slug
where r.exercise_id = e.id
  and (r.qa_status is distinct from 'approved'
       or r.qa_notes is distinct from 'V79 QA: remediación visual dedicada revisada. La imagen corresponde al ejercicio y su fase inicial/ejecución; ficha técnica completa. Aprobado para catálogo.');

-- Activation deliberately occurs as a separate statement from image_path updates.
-- This avoids attempting to update the same exercises row twice in one data-modifying CTE statement.
with targets(slug) as (
  values
    ('aperturas-polea'),('curl-femoral-sentado'),('curl-femoral-unilateral-maquina'),
    ('dead-bug'),('dominadas-asistidas'),('triceps-sobre-cabeza-polea'),
    ('extension-triceps-unilateral-polea'),('farmer-carry'),('hack-squat'),
    ('jalon-pecho-ancho'),('jalon-pecho-neutro'),('pallof-press'),
    ('prensa-horizontal'),('press-banca-barra'),('press-militar-mancuernas'),
    ('puente-gluteos'),('remo-pecho-apoyado'),('sentadilla-barra-alta'),('zancada-atras')
)
update public.exercises e
set active = true,
    updated_at = now()
from targets t
join public.exercise_library_reviews r
  on r.exercise_id = (select ee.id from public.exercises ee where ee.slug = t.slug)
where e.slug = t.slug
  and r.qa_status = 'approved'
  and nullif(btrim(e.name),'') is not null
  and nullif(btrim(e.slug),'') is not null
  and nullif(btrim(coalesce(e.primary_muscle,'')),'') is not null
  and nullif(btrim(coalesce(e.equipment,'')),'') is not null
  and nullif(btrim(coalesce(e.movement_pattern,'')),'') is not null
  and e.difficulty is not null
  and nullif(btrim(coalesce(e.instructions,'')),'') is not null
  and nullif(btrim(coalesce(e.default_tempo,'')),'') is not null
  and e.default_rest_sec is not null
  and nullif(btrim(coalesce(e.image_path,'')),'') is not null
  and e.prescription_unit in ('reps','seconds')
  and e.active is distinct from true;

commit;
