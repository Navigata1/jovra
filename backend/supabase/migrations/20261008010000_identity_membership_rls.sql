-- S76 / B-03: migration 1. Schemas, roles, enums, identity and membership tables, helpers, triggers and RLS,
-- with the B-23/B-25 hardening that lands in these tables (docs/backend/security-model.md §3, §4, §5.1, §5.2,
-- §9, §13.0, §13.11; architecture.md §4.1-§4.4):
--   * one owner role, jovra_owner, owns every table, helper, trigger function and enum (finding 26, T-DB-66);
--   * a role-first a00_rls_guard BEFORE trigger on every client-insertable table, calling the same predicate as
--     the INSERT policy, so no trigger can answer before RLS does (finding 24, T-DB-65/67);
--   * shares_project_with applies the approval predicate on both sides, so a pending coach shares nothing
--     (finding 21, T-DB-63);
--   * coded P0422 errors before any CHECK or NOT NULL constraint can emit a "Failing row contains" DETAIL.
--
-- Builds on 20261008000000_tester_signup_lock.sql (app_private, app_ops, the auth hook) and keeps its grants.
-- Nothing here names a hosted project or holds a password: the two login roles get theirs out of band (gate G2).

-- 1. Schemas --------------------------------------------------------------------------------------------------------
create schema if not exists app_private;   -- RLS helpers and trigger functions; never exposed through PostgREST
create schema if not exists app_gateway;   -- command functions (B-06); never exposed
create schema if not exists app_ops;       -- server-only tables; never exposed

revoke all on schema app_gateway from public, anon, authenticated, service_role;
-- Policies call the helpers as the querying role; EXECUTE is granted per helper in section 9.
grant usage on schema app_private to authenticated;

-- 2. Roles (cluster-wide, so created only when missing; `supabase db reset` keeps roles) ----------------------------
do $$
begin
  if not exists (select from pg_catalog.pg_roles where rolname = 'jovra_owner') then
    create role jovra_owner nologin noinherit nobypassrls;
  end if;
  if not exists (select from pg_catalog.pg_roles where rolname = 'jovra_gateway') then
    create role jovra_gateway login noinherit nobypassrls connection limit 20;
  end if;
  if not exists (select from pg_catalog.pg_roles where rolname = 'jovra_orchestrator') then
    create role jovra_orchestrator login noinherit nobypassrls connection limit 10;
  end if;
end
$$;

-- The migrating role (postgres on Supabase) creates objects and then hands them to jovra_owner; ALTER ... OWNER
-- needs SET on the new owner, and inheriting it keeps the operator's seed writes working. The grantee is named:
-- a CURRENT_USER role spec carries no name for Supabase's role hooks to check.
grant jovra_owner to postgres;
grant usage, create on schema public, app_private, app_gateway, app_ops to jovra_owner;
grant usage on schema app_gateway to jovra_gateway, jovra_orchestrator;

-- Supabase grants new public tables and functions to anon/authenticated by default; this migration revokes them
-- and grants back only what §5.2 lists. Per-schema defaults cannot revoke PUBLIC's global EXECUTE, so that one is
-- revoked globally for jovra_owner (objects created as jovra_owner) and per object below (objects handed to it).
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from anon, authenticated;
alter default privileges for role jovra_owner revoke execute on functions from public;
alter default privileges for role jovra_owner in schema public, app_private, app_gateway
  revoke execute on functions from anon, authenticated;

-- 3. Enumerated types (architecture §4.2) ---------------------------------------------------------------------------
create type public.member_role    as enum ('owner', 'coach');   -- coach = "coach or editor"
create type public.camera_slot    as enum ('primary_baseline', 'opposite_baseline', 'near_deuce_corner',
                                           'near_ad_corner', 'far_deuce_corner', 'far_ad_corner');
create type public.source_state   as enum ('declared', 'uploading', 'uploaded_unverified', 'verified', 'rejected',
                                           'deleted');
