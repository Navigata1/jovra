-- Migration 2: lessons, lesson clips, observations, story plans, artifacts and grants under every role that reaches
-- them (S77 / B-04 with findings 20, 22a, 31). T-DB-17 (columns), 18, 19, 20, 21, 22, 23, 41, 42, 45, 46, 49, 52,
-- 62 and 69, plus user stories 173 (a deleted source leaves the clip, marked missing) and 179 (lesson edits from two
-- devices conflict instead of overwriting). docs/backend/security-model.md §4, §5.3-§5.6, §6.2, §13.8, §13.9, §13.16.
-- Fixtures are written as postgres (the server path); app_gateway commands run as jovra_gateway. The file rolls back.
begin;
select plan(72);

select tests.create_supabase_user('owner');        -- owns projects A and A2 and lesson LO
select tests.create_supabase_user('owner_b');      -- owns project B
select tests.create_supabase_user('coach');        -- approved coach of A; owns lesson LC
select tests.create_supabase_user('viewer');       -- lesson_clip_view on clip CO
select tests.create_supabase_user('viewer2');      -- lesson_clip_view on the coach's clip CC, once approved
select tests.create_supabase_user('film_viewer');  -- film_view on film F
select tests.create_supabase_user('lviewer');      -- lesson_view on LO
select tests.create_supabase_user('lcoach');       -- lesson_coach on LO; not a member of A
select tests.create_supabase_user('lv_coach');     -- coach of A who only has lesson_view on LO
select tests.create_supabase_user('unrelated');
grant jovra_gateway to postgres;

insert into public.projects (id, owner_id, local_project_id, title) values
  ('a3000000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner'), gen_random_uuid(), 'Club final'),
  ('a3000000-0000-4000-8000-000000000002', tests.get_supabase_uid('owner'), gen_random_uuid(), 'Practice set'),
  ('b3000000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner_b'), gen_random_uuid(), 'Other match');
insert into public.project_members (project_id, user_id, role, granted_by, approved_at) values
  ('a3000000-0000-4000-8000-000000000001', tests.get_supabase_uid('coach'), 'coach',
   tests.get_supabase_uid('owner'), now()),
  ('a3000000-0000-4000-8000-000000000001', tests.get_supabase_uid('lv_coach'), 'coach',
   tests.get_supabase_uid('owner'), now());
insert into public.camera_sources (id, project_id, slot, local_source_id, declared_bytes, declared_sha256) values
  ('5a300000-0000-4000-8000-000000000001', 'a3000000-0000-4000-8000-000000000001', 'primary_baseline',
   gen_random_uuid(), 1000, sha256('sa'::bytea)),
  ('5a300000-0000-4000-8000-000000000002', 'a3000000-0000-4000-8000-000000000002', 'primary_baseline',
   gen_random_uuid(), 1000, sha256('sa2'::bytea)),
  ('5b300000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000001', 'primary_baseline',
   gen_random_uuid(), 1000, sha256('sb'::bytea));
insert into public.calibration_versions (project_id, source_id, calibration, provenance) values
  ('a3000000-0000-4000-8000-000000000001', '5a300000-0000-4000-8000-000000000001', '{}', 'manual');

insert into public.lessons (id, owner_id, local_lesson_id, lesson_date, title, notes) values
  ('1e300000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner'), gen_random_uuid(), current_date,
   'Serve lesson', 'Toss lower.'),
  ('1e300000-0000-4000-8000-000000000002', tests.get_supabase_uid('coach'), gen_random_uuid(), current_date,
   'Coach notes', 'Watch the split step.');
-- CO: the owner's clip of their own match (implicitly shareable).
insert into public.lesson_clips (id, lesson_id, project_id, source_id, match_start_us, match_end_us, note) values
  ('c1300000-0000-4000-8000-000000000001', '1e300000-0000-4000-8000-000000000001',
   'a3000000-0000-4000-8000-000000000001', '5a300000-0000-4000-8000-000000000001', 1000000, 5000000, 'Second serve');

