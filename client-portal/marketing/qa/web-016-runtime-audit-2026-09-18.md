# WEB-016 — Runtime QA audit

Date: 2026-09-18
Branch: `autopilot/web-master-v1`
Scope: WEB only

## Runtime safety

- Working theme: `CV Coach — V3 Refinada` (`gid://shopify/OnlineStoreTheme/162703605993`)
- Role verified via Shopify Admin API: `UNPUBLISHED`
- Theme processing: `false`
- Theme processing failed: `false`
- Published theme: `Horizon` (`gid://shopify/OnlineStoreTheme/162350858473`)
- Published theme role verified: `MAIN`
- No production publish, checkout activation, product creation, payment activation, APP/auth/Supabase/admin change performed in this audit.

## Theme-file inventory QA

Shopify Admin API returned the C.V. theme inventory with no pagination remainder (`hasNextPage=false`). Verified presence of the expected C.V. assets, sections and templates used by WEB-001..WEB-015, including:

- global header/footer and `layout/theme.liquid`
- Home, Training, Nutrition, Integrated, Plans, Start, How, About
- Blog/article, Results, Professionals, FAQ, Contact
- Legal/cookie consent, analytics bridge and custom 404
- C.V. page templates plus blog/article/404 templates

## Baseline guard

WEB-001 remains frozen. Current runtime checksums recorded for regression comparison:

- `sections/cv-home.liquid`: `29a214311c6b8e370b8509f4e475a180`
- `assets/cv-complete-vitality-home.css`: `31956c12144267372b83a2fcdb30e935`

No baseline file was modified in this audit.

## Current QA disposition

WEB-016 remains **IN PROGRESS**. Runtime integrity and theme isolation pass, but the blueprint requires the full visual/functional matrix before closure: 390 px, 430 px, tablet, 1024 px, 1440 px, navigation, CTAs, forms, checkout-safe states, links, accessibility, performance, SEO, visual regression and App Bridge.

Do not promote WEB-016 to DONE until those remaining checks have evidence. Do not activate WEB-017 until WEB-016 satisfies the blueprint definition of done.

## Production blockers preserved

- legal human review
- pricing/products/checkout approval
- payment activation approval
- domain/DNS launch configuration
- final visual acceptance
