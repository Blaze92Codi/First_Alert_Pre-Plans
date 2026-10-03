-- Global audit/workflow records are service-only. Organization administrators
-- retain access to records belonging to their own organization.
begin;
drop policy if exists workflow_events_admin_read on public.workflow_events;
create policy workflow_events_admin_read on public.workflow_events
for select to authenticated using (
  organization_id is not null
  and public.has_org_role(organization_id, array['owner','admin']::public.organization_role[])
);
drop policy if exists audit_logs_admin_read on public.audit_logs;
create policy audit_logs_admin_read on public.audit_logs
for select to authenticated using (
  organization_id is not null
  and public.has_org_role(organization_id, array['owner','admin']::public.organization_role[])
);
commit;