-- Media of A: a film with its thumbnail and captions, a preview, an edit manifest, a second film, CO's excerpt.
insert into public.artifacts (id, project_id, parent_artifact_id, lesson_clip_id, kind, bucket_class, r2_key, state)
values
  ('f3000000-0000-4000-8000-000000000001', 'a3000000-0000-4000-8000-000000000001', null, null, 'film', 'films',
   'films/a3/f1', 'ready'),
  ('f3000000-0000-4000-8000-000000000002', 'a3000000-0000-4000-8000-000000000001',
   'f3000000-0000-4000-8000-000000000001', null, 'thumbnail', 'films', 'films/a3/f1.jpg', 'ready'),
  ('f3000000-0000-4000-8000-000000000003', 'a3000000-0000-4000-8000-000000000001',
   'f3000000-0000-4000-8000-000000000001', null, 'captions', 'films', 'films/a3/f1.vtt', 'ready'),
  ('f3000000-0000-4000-8000-000000000004', 'a3000000-0000-4000-8000-000000000001', null, null, 'preview', 'work',
   'work/a3/p1', 'ready'),
  ('f3000000-0000-4000-8000-000000000005', 'a3000000-0000-4000-8000-000000000001', null, null, 'edit_manifest',
   'films', 'films/a3/em1', 'ready'),
  ('f3000000-0000-4000-8000-000000000006', 'a3000000-0000-4000-8000-000000000001', null, null, 'film', 'films',
   'films/a3/f2', 'ready'),
  ('f3000000-0000-4000-8000-000000000007', 'a3000000-0000-4000-8000-000000000001', null,
   'c1300000-0000-4000-8000-000000000001', 'clip_excerpt', 'films', 'films/a3/x-co', 'ready');
update public.lesson_clips set excerpt_artifact_id = 'f3000000-0000-4000-8000-000000000007'
 where id = 'c1300000-0000-4000-8000-000000000001';

insert into public.access_grants (id, kind, project_id, lesson_id, artifact_id, lesson_clip_id, grantee_user_id,
                                  invitee_email_hmac, created_by, redeem_by, redeemed_at)
values
  ('6a300000-0000-4000-8000-000000000001', 'film_view', 'a3000000-0000-4000-8000-000000000001', null,
   'f3000000-0000-4000-8000-000000000001', null, tests.get_supabase_uid('film_viewer'), sha256('fv'::bytea),
   tests.get_supabase_uid('owner'), now() + interval '1 day', now()),
  ('6a300000-0000-4000-8000-000000000002', 'lesson_clip_view', null, null, null,
   'c1300000-0000-4000-8000-000000000001', tests.get_supabase_uid('viewer'), sha256('v'::bytea),
   tests.get_supabase_uid('owner'), now() + interval '1 day', now()),
  ('6a300000-0000-4000-8000-000000000003', 'lesson_view', null, '1e300000-0000-4000-8000-000000000001', null, null,
   tests.get_supabase_uid('lviewer'), sha256('lv'::bytea), tests.get_supabase_uid('owner'),
   now() + interval '1 day', now()),
  ('6a300000-0000-4000-8000-000000000004', 'lesson_coach', null, '1e300000-0000-4000-8000-000000000001', null, null,
   tests.get_supabase_uid('lcoach'), sha256('lc'::bytea), tests.get_supabase_uid('owner'),
   now() + interval '1 day', now()),
  ('6a300000-0000-4000-8000-000000000005', 'lesson_view', null, '1e300000-0000-4000-8000-000000000001', null, null,
   tests.get_supabase_uid('lv_coach'), sha256('lvc'::bytea), tests.get_supabase_uid('owner'),
   now() + interval '1 day', now());

-- Observations: A only (with source SA), A + lesson LO, lesson LO only, and a server-estimated cue on A.
insert into public.observations (id, project_id, lesson_id, source_id, match_start_us, match_end_us, kind, body,
                                 provenance, review_state, created_by)
