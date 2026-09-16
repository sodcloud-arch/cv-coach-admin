-- CV Coach V103 — structured exercise technique details

alter table public.exercises
  add column if not exists technique_details jsonb not null default '{}'::jsonb;

comment on column public.exercises.technique_details is
  'Structured coaching technique content used by the client exercise detail sheet. Empty object means the exercise falls back to instructions/default tempo.';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'exercises_technique_details_object_v103'
      and conrelid = 'public.exercises'::regclass
  ) then
    alter table public.exercises
      add constraint exercises_technique_details_object_v103
      check (jsonb_typeof(technique_details) = 'object');
  end if;
end
$$;

-- First curated V103 card. Remaining exercises safely fall back to the existing
-- instruction + tempo contract until their structured technique card is curated.
update public.exercises
set technique_details = $json$
{
  "version": 1,
  "quality": "curated",
  "summary": "Tracción vertical para dorsal ancho. El objetivo es mover los codos hacia abajo con el torso estable, no convertir el ejercicio en un remo ni tirar con impulso.",
  "setup": [
    "Ajusta el apoyo de muslos para que las piernas queden firmes sin presión excesiva.",
    "Apoya ambos pies completos en el suelo y mantén pelvis y tronco estables.",
    "Colócate centrado bajo la polea para que el cable descienda sin desviarse hacia un lado."
  ],
  "grip": {
    "type": "Pronado",
    "width": "Ligeramente más ancho que los hombros",
    "arm_spacing": "Usa un ancho que permita llevar los codos hacia abajo sin dolor y mantener los antebrazos aproximadamente alineados con la trayectoria de la barra. No necesitas un agarre extremo.",
    "hands": "Muñecas neutras y agarre firme, sin doblarlas hacia atrás."
  },
  "body_position": {
    "torso": "Pecho alto y ligera inclinación hacia atrás, aproximadamente 5–15° si resulta cómoda. Evita arquear la zona lumbar para ganar recorrido.",
    "shoulders": "Empieza con hombros controlados y lejos de las orejas; inicia el tirón con depresión escapular.",
    "head": "Cabeza neutra y mirada al frente; no adelantes el mentón para encontrar la barra."
  },
  "execution_steps": [
    {"number": 1, "title": "Fija el tronco", "detail": "Antes de tirar, crea tensión abdominal suave y mantén costillas y pelvis estables."},
    {"number": 2, "title": "Inicia con las escápulas", "detail": "Deprime los hombros y después conduce los codos hacia abajo, evitando encogerlos hacia las orejas."},
    {"number": 3, "title": "Lleva la barra al pecho", "detail": "Acerca la barra a la parte alta del pecho mientras los codos continúan descendiendo. No hace falta golpear ni forzar el contacto."},
    {"number": 4, "title": "Pausa y controla", "detail": "Mantén un instante la contracción sin perder la posición del tronco."},
    {"number": 5, "title": "Regresa con control", "detail": "Permite que los brazos se extiendan de forma progresiva hasta recuperar un estiramiento cómodo del dorsal, sin soltar el peso de golpe."}
  ],
  "tempo": {
    "notation": "2-1-2",
    "phases": [
      {"label": "Tirón hacia el pecho", "seconds": 2, "cue": "Codos hacia abajo, sin impulso."},
      {"label": "Pausa abajo", "seconds": 1, "cue": "Mantén el pecho estable y siente la contracción."},
      {"label": "Retorno", "seconds": 2, "cue": "Sube la barra de forma controlada hasta el estiramiento cómodo."}
    ],
    "note": "La prioridad es mantener control y trayectoria. Si tu coach prescribe otro tempo, prevalece el tempo de la sesión."
  },
  "breathing": "Exhala durante el tirón y toma aire durante el retorno, sin perder la tensión del tronco.",
  "range_of_motion": "Empieza con brazos extendidos de forma cómoda y termina cuando la barra llega a la zona alta del pecho sin que los hombros roten hacia delante ni el tronco se balancee.",
  "cues": [
    "Piensa en llevar los codos hacia los bolsillos.",
    "Pecho alto, hombros lejos de las orejas.",
    "La barra baja porque los codos bajan; no porque tires con las manos.",
    "Mantén el mismo ángulo de torso durante toda la repetición."
  ],
  "common_errors": [
    "Usar un agarre excesivamente ancho y recortar el recorrido.",
    "Balancear el torso para mover más peso.",
    "Tirar la barra detrás de la nuca.",
    "Encoger los hombros y perder la depresión escapular.",
    "Soltar el peso rápido durante el retorno."
  ],
  "safety": [
    "No lleves la barra detrás de la nuca.",
    "Si aparece dolor articular en hombro, cuello o codo, reduce carga o rango y revisa la técnica antes de continuar.",
    "La separación exacta de las manos depende de tu antropometría; prioriza una trayectoria cómoda y controlada."
  ],
  "coach_note": "El ancho de agarre no se define por una cifra universal. Para la mayoría, ligeramente más ancho que los hombros es un buen punto de partida y después se ajusta según proporciones corporales y comodidad articular."
}
$json$::jsonb,
    updated_at = now()
where slug = 'jalon-al-pecho';

create or replace function public.get_exercise_technique_v103(p_name text)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'name', e.name,
    'slug', e.slug,
    'primary_muscle', e.primary_muscle,
    'equipment', e.equipment,
    'movement_pattern', e.movement_pattern,
    'difficulty', e.difficulty,
    'instructions', e.instructions,
    'default_tempo', e.default_tempo,
    'default_rest_sec', e.default_rest_sec,
    'image_path', e.image_path,
    'video_path', e.video_path,
    'technique_details', coalesce(e.technique_details, '{}'::jsonb)
  )
  from public.exercises e
  where e.active = true
    and lower(e.name) = lower(btrim(p_name))
  order by case when e.name = btrim(p_name) then 0 else 1 end,
           e.updated_at desc
  limit 1;
$$;

revoke all on function public.get_exercise_technique_v103(text) from public;
grant execute on function public.get_exercise_technique_v103(text) to anon, authenticated;
