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
WEB-004 — C.V. Nutrition.

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
