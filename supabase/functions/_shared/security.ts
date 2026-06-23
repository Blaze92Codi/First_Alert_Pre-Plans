import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.8';

export type OrgRole = 'owner' | 'admin' | 'editor' | 'responder' | 'viewer';

export function getSupabaseAdmin() {
  const url = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceRoleKey) throw new Error('Supabase service credentials are not configured');
  return createClient(url, serviceRoleKey, { auth: { persistSession: false } });
}

export async function requireUser(req: Request) {
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) throw new Response('Missing Authorization header', { status: 401 });
  const supabase = getSupabaseAdmin();
  const token = authHeader.replace('Bearer ', '');
  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data.user) throw new Response('Invalid session', { status: 401 });
  return { supabase, user: data.user };
}

export async function requireOrgRole(supabase: ReturnType<typeof getSupabaseAdmin>, userId: string, organizationId: string, allowedRoles: OrgRole[]) {
  const { data, error } = await supabase
    .from('organization_members')
    .select('role,status')
    .eq('organization_id', organizationId)
    .eq('user_id', userId)
    .eq('status', 'active')
    .single();

  if (error || !data || !allowedRoles.includes(data.role)) {
    throw new Response('Forbidden', { status: 403 });
  }
}

export async function writeAudit(supabase: ReturnType<typeof getSupabaseAdmin>, params: {
  organization_id: string;
  actor_user_id?: string;
  action: string;
  resource_type: string;
  resource_id?: string;
  request?: Request;
  metadata?: Record<string, unknown>;
}) {
  await supabase.from('audit_logs').insert({
    organization_id: params.organization_id,
    actor_user_id: params.actor_user_id,
    action: params.action,
    resource_type: params.resource_type,
    resource_id: params.resource_id,
    ip_address: params.request?.headers.get('x-forwarded-for')?.split(',')[0]?.trim(),
    user_agent: params.request?.headers.get('user-agent'),
    metadata: params.metadata ?? {},
  });
}

export function json(data: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(data), {
    ...init,
    headers: { 'content-type': 'application/json', ...(init.headers ?? {}) },
  });
}
