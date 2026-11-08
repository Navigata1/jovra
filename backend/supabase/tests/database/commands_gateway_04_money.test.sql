-- Gateway money commands (S79 / B-06): create_quote, accept_quote, review_job as jovra_gateway.
-- T-DB-34 (one key, expired, changed inputs), T-DB-56 (identical work, top-up, owner open cap, environment ceiling),
-- T-DB-59 command half (another project's plan or version), T-DB-60 (plan-by-job twice, in-job revise moves the key),
-- T-DB-61 (no limits row, NULL limit: P0402), the tester flag outside the local stack (§13.3), and the contract's
-- output_spec_sha256 against spec/reference/studio/core.py. User stories 185, 186, 199. The file rolls back.
-- Expected values are independent of the SQL: hashes from core.output_spec_sha256, credits and caps from the rate card
-- rates-v0-inferred worked by hand (2 sources x 100,000,000 bytes, 120 s, 7 days: storage 652 + ingest 3,815 +
-- render 360,000 = 364,467 micro-USD high, cap 455,584; story-2-3 minimum 4 credits).
begin;
select plan(65);

select tests.create_supabase_user('owner');
select tests.create_supabase_user('owner_b');
grant jovra_gateway to postgres;
insert into app_ops.settings (env) values ('local') on conflict (id) do update set env = excluded.env;
insert into app_ops.spend_limits (scope, owner_id, max_open_cap_micro_usd, daily_ceiling_micro_usd)
values ('environment', null, 1000000000000, 50000000);

-- Run one command as jovra_gateway; the result is its jsonb, or {"error": SQLSTATE, "message": ...}.
create function pg_temp.call(p_sql text) returns jsonb language plpgsql as $$
declare
  v_out   jsonb;
  v_text  text;
  v_state text;
  v_msg   text;
begin
  execute 'set local role jovra_gateway';
  execute p_sql into v_text;   -- any scalar result, as text
  execute 'reset role';
  begin
    v_out := v_text::jsonb;     -- a jsonb result
  exception when others then
    v_out := to_jsonb(v_text);  -- a uuid, timestamptz or enum result
  end;
  return coalesce(v_out, '{}'::jsonb);
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  return jsonb_build_object('error', v_state, 'message', v_msg);
end $$;
create temp table t_out (k text primary key, v jsonb not null);
create function pg_temp.keep(p_key text, p_sql text) returns jsonb language plpgsql as $$
declare
  v jsonb := pg_temp.call(p_sql);
begin
  insert into pg_temp.t_out (k, v) values (p_key, v) on conflict (k) do update set v = excluded.v;
  return v;
end $$;
create function pg_temp.got(p_key text, p_field text) returns text language sql as $$
  select v ->> p_field from pg_temp.t_out where k = p_key
$$;
create function pg_temp.uid(p_who text) returns uuid language sql as $$ select tests.get_supabase_uid(p_who) $$;
-- create_quote(actor, project, plan, version, planner, output, sources, retention)
create function pg_temp.quote_sql(p_actor uuid, p_project uuid, p_plan uuid, p_version uuid, p_sources uuid[],
                                  p_retention int default 7, p_output jsonb default null) returns text
language sql as $$
  select format('select app_gateway.create_quote(%L, %L, %L, %L, %L, %L::jsonb, %L::uuid[], %s, gen_random_uuid())',
                p_actor, p_project, p_plan, p_version, 'heuristic',
                coalesce(p_output, '{"fps":{"num":30,"den":1},"width":1920,"height":1080,"aspect":"16:9",
                                    "container":"mp4","videoCodec":"h264","audioCodec":"aac",
                                    "audioSampleRate":48000,"durationTargetSec":120}'::jsonb),
                p_sources, p_retention)
$$;
create function pg_temp.consent(p_retention int default 7) returns jsonb language sql as $$
  select jsonb_build_object('at', '2026-11-08T10:00:00Z', 'consentRecordId', 'consent-s79',
                            'consentTextVersion', 'studio-cloud-consent@1.0.0', 'modelProvider', false,
                            'retentionDays', p_retention, 'textClasses', '[]'::jsonb, 'uploadSelectedSources', true)
$$;
-- accept_quote(actor, quote from t_out, inputs hash as returned, consent, cap as returned, key)
create function pg_temp.accept_sql(p_actor uuid, p_quote_key text, p_key text, p_hash text default null,
                                   p_cap int default null, p_retention int default 7) returns text
language sql as $$
  select format('select app_gateway.accept_quote(%L, %L, decode(%L, ''hex''), %L::jsonb, %s, %L, gen_random_uuid())',
                p_actor, pg_temp.got(p_quote_key, 'quoteId'), coalesce(p_hash, pg_temp.got(p_quote_key, 'inputsSha256')),
                pg_temp.consent(p_retention), coalesce(p_cap, pg_temp.got(p_quote_key, 'capCredits')::int), p_key)
$$;

-- Fixtures (server writes, as postgres): project A of owner with two verified sources in manifest revision 1, plans
-- P1 (version V1) and P2; project B of owner_b with plan PB (version VB) and a verified source; owner was B's coach.
insert into public.projects (id, owner_id, local_project_id, title) values
  ('a7900000-0000-4000-8000-000000000001', pg_temp.uid('owner'), gen_random_uuid(), 'Club final'),
  ('b7900000-0000-4000-8000-000000000001', pg_temp.uid('owner_b'), gen_random_uuid(), 'Other match');
insert into public.project_members (project_id, user_id, role, approved_at, revoked_at) values
  ('b7900000-0000-4000-8000-000000000001', pg_temp.uid('owner'), 'coach', now() - interval '2 days', now() - interval '1 day');
insert into public.camera_sources (id, project_id, slot, local_source_id, state, declared_bytes, declared_sha256) values
  ('5c900000-0000-4000-8000-000000000001', 'a7900000-0000-4000-8000-000000000001', 'primary_baseline',
   gen_random_uuid(), 'verified', 100000000, sha256('s1'::bytea)),
  ('5c900000-0000-4000-8000-000000000002', 'a7900000-0000-4000-8000-000000000001', 'opposite_baseline',
   gen_random_uuid(), 'verified', 100000000, sha256('s2'::bytea)),
  ('5c900000-0000-4000-8000-000000000003', 'a7900000-0000-4000-8000-000000000001', 'near_deuce_corner',
   gen_random_uuid(), 'declared', 100000000, sha256('s3'::bytea)),
  ('5b900000-0000-4000-8000-000000000001', 'b7900000-0000-4000-8000-000000000001', 'primary_baseline',
   gen_random_uuid(), 'verified', 100000000, sha256('sb'::bytea));
insert into public.source_manifests (project_id, manifest, manifest_sha256, created_by_kind) values
  ('a7900000-0000-4000-8000-000000000001',
   '{"sources": [{"sourceId": "5c900000-0000-4000-8000-000000000001"},
                 {"sourceId": "5c900000-0000-4000-8000-000000000002"},
                 {"sourceId": "5c900000-0000-4000-8000-000000000003"}]}', sha256('ma'::bytea), 'render'),
  ('b7900000-0000-4000-8000-000000000001',
   '{"sources": [{"sourceId": "5b900000-0000-4000-8000-000000000001"}]}', sha256('mb'::bytea), 'render');
