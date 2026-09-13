begin;

-- CV Coach V77 · Exercise Library Lote A
-- Staging only: no exercise is activated by this migration.
-- Missing Lote A records are created as active=false and existing staging rows
-- are normalized to the current taxonomy. Activation remains gated by visual + QA.

insert into public.exercises
  (name,slug,primary_muscle,equipment,movement_pattern,difficulty,instructions,default_tempo,default_rest_sec,active,prescription_unit)
values
  ('Press inclinado en máquina','press-inclinado-maquina','pecho','máquina convergente o press inclinado','horizontal_push','beginner','Ajusta el asiento para alinear las empuñaduras con la parte alta del pecho. Mantén escápulas estables y controla el regreso.','3-0-1-0',90,false,'reps'),
  ('Flexiones inclinadas','flexiones-inclinadas','pecho','banco o soporte elevado','horizontal_push','beginner','Apoya las manos en una superficie estable, mantén el cuerpo alineado y acerca el pecho al soporte sin perder control del tronco.','3-0-1-0',60,false,'reps'),
  ('Jalón unilateral en polea','jalon-unilateral-polea','espalda','polea alta','vertical_pull','beginner','Mantén el torso estable y lleva el codo hacia abajo y atrás. Controla el regreso sin elevar el hombro.','2-1-3-0',75,false,'reps'),
  ('Remo T pecho apoyado','remo-t-pecho-apoyado','espalda','máquina remo T o barra T con apoyo','horizontal_pull','intermediate','Mantén el pecho apoyado y tira de las empuñaduras hacia el torso sin despegar el tronco. Regresa con control.','2-1-3-0',90,false,'reps'),
  ('Remo unilateral en polea','remo-unilateral-polea','espalda','polea','horizontal_pull','beginner','Tronco estable y hombro controlado. Lleva el codo hacia atrás sin rotar el cuerpo y vuelve lentamente.','2-1-3-0',75,false,'reps'),
  ('Press de hombros en máquina','press-hombros-maquina','hombros','máquina','vertical_push','beginner','Ajusta el asiento para comenzar con las empuñaduras cerca de la línea de los hombros. Empuja sin arquear la zona lumbar y baja con control.','2-0-3-0',90,false,'reps'),
  ('Elevación lateral unilateral en polea','elevacion-lateral-unilateral-polea','hombros','polea','shoulder_abduction','beginner','Mantén el torso quieto y eleva el brazo lateralmente hasta una amplitud cómoda. Evita impulsar con el cuerpo.','2-1-3-0',60,false,'reps'),
  ('Elevación lateral en máquina','elevacion-lateral-maquina','hombros','máquina','shoulder_abduction','beginner','Alinea los brazos con los apoyos, eleva lateralmente sin encoger hombros y controla el descenso.','2-1-3-0',60,false,'reps'),
  ('Pájaros en polea','pajaros-polea','hombros','polea','horizontal_abduction','beginner','Mantén una ligera flexión de codos y abre los brazos hacia atrás sin encoger los hombros. Controla el retorno.','2-1-3-0',60,false,'reps'),
  ('Curl en polea con barra','curl-polea-barra','bíceps','polea y barra recta o EZ','elbow_flexion','beginner','Mantén los codos cerca del torso. Flexiona sin balancearte y extiende de forma controlada.','2-1-3-0',60,false,'reps'),
  ('Curl inclinado con mancuernas','curl-inclinado-mancuernas','bíceps','mancuernas y banco inclinado','elbow_flexion','intermediate','Apoya la espalda en el banco, deja los brazos caer de forma natural y flexiona sin adelantar los codos.','2-1-3-0',60,false,'reps'),
  ('Curl unilateral en polea','curl-unilateral-polea','bíceps','polea','elbow_flexion','beginner','Mantén hombro y codo estables. Flexiona el codo sin girar el tronco y controla la extensión.','2-1-3-0',60,false,'reps'),
  ('Pressdown de tríceps con barra','pressdown-triceps-barra','tríceps','polea y barra','elbow_extension','beginner','Fija los codos al costado del cuerpo, extiende hasta abajo y vuelve sin mover los hombros.','2-1-3-0',60,false,'reps'),
  ('Extensión unilateral de tríceps en polea','extension-triceps-unilateral-polea','tríceps','polea','elbow_extension','beginner','Mantén el brazo estable y extiende el codo completamente dentro de una amplitud cómoda. Regresa con control.','2-1-3-0',60,false,'reps'),
  ('Sentadilla en Smith','sentadilla-smith','cuádriceps','máquina Smith','squat','intermediate','Coloca los pies en una posición estable, mantén el tronco firme y desciende con las rodillas siguiendo la dirección de los pies.','3-1-1-0',120,false,'reps'),
  ('Prensa horizontal','prensa-horizontal','cuádriceps','prensa horizontal','squat','beginner','Apoya toda la espalda y el pie completo. Flexiona rodillas dentro de una amplitud controlada y empuja sin bloquearlas de forma brusca.','3-1-1-0',120,false,'reps'),
  ('Hip thrust en máquina','hip-thrust-maquina','glúteos','máquina hip thrust','hip_extension','beginner','Ajusta el apoyo sobre la pelvis, mantén el tronco estable y extiende la cadera contrayendo glúteos sin hiperextender la zona lumbar.','2-1-2-1',90,false,'reps'),
  ('Curl femoral unilateral en máquina','curl-femoral-unilateral-maquina','isquiotibiales','máquina','knee_flexion','beginner','Alinea la rodilla con el eje de la máquina. Flexiona una pierna sin despegar la cadera y controla el regreso.','2-1-3-0',75,false,'reps'),
  ('Elevación de pantorrillas sentado','elevacion-pantorrillas-sentado','gemelos','máquina de pantorrillas sentado','plantar_flexion','beginner','Mantén el antepié firme sobre la plataforma, eleva los talones con control y desciende hasta un estiramiento cómodo.','2-1-2-1',60,false,'reps')
