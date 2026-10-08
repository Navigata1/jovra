-- Migration 1 role matrix (S76 / B-03): profiles, projects, project_members and camera_invites under the real
-- Postgres roles PostgREST uses (anon; authenticated with the claims of an owner, unrelated user, approved coach,
-- pending coach, revoked and expired coaches, viewer, signed-in camera, anonymous-authenticated user).
-- docs/backend/security-model.md §5.1, §5.2, §6.1, §6.2. Fixtures are written as postgres (the server path), then
-- every assertion runs as the role under test. The file rolls back.
begin;
select plan(74);

-- Fixtures ---------------------------------------------------------------------------------------------------------
select tests.create_supabase_user('owner_a');
select tests.create_supabase_user('owner_b');
select tests.create_supabase_user('coach');
select tests.create_supabase_user('pending_coach');
select tests.create_supabase_user('revoked_coach');
select tests.create_supabase_user('expired_coach');
select tests.create_supabase_user('viewer');
select tests.create_supabase_user('camera');
select tests.create_supabase_user('unrelated');
select tests.create_supabase_user('anonymous_user');
update auth.users set is_anonymous = true where id = tests.get_supabase_uid('anonymous_user');

-- A: owner_a's live match; B: owner_b's; D: owner_a's project whose deletion has started.
insert into public.projects (id, owner_id, local_project_id, title, kind) values
  ('a0000000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner_a'),
   'a1000000-0000-4000-8000-000000000001', 'Club final', 'match'),
  ('b0000000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner_b'),
   'b1000000-0000-4000-8000-000000000001', 'Serve practice', 'match'),
  ('d0000000-0000-4000-8000-000000000001', tests.get_supabase_uid('owner_a'),
   'd1000000-0000-4000-8000-000000000001', 'Old import', 'import');
update public.projects set deleted_at = now() where id = 'd0000000-0000-4000-8000-000000000001';

insert into public.project_members (project_id, user_id, role, granted_by, approved_at, revoked_at, expires_at)
values
  ('a0000000-0000-4000-8000-000000000001', tests.get_supabase_uid('coach'), 'coach',
   tests.get_supabase_uid('owner_a'), now(), null, null),
  ('a0000000-0000-4000-8000-000000000001', tests.get_supabase_uid('pending_coach'), 'coach',
   tests.get_supabase_uid('owner_a'), null, null, null),
  ('a0000000-0000-4000-8000-000000000001', tests.get_supabase_uid('revoked_coach'), 'coach',
   tests.get_supabase_uid('owner_a'), now(), now(), null),
  ('a0000000-0000-4000-8000-000000000001', tests.get_supabase_uid('expired_coach'), 'coach',
   tests.get_supabase_uid('owner_a'), now(), null, now() - interval '1 minute'),
  ('d0000000-0000-4000-8000-000000000001', tests.get_supabase_uid('coach'), 'coach',
   tests.get_supabase_uid('owner_a'), now(), null, null);

-- I1: redeemed by the signed-in camera and approved; I2: redeemed by it, not approved; I3: open, on D.
insert into public.camera_invites (id, project_id, slot, display_label, code_hash, created_by, redeem_by,
                                   redeemed_at, redeemed_by_user_id, device_key_thumbprint, approved_at,
                                   capability_expires_at)
values
  ('c0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', 'far_ad_corner',
   'Far corner', sha256('invite-1'::bytea), tests.get_supabase_uid('owner_a'), now() + interval '10 minutes',
   now(), tests.get_supabase_uid('camera'), sha256('device-1'::bytea), now(), now() + interval '1 hour'),
  ('c0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000001', 'opposite_baseline',
   'Opposite baseline', sha256('invite-2'::bytea), tests.get_supabase_uid('owner_a'),
   now() + interval '10 minutes', now(), tests.get_supabase_uid('camera'), sha256('device-2'::bytea), null, null),
  ('c0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000001', 'primary_baseline',
   'Baseline', sha256('invite-3'::bytea), tests.get_supabase_uid('owner_a'), now() + interval '10 minutes',
   null, null, null, null, null);