insert into public.story_plans (id, project_id, profile_id, profile_revision, title) values
  ('9a900000-0000-4000-8000-000000000001', 'a7900000-0000-4000-8000-000000000001', 'coach-cut', 1, 'Plan P1'),
  ('9a900000-0000-4000-8000-000000000002', 'a7900000-0000-4000-8000-000000000001', 'rally-pulse', 1, 'Plan P2'),
  ('9b900000-0000-4000-8000-000000000001', 'b7900000-0000-4000-8000-000000000001', 'coach-cut', 1, 'Plan PB');
insert into public.story_plan_versions (id, story_plan_id, planner_kind, planner_adapter_version, story_plan) values
  ('5a900000-0000-4000-8000-000000000001', '9a900000-0000-4000-8000-000000000001', 'heuristic', 'h1', '{}'),
  ('5b900000-0000-4000-8000-000000000009', '9b900000-0000-4000-8000-000000000001', 'heuristic', 'h1', '{}');

-- create_quote: computed from rows ------------------------------------------------------------------------------------
select is(pg_temp.keep('q1', pg_temp.quote_sql(pg_temp.uid('owner'), 'a7900000-0000-4000-8000-000000000001',
            '9a900000-0000-4000-8000-000000000001', '5a900000-0000-4000-8000-000000000001',
            array['5c900000-0000-4000-8000-000000000002', '5c900000-0000-4000-8000-000000000001']::uuid[])) ->> 'state',
  'open', 'the owner gets an open quote for plan P1 version V1 over two verified sources');
