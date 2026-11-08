-- T-DB-33 (S79 / B-06): every owner-only gateway command called with an unrelated p_actor is P0404, identical to a
-- missing object, and the gateway's follow-up app_gateway.audit_denial writes one denied audit row for it (a raised
-- command rolls its own rows back, security-model §4.1). Also: audit_denial validates its input and is append only,
-- and none of the refused calls changed anything. User story 244. The file rolls back.
begin;
select plan(37);

select tests.create_supabase_user('owner');
select tests.create_supabase_user('unrelated');
select tests.create_supabase_user('coach', 'coach.pending@example.test');
grant jovra_gateway to postgres;
insert into app_ops.settings (env) values ('local') on conflict (id) do update set env = excluded.env;
insert into app_ops.spend_limits (scope, owner_id, max_open_cap_micro_usd, daily_ceiling_micro_usd)
values ('environment', null, 1000000000000, 50000000);

create function pg_temp.call(p_sql text) returns jsonb language plpgsql as $$
declare
  v_out   jsonb;
  v_text  text;
  v_state text;
  v_msg   text;
begin
  execute 'set local role jovra_gateway';
  execute p_sql into v_text;
  execute 'reset role';
  begin
    v_out := v_text::jsonb;
  exception when others then
    v_out := to_jsonb(v_text);
  end;
  return coalesce(v_out, '{}'::jsonb);
exception when others then
  get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
  return jsonb_build_object('error', v_state, 'message', v_msg);
end $$;
create function pg_temp.uid(p_who text) returns uuid language sql as $$ select tests.get_supabase_uid(p_who) $$;
-- What the gateway does: run the command; on a refusal, record it with audit_denial in a second call.
create function pg_temp.denied(p_action text, p_target_kind text, p_target uuid, p_sql text) returns text
language plpgsql as $$
declare
  v_result jsonb := pg_temp.call(p_sql);
  v_audit  jsonb;
begin
  if v_result ? 'error' then
    v_audit := pg_temp.call(format('select app_gateway.audit_denial(%L, %L, %L, %L, %L, %L, gen_random_uuid())',
                                   'user', pg_temp.uid('unrelated'), p_action, p_target_kind, p_target,
                                   lower(v_result ->> 'message')));
    if v_audit ? 'error' then
      return 'audit_denial failed: ' || (v_audit ->> 'message');
    end if;
  end if;
  return coalesce(v_result ->> 'error', 'no error') || ' ' || coalesce(v_result ->> 'message', '');
end $$;

-- Fixtures: everything the owner has, built through the owner's own commands where the command exists.
insert into public.projects (id, owner_id, local_project_id, title) values
  ('a7930000-0000-4000-8000-000000000001', pg_temp.uid('owner'), gen_random_uuid(), 'Club final');
insert into public.camera_sources (id, project_id, slot, local_source_id, state, declared_bytes, declared_sha256) values
  ('5c930000-0000-4000-8000-000000000001', 'a7930000-0000-4000-8000-000000000001', 'primary_baseline',
   gen_random_uuid(), 'verified', 100000000, sha256('s1'::bytea)),
  ('5c930000-0000-4000-8000-000000000002', 'a7930000-0000-4000-8000-000000000001', 'opposite_baseline',
   gen_random_uuid(), 'declared', 100000000, sha256('s2'::bytea));
insert into public.source_manifests (project_id, manifest, manifest_sha256, created_by_kind) values
  ('a7930000-0000-4000-8000-000000000001', '{"sources": [{"sourceId": "5c930000-0000-4000-8000-000000000001"}]}',
   sha256('m'::bytea), 'render');
insert into public.story_plans (id, project_id, profile_id, profile_revision, title) values
  ('9a930000-0000-4000-8000-000000000001', 'a7930000-0000-4000-8000-000000000001', 'coach-cut', 1, 'Plan'),
  ('9a930000-0000-4000-8000-000000000002', 'a7930000-0000-4000-8000-000000000001', 'rally-pulse', 1, 'Plan 2');
