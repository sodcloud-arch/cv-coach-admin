# ASCEND AUTÓNOMO — WEB C.V. Complete Vitality

## Estado
ACTIVO

## Worker
ASCEND AUTÓNOMO — WEB C.V.

## Rama exclusiva
`autopilot/web-master-v1`

## Baseline visual bloqueado
- Desktop v1 aprobado y congelado.
- Referencia maestra: `00_REFERENCIA_MAESTRA_EXACTA_CV_WEB.png`
- Rama de origen: `feat/complete-vitality-landing-v1`
- No alterar Desktop v1 salvo corrección material verificada.

## Misión actual
WEB-010 — Resultados + testimonios structure.

Objetivo:
- construir la landing completa de C.V. Training sobre la arquitectura Shopify ya preparada;
- mantener identidad azul y coherencia con C.V. Complete Vitality;
- implementar Hero → problema → propuesta → personalización → rutina → ejercicios → progresión → seguimiento → app → para quién → cómo comenzar → FAQ → CTA;
- preparar CTAs para el flujo comercial híbrido sin activar pagos reales;
- validar responsive y no introducir regresión en WEB-001.

## Scope permitido
- `client-portal/marketing/**`
- `assets` o recursos exclusivos de marketing que vivan bajo ese scope
- este archivo de control
- workflow de guardia/preview exclusivo de esta rama

## Scope prohibido
- `client-portal/` fuera de `marketing/**`
- `admin/**`
- lógica de aplicación
- Supabase / migraciones / Edge Functions
- auth
- datos de clientes
- rutinas / nutrición / progresión de la app
- producción
- ramas `main`, `feat/v*`, `build/*` y cualquier `autopilot/*` de APP

## Recursos compartidos protegidos
No modificar automáticamente:
- `package.json`
- lockfiles
- `vercel.json` raíz
- variables de entorno
- configuración raíz
- workflows canónicos de APP
- esquema Supabase
- producción Vercel

Si una mejora requiere uno de esos recursos, registrar BLOQUEO y detener esa parte.

## ASCEND PARALLEL LOCK
1. WEB solo escribe en su rama exclusiva.
2. APP y WEB nunca comparten rama de trabajo.
3. WEB no hace merge automático.
4. Todo despliegue de WEB es Preview aislado.
5. No crear una nueva Edge Function por iteración.
6. No borrar funciones o recursos existentes sin confirmar dependencias.
7. SEARCH BEFORE CREATE.
8. Conservar funcionalidades existentes.
9. Revisar después de cada cambio material.
10. Si la revisión detecta defecto, corregir y volver a validar antes de avanzar.

## Loop autónomo
ANALIZAR → CRITICAR → MODIFICAR → VALIDAR → PREVIEW → REVISAR → REPETIR

## Estrategia comercial web aprobada

### Público principal
B2C — personas que buscan mejorar entrenamiento, nutrición, bienestar y progreso mediante C.V. Complete Vitality.

### Público secundario
Profesionales — coaches y nutricionistas. Tendrán una entrada secundaria y arquitectura preparada para futura expansión B2B, sin competir visualmente con la propuesta B2C principal.

### Regla de jerarquía
- Homepage, navegación principal y CTAs priorizan B2C.
- Profesionales se accede desde contenido secundario y/o footer.
- No introducir una navegación B2B con el mismo peso que Training / Nutrition / Integrated en esta etapa.
- La arquitectura técnica debe quedar preparada para C.V. for Coaches y C.V. for Nutritionists sin rehacer la web.

### Decisión
A — B2C principal + profesionales como entrada secundaria.

## Regla de decisión autónoma aprobada

Cuando existan varias opciones razonables y una recomendación técnica/estratégica clara, ASCEND seguirá automáticamente la recomendación sin pedir confirmación intermedia.

El usuario revisará el resultado completo al final y podrá solicitar cambios.