-- Profiles came from the auth.users trigger --------------------------------------------------------------------
select is((select count(*)::int from public.profiles p
            where p.id in (tests.get_supabase_uid('owner_a'), tests.get_supabase_uid('anonymous_user'))
              and p.display_name is null and not p.is_tester and p.revision = 1),
  2, 'a profile is created for every new auth user, with no display name and is_tester false');
select is((select count(*)::int from public.project_members
            where project_id = 'a0000000-0000-4000-8000-000000000001' and role = 'owner'
              and user_id = tests.get_supabase_uid('owner_a')),
  1, 'creating a project creates exactly one owner membership for its owner');

-- T-DB-01: unauthenticated ---------------------------------------------------------------------------------------
select tests.clear_authentication();
select throws_ok('select count(*) from public.profiles', '42501', 'permission denied for table profiles',
  'T-DB-01: unauthenticated select on profiles is denied');
select throws_ok('select count(*) from public.projects', '42501', 'permission denied for table projects',
  'T-DB-01: unauthenticated select on projects is denied');
select throws_ok('select count(*) from public.project_members', '42501',
  'permission denied for table project_members', 'T-DB-01: unauthenticated select on project_members is denied');
select throws_ok('select count(*) from public.camera_invites', '42501',
  'permission denied for table camera_invites', 'T-DB-01: unauthenticated select on camera_invites is denied');
select throws_ok($$insert into public.projects (local_project_id, title) values (gen_random_uuid(), 'x')$$, '42501',
  'permission denied for table projects', 'T-DB-01: unauthenticated insert into projects is denied');
select throws_ok($$select app_private.has_project_role('a0000000-0000-4000-8000-000000000001', '{owner}')$$,
  '42501', null, 'T-DB-01: unauthenticated callers cannot reach the app_private helpers');
select is_empty($$
  select c.relname::text from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind in ('r', 'p')
     and (has_any_column_privilege('anon', c.oid, 'select') or has_any_column_privilege('anon', c.oid, 'insert')
          or has_any_column_privilege('anon', c.oid, 'update') or has_table_privilege('anon', c.oid, 'delete'))
$$, 'T-DB-01: anon holds no privilege on any table in public');

-- Owner ----------------------------------------------------------------------------------------------------------
select tests.authenticate_as('owner_a');
select results_eq($$select id::text from public.projects order by id$$,
  $$values ('a0000000-0000-4000-8000-000000000001')$$,
  'owner sees their live project only (not B, not the deleted D)');
select is((select count(*)::int from public.project_members
            where project_id = 'a0000000-0000-4000-8000-000000000001'), 5,
  'owner sees every membership row of their project (owner, coach, pending, revoked, expired)');
select is((select count(*)::int from public.camera_invites), 2, 'owner sees the camera invites of their live project');
select throws_ok('select code_hash from public.camera_invites', '42501', 'permission denied for table camera_invites',
  'owner cannot select camera_invites.code_hash');
select throws_ok('select device_key_thumbprint from public.camera_invites', '42501',
  'permission denied for table camera_invites', 'owner cannot select the guest device thumbprint');
select results_eq($$
  insert into public.projects (local_project_id, title, kind)
  values ('a1000000-0000-4000-8000-000000000002', 'Doubles', 'match')
  returning owner_id, revision, deleted_at is null$$,
  $$values (tests.get_supabase_uid('owner_a'), 1::bigint, true)$$,
  'owner creates a project through the client path; owner_id defaults to auth.uid()');
select is((select role::text from public.project_members m join public.projects p on p.id = m.project_id
            where p.local_project_id = 'a1000000-0000-4000-8000-000000000002'),
  'owner', 'the new project''s owner membership is visible to the owner');
select results_eq($$update public.projects set title = 'Club final (edited)'
                    where id = 'a0000000-0000-4000-8000-000000000001' returning revision$$,
  $$values (2::bigint)$$, 'owner updates the title of their project; revision is bumped');
