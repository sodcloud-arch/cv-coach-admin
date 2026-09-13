-- CV Coach V77 — Lote A: assets aprobados + activación parcial segura
-- Reproducible e idempotente. Solo activa los 16 ejercicios cuyo asset nuevo pasó QA visual.

with assets(slug, image_path) as (
  values
    ('press-inclinado-maquina', 'https://drive.google.com/uc?export=view&id=1e2grprENCpAUxj-sk8srt9q6RALfl1Wr'),
    ('flexiones-inclinadas', 'https://drive.google.com/uc?export=view&id=1M9MIH-argDKnFqHunsnUpOQq6af8eVuL'),
    ('jalon-unilateral-polea', 'https://drive.google.com/uc?export=view&id=1oQlL8xkkHJgl6WAXkMMzIk_N_OY0h9Hw'),
    ('remo-t-pecho-apoyado', 'https://drive.google.com/uc?export=view&id=1Tcyp-YNjdDsUqxd79a6XkzaKjcF_i_ea'),
    ('remo-unilateral-polea', 'https://drive.google.com/uc?export=view&id=1Kw3sG6czGsIOBPzWP-5e9iHcjYWGsq7B'),
    ('press-hombros-maquina', 'https://drive.google.com/uc?export=view&id=1OoKrhjPJVP52uAq6D2eJomlBbAgRX8lL'),
    ('elevacion-lateral-unilateral-polea', 'https://drive.google.com/uc?export=view&id=1vRCGZsHOI3df3A38Y-sfwc0Osn_F420U'),
    ('elevacion-lateral-maquina', 'https://drive.google.com/uc?export=view&id=1S9sqWbNxBLh6kWP73dFHh4ixdml0Jg_e'),
    ('pajaros-polea', 'https://drive.google.com/uc?export=view&id=1saShhCGisnMzARqe8f36vs4L-2eqbXVC'),
    ('curl-polea-barra', 'https://drive.google.com/uc?export=view&id=1Xkt0sk1Kb_aJxa0Sp_M1LwKuEBQwMJ3K'),
    ('curl-inclinado-mancuernas', 'https://drive.google.com/uc?export=view&id=1MvaLp_X6RB8gYFUPaVccfR83xGNY-bAG'),
    ('curl-unilateral-polea', 'https://drive.google.com/uc?export=view&id=1fLVWsQD-uKEL2Z2qnkIW9E09n9GQ5yuH'),
    ('pressdown-triceps-barra', 'https://drive.google.com/uc?export=view&id=13ML6hTSywiyN7oMxsNc5HNBCKHKcREAe'),
    ('sentadilla-smith', 'https://drive.google.com/uc?export=view&id=1YsCVOELwL-m-1VukpMvZV39ErF3I0OfD'),
    ('hip-thrust-maquina', 'https://drive.google.com/uc?export=view&id=1UvseJryI5-kInhwQHkstzDyxYFcB7lU7'),
    ('elevacion-pantorrillas-sentado', 'https://drive.google.com/uc?export=view&id=1YL8GUWi2fpi8qOSl7uYnfpLlffQCK5SS')
)
update public.exercises e
set image_path = a.image_path,
    active = true,
    updated_at = now()
from assets a
where e.slug = a.slug
  and e.instructions is not null
  and e.default_tempo is not null
  and e.default_rest_sec is not null;

-- Tres assets generados fueron rechazados en QA y deben permanecer bloqueados.
update public.exercises
set active = false,
    image_path = null,
    updated_at = now()
where slug in (
  'extension-triceps-unilateral-polea',
  'prensa-horizontal',
  'curl-femoral-unilateral-maquina'
);
