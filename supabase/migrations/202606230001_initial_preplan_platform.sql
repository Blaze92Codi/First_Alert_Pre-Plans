-- First Responder Pre-Plan AI Platform initial schema.
-- Designed for Supabase Postgres with strict organization-scoped RLS.

create extension if not exists "pgcrypto";
create extension if not exists "postgis";

create type public.organization_role as enum ('owner', 'admin', 'editor', 'responder', 'viewer');
create type public.member_status as enum ('invited', 'active', 'suspended');
create type public.hazard_severity as enum ('low', 'medium', 'high', 'critical');
create type public.file_kind as enum ('floor_plan', 'site_photo', 'inspection', 'export', 'other');
create type public.utility_kind as enum ('gas', 'electric', 'water', 'sprinkler', 'alarm', 'solar', 'other');
create type public.workflow_status as enum ('queued', 'sent', 'failed', 'processed');
create type public.review_status as enum ('draft', 'pending_review', 'approved', 'rejected');

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  organization_type text not null,
  jurisdiction text,
  cjis_required boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.organization_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.organization_role not null default 'viewer',
  status public.member_status not null default 'invited',
  invited_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, user_id)
);

create table public.buildings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  name text not null,
  occupancy_type text not null,
  address_line1 text not null,
  address_line2 text,
  city text not null,
  state text not null,
  postal_code text not null,
  country text not null default 'US',
  location geography(point, 4326),
  construction_type text,
  floors_above_grade integer not null default 1 check (floors_above_grade >= 0),
  floors_below_grade integer not null default 0 check (floors_below_grade >= 0),
  square_feet integer check (square_feet is null or square_feet > 0),
  fire_protection_systems jsonb not null default '{}'::jsonb,
  access_notes text,
  responder_notes text,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id),
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.building_contacts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  building_id uuid not null references public.buildings(id) on delete cascade,
  name text not null,
  title text,
  phone text,
  email text,
  priority integer not null default 100,
  after_hours boolean not null default false,
  notes text,
  created_at timestamptz not null default now()
);

create table public.building_access_points (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  building_id uuid not null references public.buildings(id) on delete cascade,
  label text not null,
  access_type text not null,
  location_description text not null,
  coordinates geography(point, 4326),
  knox_box boolean not null default false,
  notes text,
  created_at timestamptz not null default now()
);

create table public.hydrants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  building_id uuid references public.buildings(id) on delete set null,
  identifier text not null,
  location geography(point, 4326) not null,
  flow_gpm integer check (flow_gpm is null or flow_gpm >= 0),
  main_size text,
  notes text,
  created_at timestamptz not null default now()
);

create table public.utilities (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  building_id uuid not null references public.buildings(id) on delete cascade,
  kind public.utility_kind not null,
  label text not null,
  location_description text not null,
  coordinates geography(point, 4326),
  shutdown_instructions text,
  emergency_contact text,
  notes text,
  created_at timestamptz not null default now()
);