select throws_ok($$insert into public.camera_invites (project_id, slot, code_hash, created_by, redeem_by)
                   values ('a0000000-0000-4000-8000-000000000001', 'near_ad_corner', sha256('x'::bytea),
                           auth.uid(), now())$$,
  '42501', 'permission denied for table camera_invites', 'owner cannot write camera_invites directly');
select throws_ok($$delete from public.projects where id = 'a0000000-0000-4000-8000-000000000001'$$, '42501',
  'permission denied for table projects', 'owner cannot delete a project (deletion goes through deletion_requests)');

-- T-DB-08: owner_id is immutable
select throws_ok($$update public.projects set owner_id = tests.get_supabase_uid('unrelated')
                   where id = 'a0000000-0000-4000-8000-000000000001'$$,
  '42501', 'permission denied for table projects', 'T-DB-08: owner cannot update projects.owner_id');
select throws_ok($$update public.projects set deleted_at = null where id = 'd0000000-0000-4000-8000-000000000001'$$,
  '42501', 'permission denied for table projects', 'T-DB-08: owner cannot clear deleted_at');

-- T-DB-09: another owner's project
select is_empty($$update public.projects set title = 'hijacked' where id = 'b0000000-0000-4000-8000-000000000001'
                  returning id$$, 'T-DB-09: owner updating another owner''s project title changes 0 rows');

-- T-DB-10: no self-grant or escalation
select throws_ok($$insert into public.project_members (project_id, user_id, role)
                   values ('a0000000-0000-4000-8000-000000000001', tests.get_supabase_uid('unrelated'), 'coach')$$,
  '42501', 'permission denied for table project_members', 'T-DB-10: owner cannot insert a membership directly');
select throws_ok($$update public.project_members set approved_at = now()
                   where user_id = tests.get_supabase_uid('pending_coach')$$,
  '42501', 'permission denied for table project_members',
  'T-DB-10: owner cannot approve a coach by writing project_members (approve_member only)');

-- T-DB-31: a project whose deletion has started is gone for its owner
select is((select count(*)::int from public.project_members where project_id = 'd0000000-0000-4000-8000-000000000001'),
  0, 'T-DB-31: owner sees no membership rows of a project with deleted_at set');
select is((select count(*)::int from public.camera_invites where project_id = 'd0000000-0000-4000-8000-000000000001'),
  0, 'T-DB-31: owner sees no camera invites of a project with deleted_at set');
select is_empty($$update public.projects set title = 'revived' where id = 'd0000000-0000-4000-8000-000000000001'
                  returning id$$, 'T-DB-31: owner cannot update a project with deleted_at set');

-- T-DB-63 (owner side): a pending coach's profile is not shared before approval
select results_eq($$select id from public.profiles order by id$$,
  $$select id from (values (tests.get_supabase_uid('owner_a')), (tests.get_supabase_uid('coach'))) v(id) order by id$$,
  'T-DB-63: owner sees self and the approved coach; not the pending, revoked or expired coaches');

-- T-DB-30: profiles
select throws_ok('select is_tester from public.profiles', '42501', 'permission denied for table profiles',
  'T-DB-30: is_tester is not selectable');
select throws_ok('select updated_at, revision from public.profiles', '42501', 'permission denied for table profiles',
  'T-DB-30: only id, display_name and created_at are selectable');
select results_eq($$update public.profiles set display_name = 'Alex' where id = auth.uid() returning display_name$$,
  $$values ('Alex'::text)$$, 'T-DB-30: a user updates their own display name');
select throws_ok($$update public.profiles set is_tester = true where id = auth.uid()$$, '42501',
  'permission denied for table profiles', 'T-DB-30: a user cannot set is_tester');
select throws_ok($$insert into public.profiles (id) values (gen_random_uuid())$$, '42501',
  'permission denied for table profiles', 'T-DB-30: profiles cannot be inserted by a client');

-- T-DB-06 / T-DB-07 / T-DB-30: unrelated user ---------------------------------------------------------------------
select tests.authenticate_as('unrelated');
select is((select count(*)::int from public.projects), 0, 'T-DB-06: unrelated user sees 0 projects of other owners');
select is((select count(*)::int from public.project_members), 0, 'T-DB-06: unrelated user sees 0 membership rows');
select is((select count(*)::int from public.camera_invites), 0, 'T-DB-06: unrelated user sees 0 camera invites');
select results_eq($$select id from public.profiles$$, $$values (tests.get_supabase_uid('unrelated'))$$,
  'T-DB-30: unrelated user sees only their own profile');
