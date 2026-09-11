# CV Coach — Propuesta de expansión de biblioteca V1

## Estado actual auditado
CV Coach tiene **47 ejercicios activos**.

Distribución por músculo primario:
- espalda: 8
- core: 7
- piernas: 7
- hombros: 6
- pecho: 5
- bíceps: 4
- glúteos: 4
- tríceps: 3
- isquiotibiales: 2
- gemelos: 1

La prioridad no es inflar el catálogo: es aumentar cobertura de patrones, equipamientos, niveles de estabilidad, regresiones y alternativas para que el motor pueda sustituir ejercicios sin perder el objetivo del programa.

## Objetivo recomendado
Primera meta: **100 ejercicios activos** mediante 53 incorporaciones únicas, en dos lotes. Todos los ejercicios nuevos nacen `active=false` y solo se activan después de QA técnico, mecánico y visual.

## Lote A — Base prioritaria: +28 (47 → 75)

### Pecho — 4
1. Press banca con barra
2. Press inclinado en máquina
3. Aperturas en polea
4. Flexiones inclinadas

### Espalda — 5
5. Jalón al pecho agarre neutro
6. Jalón unilateral en polea
7. Remo con mancuernas pecho apoyado
8. Remo T pecho apoyado
9. Remo unilateral en polea

### Hombros — 4
10. Press de hombros en máquina
11. Elevación lateral unilateral en polea
12. Elevación lateral en máquina
13. Pájaros en polea

### Bíceps — 3
14. Curl en polea con barra
15. Curl inclinado con mancuernas
16. Curl unilateral en polea

### Tríceps — 3
17. Extensión de tríceps sobre la cabeza con cuerda
18. Pressdown de tríceps con barra
19. Extensión unilateral de tríceps en polea

### Piernas / cuádriceps — 4
20. Hack squat
21. Sentadilla en Smith
22. Prensa horizontal
23. Zancada reversa

### Glúteos — 2
24. Glute bridge
25. Hip thrust en máquina

### Isquiotibiales — 2
26. Curl femoral sentado
27. Curl femoral unilateral en máquina

### Gemelos — 1
28. Elevación de pantorrillas sentado

## Lote B — Cobertura y adaptaciones: +25 (75 → 100)

### Pecho — 1
29. Press convergente en máquina

### Espalda — 2
30. Dominada supina asistida
31. Pullover en máquina

### Hombros — 1
32. Y-raise en polea

### Bíceps — 1
33. Curl bayesiano en polea

### Tríceps — 1
34. Press cerrado en máquina

### Piernas / cuádriceps — 2
35. Split squat asistido
36. Wall sit

### Glúteos — 2
37. Abducción de cadera en polea
38. Extensión de cadera a 45°

### Isquiotibiales — 2
39. Nordic curl asistido
40. Peso muerto rumano unilateral

### Gemelos / tibial — 3
41. Elevación de pantorrillas en prensa
42. Elevación de pantorrilla unilateral de pie
43. Tibialis raise

### Aductores — 2
44. Aducción de cadera en máquina
45. Copenhagen plank regresado

### Core — 4
46. Bird dog
47. Pallof press
48. Plancha lateral
49. Reverse crunch

### Conditioning / trabajo por tiempo — 4
50. Remo en ergómetro
51. Elíptica
52. Air bike
53. Farmer carry

## Estándar obligatorio por ejercicio nuevo
Cada ejercicio debe incluir antes de activarse:
1. Nombre y slug únicos.
2. Músculo primario y tags secundarios.
3. Patrón de movimiento normalizado.
4. Equipamiento normalizado.
5. Dificultad.
6. Unidad `reps` o `seconds` correcta.
7. Tempo y descanso por defecto coherentes.
8. Instrucciones técnicas breves orientadas al cliente.
9. Exposiciones mecánicas estructuradas en `exercise_mechanical_exposures`.
10. Imagen CV Coach horizontal de dos fases y, cuando corresponda, video.
11. Revisión de duplicados, sinónimos y variantes que no aporten cobertura real.
12. QA de visualización móvil y Admin.
13. Estado `active=false` hasta aprobar QA técnico + visual.

## Regla de activación
Un ejercicio incompleto puede existir en staging/inactivo, pero **no puede entrar al catálogo utilizable por la IA ni aparecer como opción publicable** hasta completar el estándar anterior.

## Orden recomendado
Primero producir Lote A porque maximiza sustituciones útiles dentro de musculación tradicional y resuelve los huecos más frecuentes. Después Lote B amplía adaptaciones, core, aductores, pantorrilla/tibial y conditioning. Una tercera etapa futura puede llevar la biblioteca de 100 a 150 ejercicios basándose en uso real: ejercicios solicitados por coaches, sustituciones frecuentes, equipamiento disponible y restricciones que dejen pocos candidatos compatibles.
