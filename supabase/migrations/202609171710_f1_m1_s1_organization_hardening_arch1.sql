-- ARCH-1.0 · F1.M1.S1 hardening after production advisor review.
-- Keeps tenant creation backend-only and covers the owner foreign key.

create index if not exists idx_organizations_owner_user_id
  on public.organizations(owner_user_id);

revoke execute on function public.create_organization(
  text,text,uuid,text,public.organization_status,text,text,text,jsonb,jsonb,jsonb
) from authenticated;

grant execute on function public.create_organization(
  text,text,uuid,text,public.organization_status,text,text,text,jsonb,jsonb,jsonb
) to service_role;