create table public.hazards (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  building_id uuid not null references public.buildings(id) on delete cascade,
  name text not null,
  severity public.hazard_severity not null,
  hazard_type text not null,
  location_description text not null,
  coordinates geography(point, 4326),
  response_guidance text not null,
  isolation_distance_feet integer check (isolation_distance_feet is null or isolation_distance_feet >= 0),
  sds_file_id uuid,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.building_files (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  building_id uuid not null references public.buildings(id) on delete cascade,
  kind public.file_kind not null,
  bucket text not null default 'preplan-private',
  object_path text not null,
  display_name text not null,
  content_type text,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  floor_label text,
  metadata jsonb not null default '{}'::jsonb,
  uploaded_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique (bucket, object_path),
  check (object_path like organization_id::text || '/%')
);

alter table public.hazards
  add constraint hazards_sds_file_id_fkey foreign key (sds_file_id) references public.building_files(id) on delete set null;

create table public.ai_response_summaries (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  building_id uuid not null references public.buildings(id) on delete cascade,
  model text not null,
  source_hash text not null,
  summary jsonb not null,
  review_status public.review_status not null default 'pending_review',
  generated_by uuid references auth.users(id),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.pdf_exports (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  building_id uuid not null references public.buildings(id) on delete cascade,
  file_id uuid references public.building_files(id) on delete set null,
  status text not null default 'queued',
  requested_by uuid references auth.users(id),
  error_message text,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create table public.workflow_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  event_name text not null,
  resource_type text not null,
  resource_id uuid,
  payload jsonb not null default '{}'::jsonb,
  payload_hash text not null,
  status public.workflow_status not null default 'queued',
  attempts integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete cascade,
  actor_user_id uuid references auth.users(id),
  action text not null,
  resource_type text not null,
  resource_id uuid,
  ip_address inet,
  user_agent text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.is_org_member(target_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.organization_members om
    where om.organization_id = target_organization_id
      and om.user_id = auth.uid()
      and om.status = 'active'
  );
$$;

create or replace function public.has_org_role(target_organization_id uuid, allowed_roles public.organization_role[])
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.organization_members om
    where om.organization_id = target_organization_id
      and om.user_id = auth.uid()
      and om.status = 'active'
      and om.role = any(allowed_roles)
  );
$$;

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger organizations_touch_updated_at before update on public.organizations for each row execute function public.touch_updated_at();
create trigger organization_members_touch_updated_at before update on public.organization_members for each row execute function public.touch_updated_at();
create trigger buildings_touch_updated_at before update on public.buildings for each row execute function public.touch_updated_at();
create trigger hazards_touch_updated_at before update on public.hazards for each row execute function public.touch_updated_at();

create index organization_members_user_id_idx on public.organization_members(user_id);
create index buildings_organization_id_idx on public.buildings(organization_id);
create index buildings_location_idx on public.buildings using gist(location);
create index hydrants_location_idx on public.hydrants using gist(location);
create index hazards_building_id_idx on public.hazards(building_id);
create index building_files_building_id_idx on public.building_files(building_id);
create index audit_logs_organization_created_idx on public.audit_logs(organization_id, created_at desc);
create index workflow_events_status_idx on public.workflow_events(status, created_at);

alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;
alter table public.buildings enable row level security;
alter table public.building_contacts enable row level security;
alter table public.building_access_points enable row level security;
alter table public.hydrants enable row level security;
alter table public.utilities enable row level security;
alter table public.hazards enable row level security;
alter table public.building_files enable row level security;
alter table public.ai_response_summaries enable row level security;
alter table public.pdf_exports enable row level security;
alter table public.workflow_events enable row level security;
alter table public.audit_logs enable row level security;

create policy organizations_select_member on public.organizations for select using (public.is_org_member(id));
create policy organizations_update_admin on public.organizations for update using (public.has_org_role(id, array['owner','admin']::public.organization_role[]));

create policy organization_members_select_self_or_admin on public.organization_members for select using (
  user_id = auth.uid() or public.has_org_role(organization_id, array['owner','admin']::public.organization_role[])
);
create policy organization_members_manage_admin on public.organization_members for all using (
  public.has_org_role(organization_id, array['owner','admin']::public.organization_role[])
) with check (
  public.has_org_role(organization_id, array['owner','admin']::public.organization_role[])
);

create policy buildings_select_member on public.buildings for select using (public.is_org_member(organization_id));
create policy buildings_write_editor on public.buildings for all using (
  public.has_org_role(organization_id, array['owner','admin','editor']::public.organization_role[])
) with check (
  public.has_org_role(organization_id, array['owner','admin','editor']::public.organization_role[])
);

create policy building_contacts_member_read on public.building_contacts for select using (public.is_org_member(organization_id));
create policy building_contacts_editor_write on public.building_contacts for all using (public.has_org_role(organization_id, array['owner','admin','editor']::public.organization_role[])) with check (public.has_org_role(organization_id, array['owner','admin','editor']::public.organization_role[]));

create policy building_access_points_member_read on public.building_access_points for select using (public.is_org_member(organization_id));
create policy building_access_points_editor_write on public.building_access_points for all using (public.has_org_role(organization_id, array['owner','admin','editor']::public.organization_role[])) with check (public.has_org_role(organization_id, array['owner','admin','editor']::public.organization_role[]));

create policy hydrants_member_read on public.hydrants for select using (public.is_org_member(organization_id));
create policy hydrants_editor_write on public.hydrants for all using (public.has_org_role(organization_id, array['owner','admin','editor']::public.organization_role[])) with check (public.has_org_role(organization_id, array['owner','admin','editor']::public.organization_role[]));

create policy utilities_member_read on public.utilities for select using (public.is_org_member(organization_id));
create policy utilities_editor_write on public.utilities for all using (public.has_org_role(organization_id, array['owner','admin','editor']::public.organization_role[])) with check (public.has_org_role(organization_id, array['owner','admin','editor']::public.organization_role[]));

create policy hazards_member_read on public.hazards for select using (public.is_org_member(organization_id));
create policy hazards_editor_write on public.hazards for all using (public.has_org_role(organization_id, array['owner','admin','editor']::public.organization_role[])) with check (public.has_org_role(organization_id, array['owner','admin','editor']::public.organization_role[]));

create policy building_files_member_read on public.building_files for select using (public.is_org_member(organization_id));
create policy building_files_editor_write on public.building_files for all using (public.has_org_role(organization_id, array['owner','admin','editor']::public.organization_role[])) with check (public.has_org_role(organization_id, array['owner','admin','editor']::public.organization_role[]));

create policy ai_response_summaries_member_read on public.ai_response_summaries for select using (public.is_org_member(organization_id));
create policy ai_response_summaries_responder_write on public.ai_response_summaries for insert with check (public.has_org_role(organization_id, array['owner','admin','editor','responder']::public.organization_role[]));
create policy ai_response_summaries_admin_update on public.ai_response_summaries for update using (public.has_org_role(organization_id, array['owner','admin','editor']::public.organization_role[]));

create policy pdf_exports_member_read on public.pdf_exports for select using (public.is_org_member(organization_id));
create policy pdf_exports_responder_insert on public.pdf_exports for insert with check (public.has_org_role(organization_id, array['owner','admin','editor','responder']::public.organization_role[]));
create policy pdf_exports_service_update on public.pdf_exports for update using (auth.role() = 'service_role');

create policy workflow_events_admin_read on public.workflow_events for select using (organization_id is null or public.has_org_role(organization_id, array['owner','admin']::public.organization_role[]));
create policy workflow_events_service_all on public.workflow_events for all using (auth.role() = 'service_role') with check (auth.role() = 'service_role');

create policy audit_logs_admin_read on public.audit_logs for select using (organization_id is null or public.has_org_role(organization_id, array['owner','admin']::public.organization_role[]));
create policy audit_logs_service_insert on public.audit_logs for insert with check (auth.role() = 'service_role');
