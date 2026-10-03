import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { PGlite } from '@electric-sql/pglite';
test('audit and workflow reads deny anonymous/global/cross-organization records', async () => {
 const db = new PGlite();
 await db.exec(`create role anon; create role authenticated;
 create type public.organization_role as enum ('owner','admin');
 create function public.has_org_role(uuid, public.organization_role[]) returns boolean
 language sql stable as $$ select $1::text = current_setting('test.org', true) $$;
 create table public.audit_logs (organization_id uuid);
 create table public.workflow_events (organization_id uuid);
 alter table public.audit_logs enable row level security;
 alter table public.workflow_events enable row level security;
 grant select on public.audit_logs, public.workflow_events to anon, authenticated;
 insert into public.audit_logs values (null), ('00000000-0000-0000-0000-000000000001'), ('00000000-0000-0000-0000-000000000002');
 insert into public.workflow_events select * from public.audit_logs;`);
 const sql = fs.readFileSync('supabase/migrations/202610030001_scope_audit_reads.sql','utf8');
 await db.exec(sql); await db.exec(sql);
 await db.exec("set test.org = '00000000-0000-0000-0000-000000000001'; set role authenticated;");
 for (const table of ['audit_logs','workflow_events']) {
  const result = await db.query('select * from public.' + table);
  assert.deepEqual(result.rows, [{organization_id: '00000000-0000-0000-0000-000000000001'}]);
 }
 await db.exec('reset role; set role anon;');
 for (const table of ['audit_logs','workflow_events']) assert.equal((await db.query('select * from public.'+table)).rows.length, 0);
 await db.close();
});
