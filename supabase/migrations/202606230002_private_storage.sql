-- Private storage bucket and object policies for pre-plan files.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'preplan-private',
  'preplan-private',
  false,
  104857600,
  array['application/pdf', 'image/png', 'image/jpeg', 'image/webp', 'image/tiff']
)
on conflict (id) do update set public = false;

create policy preplan_private_read_member on storage.objects
for select using (
  bucket_id = 'preplan-private'
  and public.is_org_member((storage.foldername(name))[1]::uuid)
);

create policy preplan_private_write_editor on storage.objects
for insert with check (
  bucket_id = 'preplan-private'
  and public.has_org_role((storage.foldername(name))[1]::uuid, array['owner','admin','editor']::public.organization_role[])
);

create policy preplan_private_update_editor on storage.objects
for update using (
  bucket_id = 'preplan-private'
  and public.has_org_role((storage.foldername(name))[1]::uuid, array['owner','admin','editor']::public.organization_role[])
) with check (
  bucket_id = 'preplan-private'
  and public.has_org_role((storage.foldername(name))[1]::uuid, array['owner','admin','editor']::public.organization_role[])
);

create policy preplan_private_delete_admin on storage.objects
for delete using (
  bucket_id = 'preplan-private'
  and public.has_org_role((storage.foldername(name))[1]::uuid, array['owner','admin']::public.organization_role[])
);