create type public.provenance     as enum ('manual', 'estimated', 'reviewed', 'validated');
create type public.review_state   as enum ('estimated', 'needs_review', 'reviewed', 'rejected');
create type public.planner_kind   as enum ('heuristic', 'model', 'user');
create type public.job_state      as enum ('consented', 'upload_pending', 'uploading', 'queued', 'normalizing',
                                           'syncing', 'analyzing', 'planning', 'preview_rendering',
                                           'awaiting_review', 'final_rendering', 'verifying', 'ready', 'paused',
                                           'canceled', 'failed_retryable', 'failed_terminal', 'quote_expired',
                                           'budget_exceeded', 'deleted');
create type public.job_stage      as enum ('verify_sources', 'normalize', 'sync', 'analyze', 'plan', 'validate',
                                           'preview_render', 'final_render', 'remux_no_audio', 'verify_output',
                                           'deliver', 'cleanup');
create type public.artifact_kind  as enum ('analysis_proxy', 'render_proxy', 'pts_table', 'frame_set',
                                           'contact_sheet', 'preview', 'film', 'thumbnail', 'captions', 'chapters',
                                           'edit_manifest', 'project_bundle', 'clip_excerpt');
create type public.grant_kind     as enum ('project_coach', 'lesson_coach', 'lesson_view', 'film_view',
                                           'lesson_clip_view', 'share_link');
create type public.provider_kind  as enum ('files_icloud', 'google_drive', 'box', 'dropbox');
create type public.deletion_scope as enum ('account', 'project', 'source', 'artifact', 'lesson', 'lesson_clip');

-- 4. Tables (architecture §4.3, identity and membership) ------------------------------------------------------------
-- The CHECKs stay as a backstop; the a10_validate triggers raise coded errors first (section 7).
create table public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text check (char_length(display_name) <= 80),   -- user-entered; never logged
  is_tester    boolean not null default false,                -- operator-set; read only by accept_quote (§13.3)
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  revision     bigint not null default 1
);
comment on table public.profiles is 'One per auth user, created by trigger. Email stays in auth.users.';

create table public.projects (
  id                               uuid primary key default gen_random_uuid(),
  owner_id                         uuid not null default auth.uid()
                                     references public.profiles (id) on delete cascade,
  local_project_id                 uuid not null,
  title                            text not null default '' check (char_length(title) <= 120),
  kind                             text not null default 'match' check (kind in ('match', 'import', 'lesson_set')),
  sample                           boolean not null default false,
  current_event_revision           int,
  current_source_manifest_revision int,
  current_sync_map_revision        int,
  created_at                       timestamptz not null default now(),
  updated_at                       timestamptz not null default now(),
  revision                         bigint not null default 1,
  deleted_at                       timestamptz,
  unique (owner_id, local_project_id)
);

create table public.project_members (
  project_id  uuid not null references public.projects (id) on delete cascade,
  user_id     uuid not null references public.profiles (id) on delete cascade,
  role        public.member_role not null,
  granted_by  uuid references public.profiles (id) on delete set null,
  grant_id    uuid,   -- the redeemed project_coach grant; FK to access_grants(id) on delete cascade lands with B-05
  approved_at timestamptz,   -- coach rows: the owner approved the redemption; helpers ignore the row until then
  created_at  timestamptz not null default now(),
  expires_at  timestamptz,
  revoked_at  timestamptz,
  primary key (project_id, user_id)
);
create index project_members_user_id_idx on public.project_members (user_id);
create unique index project_members_one_owner_idx on public.project_members (project_id) where role = 'owner';