values
  ('0b300000-0000-4000-8000-000000000001', 'a3000000-0000-4000-8000-000000000001', null,
   '5a300000-0000-4000-8000-000000000001', 1000000, 2000000, 'note', 'Good depth', 'manual', 'reviewed',
   tests.get_supabase_uid('owner')),
  ('0b300000-0000-4000-8000-000000000002', 'a3000000-0000-4000-8000-000000000001',
   '1e300000-0000-4000-8000-000000000001', null, 1000000, 2000000, 'note', 'Lesson + match', 'manual', 'reviewed',
   tests.get_supabase_uid('owner')),
  ('0b300000-0000-4000-8000-000000000003', null, '1e300000-0000-4000-8000-000000000001', null, null, null,
   'note', 'Lesson only', 'manual', 'reviewed', tests.get_supabase_uid('owner')),
  ('0b300000-0000-4000-8000-000000000004', 'a3000000-0000-4000-8000-000000000001', null, null, 3000000, 3500000,
   'serveContact', null, 'estimated', 'estimated', null);

-- Gateway calls run as jovra_gateway (which can reach nothing but app_gateway); the result is the SQLSTATE or ok.
create function pg_temp.gw(p_sql text) returns text language plpgsql as $$
declare
  v_state text;
begin
  execute 'set local role jovra_gateway';
  execute p_sql;
  execute 'reset role';
  return 'ok';
exception when others then
  get stacked diagnostics v_state = returned_sqlstate;
  return v_state;
end $$;
create function pg_temp.approve(p_actor text, p_clip uuid) returns text language sql as $$
  select pg_temp.gw(format('select app_gateway.approve_clip_share(%L, %L, gen_random_uuid())',
                           tests.get_supabase_uid(p_actor), p_clip))
$$;
create function pg_temp.revoke_share(p_actor text, p_clip uuid) returns text language sql as $$
  select pg_temp.gw(format('select app_gateway.revoke_clip_share(%L, %L, gen_random_uuid())',
                           tests.get_supabase_uid(p_actor), p_clip))
$$;

-- Owner --------------------------------------------------------------------------------------------------------
select tests.authenticate_as('owner');
select results_eq($$insert into public.lessons (local_lesson_id, lesson_date, title, notes)
                    values (gen_random_uuid(), current_date, 'Footwork', '') returning owner_id, revision$$,
  $$values (tests.get_supabase_uid('owner'), 1::bigint)$$, 'owner creates a lesson; owner_id defaults to the caller');
-- Story 179: a conditional update on the revision a device last saw; the second device's write changes nothing.
select results_eq($$update public.lessons set notes = 'Toss lower, device 1'
                    where id = '1e300000-0000-4000-8000-000000000001' and revision = 1 returning revision$$,
  $$values (2::bigint)$$, 'story 179: the first device''s edit at revision 1 lands as revision 2');
select is_empty($$update public.lessons set notes = 'Toss lower, device 2'
                  where id = '1e300000-0000-4000-8000-000000000001' and revision = 1 returning revision$$,
  'story 179: the second device, still at revision 1, changes 0 rows (a conflict to show, not an overwrite)');
select throws_ok($$update public.lessons set owner_id = tests.get_supabase_uid('unrelated')
                   where id = '1e300000-0000-4000-8000-000000000001'$$,
  '42501', 'permission denied for table lessons', 'lessons.owner_id is immutable');
select throws_ok($$delete from public.lessons$$, '42501', 'permission denied for table lessons',
  'T-DB-48 (grant half): owner cannot delete a lesson directly');

-- T-DB-41: a clip of a project the lesson owner neither owns nor coaches
select throws_ok($$insert into public.lesson_clips (lesson_id, project_id, match_start_us, match_end_us)
                   values ('1e300000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-000000000001',
                           0, 1000000)$$,
  '42501', 'new row violates row-level security policy for table "lesson_clips"',
  'T-DB-41: owner attaching a clip of B''s match is an RLS violation');
-- T-DB-45: a source of another project the caller can see is an FK violation, for clips, observations, calibrations
select throws_ok($$insert into public.lesson_clips (lesson_id, project_id, source_id, match_start_us, match_end_us)
                   values ('1e300000-0000-4000-8000-000000000001', 'a3000000-0000-4000-8000-000000000001',
                           '5a300000-0000-4000-8000-000000000002', 0, 1000000)$$,
  '23503', null, 'T-DB-45: a clip of A naming A2''s source is an FK violation');