insert into public.story_plan_versions (id, story_plan_id, planner_kind, planner_adapter_version, story_plan) values
  ('5a930000-0000-4000-8000-000000000001', '9a930000-0000-4000-8000-000000000001', 'heuristic', 'h1', '{}');
insert into public.camera_invites (id, project_id, slot, code_hash, created_by, redeem_by, redeemed_at,
                                   device_key_thumbprint) values
  ('17930000-0000-4000-8000-000000000001', 'a7930000-0000-4000-8000-000000000001', 'near_deuce_corner',
   sha256('code'::bytea), pg_temp.uid('owner'), now() + interval '5 minutes', now(), sha256('device'::bytea));
insert into public.artifacts (id, project_id, kind, bucket_class, r2_key, state, verified_at, verification) values
  ('f7930000-0000-4000-8000-000000000001', 'a7930000-0000-4000-8000-000000000001', 'film', 'films', 'films/a793/f1',
   'ready', now(), '{}');
insert into public.lessons (id, owner_id, local_lesson_id, title) values
  ('1e930000-0000-4000-8000-000000000001', pg_temp.uid('owner'), gen_random_uuid(), 'Footwork');
insert into public.lesson_clips (id, lesson_id, project_id, match_start_us, match_end_us) values
  ('c1930000-0000-4000-8000-000000000001', '1e930000-0000-4000-8000-000000000001',
   'a7930000-0000-4000-8000-000000000001', 1000000, 5000000);
insert into public.access_grants (id, kind, project_id, token_hash, invitee_email_hmac, created_by, redeem_by,
                                  grantee_user_id, redeemed_at) values
  ('9c930000-0000-4000-8000-000000000001', 'project_coach', 'a7930000-0000-4000-8000-000000000001',
   sha256('grant'::bytea), sha256('hmac'::bytea), pg_temp.uid('owner'), now() + interval '7 days',
   pg_temp.uid('coach'), now());
insert into public.project_members (project_id, user_id, role, granted_by, grant_id) values
  ('a7930000-0000-4000-8000-000000000001', pg_temp.uid('coach'), 'coach', pg_temp.uid('owner'),
   '9c930000-0000-4000-8000-000000000001');
create temp table t_ids as select
  (pg_temp.call(format('select app_gateway.authorize_upload(%L, %L, %L, %s, sha256(%L::bytea), gen_random_uuid())',
     'user', pg_temp.uid('owner'), '5c930000-0000-4000-8000-000000000002', 100000000, 's2')) ->> 'sessionId')::uuid
    as session_id,
  (pg_temp.call(format('select app_gateway.create_quote(%L, %L, %L, %L, %L, %L::jsonb, %L::uuid[], 7, gen_random_uuid())',
     pg_temp.uid('owner'), 'a7930000-0000-4000-8000-000000000001', '9a930000-0000-4000-8000-000000000001',
     '5a930000-0000-4000-8000-000000000001', 'heuristic',
     '{"fps":{"num":30,"den":1},"width":1920,"height":1080,"aspect":"16:9","container":"mp4","videoCodec":"h264",
       "audioCodec":"aac","audioSampleRate":48000,"durationTargetSec":120}',
     array['5c930000-0000-4000-8000-000000000001'])) ->> 'quoteId')::uuid as quote_id,
  (pg_temp.call(format('select app_gateway.create_quote(%L, %L, %L, null, %L, %L::jsonb, %L::uuid[], 7, gen_random_uuid())',
     pg_temp.uid('owner'), 'a7930000-0000-4000-8000-000000000001', '9a930000-0000-4000-8000-000000000002', 'heuristic',
     '{"fps":{"num":30,"den":1},"width":1920,"height":1080,"aspect":"16:9","container":"mp4","videoCodec":"h264",
       "audioCodec":"aac","audioSampleRate":48000,"durationTargetSec":120}',
     array['5c930000-0000-4000-8000-000000000001'])) ->> 'quoteId')::uuid as quote2_id;
