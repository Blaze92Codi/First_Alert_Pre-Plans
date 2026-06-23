import { json, requireOrgRole, requireUser, writeAudit } from '../_shared/security.ts';

Deno.serve(async (req) => {
  try {
    if (req.method !== 'POST') return json({ error: 'Method not allowed' }, { status: 405 });
    const { organization_id, building_id } = await req.json();
    if (!organization_id || !building_id) return json({ error: 'organization_id and building_id are required' }, { status: 400 });

    const { supabase, user } = await requireUser(req);
    await requireOrgRole(supabase, user.id, organization_id, ['owner', 'admin', 'editor', 'responder']);

    const { data: building, error: buildingError } = await supabase.from('buildings').select('id,name').eq('organization_id', organization_id).eq('id', building_id).single();
    if (buildingError || !building) return json({ error: 'Building not found' }, { status: 404 });

    const { data: exportJob, error } = await supabase.from('pdf_exports').insert({ organization_id, building_id, requested_by: user.id, status: 'queued' }).select('*').single();
    if (error) throw error;

    await writeAudit(supabase, { organization_id, actor_user_id: user.id, action: 'pdf_export.requested', resource_type: 'building', resource_id: building_id, request: req, metadata: { export_id: exportJob.id, building_name: building.name } });
    return json({ export: exportJob }, { status: 202 });
  } catch (error) {
    if (error instanceof Response) return error;
    return json({ error: error instanceof Error ? error.message : 'Unexpected error' }, { status: 500 });
  }
});