select throws_ok($$insert into public.observations (project_id, source_id, kind, body)
                   values ('a3000000-0000-4000-8000-000000000001', '5a300000-0000-4000-8000-000000000002',
                           'note', 'x')$$,
  '23503', null, 'T-DB-45: an observation of A naming A2''s source is an FK violation');
select throws_ok($$insert into public.calibration_versions (project_id, source_id, calibration, provenance)
                   values ('a3000000-0000-4000-8000-000000000001', '5a300000-0000-4000-8000-000000000002',
                           '{}', 'manual')$$,
  '23503', null, 'T-DB-45: a calibration of A naming A2''s source is an FK violation');
select results_eq($$insert into public.lesson_clips (lesson_id, project_id, source_id, match_start_us, match_end_us,
                                                     keeper_ref, position)
                    values ('1e300000-0000-4000-8000-000000000001', 'a3000000-0000-4000-8000-000000000001',
                            '5a300000-0000-4000-8000-000000000001', 6000000, 9000000, 'k-ace', 2)
                    returning share_approved_at is null, revision$$,
  $$values (true, 1::bigint)$$, 'owner attaches a clip of their own match (same-project source)');
select throws_ok($$insert into public.lesson_clips (lesson_id, project_id, match_start_us, match_end_us)
                   values ('1e300000-0000-4000-8000-000000000001', 'a3000000-0000-4000-8000-000000000001',
                           0, 600000001)$$,
  'P0422', 'invalid_value:match_window', 'a clip longer than 10 minutes is P0422 (no CHECK DETAIL)');

-- T-DB-42: a story plan naming a lesson the caller cannot access
select throws_ok($$insert into public.story_plans (project_id, lesson_ids, profile_id, profile_revision, title)
                   values ('a3000000-0000-4000-8000-000000000001', '{1e300000-0000-4000-8000-000000000002}',
                           'progress-story', 1, 'Progress')$$,
  'P0401', 'lesson_not_accessible', 'T-DB-42: owner binding the coach''s lesson into a plan is refused');
select results_eq($$insert into public.story_plans (project_id, lesson_ids, profile_id, profile_revision, title)
                    values ('a3000000-0000-4000-8000-000000000001', '{1e300000-0000-4000-8000-000000000001}',
                            'progress-story', 1, 'Progress') returning created_by$$,
  $$values (tests.get_supabase_uid('owner'))$$, 'owner binds their own lesson into a plan of their own project');

-- T-DB-23: provenance is never client-chosen; review turns estimated into reviewed
select throws_ok($$insert into public.observations (project_id, kind, body, provenance)
                   values ('a3000000-0000-4000-8000-000000000001', 'note', 'x', 'estimated')$$,
  '42501', 'permission denied for table observations', 'T-DB-23: owner cannot insert an estimated observation');
select throws_ok($$insert into public.observations (project_id, kind, body, provenance)
                   values ('a3000000-0000-4000-8000-000000000001', 'note', 'x', 'validated')$$,
  '42501', 'permission denied for table observations', 'T-DB-23: owner cannot insert a validated observation');
select throws_ok($$update public.observations set provenance = 'validated'$$, '42501',
  'permission denied for table observations', 'T-DB-23: owner cannot update provenance');
select results_eq($$insert into public.observations (project_id, kind, body)
                    values ('a3000000-0000-4000-8000-000000000001', 'note', 'Wide serve')
                    returning provenance::text, review_state::text, created_by$$,
  $$values ('manual', 'reviewed', tests.get_supabase_uid('owner'))$$,
  'T-DB-23: a client observation is manual, authored by the caller');
select results_eq($$update public.observations set review_state = 'reviewed'
                    where id = '0b300000-0000-4000-8000-000000000004'
                    returning provenance::text, reviewed_by, reviewed_at is not null$$,
  $$values ('reviewed', tests.get_supabase_uid('owner'), true)$$,
  'T-DB-23: reviewing an estimated cue sets provenance reviewed and reviewed_by = the caller');