alter table pg_temp.t_ids add column job_id uuid;
update pg_temp.t_ids set job_id = (pg_temp.call(format(
  'select app_gateway.accept_quote(%L, %L, (select inputs_sha256 from public.quotes where id = %L), %L::jsonb, %s, %L, gen_random_uuid())',
  pg_temp.uid('owner'), quote_id, quote_id,
  '{"at":"2026-11-08T10:00:00Z","consentRecordId":"c","consentTextVersion":"studio-cloud-consent@1.0.0",
    "modelProvider":false,"retentionDays":7,"textClasses":[],"uploadSelectedSources":true}',
  (select q.cap_credits from public.quotes q where q.id = quote_id), 'k')) ->> 'jobId')::uuid;
update public.render_jobs set state = 'awaiting_review' where id = (select job_id from pg_temp.t_ids);
select ok((select session_id is not null and quote_id is not null and quote2_id is not null and job_id is not null
             from pg_temp.t_ids), 'fixture: the owner''s session, quotes and job exist (made by the owner''s commands)');
create temp table t_before as
  select (select count(*) from public.camera_sources) as sources, (select count(*) from public.camera_invites) as invites,
         (select count(*) from public.access_grants) as grants, (select count(*) from public.quotes) as quotes,
         (select count(*) from public.render_jobs) as jobs, (select count(*) from public.deletion_requests) as deletions,
         (select count(*) from app_ops.upload_sessions where state = 'opening') as open_sessions;

-- Every owner-only command, called with an unrelated actor ----------------------------------------------------------
select is(pg_temp.denied('source.declare', 'project', 'a7930000-0000-4000-8000-000000000001', format(
  'select app_gateway.declare_source(%L, %L, %L, gen_random_uuid(), 1000, sha256(%L::bytea), %L::jsonb, gen_random_uuid())',
  pg_temp.uid('unrelated'), 'a7930000-0000-4000-8000-000000000001', 'far_ad_corner', 'x', '{}')),
  'P0404 not_found', 'T-DB-33: declare_source');
select is(pg_temp.denied('camera_invite.create', 'project', 'a7930000-0000-4000-8000-000000000001', format(
  'select app_gateway.create_camera_invite(%L, %L, %L, %L, sha256(%L::bytea), gen_random_uuid())',
  pg_temp.uid('unrelated'), 'a7930000-0000-4000-8000-000000000001', 'far_ad_corner', 'Phone', 'code-x')),
  'P0404 not_found', 'T-DB-33: create_camera_invite');
select is(pg_temp.denied('camera_invite.revoke', 'camera_invite', '17930000-0000-4000-8000-000000000001', format(
  'select app_gateway.revoke_camera_invite(%L, %L, gen_random_uuid())',
  pg_temp.uid('unrelated'), '17930000-0000-4000-8000-000000000001')), 'P0404 not_found', 'T-DB-33: revoke_camera_invite');
select is(pg_temp.denied('camera_invite.approve', 'camera_invite', '17930000-0000-4000-8000-000000000001', format(
  'select app_gateway.approve_camera_invite(%L, %L, %L, gen_random_uuid())', pg_temp.uid('unrelated'),
  '17930000-0000-4000-8000-000000000001', '000000')), 'P0404 not_found', 'T-DB-33: approve_camera_invite');
select is(pg_temp.denied('upload.authorize', 'camera_source', '5c930000-0000-4000-8000-000000000002', format(
  'select app_gateway.authorize_upload(%L, %L, %L, %s, sha256(%L::bytea), gen_random_uuid())',
  'user', pg_temp.uid('unrelated'), '5c930000-0000-4000-8000-000000000002', 100000000, 's2')),
  'P0404 not_found', 'T-DB-33: authorize_upload');
select is(pg_temp.denied('upload.attach', 'upload_session', (select session_id from pg_temp.t_ids), format(
  'select app_gateway.attach_upload_id(%L, %L, %L, %L, sha256(%L::bytea), gen_random_uuid())',
  'user', pg_temp.uid('unrelated'), (select session_id from pg_temp.t_ids), 'u', 'cap')),
  'P0404 not_found', 'T-DB-33: attach_upload_id');
select is(pg_temp.denied('upload.abort', 'upload_session', (select session_id from pg_temp.t_ids), format(
  'select app_gateway.abort_upload(%L, null, %L, gen_random_uuid())',
  (select session_id from pg_temp.t_ids), pg_temp.uid('unrelated'))), 'P0404 not_found', 'T-DB-33: abort_upload');