ASCEND solo debe escalar antes de ejecutar cuando:
- la acción sea irreversible o de alto impacto;
- implique producción, dinero real, pagos o contratos;
- requiera credenciales, aceptación legal o intervención humana obligatoria;
- afecte datos reales de clientes;
- toque recursos compartidos/protegidos fuera del scope WEB;
- exista una decisión de marca sin una opción claramente superior;
- pueda degradar una funcionalidad ya aprobada y no exista rollback seguro.

En decisiones ordinarias de arquitectura, UX, conversión, contenido estructural, responsive, SEO técnico, navegación, jerarquía, componentes y organización de Shopify, ASCEND debe elegir la alternativa recomendada, implementarla, revisarla y continuar.

## Flujo de conversión aprobado

### Decisión
C — Modelo híbrido.

### Regla
- Productos/planes estándar que puedan automatizarse: compra directa mediante Shopify.
- Servicios personalizados o premium que requieran evaluación profesional: evaluación previa, luego contratación.
- C.V. Integrated premium puede mantener evaluación previa mientras exista intervención humana relevante.
- El sistema debe quedar preparado para convertir progresivamente flujos premium a compra directa sin rehacer la arquitectura.

### Objetivo
Maximizar automatización y conversión sin eliminar revisión humana donde aporte seguridad, personalización o control de calidad.

## WEB-001 — Cierre

Estado: COMPLETADO / BASELINE CONGELADO.

### Baseline Mobile v1
- Rango objetivo validado: 390–430 px.
- Header móvil propio.
- Hero móvil propio.
- Cards apiladas y optimizadas para touch.
- Pilares responsive.
- Cierre de marca sin métricas ficticias.
- Menú con cierre, Escape y bloqueo de scroll.
- Safe areas y focus visible.
- CTAs con targets táctiles adecuados.

### Baseline Desktop v1
- Congelado.
- La validación posterior a Mobile v1 confirmó MATCH = TRUE contra el screenshot de referencia congelado.

### Regla de regresión
Cualquier misión posterior que cambie Homepage debe volver a validar Mobile 390/430 y Desktop 1024 antes de aprobarse.

## WEB-002 — Cierre

Estado: COMPLETADO / ARQUITECTURA SHOPIFY PREPARADA.

### Auditoría Shopify verificada
- Theme publicado `Horizon`: intacto; no se modificó producción.
- Theme de desarrollo `CV Coach — V3 Refinada`: UNPUBLISHED, estable y sin processing failure.
- Assets C.V. existentes en V3: identidad, estilos base, JS, estabilidad y `cv-pages-v1.css`.
- Section reutilizable `cv-page-shell.liquid` presente.
- Templates presentes para Training, Nutrition, Integrated, About, Plans, How, Results, Professionals, FAQ y Start.
- 10 páginas C.V. existen, todas `isPublished=false`, con templateSuffix correcto.
- Menús aislados `C.V. Main` y `C.V. Footer` existen sin reemplazar navegación de producción.
- Blog `C.V. Journal` existe con handle `cv`.

### Rutas preparadas
- `/pages/training`
- `/pages/nutrition`
- `/pages/integrated`
- `/pages/sobre-cv`
- `/pages/planes`
- `/pages/como-funciona`
- `/pages/resultados`
- `/pages/profesionales`
- `/pages/faq`
- `/pages/comienza-hoy`
- `/blogs/cv`

### Seguridad
- Sin publicación de theme.
- Sin publicación de páginas.
- Sin pagos reales.
- Sin cambios en APP/auth/Supabase/admin.
- Rollback: theme V3 y recursos C.V. permanecen aislados de producción.

### Siguiente dependencia
WEB-003 debe desarrollar C.V. Training usando la estructura preparada y conservar el baseline WEB-001.


## WEB-003 — Cierre

Estado: COMPLETADO / C.V. TRAINING v1 PREPARADO EN SHOPIFY DEV.

### Implementado
- Hero propio con identidad azul C.V. Training.
- Problema → propuesta → personalización → rutina → ejercicios → progresión → seguimiento.
- Integración visual y narrativa con C.V. Coach.
- Sección ¿Para quién es?.
- FAQ específica.
- CTA final + comparación de soluciones.
- Responsive desktop/mobile con refinamiento específico para 390 px.
- Focus visible y consideración prefers-reduced-motion.