-- T-DB-17: hidden columns, behaviourally
select throws_ok('select r2_key from public.artifacts', '42501', 'permission denied for table artifacts',
  'T-DB-17: artifacts.r2_key is not selectable');
select throws_ok('select bucket_class from public.artifacts', '42501', 'permission denied for table artifacts',
  'T-DB-17: artifacts.bucket_class is not selectable');
select throws_ok('select token_hash from public.access_grants', '42501', 'permission denied for table access_grants',
  'T-DB-17: access_grants.token_hash is not selectable');
select is((select count(*)::int from public.artifacts), 7, 'owner sees every member-visible artifact of A');
select throws_ok($$insert into public.access_grants (kind, lesson_id, created_by)
                   values ('lesson_view', '1e300000-0000-4000-8000-000000000001', auth.uid())$$,
  '42501', 'permission denied for table access_grants', 'T-DB-26 (grants): owner cannot write a grant directly');
reset role;

-- lcoach: lesson_coach on LO, not a member of A (T-DB-22) -------------------------------------------------------------
select tests.authenticate_as('lcoach');
select results_eq($$insert into public.observations (lesson_id, kind, body)
                    values ('1e300000-0000-4000-8000-000000000001', 'note', 'Coach: higher toss')
                    returning project_id, created_by$$,
  $$values (null::uuid, tests.get_supabase_uid('lcoach'))$$,
  'T-DB-22: a lesson coach adds a lesson-only observation');
select throws_ok($$insert into public.observations (project_id, lesson_id, kind, body)
                   values ('a3000000-0000-4000-8000-000000000001', '1e300000-0000-4000-8000-000000000001',
                           'note', 'x')$$,
  '42501', 'new row violates row-level security policy for table "observations"',
  'T-DB-22: with a project_id they do not coach, the insert is an RLS violation');
select results_eq($$select id::text from public.lessons$$, $$values ('1e300000-0000-4000-8000-000000000001')$$,
  'a lesson coach sees the lesson');
select is((select count(*)::int from public.observations where project_id is not null), 0,
  'T-DB-49 (lesson side): a lesson coach sees no observation that also belongs to a project they cannot access');
reset role;

-- lviewer: lesson_view on LO (T-DB-21) ---------------------------------------------------------------------------
select tests.authenticate_as('lviewer');
select results_eq($$select id::text from public.lessons$$, $$values ('1e300000-0000-4000-8000-000000000001')$$,
  'T-DB-21: a lesson viewer sees the lesson');
select is((select count(*)::int from public.observations), 0, 'T-DB-21: a lesson viewer sees 0 observations');
select is((select count(*)::int from public.projects), 0, 'T-DB-21: a lesson viewer sees 0 projects');
select is((select count(*)::int from public.story_plans) + (select count(*)::int from public.camera_sources), 0,
  'T-DB-21: and 0 plans or sources');
select throws_ok($$insert into public.observations (lesson_id, kind, body)
                   values ('1e300000-0000-4000-8000-000000000001', 'note', 'x')$$,
  '42501', 'new row violates row-level security policy for table "observations"',
  'a lesson viewer cannot add an observation');
reset role;

-- lv_coach: coach of A with only lesson_view on LO (T-DB-52) ----------------------------------------------------
select tests.authenticate_as('lv_coach');
select throws_ok($$insert into public.story_plans (project_id, lesson_ids, profile_id, profile_revision, title)
                   values ('a3000000-0000-4000-8000-000000000001', '{1e300000-0000-4000-8000-000000000001}',
                           'progress-story', 1, 'Progress')$$,
  'P0401', 'lesson_not_accessible', 'T-DB-52: a lesson_view grantee cannot bind that lesson into a plan');
reset role;

-- coach: approved coach of A who owns lesson LC (T-DB-49, T-DB-46 part 1) ------------------------------------------
select tests.authenticate_as('coach');
select results_eq($$select id::text from public.observations where id::text like '0b3%' order by id$$,
  $$values ('0b300000-0000-4000-8000-000000000001'), ('0b300000-0000-4000-8000-000000000004')$$,
  'T-DB-49: a project coach sees A''s own observations');