select is(pg_temp.denied('grant.create', 'project', 'a7930000-0000-4000-8000-000000000001', format(
  'select app_gateway.create_grant(%L, %L, %L, %L, null, null, null, null, sha256(%L::bytea), gen_random_uuid())',
  pg_temp.uid('unrelated'), 'project_coach', 'someone@example.test', 'a7930000-0000-4000-8000-000000000001', 'g1')),
  'P0404 not_found', 'T-DB-33: create_grant (project_coach)');
select is(pg_temp.denied('grant.create', 'lesson', '1e930000-0000-4000-8000-000000000001', format(
  'select app_gateway.create_grant(%L, %L, %L, null, %L, null, null, null, sha256(%L::bytea), gen_random_uuid())',
  pg_temp.uid('unrelated'), 'lesson_view', 'someone@example.test', '1e930000-0000-4000-8000-000000000001', 'g2')),
  'P0404 not_found', 'T-DB-33: create_grant (lesson_view)');
select is(pg_temp.denied('grant.create', 'artifact', 'f7930000-0000-4000-8000-000000000001', format(
  'select app_gateway.create_grant(%L, %L, %L, null, null, %L, null, null, sha256(%L::bytea), gen_random_uuid())',
  pg_temp.uid('unrelated'), 'film_view', 'someone@example.test', 'f7930000-0000-4000-8000-000000000001', 'g3')),
  'P0404 not_found', 'T-DB-33: create_grant (film_view)');
select is(pg_temp.denied('grant.create', 'lesson_clip', 'c1930000-0000-4000-8000-000000000001', format(
  'select app_gateway.create_grant(%L, %L, %L, null, null, null, %L, null, sha256(%L::bytea), gen_random_uuid())',
  pg_temp.uid('unrelated'), 'lesson_clip_view', 'someone@example.test', 'c1930000-0000-4000-8000-000000000001', 'g4')),
  'P0404 not_found', 'T-DB-33: create_grant (lesson_clip_view)');
select is(pg_temp.denied('member.list_pending', 'project', 'a7930000-0000-4000-8000-000000000001', format(
  'select app_gateway.list_pending_members(%L, %L, gen_random_uuid())', pg_temp.uid('unrelated'),
  'a7930000-0000-4000-8000-000000000001')), 'P0404 not_found', 'T-DB-33: list_pending_members');
select is(pg_temp.denied('member.approve', 'project', 'a7930000-0000-4000-8000-000000000001', format(
  'select app_gateway.approve_member(%L, %L, %L, %L, gen_random_uuid())', pg_temp.uid('unrelated'),
  'a7930000-0000-4000-8000-000000000001', pg_temp.uid('coach'), '000000')), 'P0404 not_found', 'T-DB-33: approve_member');
select is(pg_temp.denied('grant.revoke', 'access_grant', '9c930000-0000-4000-8000-000000000001', format(
  'select app_gateway.revoke_grant(%L, %L, gen_random_uuid())', pg_temp.uid('unrelated'),
  '9c930000-0000-4000-8000-000000000001')), 'P0404 not_found', 'T-DB-33: revoke_grant');
select is(pg_temp.denied('member.revoke', 'project', 'a7930000-0000-4000-8000-000000000001', format(
  'select app_gateway.revoke_member(%L, %L, %L, gen_random_uuid())', pg_temp.uid('unrelated'),
  'a7930000-0000-4000-8000-000000000001', pg_temp.uid('coach'))), 'P0404 not_found', 'T-DB-33: revoke_member');
select is(pg_temp.denied('share_link.create', 'artifact', 'f7930000-0000-4000-8000-000000000001', format(
  'select app_gateway.create_share_link(%L, %L, 3600, true, sha256(%L::bytea), gen_random_uuid())',
  pg_temp.uid('unrelated'), 'f7930000-0000-4000-8000-000000000001', 'l1')), 'P0404 not_found', 'T-DB-33: create_share_link');