select is_empty($$update public.profiles set display_name = 'pwned' where id = tests.get_supabase_uid('owner_a')
                  returning id$$, 'T-DB-30: updating another user''s profile changes 0 rows');
select throws_ok($$insert into public.projects (owner_id, local_project_id, title)
                   values (tests.get_supabase_uid('owner_a'), gen_random_uuid(), 'planted')$$,
  '42501', 'permission denied for table projects', 'T-DB-07: inserting a project for another owner is denied');
select is_empty($$update public.projects set title = 'x' where id = 'a0000000-0000-4000-8000-000000000001'
                  returning id$$, 'T-DB-06: unrelated user cannot update another owner''s project');
select is(app_private.has_project_role('a0000000-0000-4000-8000-000000000001', '{owner,coach}'), false,
  'T-DB-06: has_project_role is false for an unrelated user');
select is(app_private.shares_project_with(tests.get_supabase_uid('owner_a')), false,
  'T-DB-06: shares_project_with is false for an unrelated user');

-- Approved coach ---------------------------------------------------------------------------------------------------
select tests.authenticate_as('coach');
select results_eq($$select id::text from public.projects$$, $$values ('a0000000-0000-4000-8000-000000000001')$$,
  'coach sees the project they coach (not the deleted D, not B)');
select results_eq($$select user_id from public.project_members$$, $$values (tests.get_supabase_uid('coach'))$$,
  'coach sees only their own membership row');
select results_eq($$select id from public.profiles order by id$$,
  $$select id from (values (tests.get_supabase_uid('owner_a')), (tests.get_supabase_uid('coach'))) v(id) order by id$$,
  'coach sees self and the project owner (co-member); not the pending coach');
select is((select count(*)::int from public.camera_invites), 0, 'coach sees no camera invites');
select is(app_private.project_role('a0000000-0000-4000-8000-000000000001')::text, 'coach',
  'project_role is coach for an approved coach');
-- T-DB-11
select is_empty($$update public.projects set title = 'coach edit' where id = 'a0000000-0000-4000-8000-000000000001'
                  returning id$$, 'T-DB-11: coach updating the project title changes 0 rows');
-- T-DB-10
select throws_ok($$insert into public.project_members (project_id, user_id, role)
                   values ('a0000000-0000-4000-8000-000000000001', auth.uid(), 'owner')$$,
  '42501', 'permission denied for table project_members', 'T-DB-10: coach cannot grant themselves owner');
select throws_ok($$update public.project_members set role = 'owner' where user_id = auth.uid()$$,
  '42501', 'permission denied for table project_members', 'T-DB-10: coach cannot escalate their role');
-- T-DB-31
select is(app_private.has_project_role('d0000000-0000-4000-8000-000000000001', '{coach}'), false,
  'T-DB-31: a coach row on a deleted project grants nothing');

-- T-DB-63: pending coach (redeemed, not approved) ------------------------------------------------------------------
select tests.authenticate_as('pending_coach');
select results_eq($$select id from public.profiles$$, $$values (tests.get_supabase_uid('pending_coach'))$$,
  'T-DB-63: a pending coach sees only their own profile');
select is((select count(*)::int from public.project_members), 0, 'T-DB-63: a pending coach sees 0 membership rows');
select is((select count(*)::int from public.projects), 0, 'T-DB-63: a pending coach sees 0 projects');
select is(app_private.shares_project_with(tests.get_supabase_uid('owner_a')), false,
  'T-DB-63: shares_project_with is false while the coach is pending');

-- Viewer (no grant table yet; the viewer paths land with access_grants in migration 3) -----------------------------
select tests.authenticate_as('viewer');
select is((select count(*)::int from public.projects) + (select count(*)::int from public.project_members)
          + (select count(*)::int from public.camera_invites), 0,
  'viewer without a grant sees no project, membership or invite');