select is((select count(*)::int from public.observations where lesson_id is not null), 0,
  'T-DB-49: but none that also carries a lesson the coach cannot access (A + LO, LO only)');
select throws_ok($$update public.observations set body = 'edited by coach'
                   where id = '0b300000-0000-4000-8000-000000000001'$$,
  'P0401', 'not_author', 'only the author may change an observation''s text');
select results_eq($$insert into public.lesson_clips (lesson_id, project_id, source_id, match_start_us,
                                                     match_end_us, keeper_ref)
                    values ('1e300000-0000-4000-8000-000000000002', 'a3000000-0000-4000-8000-000000000001',
                            '5a300000-0000-4000-8000-000000000001', 10000000, 14000000, 'k-rally')
                    returning share_approved_at$$,
  $$values (null::timestamptz)$$, 'T-DB-46: the coach attaches a clip of the owner''s match to their own lesson');
select is((select count(*)::int from public.lesson_clips), 1,
  'the coach sees their own clip, not the owner''s lesson clips');
select throws_ok($$insert into public.lesson_clips (id, lesson_id, project_id, match_start_us, match_end_us)
                   values (gen_random_uuid(), '1e300000-0000-4000-8000-000000000002',
                           'a3000000-0000-4000-8000-000000000001', 0, 1000000)$$,
  '42501', 'permission denied for table lesson_clips', 'a client cannot choose a clip''s id');
reset role;
-- Name the coach's clip CC for the checks below (ids are server-generated; this is fixture bookkeeping).
update public.lesson_clips set id = 'c1300000-0000-4000-8000-000000000002'
 where lesson_id = '1e300000-0000-4000-8000-000000000002';

-- The server renders the coach clip's excerpt and links it; the excerpt must belong to that clip (§13.16).
insert into public.artifacts (id, project_id, lesson_clip_id, kind, bucket_class, r2_key, state) values
  ('f3000000-0000-4000-8000-000000000008', 'a3000000-0000-4000-8000-000000000001',
   'c1300000-0000-4000-8000-000000000002', 'clip_excerpt', 'films', 'films/a3/x-cc', 'ready');
select throws_ok($$update public.lesson_clips set excerpt_artifact_id = 'f3000000-0000-4000-8000-000000000008'
                   where id = 'c1300000-0000-4000-8000-000000000001'$$,
  'P0422', 'excerpt_mismatch', 'finding 31: a clip cannot link another clip''s excerpt');
update public.lesson_clips set excerpt_artifact_id = 'f3000000-0000-4000-8000-000000000008'
 where id = 'c1300000-0000-4000-8000-000000000002';

-- T-DB-46: no clip grant before the project owner approves; approval is the project owner's alone
select throws_ok($$insert into public.access_grants (kind, lesson_clip_id, grantee_user_id, invitee_email_hmac,
                                                     created_by, redeem_by, redeemed_at)
                   values ('lesson_clip_view', 'c1300000-0000-4000-8000-000000000002',
                           tests.get_supabase_uid('viewer2'), sha256('v2'::bytea), tests.get_supabase_uid('coach'),
                           now() + interval '1 day', now())$$,
  'P0409', 'clip_share_not_approved', 'T-DB-46: a grant on the coach''s clip is refused until approved');
select is(pg_temp.approve('coach', 'c1300000-0000-4000-8000-000000000002'), 'P0404',
  'T-DB-46: the coach cannot approve sharing the owner''s footage (P0404, like a missing clip)');
select is(pg_temp.approve('unrelated', 'c1300000-0000-4000-8000-000000000002'), 'P0404',
  'an unrelated actor gets P0404');
select is(pg_temp.approve('owner', 'c1300000-0000-4000-8000-000000000002'), 'ok',
  'T-DB-46: the project owner approves sharing exactly this window');
select is((select share_approved_sha256 = sha256(convert_to(concat_ws('|', project_id, source_id, match_start_us,
                                                                    match_end_us, keeper_ref, '-', '-'), 'UTF8'))
             from public.lesson_clips where id = 'c1300000-0000-4000-8000-000000000002'), true,
  'finding 20: the approval is pinned to the clip''s fingerprint');