select is((select encode(output_spec_sha256, 'hex') from public.quotes where id = pg_temp.got('q1', 'quoteId')::uuid),
  '9c52b55a2071572977bd14546c722f25221d8b1b8986e02fabad8680a5171032',
  'output_spec_sha256 equals core.output_spec_sha256 (projectId, planRevision 1, output) of the reference');
select is((select row(estimate_low_credits, estimate_high_credits, cap_credits, estimate_high_cost_micro_usd,
                      cap_cost_micro_usd, rates_version, sample)::text
             from public.quotes where id = pg_temp.got('q1', 'quoteId')::uuid),
  row(1, 4, 4, 364467::bigint, 455584::bigint, 'rates-v0-inferred'::text, true)::text,
  'the estimate follows the rate card worked example (story-2-3 minimum 4 credits) and is Sample');
select is((select line_items from public.quotes where id = pg_temp.got('q1', 'quoteId')::uuid),
  '{"sourceCount": 2, "uploadBytes": 200000000, "storageDays": 7, "outputSeconds": 120, "renderMinutesEstimate": 8,
    "plannerTokensEstimate": 0}'::jsonb, 'line items are computed from the verified bytes, angles and output');
select ok((select v from pg_temp.t_out where k = 'q1')
            ?& array['quoteId', 'inputsSha256', 'capCredits', 'estimate', 'lineItems', 'expiresAt']
          and not ((select v from pg_temp.t_out where k = 'q1') ?| array['capCostMicroUsd', 'estimateHighCostMicroUsd']),
  'the quote returned to the owner carries credits and the inputs hash, never the internal micro-USD cost');
select is(pg_temp.got('q1', 'inputsSha256'),
  (select encode(sha256(convert_to(inputs::text, 'UTF8')), 'hex') from public.quotes
    where id = pg_temp.got('q1', 'quoteId')::uuid), 'the inputs hash binds the stored inputs');
select is((select inputs -> 'sourceIds' from public.quotes where id = pg_temp.got('q1', 'quoteId')::uuid),
  '["5c900000-0000-4000-8000-000000000001", "5c900000-0000-4000-8000-000000000002"]'::jsonb,
  'source ids are stored sorted, so the same selection always hashes the same');
select is(pg_temp.call(pg_temp.quote_sql(pg_temp.uid('owner'), 'a7900000-0000-4000-8000-000000000001',
            '9a900000-0000-4000-8000-000000000001', null,
            array['5c900000-0000-4000-8000-000000000003']::uuid[])) ->> 'error', 'P0404',
  'a declared (unverified) source does not resolve through the verified manifest: P0404');