create table public.camera_invites (
  id                    uuid primary key default gen_random_uuid(),
  project_id            uuid not null references public.projects (id) on delete cascade,
  slot                  public.camera_slot not null,
  display_label         text not null default '' check (char_length(display_label) <= 60),
  code_hash             bytea not null unique check (octet_length(code_hash) = 32),
  created_by            uuid not null references public.profiles (id) on delete cascade,
  created_at            timestamptz not null default now(),
  redeem_by             timestamptz not null,
  redeemed_at           timestamptz,
  redeemed_by_user_id   uuid references public.profiles (id) on delete set null,
  device_key_thumbprint bytea check (octet_length(device_key_thumbprint) = 32),
  approved_at           timestamptz,
  capability_expires_at timestamptz,
  max_bytes             bigint not null default 8589934592 check (max_bytes > 0),   -- 8 GiB (INFERRED cap)
  revoked_at            timestamptz,
  check (redeem_by <= created_at + interval '10 minutes'),
  check (approved_at is null or redeemed_at is not null),
  check (capability_expires_at is null
         or (approved_at is not null and capability_expires_at <= approved_at + interval '24 hours'))
);
create index camera_invites_project_id_idx on public.camera_invites (project_id);
create index camera_invites_redeemed_by_user_id_idx on public.camera_invites (redeemed_by_user_id);
create index camera_invites_created_by_idx on public.camera_invites (created_by);
-- One open invite per slot. Expiry cannot be in the predicate (now() is not immutable); create_camera_invite
-- revokes an expired unredeemed invite under FOR UPDATE before inserting (B-06).
create unique index camera_invites_one_open_per_slot_idx on public.camera_invites (project_id, slot)
  where revoked_at is null and redeemed_at is null;