insert into public.access_grants (id, kind, lesson_clip_id, grantee_user_id, invitee_email_hmac, created_by,
                                  redeem_by, redeemed_at)
values ('6a300000-0000-4000-8000-000000000006', 'lesson_clip_view', 'c1300000-0000-4000-8000-000000000002',
        tests.get_supabase_uid('viewer2'), sha256('v2'::bytea), tests.get_supabase_uid('coach'),
        now() + interval '1 day', now());

select tests.authenticate_as('viewer2');
select results_eq($$select id::text from public.lesson_clips$$, $$values ('c1300000-0000-4000-8000-000000000002')$$,
  'T-DB-46: after approval the viewer sees the coach''s clip');
select results_eq($$select id::text from public.artifacts$$, $$values ('f3000000-0000-4000-8000-000000000008')$$,
  'T-DB-46: and its excerpt, nothing else of the match');
reset role;
update public.project_members set revoked_at = now()
 where project_id = 'a3000000-0000-4000-8000-000000000001' and user_id = tests.get_supabase_uid('coach');
select tests.authenticate_as('viewer2');
select is((select count(*)::int from public.lesson_clips) + (select count(*)::int from public.artifacts), 0,
  'T-DB-46: once the owner revokes the coach, the downstream viewer gets 0 rows at once');
reset role;
update public.project_members set revoked_at = null
 where project_id = 'a3000000-0000-4000-8000-000000000001' and user_id = tests.get_supabase_uid('coach');

-- T-DB-62: moving an approved window clears the approval and unlinks the excerpt ----------------------------------
select tests.authenticate_as('coach');
select results_eq($$update public.lesson_clips set match_start_us = 11000000
                    where id = 'c1300000-0000-4000-8000-000000000002'
                    returning share_approved_at is null, share_approved_sha256 is null, excerpt_artifact_id is null$$,
  $$values (true, true, true)$$, 'T-DB-62: moving the window clears share_approved_at and unlinks the excerpt');
reset role;
select isnt((select deleted_at from public.artifacts where id = 'f3000000-0000-4000-8000-000000000008'), null,
  'T-DB-62: the unlinked excerpt is hidden at once (deleted_at set; the object goes with the deletion job)');
select tests.authenticate_as('viewer2');
select is((select count(*)::int from public.lesson_clips) + (select count(*)::int from public.artifacts), 0,
  'T-DB-62: the viewer sees 0 rows until re-approved');
reset role;
select is(pg_temp.approve('owner', 'c1300000-0000-4000-8000-000000000002'), 'ok', 'T-DB-62: the owner re-approves');
select tests.authenticate_as('viewer2');
select is((select count(*)::int from public.lesson_clips), 1, 'T-DB-62: after re-approval the clip is visible again');
reset role;
select is(pg_temp.revoke_share('coach', 'c1300000-0000-4000-8000-000000000002'), 'P0404',
  'finding 20: the coach cannot withdraw the owner''s approval either');
select is(pg_temp.revoke_share('owner', 'c1300000-0000-4000-8000-000000000002'), 'ok',
  'finding 20: the project owner withdraws the approval with revoke_clip_share');
select tests.authenticate_as('viewer2');
select is((select count(*)::int from public.lesson_clips), 0, 'T-DB-62: revoke_clip_share has the same effect: 0 rows');
select tests.authenticate_as('coach');
select is((select count(*)::int from public.lesson_clips where id = 'c1300000-0000-4000-8000-000000000002'), 1,
  'the coach still sees their own clip after the withdrawal');
reset role;

-- T-DB-69: even with the pinning trigger bypassed, a moved window is not visible under the old approval -----------
select is(pg_temp.approve('owner', 'c1300000-0000-4000-8000-000000000002'), 'ok', 'T-DB-69: approved again');
set local role jovra_owner;
alter table public.lesson_clips disable trigger b20_pin_shared_clip;
update public.lesson_clips set match_end_us = 15000000 where id = 'c1300000-0000-4000-8000-000000000002';
alter table public.lesson_clips enable trigger b20_pin_shared_clip;
reset role;
select isnt((select share_approved_at from public.lesson_clips where id = 'c1300000-0000-4000-8000-000000000002'),
  null, 'T-DB-69: with the trigger disabled the approval timestamp survived the move');