### QA verificado
- Theme CV Coach — V3 Refinada: UNPUBLISHED, estable, processing=false, processingFailed=false.
- Página Training: isPublished=false, template cv-training.
- Sin precios publicados.
- Sin métricas inventadas.
- Checksums de cv-home.liquid y cv-complete-vitality-home.css sin cambios durante WEB-003.
- Sin modificaciones en APP, Supabase, auth, admin o theme publicado.

### Dependencia siguiente
WEB-004 debe auditar y completar C.V. Nutrition con identidad verde, recorrido propio y el mismo estándar de conversión/QA.


## WEB-004 — Cierre

Estado: COMPLETADO / C.V. NUTRITION v1 PREPARADO EN SHOPIFY DEV.

### Implementado
- Hero propio con identidad verde C.V. Nutrition.
- Problema → evaluación → estrategia → planificación flexible → educación → hábitos/adherencia → seguimiento.
- Integración explícita con C.V. Integrated cuando Training y Nutrition necesitan compartir contexto.
- Mensajería responsable: el registro nutricional se presenta como arquitectura preparada y no como función activa no verificada.
- Sección ¿Para quién es? con derivación a profesional sanitario cuando exista necesidad clínica.
- FAQ específica, CTA final y comparación de soluciones.
- Responsive desktop/mobile, focus visible y consideración prefers-reduced-motion.

### QA verificado
- Theme CV Coach — V3 Refinada: UNPUBLISHED, estable, processing=false, processingFailed=false.
- Página Nutrition: isPublished=false, template cv-nutrition.
- Flujo requerido del blueprint presente en contenido/section.
- Sin precios publicados, sin métricas inventadas y sin promesas de resultados.
- Checksums de cv-home.liquid y cv-complete-vitality-home.css permanecen sin cambios.
- Sin modificaciones en APP, Supabase, auth, admin o theme publicado.

### Dependencia siguiente
WEB-005 debe auditar y completar C.V. Integrated con identidad dorada, problema de sistemas aislados, decisiones conectadas, seguimiento conjunto, experiencia C.V. Coach y flujo premium de evaluación previa.


## WEB-005 — Cierre

Estado: COMPLETADO / C.V. INTEGRATED v1 PREPARADO EN SHOPIFY DEV.

### Implementado
- Hero propio con identidad dorada C.V. Integrated.
- Problema de sistemas aislados → propuesta integrada → Training + Nutrition → decisiones conectadas → seguimiento conjunto.
- Experiencia C.V. Coach presentada por módulos, sin afirmar funciones no habilitadas.
- Flujo premium explícito: elección → evaluación previa → modalidad → onboarding.
- FAQ específica, CTA de evaluación y comparación de soluciones.
- Responsive desktop/mobile, focus visible y consideración prefers-reduced-motion.

### QA verificado
- Theme CV Coach — V3 Refinada: UNPUBLISHED, estable, processing=false, processingFailed=false.
- Página Integrated: isPublished=false, template cv-integrated.
- Todos los bloques requeridos por WEB-005 presentes en página/section.
- Sin precios reales, métricas inventadas ni promesas de resultados.
- Homepage congelada sin cambios en checksums de cv-home.liquid y cv-complete-vitality-home.css.
- Sin modificaciones en APP, Supabase, auth, admin o theme publicado.

### Dependencia siguiente
WEB-006 debe completar Planes + conversión: comparador claro, selector de ruta, modelo híbrido, estados de CTA y preparación técnica para productos/checkout sin activar cobros ni inventar precios.


## WEB-006 — Cierre

Estado: COMPLETADO / PLANES + CONVERSIÓN v1 PREPARADOS EN SHOPIFY DEV.

### Implementado
- Comparador Training / Nutrition / Integrated con identidad de color por solución.
- CTAs separados: elegir ruta y ver detalles.
- Selector C.V. con preselección por query `route`, estado `aria-pressed` y resultado `aria-live`.
- Modelo híbrido documentado en interfaz: compra directa para componentes estandarizables y evaluación previa para servicios personalizados/premium.
- Flujo posterior: elegir → confirmar modalidad → onboarding/C.V. Coach.
- Sin checkout activo; arquitectura preparada para conectarlo cuando existan precios/productos aprobados.
- Focus visible y consideración prefers-reduced-motion.

