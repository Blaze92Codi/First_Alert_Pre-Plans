import OpenAI from 'https://esm.sh/openai@4.104.0';
import { json, requireOrgRole, requireUser, writeAudit } from '../_shared/security.ts';

const responseSchema = {
  name: 'preplan_response_summary',
  strict: true,
  schema: {
    type: 'object',
    additionalProperties: false,
    required: ['incident_summary', 'life_safety_priorities', 'fire_attack_considerations', 'ems_considerations', 'law_enforcement_considerations', 'utility_shutdowns', 'known_hazards', 'recommended_staging', 'confidence', 'review_required'],
    properties: {
      incident_summary: { type: 'string' },
      life_safety_priorities: { type: 'array', items: { type: 'string' } },
      fire_attack_considerations: { type: 'array', items: { type: 'string' } },
      ems_considerations: { type: 'array', items: { type: 'string' } },
      law_enforcement_considerations: { type: 'array', items: { type: 'string' } },
      utility_shutdowns: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['type', 'location', 'instructions'], properties: { type: { type: 'string' }, location: { type: 'string' }, instructions: { type: 'string' } } } },
      known_hazards: { type: 'array', items: { type: 'object', additionalProperties: false, required: ['name', 'severity', 'response_note'], properties: { name: { type: 'string' }, severity: { type: 'string' }, response_note: { type: 'string' } } } },
      recommended_staging: { type: 'array', items: { type: 'string' } },
      confidence: { type: 'number', minimum: 0, maximum: 1 },
      review_required: { type: 'boolean' },
    },
  },
} as const;

Deno.serve(async (req) => {
  try {
    if (req.method !== 'POST') return json({ error: 'Method not allowed' }, { status: 405 });
    const { organization_id, building_id } = await req.json();
    if (!organization_id || !building_id) return json({ error: 'organization_id and building_id are required' }, { status: 400 });

    const { supabase, user } = await requireUser(req);
    await requireOrgRole(supabase, user.id, organization_id, ['owner', 'admin', 'editor', 'responder']);

    const [building, contacts, hazards, utilities] = await Promise.all([
      supabase.from('buildings').select('*').eq('organization_id', organization_id).eq('id', building_id).single(),
      supabase.from('building_contacts').select('*').eq('organization_id', organization_id).eq('building_id', building_id).order('priority'),
      supabase.from('hazards').select('*').eq('organization_id', organization_id).eq('building_id', building_id).eq('active', true),
      supabase.from('utilities').select('*').eq('organization_id', organization_id).eq('building_id', building_id),
    ]);
    if (building.error || !building.data) return json({ error: 'Building not found' }, { status: 404 });

    const promptPayload = { building: building.data, contacts: contacts.data ?? [], hazards: hazards.data ?? [], utilities: utilities.data ?? [] };
    const sourceHash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(promptPayload))).then((hash) => Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, '0')).join(''));

    const openai = new OpenAI({ apiKey: Deno.env.get('OPENAI_API_KEY') });
    const completion = await openai.chat.completions.create({
      model: Deno.env.get('OPENAI_PREPLAN_MODEL') ?? 'gpt-4.1-mini',
      messages: [
        { role: 'system', content: 'Generate concise emergency response pre-plan guidance. Do not invent facts. Mark review_required true for missing or ambiguous critical details.' },
        { role: 'user', content: JSON.stringify(promptPayload) },
      ],
      response_format: { type: 'json_schema', json_schema: responseSchema },
    });

    const summary = JSON.parse(completion.choices[0]?.message?.content ?? '{}');
    const { data, error } = await supabase.from('ai_response_summaries').insert({
      organization_id,
      building_id,
      model: completion.model,
      source_hash: sourceHash,
      summary,
      generated_by: user.id,
    }).select('*').single();
    if (error) throw error;

    await writeAudit(supabase, { organization_id, actor_user_id: user.id, action: 'ai_summary.generated', resource_type: 'building', resource_id: building_id, request: req, metadata: { summary_id: data.id, model: completion.model } });
    return json({ summary: data });
  } catch (error) {
    if (error instanceof Response) return error;
    return json({ error: error instanceof Error ? error.message : 'Unexpected error' }, { status: 500 });
  }
});