select is(pg_temp.call(pg_temp.quote_sql(pg_temp.uid('owner'), 'a7900000-0000-4000-8000-000000000001',
            '9a900000-0000-4000-8000-000000000001', null, array['5c900000-0000-4000-8000-000000000001']::uuid[],
            7, '{"fps":{"num":30,"den":1},"width":1921,"height":1080,"aspect":"16:9","container":"mp4",
                 "videoCodec":"h264","audioCodec":"aac","audioSampleRate":48000,"durationTargetSec":120}')) ->> 'message',
  'invalid_value:output_spec', 'an odd width is refused as P0422 invalid_value:output_spec');
select is(pg_temp.call(pg_temp.quote_sql(pg_temp.uid('owner'), 'a7900000-0000-4000-8000-000000000001',
            '9a900000-0000-4000-8000-000000000001', null, array['5c900000-0000-4000-8000-000000000001']::uuid[],
            14)) ->> 'message', 'invalid_value:retention_days', 'retention is 1, 7 or 30 days only');

-- T-DB-59 (command half): another project's plan, version or source is P0404, also for a former coach -----------------
select is(pg_temp.call(pg_temp.quote_sql(pg_temp.uid('owner'), 'a7900000-0000-4000-8000-000000000001',
            '9b900000-0000-4000-8000-000000000001', null, array['5c900000-0000-4000-8000-000000000001']::uuid[]))
          ->> 'error', 'P0404', 'T-DB-59: create_quote naming B''s story plan in A is P0404');
select is(pg_temp.call(pg_temp.quote_sql(pg_temp.uid('owner'), 'a7900000-0000-4000-8000-000000000001',
            '9a900000-0000-4000-8000-000000000001', '5b900000-0000-4000-8000-000000000009',
            array['5c900000-0000-4000-8000-000000000001']::uuid[])) ->> 'error', 'P0404',
  'T-DB-59: create_quote naming B''s plan version under A''s plan is P0404');
select is(pg_temp.call(pg_temp.quote_sql(pg_temp.uid('owner'), 'b7900000-0000-4000-8000-000000000001',
            '9b900000-0000-4000-8000-000000000001', null, array['5b900000-0000-4000-8000-000000000001']::uuid[]))
          ->> 'error', 'P0404', 'T-DB-59: the former coach of B cannot quote in B');
select is(pg_temp.call(pg_temp.quote_sql(pg_temp.uid('owner'), 'a7900000-0000-4000-8000-000000000001',
            '9a900000-0000-4000-8000-000000000001', null,
            array['5c900000-0000-4000-8000-000000000001', '5b900000-0000-4000-8000-000000000001']::uuid[]))
          ->> 'error', 'P0404', 'a foreign source id is P0404, identical to an unknown one');

-- T-DB-34: one key, one job and one reservation ---------------------------------------------------------------------
select is(pg_temp.keep('a1', pg_temp.accept_sql(pg_temp.uid('owner'), 'q1', 'key-1')) ->> 'state', 'consented',
  'T-DB-34: accept_quote creates the job in consented');
select is(pg_temp.keep('a1r', pg_temp.accept_sql(pg_temp.uid('owner'), 'q1', 'key-1')) ->> 'replayed', 'true',
  'T-DB-34: a retry with the same key is a replay');
select is(pg_temp.got('a1r', 'jobId'), pg_temp.got('a1', 'jobId'), 'T-DB-34: the replay returns the same job');
select is((select count(*)::int from public.render_jobs where quote_id = pg_temp.got('q1', 'quoteId')::uuid), 1,
  'T-DB-34: one job for the quote');
select is((select count(*)::int from public.usage_reservations
            where initial_quote_id = pg_temp.got('q1', 'quoteId')::uuid and state = 'held'), 1,
  'T-DB-34: one held reservation for the quote');
select is((select count(*)::int from app_ops.spend_commitments
            where owner_id = pg_temp.uid('owner') and kind = 'cap_open' and amount_micro_usd = 455584), 1,
  'T-DB-34: one cap_open commitment for the quote''s cap (story 199: one charge)');
select is(pg_temp.call(pg_temp.accept_sql(pg_temp.uid('owner'), 'q1', 'key-2')) ->> 'message', 'already_accepted',
  'another key for an accepted quote is P0409 already_accepted');
select ok((select r.cap_cost_micro_usd = 455584 and r.reserved_cost_micro_usd = 0 and r.job_id = j.id
                  and j.requested_by = pg_temp.uid('owner') and j.idempotency_key = 'key-1'
                  and j.output_spec ->> 'durationTargetSec' = '120' and q.state = 'accepted'
                  and q.consent ->> 'consentRecordId' = 'consent-s79'
             from public.render_jobs j join public.usage_reservations r on r.id = j.reservation_id
             join public.quotes q on q.id = j.quote_id where j.id = pg_temp.got('a1', 'jobId')::uuid),
  'the hold bounds the job at the quote''s cap; the job records its requester, key, output and the consent');
select is((select count(*)::int from app_ops.job_outbox
            where job_id = pg_temp.got('a1', 'jobId')::uuid and kind = 'start_workflow' and dispatched_at is null
              and payload = jsonb_build_object('jobId', pg_temp.got('a1', 'jobId'))), 1,
  'the start_workflow outbox row (ids only) is written in the same transaction');
select is((select count(*)::int from app_ops.audit_events
            where action = 'quote.accept' and outcome = 'allowed' and target_id = pg_temp.got('q1', 'quoteId')::uuid),
  1, 'the acceptance is audited once');

-- T-DB-34: an expired quote is P0410; changed inputs are P0409 ------------------------------------------------------
select is(pg_temp.keep('q2', pg_temp.quote_sql(pg_temp.uid('owner'), 'a7900000-0000-4000-8000-000000000001',
            '9a900000-0000-4000-8000-000000000002', null,
            array['5c900000-0000-4000-8000-000000000001']::uuid[])) ->> 'state', 'open', 'a plan-by-job quote for P2');
update public.quotes set created_at = now() - interval '2 hours', expires_at = now() - interval '90 minutes'
 where id = pg_temp.got('q2', 'quoteId')::uuid;
select is(pg_temp.call(pg_temp.accept_sql(pg_temp.uid('owner'), 'q2', 'key-q2')) ->> 'error', 'P0410',
  'T-DB-34 / story 185: an expired quote is P0410 and needs a fresh quote');
select is((select state from public.quotes where id = pg_temp.got('q2', 'quoteId')::uuid), 'open',
  'nothing changed: no job, the quote is not auto-accepted');

select is(pg_temp.keep('q3', pg_temp.quote_sql(pg_temp.uid('owner'), 'a7900000-0000-4000-8000-000000000001',
            '9a900000-0000-4000-8000-000000000002', null,
            array['5c900000-0000-4000-8000-000000000002']::uuid[])) ->> 'state', 'open', 'a second P2 quote');
select is(pg_temp.call(pg_temp.accept_sql(pg_temp.uid('owner'), 'q3', 'key-q3', repeat('00', 32))) ->> 'message',
  'inputs_changed', 'T-DB-34: a different inputs hash is P0409 inputs_changed');
select is(pg_temp.call(pg_temp.accept_sql(pg_temp.uid('owner'), 'q3', 'key-q3', null, 99)) ->> 'message',
  'cap_mismatch', 'a cap other than the quoted one is P0409 cap_mismatch');
select is(pg_temp.call(replace(pg_temp.accept_sql(pg_temp.uid('owner'), 'q3', 'key-q3'), '"modelProvider": false',
                               '"modelProvider": true')) ->> 'message',
  'invalid_value:consent', 'consent that does not match the planner choice is P0422');
update public.camera_sources set state = 'rejected', rejected_reason = 'hash_mismatch'
 where id = '5c900000-0000-4000-8000-000000000002';
select is(pg_temp.call(pg_temp.accept_sql(pg_temp.uid('owner'), 'q3', 'key-q3')) ->> 'message', 'inputs_changed',
  'T-DB-34: a source rejected since the quote makes the presented (correct) hash stale: P0409 inputs_changed');
update public.camera_sources set state = 'verified', rejected_reason = null
 where id = '5c900000-0000-4000-8000-000000000002';

-- T-DB-60: plan-by-job work (version null) holds once ------------------------------------------------------------------
select is(pg_temp.keep('a3', pg_temp.accept_sql(pg_temp.uid('owner'), 'q3', 'key-q3')) ->> 'state', 'consented',
  'T-DB-60: the first plan-by-job acceptance for P2 holds');
select is((select encode(output_spec_sha256, 'hex') from public.usage_reservations
            where id = pg_temp.got('a3', 'reservationId')::uuid),
  '77bf1da896bc0d75fb7bb6a094388191cdb939d95c210d7cb11ab703f3965c97',
  'T-DB-60: the plan-by-job hold is keyed with planRevision null (core.output_spec_sha256)');
select is(pg_temp.keep('q4', pg_temp.quote_sql(pg_temp.uid('owner'), 'a7900000-0000-4000-8000-000000000001',
            '9a900000-0000-4000-8000-000000000002', null,
            array['5c900000-0000-4000-8000-000000000001', '5c900000-0000-4000-8000-000000000002']::uuid[]))
          ->> 'state', 'open', 'a quote for identical plan-by-job work of P2 (other sources, same output)');
select is(pg_temp.call(pg_temp.accept_sql(pg_temp.uid('owner'), 'q4', 'key-q4')) ->> 'message', 'duplicate_work',
  'T-DB-60: the second plan-by-job acceptance of the same plan and output is P0409 duplicate_work');
select is((select count(*)::int from public.usage_reservations
            where project_id = 'a7900000-0000-4000-8000-000000000001'
              and story_plan_id = '9a900000-0000-4000-8000-000000000002' and state = 'held'), 1,
  'T-DB-60: one held reservation for P2');

-- T-DB-56: identical work under a second quote while held is P0409 ----------------------------------------------------
select is(pg_temp.keep('q5', pg_temp.quote_sql(pg_temp.uid('owner'), 'a7900000-0000-4000-8000-000000000001',
            '9a900000-0000-4000-8000-000000000001', '5a900000-0000-4000-8000-000000000001',
            array['5c900000-0000-4000-8000-000000000001', '5c900000-0000-4000-8000-000000000002']::uuid[]))
          ->> 'supersedesQuoteId', null, 'a re-quote of held work whose job is running supersedes nothing');
select is(pg_temp.call(pg_temp.accept_sql(pg_temp.uid('owner'), 'q5', 'key-q5')) ->> 'message', 'duplicate_work',
  'T-DB-56: identical work under a second quote while a reservation is held is P0409');

-- T-DB-56: after budget_exceeded, a superseding re-quote tops the same hold up (story 186) ---------------------------
update public.render_jobs set state = 'budget_exceeded' where id = pg_temp.got('a1', 'jobId')::uuid;
select is(pg_temp.keep('q6', pg_temp.quote_sql(pg_temp.uid('owner'), 'a7900000-0000-4000-8000-000000000001',
            '9a900000-0000-4000-8000-000000000001', '5a900000-0000-4000-8000-000000000001',
            array['5c900000-0000-4000-8000-000000000001', '5c900000-0000-4000-8000-000000000002']::uuid[], 30))
          ->> 'supersedesQuoteId', pg_temp.got('q1', 'quoteId'),
  'the re-quote of a job stopped at budget_exceeded supersedes the hold''s quote');
select is(pg_temp.keep('a6', pg_temp.accept_sql(pg_temp.uid('owner'), 'q6', 'key-q6', null, null, 30)) ->> 'toppedUp',
  'true', 'T-DB-56: accepting the superseding quote tops the held reservation up');
select is(pg_temp.got('a6', 'jobId'), pg_temp.got('a1', 'jobId'), 'the top-up returns the existing job, not a second one');
select ok((select r.quote_id = pg_temp.got('q6', 'quoteId')::uuid and r.cap_cost_micro_usd = 458262 and r.state = 'held'
                  and j.state = 'consented'
             from public.usage_reservations r join public.render_jobs j on j.id = r.job_id
            where r.id = pg_temp.got('a1', 'reservationId')::uuid),
  'the hold now carries the new quote and its cap (458,262), and the job is consented again');
select is((select state from public.quotes where id = pg_temp.got('q1', 'quoteId')::uuid), 'superseded',
  'the old quote is superseded');
select is((select array_agg(amount_micro_usd order by id) from app_ops.spend_commitments
            where reservation_id = pg_temp.got('a1', 'reservationId')::uuid),
  array[455584, 2678]::bigint[], 'the ledger holds the open cap and only the top-up delta');

-- T-DB-59 (command half): review_job naming B's plan version ---------------------------------------------------------
update public.render_jobs set state = 'awaiting_review' where id = pg_temp.got('a1', 'jobId')::uuid;
select is(pg_temp.call(format('select app_gateway.review_job(%L, %L, %L, %L, gen_random_uuid())', pg_temp.uid('owner'),
            pg_temp.got('a1', 'jobId'), 'revise', '5b900000-0000-4000-8000-000000000009')) ->> 'error', 'P0404',
  'T-DB-59: review_job naming B''s plan version is P0404');

-- T-DB-60: an in-job revise moves the key of the job and the hold together -----------------------------------------
insert into public.story_plan_versions (id, story_plan_id, planner_kind, planner_adapter_version, story_plan) values
  ('5a900000-0000-4000-8000-000000000002', '9a900000-0000-4000-8000-000000000001', 'user', 'h1', '{}');
select is(pg_temp.call(format('select app_gateway.review_job(%L, %L, %L, %L, gen_random_uuid())', pg_temp.uid('owner'),
            pg_temp.got('a1', 'jobId'), 'revise', '5a900000-0000-4000-8000-000000000002')) ->> 'state', 'planning',
  'T-DB-60: a revision to V2 within the remaining reservation continues the same job');
select ok((select j.story_plan_version_id = '5a900000-0000-4000-8000-000000000002'
                  and r.story_plan_version_id = '5a900000-0000-4000-8000-000000000002'
                  and encode(j.output_spec_sha256, 'hex') = 'fbd0d61a3d2cd99cea83ea402ea5156a5968e6736e6e1de6322a72fd21c081e3'
                  and r.output_spec_sha256 = j.output_spec_sha256
             from public.render_jobs j join public.usage_reservations r on r.id = j.reservation_id
            where j.id = pg_temp.got('a1', 'jobId')::uuid),
  'T-DB-60: the job and its hold both moved to (P1, V2, core.output_spec_sha256 with planRevision 2)');
select is(pg_temp.keep('q7', pg_temp.quote_sql(pg_temp.uid('owner'), 'a7900000-0000-4000-8000-000000000001',
            '9a900000-0000-4000-8000-000000000001', '5a900000-0000-4000-8000-000000000002',
            array['5c900000-0000-4000-8000-000000000001']::uuid[])) ->> 'state', 'open',
  'a quote for the new version V2 and the same output');
select is(pg_temp.call(pg_temp.accept_sql(pg_temp.uid('owner'), 'q7', 'key-q7')) ->> 'message', 'duplicate_work',
  'T-DB-60: the revise moved the reservation key, so the quote for V2 is refused (never a second hold)');
update public.render_jobs set state = 'awaiting_review' where id = pg_temp.got('a1', 'jobId')::uuid;
update public.usage_reservations set reserved_cost_micro_usd = 300000 where id = pg_temp.got('a1', 'reservationId')::uuid;
select is(pg_temp.call(format('select app_gateway.review_job(%L, %L, %L, %L, gen_random_uuid())', pg_temp.uid('owner'),
            pg_temp.got('a1', 'jobId'), 'revise', '5a900000-0000-4000-8000-000000000001')) ->> 'message',
  'requote_required', 'a revision over the remaining reservation is P0409 requote_required');
select is(pg_temp.call(format('select app_gateway.review_job(%L, %L, %L, null, gen_random_uuid())', pg_temp.uid('owner'),
            pg_temp.got('a1', 'jobId'), 'approve')) ->> 'state', 'final_rendering',
  'approving the reviewed preview moves the job to final_rendering');
select is(pg_temp.call(format('select app_gateway.review_job(%L, %L, %L, null, gen_random_uuid())', pg_temp.uid('owner'),
            pg_temp.got('a1', 'jobId'), 'approve')) ->> 'message', 'not_awaiting_review',
  'a job that is not awaiting review cannot be reviewed again');

-- T-DB-56: beyond the owner's open cap or the environment's daily ceiling is P0402 -------------------------------------
select is(pg_temp.keep('q8', pg_temp.quote_sql(pg_temp.uid('owner'), 'a7900000-0000-4000-8000-000000000001',
            '9a900000-0000-4000-8000-000000000002', null,
            array['5c900000-0000-4000-8000-000000000001']::uuid[], 7,
            '{"fps":{"num":30,"den":1},"width":1280,"height":720,"aspect":"16:9","container":"mp4",
              "videoCodec":"h264","audioCodec":"aac","audioSampleRate":48000,"durationTargetSec":120}')) ->> 'state',
  'open', 'a quote for other work (720p) of P2');
insert into app_ops.spend_limits (scope, owner_id, max_open_cap_micro_usd, daily_ceiling_micro_usd)
values ('owner', pg_temp.uid('owner'), 800000, 10000000);
select is(pg_temp.call(pg_temp.accept_sql(pg_temp.uid('owner'), 'q8', 'key-q8')) ->> 'error', 'P0402',
  'T-DB-56 / story 186: held caps plus the new cap beyond the owner''s open cap is P0402');
delete from app_ops.spend_limits where scope = 'owner' and owner_id = pg_temp.uid('owner');
update app_ops.spend_limits set daily_ceiling_micro_usd =
  (select sum(amount_micro_usd) from app_ops.spend_commitments
    where at >= date_trunc('day', now(), 'UTC') and kind in ('cap_open', 'cap_topup')) + 100000
 where scope = 'environment';
select is(pg_temp.call(pg_temp.accept_sql(pg_temp.uid('owner'), 'q8', 'key-q8')) ->> 'error', 'P0402',
  'T-DB-56: today''s commitments plus the new cap beyond the environment ceiling is P0402');
update app_ops.spend_limits set daily_ceiling_micro_usd = 50000000 where scope = 'environment';

-- T-DB-61: fail closed ---------------------------------------------------------------------------------------------
create temp table t_limits as select scope, owner_id, max_open_cap_micro_usd, daily_ceiling_micro_usd
  from app_ops.spend_limits;
delete from app_ops.spend_limits;
select is(pg_temp.call(pg_temp.accept_sql(pg_temp.uid('owner'), 'q8', 'key-q8')) ->> 'error', 'P0402',
  'T-DB-61: with no spend_limits rows at all, accept_quote is P0402');
insert into app_ops.spend_limits (scope, owner_id, max_open_cap_micro_usd, daily_ceiling_micro_usd)
select scope, owner_id, max_open_cap_micro_usd, daily_ceiling_micro_usd from t_limits where scope = 'owner';
select is(pg_temp.call(pg_temp.accept_sql(pg_temp.uid('owner'), 'q8', 'key-q8')) ->> 'error', 'P0402',
  'T-DB-61: the default owner row alone (no environment row) is P0402');
alter table app_ops.spend_limits alter column daily_ceiling_micro_usd drop not null;
alter table app_ops.spend_limits alter column max_open_cap_micro_usd drop not null;
insert into app_ops.spend_limits (scope, owner_id, max_open_cap_micro_usd, daily_ceiling_micro_usd)
values ('environment', null, 1000000000000, null);
select is(pg_temp.call(pg_temp.accept_sql(pg_temp.uid('owner'), 'q8', 'key-q8')) ->> 'error', 'P0402',
  'T-DB-61: a NULL environment ceiling is P0402 (never a NULL comparison that passes)');
update app_ops.spend_limits set daily_ceiling_micro_usd = 50000000 where scope = 'environment';
update app_ops.spend_limits set max_open_cap_micro_usd = null where scope = 'owner' and owner_id is null;
select is(pg_temp.call(pg_temp.accept_sql(pg_temp.uid('owner'), 'q8', 'key-q8')) ->> 'error', 'P0402',
  'T-DB-61: a NULL owner open cap is P0402');
update app_ops.spend_limits set max_open_cap_micro_usd = 5000000 where scope = 'owner' and owner_id is null;
select is(pg_temp.call(pg_temp.accept_sql(pg_temp.uid('owner'), 'q8', 'key-q8')) ->> 'state', 'consented',
  'with both rows present and in budget, the same acceptance succeeds (the refusals above were the limits)');

-- §13.3: outside the local stack only testers may accept ----------------------------------------------------------
select is(pg_temp.keep('q9', pg_temp.quote_sql(pg_temp.uid('owner'), 'a7900000-0000-4000-8000-000000000001',
            '9a900000-0000-4000-8000-000000000002', null,
            array['5c900000-0000-4000-8000-000000000002']::uuid[], 7,
            '{"fps":{"num":25,"den":1},"width":1280,"height":720,"aspect":"16:9","container":"mp4",
              "videoCodec":"h264","audioCodec":"aac","audioSampleRate":48000,"durationTargetSec":60}')) ->> 'state',
  'open', 'a quote for other work (25 fps) of P2');
update app_ops.settings set env = 'test';
select is(pg_temp.call(pg_temp.accept_sql(pg_temp.uid('owner'), 'q9', 'key-q9')) ->> 'error', 'P0401',
  '§13.3: in test, a user without the tester flag cannot accept (P0401)');
delete from app_ops.settings;
select is(pg_temp.call(pg_temp.accept_sql(pg_temp.uid('owner'), 'q9', 'key-q9')) ->> 'error', 'P0401',
  '§13.3: with no environment row the database reads as test (fail closed)');
insert into app_ops.settings (env) values ('test');
update public.profiles set is_tester = true where id = pg_temp.uid('owner');
select is(pg_temp.call(pg_temp.accept_sql(pg_temp.uid('owner'), 'q9', 'key-q9')) ->> 'state', 'consented',
  '§13.3: the operator-set tester may accept in test');

select * from finish();
rollback;