### QA verificado
- Planes y Comienza hoy permanecen `isPublished=false` con templates correctos.
- Theme de trabajo sigue UNPUBLISHED, estable y sin processing failure.
- Selector contiene las tres rutas y soporta prefill por URL.
- No existen llamadas activas a checkout, cart/add, productId o variantId en el selector.
- Sin precios, métricas o claims inventados.
- Homepage congelada sin cambios en checksums.

### Dependencia siguiente
WEB-007 debe auditar Cómo funciona y reforzar el puente Shopify → C.V. Coach, separando con claridad educación/conversión de ejecución/autenticación.


## WEB-007 — Cierre

Estado: COMPLETADO / CÓMO FUNCIONA + APP BRIDGE v1 PREPARADO EN SHOPIFY DEV.

### Implementado
- Recorrido completo Descubrir → Elegir → Contratar → Onboarding → Ejecutar → Medir → Ajustar → Progresar.
- Frontera explícita Shopify vs C.V. Coach: antes de contratar / después del onboarding.
- Puente real de login hacia C.V. Coach App.
- Mensajería modular: solo se consideran activas las funciones realmente habilitadas.
- CTAs de Comienza hoy y acceso existente.
- Responsive y focus visible.

### QA verificado
- Página Cómo funciona permanece `isPublished=false`, template `cv-how`.
- Theme de trabajo sigue UNPUBLISHED, estable y sin processing failure.
- Ocho pasos, frontera Shopify/App y login bridge presentes.
- Estructura HTML section/div balanceada.
- Homepage congelada sin cambios en checksums.

### Dependencia siguiente
WEB-008 debe completar Sobre C.V. con propósito, principios, arquitectura del ecosistema, visión de marca y CTA hacia el recorrido principal.


## WEB-008 — Cierre

Estado: COMPLETADO / SOBRE C.V. v1 PREPARADO EN SHOPIFY DEV.

### Implementado
- Hero Complete Vitality + A Higher Standard.
- Principios: Disciplina, Progreso, Libertad e Integración.
- Arquitectura explícita C.V. Training / Nutrition / Integrated / Coach.
- Propósito: medir antes de asumir, automatizar sin perder criterio y construir para evolucionar.
- Visión de marca y CTA hacia Comienza hoy / Cómo funciona.

### QA verificado
- Página Sobre C.V. permanece `isPublished=false`, template `cv-about`.
- Theme UNPUBLISHED estable, sin processing failure.
- Propósito, principios, arquitectura y visión presentes.
- Estructura HTML balanceada.
- Homepage congelada sin cambios en checksums.

### Dependencia siguiente
WEB-009 debe consolidar C.V. Journal + template de artículo, categorías editoriales y al menos un artículo borrador revisable sin publicar contenido automáticamente.


## WEB-009 — Cierre

Estado: COMPLETADO / C.V. JOURNAL + ARTICLE TEMPLATE v1 PREPARADOS EN SHOPIFY DEV.

### Implementado
- Hub C.V. Journal con temas editoriales Training, Nutrition, Integrated, Progreso, Hábitos y Sistema C.V.
- Estándar editorial visible: separar evidencia de opinión, no prometer resultados y actualizar contenido cuando corresponda.
- Template de artículo con navegación de regreso y CTA hacia C.V.
- Tres artículos en borrador: Complete Vitality, progresión medible y adherencia sostenible.
- Comentarios cerrados en esta etapa.

### QA verificado
- Blog `cv` usa template `cv` y permanece dentro del theme de desarrollo.
- Los 3 artículos están `isPublished=false` y usan template `cv`.
- Ningún artículo fue publicado automáticamente.
- Homepage congelada sin cambios en checksums.

### Dependencia siguiente
WEB-010 debe construir Resultados + testimonios como estructura segura para evidencia real, sin inventar métricas, transformaciones ni reseñas.