select results_eq($$select id from public.profiles$$, $$values (tests.get_supabase_uid('viewer'))$$,
  'viewer sees only their own profile');

-- Camera uploader (signed in) --------------------------------------------------------------------------------------
select tests.authenticate_as('camera');
select results_eq($$select id::text, display_label from public.camera_invites$$,
  $$values ('c0000000-0000-4000-8000-000000000001', 'Far corner')$$,
  'camera sees the invite it redeemed after approval, and not the unapproved one');
select is((select count(*)::int from public.projects) + (select count(*)::int from public.project_members), 0,
  'camera sees no project and no membership');
select results_eq($$select id from public.profiles$$, $$values (tests.get_supabase_uid('camera'))$$,
  'camera sees only its own profile');

-- T-DB-28: anonymous-authenticated (is_anonymous true) --------------------------------------------------------------
-- Claims first (still postgres), then the role, as PostgREST does for a token whose is_anonymous claim is true.
select set_config('request.jwt.claims', jsonb_build_object(
  'sub', tests.get_supabase_uid('anonymous_user')::text,
  'role', 'authenticated', 'aud', 'authenticated', 'is_anonymous', true)::text, true);
select set_config('role', 'authenticated', true);
select is(auth.uid() is not null and (auth.jwt() ->> 'is_anonymous')::boolean, true,
  'T-DB-28: acting as an anonymous-authenticated user');
select is((select count(*)::int from public.profiles), 0, 'T-DB-28: anonymous user sees 0 profiles, not even its own');
select is((select count(*)::int from public.projects), 0, 'T-DB-28: anonymous user sees 0 projects');
select is((select count(*)::int from public.project_members), 0, 'T-DB-28: anonymous user sees 0 memberships');
select is((select count(*)::int from public.camera_invites), 0, 'T-DB-28: anonymous user sees 0 camera invites');
select throws_ok($$insert into public.projects (local_project_id, title) values (gen_random_uuid(), 'lobby')$$,
  '42501', 'new row violates row-level security policy for table "projects"',
  'T-DB-28: anonymous user cannot insert a project (RLS violation)');
select is_empty($$update public.profiles set display_name = 'anon' where id = auth.uid() returning id$$,
  'T-DB-28: anonymous user cannot update even its own profile');

-- T-DB-32: revocation and expiry apply immediately, with no token refresh --------------------------------------------
select tests.authenticate_as('revoked_coach');
select is((select count(*)::int from public.projects) + (select count(*)::int from public.project_members), 0,
  'T-DB-32: a revoked coach sees 0 projects and 0 memberships');
select tests.authenticate_as('expired_coach');
select is((select count(*)::int from public.projects) + (select count(*)::int from public.project_members), 0,
  'T-DB-32: an expired coach sees 0 projects and 0 memberships');
-- The approved coach loses access mid-session: same claims, the row changes underneath.
reset role;
update public.project_members set revoked_at = now()
 where project_id = 'a0000000-0000-4000-8000-000000000001' and user_id = tests.get_supabase_uid('coach');
select tests.authenticate_as('coach');
select is((select count(*)::int from public.projects), 0, 'T-DB-32: revoking the coach removes the project at once');
select results_eq($$select id from public.profiles$$, $$values (tests.get_supabase_uid('coach'))$$,
  'T-DB-32: the revoked coach no longer sees the owner''s profile');
reset role;

-- After all of it, nothing an attacker tried landed --------------------------------------------------------------
select results_eq($$select title, revision from public.projects where id = 'b0000000-0000-4000-8000-000000000001'$$,
  $$values ('Serve practice'::text, 1::bigint)$$, 'B''s title and revision are untouched');
select results_eq($$select owner_id from public.projects where id = 'a0000000-0000-4000-8000-000000000001'$$,
  $$values (tests.get_supabase_uid('owner_a'))$$, 'A''s owner is unchanged');
select is((select display_name from public.profiles where id = tests.get_supabase_uid('owner_a')), 'Alex',
  'owner_a''s display name is the one they set');

select * from finish();
rollback;
