import { json, getSupabaseAdmin } from '../_shared/security.ts';

async function hmac(secret: string, body: string) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(body));
  return Array.from(new Uint8Array(signature)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async (req) => {
  try {
    if (req.method !== 'POST') return json({ error: 'Method not allowed' }, { status: 405 });
    const webhookUrl = Deno.env.get('N8N_WEBHOOK_URL');
    const webhookSecret = Deno.env.get('N8N_WEBHOOK_SECRET');
    const dispatchSecret = Deno.env.get('PLATFORM_DISPATCH_SECRET');
    if (!webhookUrl || !webhookSecret || !dispatchSecret) return json({ error: 'Workflow dispatch is not configured' }, { status: 500 });
    if (req.headers.get('x-platform-dispatch-secret') !== dispatchSecret) return json({ error: 'Forbidden' }, { status: 403 });

    const payload = await req.json();
    const body = JSON.stringify({ ...payload, dispatched_at: new Date().toISOString() });
    const signature = await hmac(webhookSecret, body);
    const response = await fetch(webhookUrl, { method: 'POST', headers: { 'content-type': 'application/json', 'x-preplan-signature': signature }, body });

    const supabase = getSupabaseAdmin();
    await supabase.from('workflow_events').insert({
      organization_id: payload.organization_id ?? null,
      event_name: payload.event_name,
      resource_type: payload.resource_type,
      resource_id: payload.resource_id ?? null,
      payload,
      payload_hash: await hmac(webhookSecret, JSON.stringify(payload)),
      status: response.ok ? 'sent' : 'failed',
      attempts: 1,
      last_error: response.ok ? null : await response.text(),
      processed_at: response.ok ? new Date().toISOString() : null,
    });

    return json({ delivered: response.ok }, { status: response.ok ? 202 : 502 });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : 'Unexpected error' }, { status: 500 });
  }
});
