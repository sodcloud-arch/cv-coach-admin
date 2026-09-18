# ASCEND AUTÓNOMO — WEB C.V. Complete Vitality

## Estado
ACTIVO

## Worker
ASCEND AUTÓNOMO — WEB C.V.

## Rama exclusiva
`autopilot/web-complete-vitality-mobile-v1`

## Baseline visual bloqueado
- Desktop v1 aprobado y congelado.
- Referencia maestra: `00_REFERENCIA_MAESTRA_EXACTA_CV_WEB.png`
- Rama de origen: `feat/complete-vitality-landing-v1`
- No alterar Desktop v1 salvo corrección material verificada.

## Misión actual
WEB-001 — Construir y perfeccionar la experiencia MOBILE de C.V. Complete Vitality para 390–430 px sin degradar Desktop v1.

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

## Criterio WEB-001
- 390 px: sin overflow horizontal, texto legible, CTAs accionables.
- 430 px: composición equivalente y estable.
- Header móvil propio.
- Hero móvil diseñado, no desktop encogido.
- Cards apiladas con jerarquía premium.
- Pilares reorganizados.
- Métricas no muestran cifras ficticias.
- Desktop v1 permanece visualmente estable.
- Sin cambios en APP ni producción.

## Salida
Cuando WEB-001 cumpla los criterios:
- congelar Mobile v1;
- abrir siguiente misión WEB solo desde esta rama;
- escalar al usuario únicamente decisiones de marca, negocio o bloqueos compartidos.