-- 5. Helpers (security-model §4, §13.0) ------------------------------------------------------------------------------
-- The definer helpers run as jovra_owner, which has no access to the auth schema, so they read the request claims
-- the way auth.uid() and auth.jwt() do (identity_03 pins current_actor() to auth.uid()). Policies call auth.uid()
-- directly, as the querying role.
create function app_private.current_actor() returns uuid
language sql stable set search_path = '' as $$
  select nullif(coalesce(nullif(pg_catalog.current_setting('request.jwt.claim.sub', true), ''),
                         (nullif(pg_catalog.current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')),
                '')::uuid
$$;

create function app_private.is_real_user() returns boolean
language sql stable set search_path = '' as $$
  select app_private.current_actor() is not null
     and coalesce((coalesce(nullif(pg_catalog.current_setting('request.jwt.claim', true), ''),
                            nullif(pg_catalog.current_setting('request.jwt.claims', true), ''))::jsonb
                   ->> 'is_anonymous')::boolean, false) = false
$$;

-- PostgREST sets the role setting per request; a security definer function changes current_user, not the setting.
create function app_private.is_client_path() returns boolean
language sql stable set search_path = '' as $$
  select coalesce(pg_catalog.current_setting('role', true), '') in ('authenticated', 'anon')
$$;

create function app_private.project_role(p_project uuid) returns public.member_role
language sql stable security definer set search_path = '' as $$
  select m.role
    from public.project_members m
    join public.projects p on p.id = m.project_id
   where m.project_id = p_project
     and m.user_id = (select app_private.current_actor())
     and m.revoked_at is null
     and (m.expires_at is null or m.expires_at > now())
     and (m.role = 'owner' or m.approved_at is not null)   -- a redeemed coach code is pending until approved
     and p.deleted_at is null
$$;

create function app_private.has_project_role(p_project uuid, p_roles public.member_role[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(app_private.project_role(p_project) = any (p_roles), false)
$$;

create function app_private.shares_project_with(p_user uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.project_members a
                   join public.project_members b on a.project_id = b.project_id
                   join public.projects p on p.id = a.project_id and p.deleted_at is null
                  where a.user_id = (select app_private.current_actor()) and b.user_id = p_user
                    and a.revoked_at is null and b.revoked_at is null
                    and (a.expires_at is null or a.expires_at > now())
                    and (b.expires_at is null or b.expires_at > now())
                    -- the activity predicate of project_role on both sides: a pending (unapproved) coach shares
                    -- nothing, so a stranger awaiting approval cannot read members' display names (T-DB-63)
                    and (a.role = 'owner' or a.approved_at is not null)
                    and (b.role = 'owner' or b.approved_at is not null))
$$;

-- A project whose deletion has started is hidden everywhere (T-DB-31), also from a camera that cannot read it.
create function app_private.project_is_live(p_project uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.projects p where p.id = p_project and p.deleted_at is null)
$$;

-- The INSERT predicate for projects, shared by the policy and the a00_rls_guard trigger (§13.11).
create function app_private.can_insert_projects(p_owner uuid, p_deleted_at timestamptz) returns boolean
language sql stable set search_path = '' as $$
  select app_private.is_real_user()
     and coalesce(p_owner = app_private.current_actor(), false)
     and p_deleted_at is null
$$;

-- 6. Trigger functions (architecture §4.4) ----------------------------------------------------------------------------
create function app_private.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end
$$;

create function app_private.bump_revision() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.revision := old.revision + 1;
  new.updated_at := now();
  return new;
end
$$;

-- a00: same error as RLS, before any lock, lookup or validation (finding 24).
create function app_private.rls_guard_projects() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if app_private.is_client_path() and not app_private.can_insert_projects(new.owner_id, new.deleted_at) then
    raise exception using errcode = '42501',
      message = 'new row violates row-level security policy for table "projects"';
  end if;
  return new;
end
$$;

-- a10: coded errors without values (security-model §9).
create function app_private.validate_profiles() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.display_name is not null and char_length(new.display_name) > 80 then
    raise exception using errcode = 'P0422', message = 'field_too_long:display_name';
  end if;
  if new.is_tester is null then
    raise exception using errcode = 'P0422', message = 'required:is_tester';
  end if;
  return new;
end
$$;

create function app_private.validate_projects() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.owner_id is null then
    raise exception using errcode = 'P0422', message = 'required:owner_id';
  end if;
  if new.local_project_id is null then
    raise exception using errcode = 'P0422', message = 'required:local_project_id';
  end if;
  if new.title is null then
    raise exception using errcode = 'P0422', message = 'required:title';
  end if;
  if char_length(new.title) > 120 then
    raise exception using errcode = 'P0422', message = 'field_too_long:title';
  end if;
  if new.kind is null or new.kind not in ('match', 'import', 'lesson_set') then
    raise exception using errcode = 'P0422', message = 'invalid_value:kind';
  end if;
  if new.sample is null then
    raise exception using errcode = 'P0422', message = 'required:sample';
  end if;
  return new;
end
$$;

create function app_private.validate_project_members() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.project_id is null or new.user_id is null or new.role is null then
    raise exception using errcode = 'P0422', message = 'required:project_member';
  end if;
  -- exactly one owner row, equal to projects.owner_id (architecture §4.3)
  if new.role = 'owner'
     and new.user_id is distinct from (select p.owner_id from public.projects p where p.id = new.project_id) then
    raise exception using errcode = 'P0422', message = 'invalid_value:role';
  end if;
  return new;
end
$$;

create function app_private.validate_camera_invites() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.project_id is null or new.slot is null or new.created_by is null or new.redeem_by is null
     or new.display_label is null or new.max_bytes is null then
    raise exception using errcode = 'P0422', message = 'required:camera_invite';
  end if;
  if char_length(new.display_label) > 60 then
    raise exception using errcode = 'P0422', message = 'field_too_long:display_label';
  end if;
  if new.code_hash is null or octet_length(new.code_hash) <> 32 then
    raise exception using errcode = 'P0422', message = 'invalid_value:code_hash';
  end if;
  if new.device_key_thumbprint is not null and octet_length(new.device_key_thumbprint) <> 32 then
    raise exception using errcode = 'P0422', message = 'invalid_value:device_key_thumbprint';
  end if;
  if new.redeem_by > new.created_at + interval '10 minutes' then
    raise exception using errcode = 'P0422', message = 'invalid_value:redeem_by';
  end if;
  if new.approved_at is not null and new.redeemed_at is null then
    raise exception using errcode = 'P0422', message = 'invalid_value:approved_at';
  end if;
  if new.capability_expires_at is not null
     and (new.approved_at is null or new.capability_expires_at > new.approved_at + interval '24 hours') then
    raise exception using errcode = 'P0422', message = 'invalid_value:capability_expires_at';
  end if;
  if new.max_bytes <= 0 then
    raise exception using errcode = 'P0422', message = 'invalid_value:max_bytes';
  end if;
  if new.created_by is distinct from (select p.owner_id from public.projects p where p.id = new.project_id) then
    raise exception using errcode = 'P0422', message = 'invalid_value:created_by';
  end if;
  return new;
end
$$;

-- The owner row, so the helpers treat owners and coaches uniformly.
create function app_private.create_owner_membership() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.project_members (project_id, user_id, role) values (new.id, new.owner_id, 'owner');
  return new;
end
$$;

-- 7. Triggers (names sort in the §13.0 order; same-event triggers fire alphabetically) -------------------------------
create trigger jovra_handle_new_user after insert on auth.users
  for each row execute function app_private.handle_new_user();

create trigger a10_validate before insert or update on public.profiles
  for each row execute function app_private.validate_profiles();
create trigger b50_bump_revision before update on public.profiles
  for each row execute function app_private.bump_revision();

create trigger a00_rls_guard before insert on public.projects
  for each row execute function app_private.rls_guard_projects();
create trigger a10_validate before insert or update on public.projects
  for each row execute function app_private.validate_projects();
create trigger b50_bump_revision before update on public.projects
  for each row execute function app_private.bump_revision();
create trigger a10_create_owner_membership after insert on public.projects
  for each row execute function app_private.create_owner_membership();

create trigger a10_validate before insert or update on public.project_members
  for each row execute function app_private.validate_project_members();

create trigger a10_validate before insert or update on public.camera_invites
  for each row execute function app_private.validate_camera_invites();

-- 8. Row level security (security-model §5.1, §5.2) -------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.projects enable row level security;
alter table public.project_members enable row level security;
alter table public.camera_invites enable row level security;

-- Anonymous Supabase users (test-only lobby experiments) never touch Studio tables.
create policy profiles_real_users_only on public.profiles as restrictive for all to authenticated
  using (app_private.is_real_user()) with check (app_private.is_real_user());
create policy projects_real_users_only on public.projects as restrictive for all to authenticated
  using (app_private.is_real_user()) with check (app_private.is_real_user());
create policy project_members_real_users_only on public.project_members as restrictive for all to authenticated
  using (app_private.is_real_user()) with check (app_private.is_real_user());
create policy camera_invites_real_users_only on public.camera_invites as restrictive for all to authenticated
  using (app_private.is_real_user()) with check (app_private.is_real_user());

-- profiles: self, and members of a project both sides actively share. No insert (trigger), no delete (deletion
-- workflow).
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or app_private.shares_project_with(id));
create policy profiles_update on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- projects: the owner and active coaches read; only the owner inserts and edits title/kind. No delete grant.
create policy projects_select on public.projects for select to authenticated
  using (deleted_at is null and (owner_id = (select auth.uid()) or app_private.has_project_role(id, '{coach}')));
create policy projects_insert on public.projects for insert to authenticated
  with check (app_private.can_insert_projects(owner_id, deleted_at));
create policy projects_update on public.projects for update to authenticated
  using (owner_id = (select auth.uid()) and deleted_at is null)
  with check (owner_id = (select auth.uid()));

-- project_members (writes only via app_gateway): the owner reads the project's rows; a coach reads its own row
-- while it is active (approved, not revoked or expired, project live), so a pending coach sees 0 rows (T-DB-63)
-- and a revoked one 0 rows at once (T-DB-32). Narrower than §5.2's "user_id = auth.uid()" so T-DB-31/32/63 hold.
create policy project_members_select on public.project_members for select to authenticated
  using (app_private.has_project_role(project_id, '{owner}')
         or (user_id = (select auth.uid()) and app_private.has_project_role(project_id, '{coach}')));

-- camera_invites (writes only via app_gateway); code_hash and the device thumbprint are never selectable.
create policy camera_invites_select on public.camera_invites for select to authenticated
  using (app_private.has_project_role(project_id, '{owner}')
         or (redeemed_by_user_id = (select auth.uid())
             and approved_at is not null and revoked_at is null           -- nothing before approval
             and app_private.project_is_live(project_id)));

-- 9. Grants -----------------------------------------------------------------------------------------------------------
revoke all on public.profiles, public.projects, public.project_members, public.camera_invites
  from public, anon, authenticated;

grant select (id, display_name, created_at) on public.profiles to authenticated;
grant update (display_name) on public.profiles to authenticated;

grant select on public.projects to authenticated;
grant insert (local_project_id, title, kind, sample) on public.projects to authenticated;   -- owner_id: auth.uid()
grant update (title, kind) on public.projects to authenticated;

grant select on public.project_members to authenticated;

grant select (id, project_id, slot, display_label, redeem_by, redeemed_at, approved_at, capability_expires_at,
              max_bytes, revoked_at, created_at) on public.camera_invites to authenticated;

revoke all on function
  app_private.current_actor(), app_private.is_real_user(), app_private.is_client_path(),
  app_private.project_role(uuid), app_private.has_project_role(uuid, public.member_role[]),
  app_private.shares_project_with(uuid), app_private.project_is_live(uuid),
  app_private.can_insert_projects(uuid, timestamptz),
  app_private.handle_new_user(), app_private.bump_revision(), app_private.rls_guard_projects(),
  app_private.validate_profiles(), app_private.validate_projects(), app_private.validate_project_members(),
  app_private.validate_camera_invites(), app_private.create_owner_membership()
  from public, anon, authenticated, service_role;

-- Only what policies call. is_client_path() and every trigger function: no EXECUTE for any client role.
grant execute on function
  app_private.current_actor(), app_private.is_real_user(), app_private.project_role(uuid),
  app_private.has_project_role(uuid, public.member_role[]), app_private.shares_project_with(uuid),
  app_private.project_is_live(uuid), app_private.can_insert_projects(uuid, timestamptz)
  to authenticated;

-- 10. One owner (T-DB-66). Last, so every grant above was made by the migrating role. ---------------------------------
alter table public.profiles owner to jovra_owner;
alter table public.projects owner to jovra_owner;
alter table public.project_members owner to jovra_owner;
alter table public.camera_invites owner to jovra_owner;
alter table app_ops.tester_allowlist owner to jovra_owner;

alter type public.member_role owner to jovra_owner;
alter type public.camera_slot owner to jovra_owner;
alter type public.source_state owner to jovra_owner;
alter type public.provenance owner to jovra_owner;
alter type public.review_state owner to jovra_owner;
alter type public.planner_kind owner to jovra_owner;
alter type public.job_state owner to jovra_owner;
alter type public.job_stage owner to jovra_owner;
alter type public.artifact_kind owner to jovra_owner;
alter type public.grant_kind owner to jovra_owner;
alter type public.provider_kind owner to jovra_owner;
alter type public.deletion_scope owner to jovra_owner;

alter function app_private.current_actor() owner to jovra_owner;
alter function app_private.is_real_user() owner to jovra_owner;
alter function app_private.is_client_path() owner to jovra_owner;
alter function app_private.project_role(uuid) owner to jovra_owner;
alter function app_private.has_project_role(uuid, public.member_role[]) owner to jovra_owner;
alter function app_private.shares_project_with(uuid) owner to jovra_owner;
alter function app_private.project_is_live(uuid) owner to jovra_owner;
alter function app_private.can_insert_projects(uuid, timestamptz) owner to jovra_owner;
alter function app_private.handle_new_user() owner to jovra_owner;
alter function app_private.bump_revision() owner to jovra_owner;
alter function app_private.rls_guard_projects() owner to jovra_owner;
alter function app_private.validate_profiles() owner to jovra_owner;
alter function app_private.validate_projects() owner to jovra_owner;
alter function app_private.validate_project_members() owner to jovra_owner;
alter function app_private.validate_camera_invites() owner to jovra_owner;
alter function app_private.create_owner_membership() owner to jovra_owner;