select tests.authenticate_as('viewer2');
select is((select count(*)::int from public.lesson_clips), 0,
  'T-DB-69: the viewer still sees 0 rows: share_approved_sha256 no longer equals the fingerprint');
reset role;

-- film_viewer: film_view on F (T-DB-18, T-DB-19) --------------------------------------------------------------------
select tests.authenticate_as('film_viewer');
select results_eq($$select id::text from public.artifacts order by id$$,
  $$values ('f3000000-0000-4000-8000-000000000001'), ('f3000000-0000-4000-8000-000000000002'),
           ('f3000000-0000-4000-8000-000000000003')$$,
  'T-DB-18: the film, its thumbnail and captions; not the preview, edit manifest, other film or excerpts');
select is((select count(*)::int from public.projects) + (select count(*)::int from public.lesson_clips), 0,
  'T-DB-18: no project and no clip');
select results_eq($$select id::text from public.access_grants$$, $$values ('6a300000-0000-4000-8000-000000000001')$$,
  'the grantee sees their own grant row');
reset role;
update public.access_grants set revoked_at = now() where id = '6a300000-0000-4000-8000-000000000001';
select tests.authenticate_as('film_viewer');
select is((select count(*)::int from public.artifacts), 0, 'T-DB-19: after revoke, 0 rows (no token refresh)');
reset role;
update public.access_grants set revoked_at = null, expires_at = now() - interval '1 second'
 where id = '6a300000-0000-4000-8000-000000000001';
select tests.authenticate_as('film_viewer');
select is((select count(*)::int from public.artifacts), 0, 'T-DB-19: after expires_at, 0 rows');
reset role;

-- viewer: lesson_clip_view on CO (T-DB-20) --------------------------------------------------------------------------
select tests.authenticate_as('viewer');
select results_eq($$select id::text from public.lesson_clips$$, $$values ('c1300000-0000-4000-8000-000000000001')$$,
  'T-DB-20: the clip grantee sees that clip only');
select results_eq($$select id::text from public.artifacts$$, $$values ('f3000000-0000-4000-8000-000000000007')$$,
  'T-DB-20: and its excerpt only (not the match film)');
select is((select count(*)::int from public.lessons) + (select count(*)::int from public.projects)
          + (select count(*)::int from public.observations), 0,
  'T-DB-20: the lesson, the project and its observations: 0 rows');
reset role;

-- unrelated (T-DB-06 for the lesson tables) ---------------------------------------------------------------------
select tests.authenticate_as('unrelated');
select is((select count(*)::int from public.lessons) + (select count(*)::int from public.lesson_clips)
          + (select count(*)::int from public.observations) + (select count(*)::int from public.story_plans)
          + (select count(*)::int from public.artifacts) + (select count(*)::int from public.access_grants), 0,
  'T-DB-06: an unrelated user sees 0 lessons, clips, observations, plans, artifacts and grants');
reset role;

-- Story 173 / finding 22a: deleting a source keeps the clip and the observation, marked missing ----------------
delete from public.camera_sources where id = '5a300000-0000-4000-8000-000000000001';
select results_eq($$select source_id, project_id::text from public.lesson_clips
                     where id = 'c1300000-0000-4000-8000-000000000001'$$,
  $$values (null::uuid, 'a3000000-0000-4000-8000-000000000001')$$,
  'story 173: the clip survives its source''s deletion with source_id null and its project kept');
select results_eq($$select source_id, project_id::text from public.observations
                     where id = '0b300000-0000-4000-8000-000000000001'$$,
  $$values (null::uuid, 'a3000000-0000-4000-8000-000000000001')$$,
  'finding 22a: the observation survives too (no stalled deletion)');
select is((select count(*)::int from public.calibration_versions
            where project_id = 'a3000000-0000-4000-8000-000000000001'), 0,
  'the source''s calibrations go with it');

select * from finish();
rollback;