select is(pg_temp.denied('quote.create', 'project', 'a7930000-0000-4000-8000-000000000001', format(
  'select app_gateway.create_quote(%L, %L, %L, %L, %L, %L::jsonb, %L::uuid[], 7, gen_random_uuid())',
  pg_temp.uid('unrelated'), 'a7930000-0000-4000-8000-000000000001', '9a930000-0000-4000-8000-000000000001',
  '5a930000-0000-4000-8000-000000000001', 'heuristic',
  '{"fps":{"num":30,"den":1},"width":1920,"height":1080,"aspect":"16:9","container":"mp4","videoCodec":"h264",
    "audioCodec":"aac","audioSampleRate":48000,"durationTargetSec":120}',
  array['5c930000-0000-4000-8000-000000000001'])), 'P0404 not_found', 'T-DB-33: create_quote');
select is(pg_temp.denied('quote.accept', 'quote', (select quote2_id from pg_temp.t_ids), format(
  'select app_gateway.accept_quote(%L, %L, (select inputs_sha256 from public.quotes where id = %L), %L::jsonb, 4, %L, gen_random_uuid())',
  pg_temp.uid('unrelated'), (select quote2_id from pg_temp.t_ids), (select quote2_id from pg_temp.t_ids),
  '{"at":"2026-11-08T10:00:00Z","consentRecordId":"c","consentTextVersion":"studio-cloud-consent@1.0.0",
    "modelProvider":false,"retentionDays":7,"textClasses":[],"uploadSelectedSources":true}', 'k2')),
  'P0404 not_found', 'T-DB-33: accept_quote');
select is(pg_temp.denied('job.review', 'render_job', (select job_id from pg_temp.t_ids), format(
  'select app_gateway.review_job(%L, %L, %L, null, gen_random_uuid())', pg_temp.uid('unrelated'),
  (select job_id from pg_temp.t_ids), 'approve')), 'P0404 not_found', 'T-DB-33: review_job');
select is(pg_temp.denied('deletion.request', 'project', 'a7930000-0000-4000-8000-000000000001', format(
  'select app_gateway.request_deletion(%L, %L, %L, null, true, gen_random_uuid())', pg_temp.uid('unrelated'),
  'project', 'a7930000-0000-4000-8000-000000000001')), 'P0404 not_found', 'T-DB-33: request_deletion (project)');
select is(pg_temp.denied('deletion.request', 'source', '5c930000-0000-4000-8000-000000000001', format(
  'select app_gateway.request_deletion(%L, %L, %L, null, true, gen_random_uuid())', pg_temp.uid('unrelated'),
  'source', '5c930000-0000-4000-8000-000000000001')), 'P0404 not_found', 'T-DB-33: request_deletion (source)');
select is(pg_temp.denied('deletion.request', 'artifact', 'f7930000-0000-4000-8000-000000000001', format(
  'select app_gateway.request_deletion(%L, %L, %L, null, true, gen_random_uuid())', pg_temp.uid('unrelated'),
  'artifact', 'f7930000-0000-4000-8000-000000000001')), 'P0404 not_found', 'T-DB-33: request_deletion (artifact)');
select is(pg_temp.denied('deletion.request', 'lesson', '1e930000-0000-4000-8000-000000000001', format(
  'select app_gateway.request_deletion(%L, %L, %L, null, true, gen_random_uuid())', pg_temp.uid('unrelated'),
  'lesson', '1e930000-0000-4000-8000-000000000001')), 'P0404 not_found', 'T-DB-33: request_deletion (lesson)');
select is(pg_temp.denied('deletion.request', 'lesson_clip', 'c1930000-0000-4000-8000-000000000001', format(
  'select app_gateway.request_deletion(%L, %L, %L, null, true, gen_random_uuid())', pg_temp.uid('unrelated'),
  'lesson_clip', 'c1930000-0000-4000-8000-000000000001')), 'P0404 not_found', 'T-DB-33: request_deletion (lesson_clip)');
select is(pg_temp.denied('deletion.request', 'profile', pg_temp.uid('owner'), format(
  'select app_gateway.request_deletion(%L, %L, %L, null, true, gen_random_uuid())', pg_temp.uid('unrelated'),
  'account', pg_temp.uid('owner'))), 'P0404 not_found', 'T-DB-33: request_deletion (another user''s account)');
select is(pg_temp.denied('clip_share.approve', 'lesson_clip', 'c1930000-0000-4000-8000-000000000001', format(
  'select app_gateway.approve_clip_share(%L, %L, gen_random_uuid())', pg_temp.uid('unrelated'),
  'c1930000-0000-4000-8000-000000000001')), 'P0404 not_found', 'T-DB-33: approve_clip_share');
select is(pg_temp.denied('clip_share.revoke', 'lesson_clip', 'c1930000-0000-4000-8000-000000000001', format(
  'select app_gateway.revoke_clip_share(%L, %L, gen_random_uuid())', pg_temp.uid('unrelated'),
  'c1930000-0000-4000-8000-000000000001')), 'P0404 not_found', 'T-DB-33: revoke_clip_share');

-- The audit rows ----------------------------------------------------------------------------------------------------
select is((select count(*)::int from app_ops.audit_events
            where actor_kind = 'user' and actor_id = pg_temp.uid('unrelated') and outcome = 'denied'
              and reason_code = 'not_found' and project_id is null and request_id is not null), 27,
  'T-DB-33: audit_denial wrote one denied row per refused command (27)');
select is((select count(*)::int from app_ops.audit_events
            where actor_id = pg_temp.uid('unrelated') and outcome <> 'denied'), 0,
  'T-DB-33: no refused command left an allowed row (its own rows rolled back)');
select is((select count(distinct action)::int from app_ops.audit_events
            where actor_id = pg_temp.uid('unrelated') and outcome = 'denied'), 19,
  'the denied rows name the refused actions');
select ok((select row(sources, invites, grants, quotes, jobs, deletions, open_sessions)
             = row((select count(*) from public.camera_sources), (select count(*) from public.camera_invites),
                   (select count(*) from public.access_grants), (select count(*) from public.quotes),
                   (select count(*) from public.render_jobs), (select count(*) from public.deletion_requests),
                   (select count(*) from app_ops.upload_sessions where state = 'opening'))
             from pg_temp.t_before),
  'none of the refused calls created or changed a source, invite, grant, quote, job, deletion or session');
select ok((select p.deleted_at is null and r.state = 'awaiting_review' and m.approved_at is null and m.revoked_at is null
                  and g.revoked_at is null and i.approved_at is null and i.revoked_at is null
             from public.projects p, public.render_jobs r, public.project_members m, public.access_grants g,
                  public.camera_invites i
            where p.id = 'a7930000-0000-4000-8000-000000000001' and r.id = (select job_id from pg_temp.t_ids)
              and m.user_id = pg_temp.uid('coach') and g.id = '9c930000-0000-4000-8000-000000000001'
              and i.id = '17930000-0000-4000-8000-000000000001'),
  'the owner''s project, job, pending coach, grant and invite are exactly as they were');

-- audit_denial itself ------------------------------------------------------------------------------------------------
select is(pg_temp.call(format('select app_gateway.audit_denial(%L, %L, %L, null, null, %L, gen_random_uuid())',
            'render_host', gen_random_uuid(), 'upload.part', 'stale_lease')) ->> 'message', 'invalid_value:actor_kind',
  'audit_denial refuses the render_host actor kind (host routes use the orchestrator''s twin, S80)');
select is(pg_temp.call(format('select app_gateway.audit_denial(%L, %L, %L, null, null, %L, gen_random_uuid())',
            'user', gen_random_uuid(), 'quote.accept', 'someone@example.test')) ->> 'message', 'invalid_value:reason',
  'audit_denial stores coded reasons only (no free text, no email)');
select is(pg_temp.call(format('select app_gateway.audit_denial(%L, %L, %L, null, null, %L, gen_random_uuid())',
            'user', gen_random_uuid(), 'Not An Action', 'not_found')) ->> 'message', 'invalid_value:action',
  'audit_denial refuses an action that is not a dotted code');
select throws_ok($$update app_ops.audit_events set reason_code = 'changed' where outcome = 'denied'$$, 'P0409',
  'append_only', 'denial rows are append only');

select * from finish();
rollback;