on conflict (slug) do nothing;

-- Normalize the nine Lote A candidates that already existed in staging.
update public.exercises set primary_muscle='pecho', equipment='barra y banco', movement_pattern='horizontal_push', updated_at=now()
where slug='press-banca-barra' and active=false;
update public.exercises set primary_muscle='pecho', movement_pattern='horizontal_adduction', updated_at=now()
where slug='aperturas-polea' and active=false;
update public.exercises set primary_muscle='espalda', equipment='polea alta', movement_pattern='vertical_pull', updated_at=now()
where slug='jalon-pecho-neutro' and active=false;
update public.exercises set primary_muscle='espalda', equipment='mancuernas y banco', movement_pattern='horizontal_pull', updated_at=now()
where slug='remo-pecho-apoyado' and active=false;
update public.exercises set name='Extensión de tríceps sobre la cabeza con cuerda', equipment='polea y cuerda', movement_pattern='elbow_extension', updated_at=now()
where slug='triceps-sobre-cabeza-polea' and active=false;
update public.exercises set primary_muscle='cuádriceps', movement_pattern='squat', updated_at=now()
where slug='hack-squat' and active=false;
update public.exercises set name='Zancada reversa', movement_pattern='lunge', updated_at=now()
where slug='zancada-atras' and active=false;
update public.exercises set movement_pattern='hip_extension', updated_at=now()
where slug='puente-gluteos' and active=false;
update public.exercises set movement_pattern='knee_flexion', updated_at=now()
where slug='curl-femoral-sentado' and active=false;

-- Mechanical exposures that are unambiguous in the current constraint catalog.
with exposure(slug,constraint_code,exposure_level,note) as (
  values
    ('press-hombros-maquina','overhead_press','moderate',null),
    ('elevacion-lateral-unilateral-polea','shoulder_abduction','moderate',null),
    ('elevacion-lateral-maquina','shoulder_abduction','moderate',null),
    ('hack-squat','knee_flexion_loaded','moderate',null),
    ('sentadilla-smith','knee_flexion_loaded','moderate',null),
    ('sentadilla-smith','axial_load','moderate',null),
    ('prensa-horizontal','knee_flexion_loaded','moderate',null),
    ('zancada-atras','knee_flexion_loaded','moderate',null),
    ('zancada-atras','knee_unilateral_load','moderate',null),
    ('zancada-atras','high_balance_demand','moderate',null)
)
insert into public.exercise_mechanical_exposures (exercise_id,constraint_code,exposure_level,note)
select e.id,x.constraint_code,x.exposure_level,x.note
from exposure x
join public.exercises e on e.slug=x.slug
where e.active=false
on conflict (exercise_id,constraint_code)
do update set exposure_level=excluded.exposure_level,note=excluded.note;

commit;
