alter table public.cv_canary_runs
  alter column baseline type json
  using baseline::json;

comment on column public.cv_canary_runs.baseline is
  'V76 QA baseline stored as ordered JSON so deterministic fingerprint comparison is not affected by jsonb key canonicalization.';
