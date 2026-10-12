-- S77 / B-04: migration 2. Sources, manifests, sync maps, calibrations, event revisions, observations, lessons,
-- lesson clips, story plans and plan versions, with RLS and the B-23/B-25 hardening that lands in these tables
-- (docs/backend/architecture.md §4.1, §4.3, §4.4; security-model.md §4, §5.3-§5.6, §13.0, §13.5, §13.8-§13.11,
-- §13.16):
--   * composite foreign keys, so a row of project A can never name project B's source, plan or artifact (findings
--     17 and 31); ON DELETE SET NULL (source_id) where a source deletion would otherwise stall (finding 22a);
--   * append-only revision tables: revision/version assigned under a per-project advisory lock, event revisions
--     refused with P0409 on a stale parent, older films, previews, excerpts and plan versions marked stale;
--   * clip share approval pinned by a fingerprint (b20_pin_shared_clip, can_view_lesson_clip), withdrawable with
--     app_gateway.revoke_clip_share (finding 20);
--   * quotas on direct PostgREST writes: per project or per user, plus a per-user aggregate, P0429, fail closed on
--     a missing limits row, never a NULL subject (finding 23);
--   * every client-insertable table: a00_rls_guard calling the INSERT policy's own predicate first (finding 24),
--     coded P0422 errors before any CHECK or NOT NULL can emit a "Failing row contains" DETAIL.
--
-- Two tables of migration 3's list are created here because this migration's policies and triggers need them:
-- `access_grants` (lesson_access, clip sharing) and `artifacts` (lesson_clips.excerpt_artifact_id, stale marking,
-- what a viewer may stream). Their columns follow architecture §4.3 in full; the foreign keys to render_jobs and
-- render_attempts (artifacts.job_id, artifacts.attempt_id) and artifact_sources are added by migration 3 (S78)
-- together with those tables. Audit rows for the clip-share commands and the outbox row that deletes an unlinked
-- excerpt's object also land with S78's app_ops.audit_events and app_ops.job_outbox.
--
-- Hashes use pg_catalog.sha256 (definer functions run as jovra_owner, which has no USAGE on `extensions`).
-- Objects are created by the migrating role and handed to jovra_owner at the end (T-DB-66), as in migration 1.

-- 1. Tables ------------------------------------------------------------------------------------------------------------
-- The CHECKs are a backstop; the a10_validate triggers raise coded errors first (section 3).

create table public.camera_sources (
  id                 uuid primary key default gen_random_uuid(),
  project_id         uuid not null references public.projects (id) on delete cascade,
  slot               public.camera_slot not null,
  local_source_id    uuid not null,
  invite_id          uuid references public.camera_invites (id) on delete set null,
  uploader_user_id   uuid references public.profiles (id) on delete set null,
  label              text not null default '' check (char_length(label) <= 60),
  state              public.source_state not null default 'declared',
  declared_bytes     bigint not null check (declared_bytes > 0),
  declared_sha256    bytea not null check (octet_length(declared_sha256) = 32),
  verified_sha256    bytea check (octet_length(verified_sha256) = 32),
  verified_at        timestamptz,
  retention_until    timestamptz,
  verified_etag      text check (char_length(verified_etag) <= 200),
  current_session_id uuid,
  client_probe       jsonb not null default '{}' check (octet_length(client_probe::text) <= 2048),
  probe              jsonb check (octet_length(probe::text) <= 16384),
  r2_key             text unique check (char_length(r2_key) <= 512),
  rejected_reason    text check (rejected_reason in ('hash_mismatch', 'probe_rejected', 'size_mismatch')),
  participant_ack_at timestamptz,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  revision           bigint not null default 1,
  unique (project_id, id)   -- the target of every composite source FK (finding 31)
);
create unique index camera_sources_one_live_per_slot_idx on public.camera_sources (project_id, slot)
  where state <> 'deleted';
create index camera_sources_invite_id_idx on public.camera_sources (invite_id);
create index camera_sources_uploader_user_id_idx on public.camera_sources (uploader_user_id);

create table public.source_manifests (
  id              uuid primary key default gen_random_uuid(),
  project_id      uuid not null references public.projects (id) on delete cascade,
  revision        int not null,
  manifest        jsonb not null check (octet_length(manifest::text) <= 524288),
  manifest_sha256 bytea not null check (octet_length(manifest_sha256) = 32),
  created_by_kind text not null check (created_by_kind in ('gateway', 'render')),
  created_at      timestamptz not null default now(),
  unique (project_id, revision)
);

create table public.sync_maps (
  id                       uuid primary key default gen_random_uuid(),
  project_id               uuid not null references public.projects (id) on delete cascade,
  revision                 int not null,
  source_manifest_revision int not null,
  map                      jsonb not null check (octet_length(map::text) <= 1048576),
  map_sha256               bytea check (octet_length(map_sha256) = 32),
  review_state             public.review_state not null default 'estimated',
  reviewed_by              uuid references public.profiles (id) on delete set null,
  reviewed_at              timestamptz,
  method                   text check (char_length(method) <= 80),
  method_version           text check (char_length(method_version) <= 40),
  created_by               uuid references public.profiles (id) on delete set null,
  sample                   boolean not null default false,
  created_at               timestamptz not null default now(),
  unique (project_id, revision),
  foreign key (project_id, source_manifest_revision)
    references public.source_manifests (project_id, revision) on delete cascade
);

create table public.calibration_versions (
  id             uuid primary key default gen_random_uuid(),
  project_id     uuid not null references public.projects (id) on delete cascade,
  source_id      uuid not null,
  version        int not null,
  calibration    jsonb not null check (octet_length(calibration::text) <= 65536),
  method         text check (char_length(method) <= 80),
  method_version text check (char_length(method_version) <= 40),
  provenance     public.provenance not null default 'manual',
  reviewed_by    uuid references public.profiles (id) on delete set null,
  reviewed_at    timestamptz,
  created_by     uuid references public.profiles (id) on delete set null,
  created_at     timestamptz not null default now(),
  unique (source_id, version),
  foreign key (project_id, source_id) references public.camera_sources (project_id, id) on delete cascade
);
create index calibration_versions_project_source_idx on public.calibration_versions (project_id, source_id);

create table public.point_event_revisions (
  id               uuid primary key default gen_random_uuid(),
  project_id       uuid not null references public.projects (id) on delete cascade,
  revision         int not null,
  parent_revision  int,
  local_session_id uuid not null,
  schema_version   text not null check (char_length(schema_version) <= 20),
  event_log        jsonb not null check (octet_length(event_log::text) <= 2097152),
  event_log_sha256 bytea not null check (octet_length(event_log_sha256) = 32),
  created_by       uuid references public.profiles (id) on delete set null,
  client_device_id uuid,
  created_at       timestamptz not null default now(),
  unique (project_id, revision),
  check (parent_revision is null or parent_revision = revision - 1)
);

create table public.lessons (
  id              uuid primary key default gen_random_uuid(),
  owner_id        uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  local_lesson_id uuid not null,
  lesson_date     date,
  title           text not null default '' check (char_length(title) <= 120),
  notes           text not null default '' check (char_length(notes) <= 10000),
  next_goal       text not null default '' check (char_length(next_goal) <= 500),
  practice        jsonb not null default '{}' check (octet_length(practice::text) <= 32768),
  sample          boolean not null default false,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  revision        bigint not null default 1,
  unique (owner_id, local_lesson_id)
);

create table public.lesson_clips (
  id                    uuid primary key default gen_random_uuid(),
  lesson_id             uuid not null references public.lessons (id) on delete cascade,
  project_id            uuid not null references public.projects (id) on delete cascade,
  source_id             uuid,
  share_approved_at     timestamptz,
  share_approved_sha256 bytea check (octet_length(share_approved_sha256) = 32),
  match_start_us        bigint not null,
  match_end_us          bigint not null,
  sync_map_revision     int,
  event_revision        int,
  keeper_ref            text check (char_length(keeper_ref) <= 96),
  excerpt_artifact_id   uuid,   -- FK to artifacts below
  note                  text not null default '' check (char_length(note) <= 1000),
  position              int not null default 0,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  revision              bigint not null default 1,
  check (match_start_us >= 0 and match_end_us - match_start_us > 0
         and match_end_us - match_start_us <= 600000000),   -- at most 10 minutes
  check ((share_approved_at is null) = (share_approved_sha256 is null)),
  -- a source of this clip's own project only; deleting the source keeps the clip, marked missing (finding 22a)
  foreign key (project_id, source_id) references public.camera_sources (project_id, id)
    on delete set null (source_id)
);
create index lesson_clips_lesson_id_idx on public.lesson_clips (lesson_id);
create index lesson_clips_project_source_idx on public.lesson_clips (project_id, source_id);

create table public.artifacts (
  id                       uuid primary key default gen_random_uuid(),
  project_id               uuid not null references public.projects (id) on delete cascade,
  job_id                   uuid,   -- FK to render_jobs(id) on delete set null: migration 3 (S78)
  attempt_id               uuid,   -- FK to render_attempts(id) on delete set null: migration 3 (S78)
  source_id                uuid,
  parent_artifact_id       uuid,
  lesson_clip_id           uuid references public.lesson_clips (id) on delete cascade,
  kind                     public.artifact_kind not null,
  bucket_class             text not null check (bucket_class in ('work', 'films')),
  r2_key                   text not null unique check (char_length(r2_key) <= 512),
  bytes                    bigint check (bytes >= 0),
  sha256                   bytea check (octet_length(sha256) = 32),
  media                    jsonb check (octet_length(media::text) <= 16384),
  state                    text not null default 'writing'
                             check (state in ('writing', 'verifying', 'ready', 'failed', 'deleted')),
  verification             jsonb check (octet_length(verification::text) <= 65536),
  edl_sha256               bytea check (octet_length(edl_sha256) = 32),
  event_revision           int,
  sync_map_revision        int,
  source_manifest_revision int,
  profile_id               text check (char_length(profile_id) <= 40),
  profile_revision         int,
  renderer_version         text check (char_length(renderer_version) <= 40),
  stale                    boolean not null default false,
  retention_until          timestamptz,
  display_title            text not null default '' check (char_length(display_title) <= 120),
  sample                   boolean not null default false,
  created_at               timestamptz not null default now(),
  verified_at              timestamptz,
  deleted_at               timestamptz,
  unique (project_id, id),
  foreign key (project_id, source_id) references public.camera_sources (project_id, id) on delete cascade
);
alter table public.artifacts add foreign key (project_id, parent_artifact_id)
  references public.artifacts (project_id, id) on delete cascade;
create index artifacts_parent_artifact_id_idx on public.artifacts (parent_artifact_id);
create index artifacts_lesson_clip_id_idx on public.artifacts (lesson_clip_id);
create index artifacts_project_source_idx on public.artifacts (project_id, source_id);

alter table public.lesson_clips add foreign key (excerpt_artifact_id)
  references public.artifacts (id) on delete set null;
create index lesson_clips_excerpt_artifact_id_idx on public.lesson_clips (excerpt_artifact_id);

create table public.access_grants (
  id                 uuid primary key default gen_random_uuid(),
  kind               public.grant_kind not null,
  project_id         uuid references public.projects (id) on delete cascade,
  lesson_id          uuid references public.lessons (id) on delete cascade,
  artifact_id        uuid,
  lesson_clip_id     uuid references public.lesson_clips (id) on delete cascade,
  grantee_user_id    uuid references public.profiles (id) on delete cascade,
  token_hash         bytea unique check (octet_length(token_hash) = 32),
  invitee_email_hmac bytea check (octet_length(invitee_email_hmac) = 32),
  created_by         uuid not null references public.profiles (id) on delete cascade,
  redeem_by          timestamptz,
  expires_at         timestamptz,
  redeemed_at        timestamptz,
  revoked_at         timestamptz,
  created_at         timestamptz not null default now(),
  foreign key (project_id, artifact_id) references public.artifacts (project_id, id) on delete cascade,
  check (artifact_id is null or project_id is not null),
  -- exactly the target columns the kind needs
  check (case kind
           when 'project_coach' then project_id is not null and num_nulls(lesson_id, artifact_id, lesson_clip_id) = 3
           when 'lesson_coach' then lesson_id is not null and num_nulls(project_id, artifact_id, lesson_clip_id) = 3
           when 'lesson_view' then lesson_id is not null and num_nulls(project_id, artifact_id, lesson_clip_id) = 3
           when 'film_view' then num_nonnulls(project_id, artifact_id) = 2 and num_nulls(lesson_id, lesson_clip_id) = 2
           when 'lesson_clip_view' then lesson_clip_id is not null
                                        and num_nulls(project_id, lesson_id, artifact_id) = 3
           when 'share_link' then num_nonnulls(project_id, artifact_id) = 2
                                  and num_nulls(lesson_id, lesson_clip_id, grantee_user_id) = 3
         end)
);
create index access_grants_grantee_user_id_idx on public.access_grants (grantee_user_id);
create index access_grants_created_by_idx on public.access_grants (created_by);
create index access_grants_lesson_id_idx on public.access_grants (lesson_id);
create index access_grants_lesson_clip_id_idx on public.access_grants (lesson_clip_id);
create index access_grants_project_artifact_idx on public.access_grants (project_id, artifact_id);

-- project_members.grant_id: the redeemed project_coach grant (migration 1 left this FK for the grants table).
alter table public.project_members add foreign key (grant_id) references public.access_grants (id) on delete cascade;
create index project_members_grant_id_idx on public.project_members (grant_id);

create table public.observations (
  id                     uuid primary key default gen_random_uuid(),
  project_id             uuid references public.projects (id) on delete cascade,
  lesson_id              uuid references public.lessons (id) on delete cascade,
  source_id              uuid,
  match_start_us         bigint,
  match_end_us           bigint,
  sync_map_revision      int,
  event_revision         int,
  capability_id          text check (char_length(capability_id) <= 80),
  kind                   text not null check (char_length(kind) between 1 and 40),
  body                   text check (char_length(body) <= 2000),   -- data, never instructions
  provenance             public.provenance not null default 'manual',
  confidence_milli       int check (confidence_milli between 0 and 1000),
  -- a calibration dies with its source; the observation keeps its row (finding 22a)
  calibration_version_id uuid references public.calibration_versions (id) on delete set null,
  method                 text check (char_length(method) <= 80),
  method_version         text check (char_length(method_version) <= 40),
  review_state           public.review_state not null default 'needs_review',
  reviewed_by            uuid references public.profiles (id) on delete set null,
  reviewed_at            timestamptz,
  created_by             uuid references public.profiles (id) on delete set null,
  sample                 boolean not null default false,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  revision               bigint not null default 1,
  check (num_nonnulls(project_id, lesson_id) >= 1),
  check (source_id is null or project_id is not null),
  check (match_start_us is null or match_end_us is null or match_start_us < match_end_us),
  foreign key (project_id, source_id) references public.camera_sources (project_id, id)
    on delete set null (source_id)
);
create index observations_project_source_idx on public.observations (project_id, source_id);
create index observations_lesson_id_idx on public.observations (lesson_id);
create index observations_calibration_version_id_idx on public.observations (calibration_version_id);

create table public.story_plans (
  id               uuid primary key default gen_random_uuid(),
  project_id       uuid not null references public.projects (id) on delete cascade,
  lesson_ids       uuid[] not null default '{}' check (cardinality(lesson_ids) <= 12),
  profile_id       text not null check (profile_id in ('coach-cut', 'match-broadcast', 'rally-pulse',
                                                       'progress-story', 'court-memories')),
  profile_revision int not null check (profile_revision >= 1),
  title            text not null default '' check (char_length(title) <= 120),
  current_version  int,
  created_by       uuid references public.profiles (id) on delete set null,
  sample           boolean not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  revision         bigint not null default 1,
  unique (project_id, id)   -- the target of the composite plan FKs (finding 17)
);

create table public.story_plan_versions (
  id                             uuid primary key default gen_random_uuid(),
  story_plan_id                  uuid not null references public.story_plans (id) on delete cascade,
  project_id                     uuid not null,   -- set by a05_set_parent_project, never by a client
  version                        int not null,
  planner_kind                   public.planner_kind not null,
  planner_model_id               text check (char_length(planner_model_id) <= 80),
  planner_adapter_version        text not null check (char_length(planner_adapter_version) <= 40),
  story_plan                     jsonb not null check (octet_length(story_plan::text) <= 262144),
  edl                            jsonb check (octet_length(edl::text) <= 1048576),
  edl_sha256                     bytea check (octet_length(edl_sha256) = 32),
  bound_source_manifest_revision int,
  bound_sync_map_revision        int,
  bound_event_revision           int,
  validation_state               text not null default 'unvalidated'
                                   check (validation_state in ('unvalidated', 'valid', 'invalid')),
  validation_report              jsonb check (octet_length(validation_report::text) <= 65536),
  stale                          boolean not null default false,
  created_by                     uuid references public.profiles (id) on delete set null,
  created_at                     timestamptz not null default now(),
  unique (story_plan_id, version),
  unique (story_plan_id, id),   -- targets for render_jobs, quotes, usage_reservations (S78)
  unique (project_id, id),
  foreign key (project_id, story_plan_id) references public.story_plans (project_id, id) on delete cascade
);
create index story_plan_versions_project_id_idx on public.story_plan_versions (project_id, bound_event_revision);

-- Quotas (security-model §13.10): one counter row per (table, subject, UTC day) plus a lifetime row
-- (day = 'infinity'), and the same pair for the per-user aggregate ('*user_total').
create table app_ops.quota_limits (
  table_name        text primary key,
  subject           text not null check (subject in ('project', 'user')),
  max_rows_per_day  int not null check (max_rows_per_day > 0),
  max_bytes_per_day bigint not null check (max_bytes_per_day > 0),
  max_bytes_total   bigint not null check (max_bytes_total > 0)
);
create table app_ops.quota_counters (
  table_name text not null,
  subject_id uuid not null,
  day        date not null,
  n          int not null,
  bytes      bigint not null,
  primary key (table_name, subject_id, day)
);
alter table app_ops.quota_limits enable row level security;
alter table app_ops.quota_counters enable row level security;
revoke all on app_ops.quota_limits, app_ops.quota_counters from public, anon, authenticated, service_role;

-- INFERRED starting values (rows/day, bytes/day, bytes total); tune after measurement. The aggregate sits below the
-- sum of the per-table limits, so a user who creates many projects reaches it first.
insert into app_ops.quota_limits (table_name, subject, max_rows_per_day, max_bytes_per_day, max_bytes_total) values
  ('projects',              'user',      20,   1048576,   16777216),
  ('point_event_revisions', 'project',   50,  33554432,  268435456),
  ('story_plans',           'project',   50,   1048576,   16777216),
  ('story_plan_versions',   'project',  200,  67108864,  268435456),
  ('sync_maps',             'project',   20,  16777216,  134217728),
  ('calibration_versions',  'project',   20,   2097152,   33554432),
  ('observations',          'project', 1000,   4194304,   67108864),
  ('lessons',               'user',      50,   2097152,  134217728),
  ('lesson_clips',          'user',     500,   1048576,   33554432),
  ('*user_total',           'user',    2000, 100663296, 1073741824);

-- 2. Helpers (security-model §4) --------------------------------------------------------------------------------------
-- Definer helpers read the request claims through app_private.current_actor() (migration 1): jovra_owner has no
-- access to the auth schema. Policies call auth.uid() directly, as the querying role.

-- An access grant is active when redeemed (or a share link), not revoked and not expired.
create function app_private.grant_active(g public.access_grants) returns boolean
language sql stable set search_path = '' as $$
  select g.revoked_at is null
     and (g.expires_at is null or g.expires_at > now())
     and (g.kind = 'share_link' or g.redeemed_at is not null)
$$;

-- 'owner' | 'coach' | 'viewer' | null
create function app_private.lesson_access(p_lesson uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case
    when exists (select 1 from public.lessons l
                  where l.id = p_lesson and l.owner_id = app_private.current_actor()) then 'owner'
    when exists (select 1 from public.access_grants g
                  where g.lesson_id = p_lesson and g.kind = 'lesson_coach'
                    and g.grantee_user_id = app_private.current_actor() and app_private.grant_active(g)) then 'coach'
    when exists (select 1 from public.access_grants g
                  where g.lesson_id = p_lesson and g.kind = 'lesson_view'
                    and g.grantee_user_id = app_private.current_actor() and app_private.grant_active(g)) then 'viewer'
  end
$$;

-- Everything a viewer of a shared clip would see (security-model §13.8). It takes the clip's columns rather than a
-- clip id, so the SELECT policy can judge a row from its own values (also a row being inserted, which a lookup by
-- id cannot see). It hashes values the caller already holds, so authenticated may execute it.
create function app_private.clip_share_fingerprint(p_project uuid, p_source uuid, p_start_us bigint, p_end_us bigint,
                                                   p_keeper text, p_sync_map_revision int, p_event_revision int)
returns bytea language sql immutable set search_path = '' as $$
  select pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.concat_ws('|',
           p_project::text, coalesce(p_source::text, '-'), p_start_us::text, p_end_us::text,
           coalesce(p_keeper, '-'), coalesce(p_sync_map_revision::text, '-'),
           coalesce(p_event_revision::text, '-')), 'UTF8'))
$$;

-- A clip is shareable when the lesson owner owns the clip's project, or the project owner approved exactly this
-- window (the approval still equals the fingerprint).
create function app_private.clip_is_shareable(p_clip uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.lesson_clips c
      join public.lessons l  on l.id = c.lesson_id
      join public.projects p on p.id = c.project_id and p.deleted_at is null
     where c.id = p_clip
       and (p.owner_id = l.owner_id
            or (c.share_approved_at is not null
                and c.share_approved_sha256 = app_private.clip_share_fingerprint(
                      c.project_id, c.source_id, c.match_start_us, c.match_end_us, c.keeper_ref, c.sync_map_revision,
                      c.event_revision))))
$$;

-- A clip is visible only while (a) its project is not deleted, (b) the lesson owner still holds an active role on
-- the clip's project, and (c) for anyone but the lesson owner, the clip is shareable (the lesson owner owns the
-- project, or p_approved: the project owner's approval still equals the clip's fingerprint). Revoking a coach
-- therefore removes every downstream viewer's access too. The policy passes the row's own columns.
create function app_private.can_view_lesson_clip_row(p_clip uuid, p_lesson uuid, p_project uuid, p_approved boolean)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.lessons l
      join public.projects p on p.id = p_project and p.deleted_at is null
     where l.id = p_lesson
       and exists (select 1 from public.project_members m
                    where m.project_id = p_project and m.user_id = l.owner_id and m.revoked_at is null
                      and (m.expires_at is null or m.expires_at > now())
                      and (m.role = 'owner' or m.approved_at is not null))
       and (l.owner_id = app_private.current_actor()
            or ((p.owner_id = l.owner_id or coalesce(p_approved, false))
                and (app_private.lesson_access(p_lesson) in ('coach', 'viewer')
                     or exists (select 1 from public.access_grants g
                                 where g.lesson_clip_id = p_clip and g.kind = 'lesson_clip_view'
                                   and g.grantee_user_id = app_private.current_actor()
                                   and app_private.grant_active(g))))))
$$;

create function app_private.can_view_lesson_clip(p_clip uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select app_private.can_view_lesson_clip_row(c.id, c.lesson_id, c.project_id,
                            c.share_approved_at is not null
                            and c.share_approved_sha256 = app_private.clip_share_fingerprint(
                                  c.project_id, c.source_id, c.match_start_us, c.match_end_us, c.keeper_ref,
                                  c.sync_map_revision, c.event_revision))
                     from public.lesson_clips c where c.id = p_clip), false)
$$;

-- Viewer path only (owners and coaches use has_project_role). A viewer may see a granted film or clip excerpt and
-- that artifact's thumbnail, captions and chapters; nothing else.
create function app_private.viewer_can_see_artifact(p_artifact uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  with a as (
    select coalesce(x.parent_artifact_id, x.id) as root_id, x.kind
      from public.artifacts x
     where x.id = p_artifact and x.state = 'ready' and x.deleted_at is null
  ), root as (
    select r.id, r.kind from public.artifacts r join a on r.id = a.root_id
     where r.state = 'ready' and r.deleted_at is null and r.kind in ('film', 'clip_excerpt')
  )
  select exists (select 1 from a, root
                  where (a.kind in ('film', 'clip_excerpt') and a.root_id = root.id)
                     or a.kind in ('thumbnail', 'captions', 'chapters'))
     and exists (select 1 from public.artifacts r join public.projects p on p.id = r.project_id, root
                  where r.id = root.id and p.deleted_at is null)   -- viewers lose access when deletion starts
     and (
       exists (select 1 from public.access_grants g, root
                where g.artifact_id = root.id and g.kind = 'film_view'
                  and g.grantee_user_id = app_private.current_actor() and app_private.grant_active(g))
       or exists (select 1 from public.lesson_clips c, root
                   where c.excerpt_artifact_id = root.id and app_private.can_view_lesson_clip(c.id))
     )
$$;

-- A signed-in camera sees its own source only while its invite is approved, unrevoked and the project live.
create function app_private.is_own_live_camera_invite(p_invite uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.camera_invites i
                   join public.projects p on p.id = i.project_id and p.deleted_at is null
                  where i.id = p_invite and i.redeemed_by_user_id = app_private.current_actor()
                    and i.approved_at is not null and i.revoked_at is null)
$$;

-- INSERT predicates: one per client-insertable table, called by its INSERT policy and its a00_rls_guard (§13.11).
-- coalesce(..., false): a NULL would let the guard pass and leave the refusal to WITH CHECK, after other triggers.
create function app_private.can_insert_sync_maps(p_project uuid, p_review_state public.review_state)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(app_private.is_real_user() and app_private.has_project_role(p_project, '{owner}')
                  and p_review_state in ('estimated', 'needs_review', 'reviewed'), false)
$$;

create function app_private.can_insert_calibration_versions(p_project uuid, p_provenance public.provenance)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(app_private.is_real_user() and app_private.has_project_role(p_project, '{owner}')
                  and p_provenance in ('manual', 'estimated'), false)
$$;

create function app_private.can_insert_point_event_revisions(p_project uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(app_private.is_real_user() and app_private.has_project_role(p_project, '{owner}'), false)
$$;

-- Every non-null parent must be accessible (AND, never OR).
create function app_private.can_insert_observations(p_project uuid, p_lesson uuid, p_provenance public.provenance)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(app_private.is_real_user()
                  and p_provenance = 'manual'
                  and num_nonnulls(p_project, p_lesson) >= 1
                  and (p_project is null or app_private.has_project_role(p_project, '{owner,coach}'))
                  and (p_lesson is null or app_private.lesson_access(p_lesson) in ('owner', 'coach')), false)
$$;

create function app_private.can_insert_lessons(p_owner uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(app_private.is_real_user() and p_owner = app_private.current_actor(), false)
$$;

create function app_private.can_insert_lesson_clips(p_lesson uuid, p_project uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(app_private.is_real_user() and app_private.lesson_access(p_lesson) = 'owner'
                  and app_private.has_project_role(p_project, '{owner,coach}'), false)
$$;

create function app_private.can_insert_story_plans(p_project uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(app_private.is_real_user() and app_private.has_project_role(p_project, '{owner,coach}'), false)
$$;

-- Resolves the plan's own project from the plan id, never from a client-supplied project_id.
create function app_private.can_insert_story_plan_versions(p_plan uuid, p_planner_kind public.planner_kind)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(app_private.is_real_user() and p_planner_kind in ('user', 'heuristic')
                  and exists (select 1 from public.story_plans p
                               where p.id = p_plan and app_private.has_project_role(p.project_id, '{owner,coach}')),
                  false)
$$;

-- Coded validation helpers (security-model §9): raise P0422 naming the column, never the value.
create function app_private.check_len(p_value text, p_max int, p_column text) returns void
language plpgsql immutable set search_path = '' as $$
begin
  if p_value is not null and pg_catalog.char_length(p_value) > p_max then
    raise exception using errcode = 'P0422', message = 'field_too_long:' || p_column;
  end if;
end
$$;

create function app_private.check_json(p_value jsonb, p_max int, p_column text) returns void
language plpgsql immutable set search_path = '' as $$
begin
  if p_value is not null and pg_catalog.octet_length(p_value::text) > p_max then
    raise exception using errcode = 'P0422', message = 'field_too_long:' || p_column;
  end if;
end
$$;

create function app_private.check_hash(p_value bytea, p_column text) returns void
language plpgsql immutable set search_path = '' as $$
begin
  if p_value is not null and pg_catalog.octet_length(p_value) <> 32 then
    raise exception using errcode = 'P0422', message = 'invalid_value:' || p_column;
  end if;
end
$$;

create function app_private.check_required(p_missing boolean, p_column text) returns void
language plpgsql immutable set search_path = '' as $$
begin
  if p_missing then
    raise exception using errcode = 'P0422', message = 'required:' || p_column;
  end if;
end
$$;

create function app_private.check_valid(p_ok boolean, p_column text) returns void
language plpgsql immutable set search_path = '' as $$
begin
  if not coalesce(p_ok, false) then
    raise exception using errcode = 'P0422', message = 'invalid_value:' || p_column;
  end if;
end
$$;

-- 3. Trigger functions ---------------------------------------------------------------------------------------------
-- a00: the INSERT policy's predicate first, with RLS's own error, before any lock, lookup or counter (§13.11).
-- One function for the eight tables; a table it does not know is refused (fail closed).
create function app_private.rls_guard() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_ok boolean;
begin
  if not app_private.is_client_path() then
    return new;
  end if;
  -- A CASE statement, not a CASE expression: each branch names columns only its own table has.
  case tg_table_name
    when 'sync_maps' then
      v_ok := app_private.can_insert_sync_maps(new.project_id, new.review_state);
    when 'calibration_versions' then
      v_ok := app_private.can_insert_calibration_versions(new.project_id, new.provenance);
    when 'point_event_revisions' then
      v_ok := app_private.can_insert_point_event_revisions(new.project_id);
    when 'observations' then
      v_ok := app_private.can_insert_observations(new.project_id, new.lesson_id, new.provenance);
    when 'lessons' then
      v_ok := app_private.can_insert_lessons(new.owner_id);
    when 'lesson_clips' then
      v_ok := app_private.can_insert_lesson_clips(new.lesson_id, new.project_id);
    when 'story_plans' then
      v_ok := app_private.can_insert_story_plans(new.project_id);
    when 'story_plan_versions' then
      v_ok := app_private.can_insert_story_plan_versions(new.story_plan_id, new.planner_kind);
    else
      v_ok := false;
  end case;
  if not coalesce(v_ok, false) then
    raise exception using errcode = '42501',
      message = pg_catalog.format('new row violates row-level security policy for table "%s"', tg_table_name);
  end if;
  return new;
end
$$;

-- a05: plan versions carry their plan's project; a client never chooses it. A server path that supplies one keeps
-- it, so the composite FK (not this trigger) is what refuses a mismatched pair (T-DB-59).
create function app_private.set_parent_project() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if app_private.is_client_path() or new.project_id is null then
    new.project_id := (select p.project_id from public.story_plans p where p.id = new.story_plan_id);
  end if;
  return new;
end
$$;

-- a10: coded errors without values (security-model §9), one function per table.
create function app_private.validate_camera_sources() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.check_required(new.project_id is null or new.slot is null or new.local_source_id is null
                                     or new.state is null, 'camera_source');
  perform app_private.check_required(new.label is null, 'label');
  perform app_private.check_len(new.label, 60, 'label');
  perform app_private.check_valid(new.declared_bytes > 0, 'declared_bytes');
  perform app_private.check_required(new.declared_sha256 is null, 'declared_sha256');
  perform app_private.check_hash(new.declared_sha256, 'declared_sha256');
  perform app_private.check_hash(new.verified_sha256, 'verified_sha256');
  perform app_private.check_len(new.verified_etag, 200, 'verified_etag');
  perform app_private.check_len(new.r2_key, 512, 'r2_key');
  perform app_private.check_required(new.client_probe is null, 'client_probe');
  perform app_private.check_json(new.client_probe, 2048, 'client_probe');
  -- the device's declaration, allowlisted: never free-form tags (QuickTime location)
  perform app_private.check_valid(pg_catalog.jsonb_typeof(new.client_probe) = 'object'
    and not exists (select 1 from pg_catalog.jsonb_object_keys(new.client_probe) k
                     where k not in ('codec', 'width', 'height', 'fps', 'duration', 'rotation')), 'client_probe');
  perform app_private.check_json(new.probe, 16384, 'probe');
  perform app_private.check_valid(new.rejected_reason is null
    or new.rejected_reason in ('hash_mismatch', 'probe_rejected', 'size_mismatch'), 'rejected_reason');
  return new;
end
$$;

create function app_private.validate_source_manifests() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.check_required(new.project_id is null or new.manifest is null, 'source_manifest');
  perform app_private.check_json(new.manifest, 524288, 'manifest');
  perform app_private.check_required(new.manifest_sha256 is null, 'manifest_sha256');
  perform app_private.check_hash(new.manifest_sha256, 'manifest_sha256');
  perform app_private.check_valid(new.created_by_kind in ('gateway', 'render'), 'created_by_kind');
  return new;
end
$$;

create function app_private.validate_sync_maps() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.check_required(new.project_id is null or new.source_manifest_revision is null
                                     or new.map is null or new.review_state is null or new.sample is null,
                                     'sync_map');
  perform app_private.check_json(new.map, 1048576, 'map');
  perform app_private.check_hash(new.map_sha256, 'map_sha256');
  perform app_private.check_len(new.method, 80, 'method');
  perform app_private.check_len(new.method_version, 40, 'method_version');
  return new;
end
$$;

create function app_private.validate_calibration_versions() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.check_required(new.project_id is null or new.source_id is null or new.calibration is null
                                     or new.provenance is null, 'calibration');
  perform app_private.check_json(new.calibration, 65536, 'calibration');
  perform app_private.check_len(new.method, 80, 'method');
  perform app_private.check_len(new.method_version, 40, 'method_version');
  return new;
end
$$;

create function app_private.validate_point_event_revisions() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.check_required(new.project_id is null or new.local_session_id is null, 'event_revision');
  perform app_private.check_required(new.schema_version is null, 'schema_version');
  perform app_private.check_len(new.schema_version, 20, 'schema_version');
  perform app_private.check_required(new.event_log is null, 'event_log');
  perform app_private.check_json(new.event_log, 2097152, 'event_log');
  perform app_private.check_valid(pg_catalog.jsonb_typeof(new.event_log) = 'array', 'event_log');
  return new;
end
$$;

create function app_private.validate_observations() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.check_required(num_nonnulls(new.project_id, new.lesson_id) = 0, 'parent');
  perform app_private.check_valid(new.source_id is null or new.project_id is not null, 'source_id');
  perform app_private.check_required(new.kind is null or new.kind = '', 'kind');
  perform app_private.check_len(new.kind, 40, 'kind');
  perform app_private.check_len(new.body, 2000, 'body');
  perform app_private.check_len(new.capability_id, 80, 'capability_id');
  perform app_private.check_len(new.method, 80, 'method');
  perform app_private.check_len(new.method_version, 40, 'method_version');
  perform app_private.check_valid(new.match_start_us is null or new.match_end_us is null
                                  or new.match_start_us < new.match_end_us, 'match_window');
  perform app_private.check_valid(new.confidence_milli is null or new.confidence_milli between 0 and 1000,
                                  'confidence_milli');
  perform app_private.check_required(new.provenance is null or new.review_state is null or new.sample is null,
                                     'observation');
  return new;
end
$$;

create function app_private.validate_lessons() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.check_required(new.owner_id is null, 'owner_id');
  perform app_private.check_required(new.local_lesson_id is null, 'local_lesson_id');
  perform app_private.check_required(new.title is null, 'title');
  perform app_private.check_len(new.title, 120, 'title');
  perform app_private.check_required(new.notes is null, 'notes');
  perform app_private.check_len(new.notes, 10000, 'notes');
  perform app_private.check_required(new.next_goal is null, 'next_goal');
  perform app_private.check_len(new.next_goal, 500, 'next_goal');
  perform app_private.check_required(new.practice is null, 'practice');
  perform app_private.check_json(new.practice, 32768, 'practice');
  perform app_private.check_required(new.sample is null, 'sample');
  return new;
end
$$;

create function app_private.validate_lesson_clips() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.check_required(new.lesson_id is null or new.project_id is null, 'lesson_clip');
  perform app_private.check_required(new.match_start_us is null or new.match_end_us is null, 'match_window');
  perform app_private.check_valid(new.match_start_us >= 0 and new.match_end_us - new.match_start_us > 0
                                  and new.match_end_us - new.match_start_us <= 600000000, 'match_window');
  perform app_private.check_len(new.keeper_ref, 96, 'keeper_ref');
  perform app_private.check_required(new.note is null, 'note');
  perform app_private.check_len(new.note, 1000, 'note');
  perform app_private.check_required(new.position is null, 'position');
  perform app_private.check_hash(new.share_approved_sha256, 'share_approved_sha256');
  return new;
end
$$;

create function app_private.validate_artifacts() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.check_required(new.project_id is null or new.kind is null, 'artifact');
  perform app_private.check_valid(new.bucket_class in ('work', 'films'), 'bucket_class');
  perform app_private.check_required(new.r2_key is null, 'r2_key');
  perform app_private.check_len(new.r2_key, 512, 'r2_key');
  perform app_private.check_valid(new.state in ('writing', 'verifying', 'ready', 'failed', 'deleted'), 'state');
  perform app_private.check_valid(new.bytes is null or new.bytes >= 0, 'bytes');
  perform app_private.check_hash(new.sha256, 'sha256');
  perform app_private.check_hash(new.edl_sha256, 'edl_sha256');
  perform app_private.check_json(new.media, 16384, 'media');
  perform app_private.check_json(new.verification, 65536, 'verification');
  perform app_private.check_len(new.profile_id, 40, 'profile_id');
  perform app_private.check_len(new.renderer_version, 40, 'renderer_version');
  perform app_private.check_required(new.display_title is null, 'display_title');
  perform app_private.check_len(new.display_title, 120, 'display_title');
  return new;
end
$$;

create function app_private.validate_access_grants() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.check_required(new.kind is null or new.created_by is null, 'grant');
  perform app_private.check_valid(case new.kind
      when 'project_coach' then new.project_id is not null
                                and num_nulls(new.lesson_id, new.artifact_id, new.lesson_clip_id) = 3
      when 'lesson_coach' then new.lesson_id is not null
                               and num_nulls(new.project_id, new.artifact_id, new.lesson_clip_id) = 3
      when 'lesson_view' then new.lesson_id is not null
                              and num_nulls(new.project_id, new.artifact_id, new.lesson_clip_id) = 3
      when 'film_view' then num_nonnulls(new.project_id, new.artifact_id) = 2
                            and num_nulls(new.lesson_id, new.lesson_clip_id) = 2
      when 'lesson_clip_view' then new.lesson_clip_id is not null
                                   and num_nulls(new.project_id, new.lesson_id, new.artifact_id) = 3
      when 'share_link' then num_nonnulls(new.project_id, new.artifact_id) = 2
                             and num_nulls(new.lesson_id, new.lesson_clip_id, new.grantee_user_id) = 3
    end, 'target');
  -- every invitation is bound to its recipient (§13.2); share links are bearer tokens with a 24 h ceiling
  perform app_private.check_required(new.kind <> 'share_link' and new.invitee_email_hmac is null,
                                     'invitee_email_hmac');
  perform app_private.check_hash(new.invitee_email_hmac, 'invitee_email_hmac');
  perform app_private.check_hash(new.token_hash, 'token_hash');
  perform app_private.check_valid(new.redeem_by is null or new.redeem_by <= new.created_at + interval '7 days',
                                  'redeem_by');
  perform app_private.check_valid(new.kind <> 'share_link'
    or (new.expires_at is not null and new.expires_at <= new.created_at + interval '24 hours'), 'expires_at');
  return new;
end
$$;

create function app_private.validate_story_plans() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.check_required(new.project_id is null, 'project_id');
  perform app_private.check_required(new.lesson_ids is null, 'lesson_ids');
  perform app_private.check_valid(pg_catalog.cardinality(new.lesson_ids) <= 12
                                  and pg_catalog.array_position(new.lesson_ids, null) is null, 'lesson_ids');
  perform app_private.check_valid(new.profile_id in ('coach-cut', 'match-broadcast', 'rally-pulse', 'progress-story',
                                                     'court-memories'), 'profile_id');
  perform app_private.check_valid(new.profile_revision >= 1, 'profile_revision');
  perform app_private.check_required(new.title is null, 'title');
  perform app_private.check_len(new.title, 120, 'title');
  perform app_private.check_required(new.sample is null, 'sample');
  return new;
end
$$;

create function app_private.validate_story_plan_versions() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.check_required(new.story_plan_id is null or new.planner_kind is null, 'plan_version');
  perform app_private.check_required(new.planner_adapter_version is null, 'planner_adapter_version');
  perform app_private.check_len(new.planner_adapter_version, 40, 'planner_adapter_version');
  perform app_private.check_len(new.planner_model_id, 80, 'planner_model_id');
  perform app_private.check_required(new.story_plan is null, 'story_plan');
  perform app_private.check_json(new.story_plan, 262144, 'story_plan');
  perform app_private.check_json(new.edl, 1048576, 'edl');
  perform app_private.check_hash(new.edl_sha256, 'edl_sha256');
  perform app_private.check_json(new.validation_report, 65536, 'validation_report');
  perform app_private.check_valid(new.validation_state in ('unvalidated', 'valid', 'invalid'), 'validation_state');
  perform app_private.check_required(new.stale is null, 'stale');
  return new;
end
$$;

-- a20: quotas on direct PostgREST writes (security-model §13.10, finding 23). Server stages skip them; their writes
-- are bounded by reservations. A refusal raises, which also rolls the increments back.
create function app_private.enforce_quota() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_actor   uuid := app_private.current_actor();
  v_lim     app_ops.quota_limits;
  v_agg     app_ops.quota_limits;
  v_subject uuid;
  v_bytes   bigint := pg_catalog.octet_length(pg_catalog.to_jsonb(new)::text);
  v_today   date := (now() at time zone 'UTC')::date;
  v_day     app_ops.quota_counters;
  v_total   app_ops.quota_counters;
begin
  if not app_private.is_client_path() then
    return new;
  end if;
  select * into v_lim from app_ops.quota_limits q where q.table_name = tg_table_name;
  if not found then
    raise exception using errcode = 'P0429', message = 'quota_exceeded';   -- no limits row: refuse
  end if;
  select * into v_agg from app_ops.quota_limits q where q.table_name = '*user_total';
  if not found then
    raise exception using errcode = 'P0429', message = 'quota_exceeded';
  end if;
  -- A row with no project (a lesson-only observation) counts against the writing user, never a NULL subject.
  v_subject := case v_lim.subject
                 when 'user' then v_actor
                 else coalesce((pg_catalog.to_jsonb(new) ->> 'project_id')::uuid, v_actor)
               end;
  if v_subject is null or v_actor is null then
    raise exception using errcode = 'P0429', message = 'quota_exceeded';
  end if;

  insert into app_ops.quota_counters as q (table_name, subject_id, day, n, bytes)
  values (tg_table_name, v_subject, v_today, 1, v_bytes)
  on conflict (table_name, subject_id, day) do update set n = q.n + 1, bytes = q.bytes + excluded.bytes
  returning * into v_day;
  insert into app_ops.quota_counters as q (table_name, subject_id, day, n, bytes)
  values (tg_table_name, v_subject, 'infinity', 1, v_bytes)
  on conflict (table_name, subject_id, day) do update set n = q.n + 1, bytes = q.bytes + excluded.bytes
  returning * into v_total;
  if v_day.n > v_lim.max_rows_per_day or v_day.bytes > v_lim.max_bytes_per_day
     or v_total.bytes > v_lim.max_bytes_total then
    raise exception using errcode = 'P0429', message = 'quota_exceeded';
  end if;

  -- The per-user aggregate across every quota'd table and project: per-project limits alone multiply with the
  -- number of projects a user creates.
  insert into app_ops.quota_counters as q (table_name, subject_id, day, n, bytes)
  values ('*user_total', v_actor, v_today, 1, v_bytes)
  on conflict (table_name, subject_id, day) do update set n = q.n + 1, bytes = q.bytes + excluded.bytes
  returning * into v_day;
  insert into app_ops.quota_counters as q (table_name, subject_id, day, n, bytes)
  values ('*user_total', v_actor, 'infinity', 1, v_bytes)
  on conflict (table_name, subject_id, day) do update set n = q.n + 1, bytes = q.bytes + excluded.bytes
  returning * into v_total;
  if false and v_day.n > v_agg.max_rows_per_day or false and v_day.bytes > v_agg.max_bytes_per_day   -- MUTATION M2
     or v_total.bytes > v_agg.max_bytes_total then
    raise exception using errcode = 'P0429', message = 'quota_exceeded';
  end if;
  return new;
end
$$;

-- a30: actor and server-owned columns are the caller's or the server's, never client-chosen (client path only).
create function app_private.force_actor_columns() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := app_private.current_actor();
begin
  if not app_private.is_client_path() then
    return new;
  end if;
  case tg_table_name
    when 'sync_maps' then
      new.created_by := v_actor;
      if new.review_state = 'reviewed' then   -- a reviewed map records who reviewed it (T-DB-43)
        new.reviewed_by := v_actor;
        new.reviewed_at := now();
      else
        new.reviewed_by := null;
        new.reviewed_at := null;
      end if;
      new.map_sha256 := null;   -- computed in a40
    when 'calibration_versions' then
      new.created_by := v_actor;
      new.reviewed_by := null;
      new.reviewed_at := null;
    when 'point_event_revisions' then
      new.created_by := v_actor;
    when 'observations' then
      new.created_by := v_actor;
      new.provenance := 'manual';       -- 'estimated'/'validated' only from server stages
      new.review_state := 'reviewed';   -- a person wrote it
      new.reviewed_by := null;
      new.reviewed_at := null;
      new.confidence_milli := null;
      new.calibration_version_id := null;
    when 'story_plans' then
      new.created_by := v_actor;
      new.current_version := null;
    when 'story_plan_versions' then
      new.created_by := v_actor;
      new.validation_state := 'unvalidated';   -- only the gateway/Workflow validates
      new.validation_report := null;
      new.planner_model_id := null;
      new.edl_sha256 := null;
      new.stale := false;
    else
      null;
  end case;
  return new;
end
$$;

-- a40: append-only revision numbers under a per-project advisory lock.
create function app_private.assign_next_revision() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(new.project_id::text));
  case tg_table_name
    when 'source_manifests' then
      new.revision := coalesce((select max(m.revision) from public.source_manifests m
                                 where m.project_id = new.project_id), 0) + 1;
    when 'sync_maps' then
      new.revision := coalesce((select max(m.revision) from public.sync_maps m
                                 where m.project_id = new.project_id), 0) + 1;
      if new.map_sha256 is null then
        new.map_sha256 := pg_catalog.sha256(pg_catalog.convert_to(new.map::text, 'UTF8'));
      end if;
    when 'calibration_versions' then
      new.version := coalesce((select max(c.version) from public.calibration_versions c
                                where c.source_id = new.source_id), 0) + 1;
    when 'story_plan_versions' then
      new.version := coalesce((select max(v.version) from public.story_plan_versions v
                                where v.story_plan_id = new.story_plan_id), 0) + 1;
    else
      raise exception using errcode = 'P0422', message = 'invalid_value:table';
  end case;
  return new;
end
$$;

-- a40 on point_event_revisions: the parent must be the project's current revision, else P0409 revision_conflict.
-- The log hash is computed here from the stored JSON (its jsonb text form), so a client never supplies it.
create function app_private.check_event_parent() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_current int;
begin
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext(new.project_id::text));
  select p.current_event_revision into v_current from public.projects p where p.id = new.project_id for update;
  if not found then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  if false then   -- MUTATION M3
    raise exception using errcode = 'P0409', message = 'revision_conflict';
  end if;
  new.revision := coalesce(v_current, 0) + 1;
  new.event_log_sha256 := pg_catalog.sha256(pg_catalog.convert_to(new.event_log::text, 'UTF8'));
  update public.projects set current_event_revision = new.revision where id = new.project_id;
  return new;
end
$$;

-- After a new event revision: films, previews and excerpts made from older revisions, and plan versions bound to
-- them, are stale (still downloadable, labelled "older version").
create function app_private.mark_stale() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.artifacts a set stale = true
   where a.project_id = new.project_id and a.event_revision < new.revision
     and a.kind in ('preview', 'film', 'clip_excerpt') and not a.stale;
  update public.story_plan_versions v set stale = true
   where v.project_id = new.project_id and v.bound_event_revision < new.revision and not v.stale;
  return null;
end
$$;

-- After a new manifest, sync map or plan version: the project's (or plan's) current pointer follows.
create function app_private.set_current_pointer() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  case tg_table_name
    when 'source_manifests' then
      update public.projects set current_source_manifest_revision = new.revision where id = new.project_id;
    when 'sync_maps' then
      update public.projects set current_sync_map_revision = new.revision where id = new.project_id;
    when 'story_plan_versions' then
      update public.story_plans set current_version = new.version where id = new.story_plan_id;
    else
      null;
  end case;
  return null;
end
$$;

-- a45 on story_plans: on the client path, every lesson id this statement adds must be the caller's as owner or
-- lesson coach (a viewer grant never binds a lesson); on every path, every lesson belongs to the project's owner.
-- Removing an id never grants access, so the server path (lesson-scope deletion) skips the caller check (T-DB-73).
create function app_private.check_story_plan_lessons() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_added uuid[];
begin
  if tg_op = 'INSERT' then
    v_added := new.lesson_ids;
  else
    v_added := array(select x from pg_catalog.unnest(new.lesson_ids) x where not (x = any (old.lesson_ids)));
  end if;
  if app_private.is_client_path()
     and exists (select 1 from pg_catalog.unnest(v_added) x
                  where coalesce(app_private.lesson_access(x) not in ('owner', 'coach'), true)) then
    raise exception using errcode = 'P0401', message = 'lesson_not_accessible';
  end if;
  if exists (select 1 from pg_catalog.unnest(new.lesson_ids) x
               left join public.lessons l on l.id = x
              where l.owner_id is distinct from (select p.owner_id from public.projects p where p.id = new.project_id))
  then
    raise exception using errcode = 'P0422', message = 'invalid_value:lesson_ids';
  end if;
  return new;
end
$$;

-- b20 on lesson_clips: the excerpt a clip links is a clip_excerpt of this clip and project (§13.16).
create function app_private.check_clip_excerpt() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.excerpt_artifact_id is not null and not exists (
       select 1 from public.artifacts a
        where a.id = new.excerpt_artifact_id and a.kind = 'clip_excerpt'
          and a.lesson_clip_id = new.id and a.project_id = new.project_id) then
    raise exception using errcode = 'P0422', message = 'excerpt_mismatch';
  end if;
  return new;
end
$$;

-- b20 on lesson_clips: an approval never follows a moved window (§13.8, finding 20). A change of anything the
-- fingerprint covers clears the approval, unlinks the excerpt and hides it at once; S78's outbox adds the row that
-- deletes its object.
create function app_private.pin_shared_clip() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if app_private.clip_share_fingerprint(new.project_id, new.source_id, new.match_start_us, new.match_end_us,
                                        new.keeper_ref, new.sync_map_revision, new.event_revision)
     is distinct from
     app_private.clip_share_fingerprint(old.project_id, old.source_id, old.match_start_us, old.match_end_us,
                                        old.keeper_ref, old.sync_map_revision, old.event_revision) then
    new.share_approved_at := null;
    new.share_approved_sha256 := null;
    if old.excerpt_artifact_id is not null then
      new.excerpt_artifact_id := null;
      update public.artifacts set deleted_at = now() where id = old.excerpt_artifact_id and deleted_at is null;
    end if;
  end if;
  return new;
end
$$;

-- b20 on access_grants: a clip-bearing grant needs each clip shareable (the creator owns the clip's project or the
-- project owner approved exactly that window). The gateway's create_grant (S79) checks the creator; this is the
-- table-level backstop that holds for every path (T-DB-46).
create function app_private.check_grant_clips() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if (new.kind = 'lesson_clip_view' and not app_private.clip_is_shareable(new.lesson_clip_id))
     or (new.kind = 'lesson_view'
         and exists (select 1 from public.lesson_clips c
                      where c.lesson_id = new.lesson_id and not app_private.clip_is_shareable(c.id))) then
    raise exception using errcode = 'P0409', message = 'clip_share_not_approved';
  end if;
  return new;
end
$$;

-- b30 on observations: text changes only by its author; review turns 'estimated' into 'reviewed' and records the
-- reviewer. No delete: reject instead (review_state 'rejected').
create function app_private.review_observation() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_actor uuid := app_private.current_actor();
begin
  if not app_private.is_client_path() then
    return new;
  end if;
  if new.body is distinct from old.body and old.created_by is distinct from v_actor then
    raise exception using errcode = 'P0401', message = 'not_author';
  end if;
  if new.review_state is distinct from old.review_state then
    if new.review_state = 'reviewed' then
      if old.provenance = 'estimated' then
        new.provenance := 'reviewed';
      end if;
    elsif new.review_state <> 'rejected' then
      raise exception using errcode = 'P0422', message = 'invalid_value:review_state';
    end if;
    new.reviewed_by := v_actor;
    new.reviewed_at := now();
  end if;
  return new;
end
$$;

-- 4. Triggers (names sort in the §13.0 order; same-event triggers fire alphabetically) ---------------------------
-- projects gains its quota here (migration 1 left a20_enforce_quota for this ticket).
create trigger a20_enforce_quota before insert on public.projects
  for each row execute function app_private.enforce_quota();

create trigger a10_validate before insert or update on public.camera_sources
  for each row execute function app_private.validate_camera_sources();
create trigger b50_bump_revision before update on public.camera_sources
  for each row execute function app_private.bump_revision();

create trigger a10_validate before insert on public.source_manifests
  for each row execute function app_private.validate_source_manifests();
create trigger a40_assign_next_revision before insert on public.source_manifests
  for each row execute function app_private.assign_next_revision();
create trigger c10_set_current_pointer after insert on public.source_manifests
  for each row execute function app_private.set_current_pointer();

create trigger a00_rls_guard before insert on public.sync_maps
  for each row execute function app_private.rls_guard();
create trigger a10_validate before insert on public.sync_maps
  for each row execute function app_private.validate_sync_maps();
create trigger a20_enforce_quota before insert on public.sync_maps
  for each row execute function app_private.enforce_quota();
create trigger a30_force_actor_columns before insert on public.sync_maps
  for each row execute function app_private.force_actor_columns();
create trigger a40_assign_next_revision before insert on public.sync_maps
  for each row execute function app_private.assign_next_revision();
create trigger c10_set_current_pointer after insert on public.sync_maps
  for each row execute function app_private.set_current_pointer();

create trigger a00_rls_guard before insert on public.calibration_versions
  for each row execute function app_private.rls_guard();
create trigger a10_validate before insert on public.calibration_versions
  for each row execute function app_private.validate_calibration_versions();
create trigger a20_enforce_quota before insert on public.calibration_versions
  for each row execute function app_private.enforce_quota();
create trigger a30_force_actor_columns before insert on public.calibration_versions
  for each row execute function app_private.force_actor_columns();
create trigger a40_assign_next_revision before insert on public.calibration_versions
  for each row execute function app_private.assign_next_revision();

create trigger a00_rls_guard before insert on public.point_event_revisions
  for each row execute function app_private.rls_guard();
create trigger a10_validate before insert on public.point_event_revisions
  for each row execute function app_private.validate_point_event_revisions();
create trigger a20_enforce_quota before insert on public.point_event_revisions
  for each row execute function app_private.enforce_quota();
create trigger a30_force_actor_columns before insert on public.point_event_revisions
  for each row execute function app_private.force_actor_columns();
create trigger a40_check_event_parent before insert on public.point_event_revisions
  for each row execute function app_private.check_event_parent();
create trigger c20_mark_stale after insert on public.point_event_revisions
  for each row execute function app_private.mark_stale();

create trigger a00_rls_guard before insert on public.observations
  for each row execute function app_private.rls_guard();
create trigger a10_validate before insert or update on public.observations
  for each row execute function app_private.validate_observations();
create trigger a20_enforce_quota before insert on public.observations
  for each row execute function app_private.enforce_quota();
create trigger a30_force_actor_columns before insert on public.observations
  for each row execute function app_private.force_actor_columns();
create trigger b30_review_observation before update on public.observations
  for each row execute function app_private.review_observation();
create trigger b50_bump_revision before update on public.observations
  for each row execute function app_private.bump_revision();

create trigger a00_rls_guard before insert on public.lessons
  for each row execute function app_private.rls_guard();
create trigger a10_validate before insert or update on public.lessons
  for each row execute function app_private.validate_lessons();
create trigger a20_enforce_quota before insert on public.lessons
  for each row execute function app_private.enforce_quota();
create trigger b50_bump_revision before update on public.lessons
  for each row execute function app_private.bump_revision();

create trigger a00_rls_guard before insert on public.lesson_clips
  for each row execute function app_private.rls_guard();
create trigger a10_validate before insert or update on public.lesson_clips
  for each row execute function app_private.validate_lesson_clips();
create trigger a20_enforce_quota before insert on public.lesson_clips
  for each row execute function app_private.enforce_quota();
create trigger b20_check_clip_excerpt before insert or update of excerpt_artifact_id on public.lesson_clips
  for each row execute function app_private.check_clip_excerpt();
create trigger b20_pin_shared_clip before update on public.lesson_clips
  for each row execute function app_private.pin_shared_clip();
create trigger b50_bump_revision before update on public.lesson_clips
  for each row execute function app_private.bump_revision();

create trigger a10_validate before insert or update on public.artifacts
  for each row execute function app_private.validate_artifacts();

create trigger a10_validate before insert or update on public.access_grants
  for each row execute function app_private.validate_access_grants();
create trigger b20_check_grant_clips before insert on public.access_grants
  for each row execute function app_private.check_grant_clips();

create trigger a00_rls_guard before insert on public.story_plans
  for each row execute function app_private.rls_guard();
create trigger a10_validate before insert or update on public.story_plans
  for each row execute function app_private.validate_story_plans();
create trigger a20_enforce_quota before insert on public.story_plans
  for each row execute function app_private.enforce_quota();
create trigger a30_force_actor_columns before insert on public.story_plans
  for each row execute function app_private.force_actor_columns();
create trigger a45_check_story_plan_lessons before insert or update of lesson_ids on public.story_plans
  for each row execute function app_private.check_story_plan_lessons();
create trigger b50_bump_revision before update on public.story_plans
  for each row execute function app_private.bump_revision();

create trigger a00_rls_guard before insert on public.story_plan_versions
  for each row execute function app_private.rls_guard();
create trigger a05_set_parent_project before insert on public.story_plan_versions
  for each row execute function app_private.set_parent_project();
create trigger a10_validate before insert on public.story_plan_versions
  for each row execute function app_private.validate_story_plan_versions();
create trigger a20_enforce_quota before insert on public.story_plan_versions
  for each row execute function app_private.enforce_quota();
create trigger a30_force_actor_columns before insert on public.story_plan_versions
  for each row execute function app_private.force_actor_columns();
create trigger a40_assign_next_revision before insert on public.story_plan_versions
  for each row execute function app_private.assign_next_revision();
create trigger c10_set_current_pointer after insert on public.story_plan_versions
  for each row execute function app_private.set_current_pointer();

-- 5. Row level security (security-model §5.1, §5.3-§5.6) -------------------------------------------------------------
alter table public.camera_sources enable row level security;
alter table public.source_manifests enable row level security;
alter table public.sync_maps enable row level security;
alter table public.calibration_versions enable row level security;
alter table public.point_event_revisions enable row level security;
alter table public.observations enable row level security;
alter table public.lessons enable row level security;
alter table public.lesson_clips enable row level security;
alter table public.artifacts enable row level security;
alter table public.access_grants enable row level security;
alter table public.story_plans enable row level security;
alter table public.story_plan_versions enable row level security;

-- Anonymous Supabase users (test-only lobby experiments) never touch Studio tables.
create policy camera_sources_real_users_only on public.camera_sources as restrictive for all to authenticated
  using (app_private.is_real_user()) with check (app_private.is_real_user());
create policy source_manifests_real_users_only on public.source_manifests as restrictive for all to authenticated
  using (app_private.is_real_user()) with check (app_private.is_real_user());
create policy sync_maps_real_users_only on public.sync_maps as restrictive for all to authenticated
  using (app_private.is_real_user()) with check (app_private.is_real_user());
create policy calibration_versions_real_users_only on public.calibration_versions as restrictive for all
  to authenticated using (app_private.is_real_user()) with check (app_private.is_real_user());
create policy point_event_revisions_real_users_only on public.point_event_revisions as restrictive for all
  to authenticated using (app_private.is_real_user()) with check (app_private.is_real_user());
create policy observations_real_users_only on public.observations as restrictive for all to authenticated
  using (app_private.is_real_user()) with check (app_private.is_real_user());
create policy lessons_real_users_only on public.lessons as restrictive for all to authenticated
  using (app_private.is_real_user()) with check (app_private.is_real_user());
create policy lesson_clips_real_users_only on public.lesson_clips as restrictive for all to authenticated
  using (app_private.is_real_user()) with check (app_private.is_real_user());
create policy artifacts_real_users_only on public.artifacts as restrictive for all to authenticated
  using (app_private.is_real_user()) with check (app_private.is_real_user());
create policy access_grants_real_users_only on public.access_grants as restrictive for all to authenticated
  using (app_private.is_real_user()) with check (app_private.is_real_user());
create policy story_plans_real_users_only on public.story_plans as restrictive for all to authenticated
  using (app_private.is_real_user()) with check (app_private.is_real_user());
create policy story_plan_versions_real_users_only on public.story_plan_versions as restrictive for all
  to authenticated using (app_private.is_real_user()) with check (app_private.is_real_user());

-- camera_sources: owners and coaches read; a signed-in camera reads only its own source while its invite is
-- approved and live (T-DB-16); the owner edits the label. Everything else is written by app_gateway.
create policy camera_sources_select on public.camera_sources for select to authenticated
  using (app_private.has_project_role(project_id, '{owner,coach}')
         or (uploader_user_id = (select auth.uid()) and app_private.is_own_live_camera_invite(invite_id)));
create policy camera_sources_update_label on public.camera_sources for update to authenticated
  using (app_private.has_project_role(project_id, '{owner}'))
  with check (app_private.has_project_role(project_id, '{owner}'));

create policy source_manifests_select on public.source_manifests for select to authenticated
  using (app_private.has_project_role(project_id, '{owner,coach}'));

create policy sync_maps_select on public.sync_maps for select to authenticated
  using (app_private.has_project_role(project_id, '{owner,coach}'));
create policy sync_maps_insert on public.sync_maps for insert to authenticated
  with check (app_private.can_insert_sync_maps(project_id, review_state));

create policy calibration_versions_select on public.calibration_versions for select to authenticated
  using (app_private.has_project_role(project_id, '{owner,coach}'));
create policy calibration_versions_insert on public.calibration_versions for insert to authenticated
  with check (app_private.can_insert_calibration_versions(project_id, provenance));

create policy point_event_revisions_select on public.point_event_revisions for select to authenticated
  using (app_private.has_project_role(project_id, '{owner,coach}'));
create policy point_event_revisions_insert on public.point_event_revisions for insert to authenticated
  with check (app_private.can_insert_point_event_revisions(project_id));

-- observations: every non-null parent must be accessible (AND, never OR), so a project coach cannot read a row that
-- also belongs to a lesson they cannot access, and vice versa (T-DB-49).
create policy observations_select on public.observations for select to authenticated
  using ((project_id is null or app_private.has_project_role(project_id, '{owner,coach}'))
         and (lesson_id is null or app_private.lesson_access(lesson_id) in ('owner', 'coach'))
         and num_nonnulls(project_id, lesson_id) >= 1);
create policy observations_insert on public.observations for insert to authenticated
  with check (app_private.can_insert_observations(project_id, lesson_id, provenance));
create policy observations_update on public.observations for update to authenticated
  using ((project_id is null or app_private.has_project_role(project_id, '{owner,coach}'))
         and (lesson_id is null or app_private.lesson_access(lesson_id) in ('owner', 'coach'))
         and num_nonnulls(project_id, lesson_id) >= 1)
  with check (provenance <> 'validated');

create policy lessons_select on public.lessons for select to authenticated
  using (owner_id = (select auth.uid()) or app_private.lesson_access(id) in ('coach', 'viewer'));
create policy lessons_insert on public.lessons for insert to authenticated
  with check (app_private.can_insert_lessons(owner_id));
create policy lessons_update on public.lessons for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));

-- lesson_clips: a viewer sees the clip row (window, note, keeper ref), never the project, its sources or other
-- clips; the media they can stream is only the clip_excerpt artifact.
create policy lesson_clips_select on public.lesson_clips for select to authenticated
  using (app_private.can_view_lesson_clip_row(id, lesson_id, project_id,
           share_approved_at is not null));   -- MUTATION M1
create policy lesson_clips_insert on public.lesson_clips for insert to authenticated
  with check (app_private.can_insert_lesson_clips(lesson_id, project_id));
create policy lesson_clips_update on public.lesson_clips for update to authenticated
  using (app_private.lesson_access(lesson_id) = 'owner')
  with check (app_private.lesson_access(lesson_id) = 'owner'
              and app_private.has_project_role(project_id, '{owner,coach}'));

create policy story_plans_select on public.story_plans for select to authenticated
  using (app_private.has_project_role(project_id, '{owner,coach}'));
create policy story_plans_insert on public.story_plans for insert to authenticated
  with check (app_private.can_insert_story_plans(project_id));
create policy story_plans_update on public.story_plans for update to authenticated
  using (app_private.has_project_role(project_id, '{owner,coach}'))
  with check (app_private.has_project_role(project_id, '{owner,coach}'));

create policy story_plan_versions_select on public.story_plan_versions for select to authenticated
  using (app_private.has_project_role(project_id, '{owner,coach}'));
create policy story_plan_versions_insert on public.story_plan_versions for insert to authenticated
  with check (app_private.can_insert_story_plan_versions(story_plan_id, planner_kind));

-- artifacts: members read client-visible kinds (owners also the project bundle); viewers read only what a grant or
-- a shareable clip reaches. No client writes.
create policy artifacts_select_members on public.artifacts for select to authenticated
  using (deleted_at is null
         and ((kind in ('preview', 'film', 'thumbnail', 'captions', 'chapters', 'edit_manifest', 'clip_excerpt')
               and app_private.has_project_role(project_id, '{owner,coach}'))
              or (kind = 'project_bundle' and app_private.has_project_role(project_id, '{owner}'))));
create policy artifacts_select_viewers on public.artifacts for select to authenticated
  using (app_private.viewer_can_see_artifact(id));

create policy access_grants_select on public.access_grants for select to authenticated
  using (created_by = (select auth.uid()) or grantee_user_id = (select auth.uid()));

-- 6. Grants -----------------------------------------------------------------------------------------------------------
revoke all on public.camera_sources, public.source_manifests, public.sync_maps, public.calibration_versions,
  public.point_event_revisions, public.observations, public.lessons, public.lesson_clips, public.artifacts,
  public.access_grants, public.story_plans, public.story_plan_versions
  from public, anon, authenticated;

-- not granted: r2_key, verified_etag, current_session_id, client_probe (the device's declaration stays server-side)
grant select (id, project_id, slot, local_source_id, invite_id, uploader_user_id, label, state, declared_bytes,
              declared_sha256, verified_sha256, verified_at, probe, rejected_reason, participant_ack_at,
              created_at, updated_at, revision) on public.camera_sources to authenticated;
grant update (label) on public.camera_sources to authenticated;

grant select on public.source_manifests to authenticated;

grant select on public.sync_maps to authenticated;
grant insert (project_id, source_manifest_revision, map, review_state, method, method_version, sample)
  on public.sync_maps to authenticated;

grant select on public.calibration_versions to authenticated;
grant insert (project_id, source_id, calibration, method, method_version, provenance)
  on public.calibration_versions to authenticated;

grant select on public.point_event_revisions to authenticated;
grant insert (project_id, parent_revision, local_session_id, schema_version, event_log, client_device_id)
  on public.point_event_revisions to authenticated;

grant select on public.observations to authenticated;
grant insert (project_id, lesson_id, source_id, match_start_us, match_end_us, sync_map_revision, event_revision,
              capability_id, kind, body, sample) on public.observations to authenticated;   -- provenance: 'manual'
grant update (review_state, body) on public.observations to authenticated;

grant select on public.lessons to authenticated;
grant insert (local_lesson_id, lesson_date, title, notes, next_goal, practice, sample) on public.lessons
  to authenticated;   -- owner_id: auth.uid()
grant update (lesson_date, title, notes, next_goal, practice) on public.lessons to authenticated;

grant select on public.lesson_clips to authenticated;
grant insert (lesson_id, project_id, source_id, match_start_us, match_end_us, sync_map_revision, event_revision,
              keeper_ref, note, position) on public.lesson_clips to authenticated;
grant update (match_start_us, match_end_us, keeper_ref, note, position) on public.lesson_clips to authenticated;

grant select on public.story_plans to authenticated;
grant insert (project_id, lesson_ids, profile_id, profile_revision, title, sample) on public.story_plans
  to authenticated;
grant update (title) on public.story_plans to authenticated;

grant select on public.story_plan_versions to authenticated;
grant insert (story_plan_id, planner_kind, planner_adapter_version, story_plan, edl, bound_source_manifest_revision,
              bound_sync_map_revision, bound_event_revision) on public.story_plan_versions to authenticated;

-- not granted: r2_key, bucket_class, attempt_id, lesson_clip_id, deleted_at
grant select (id, project_id, job_id, source_id, parent_artifact_id, kind, bytes, sha256, media, state, verification,
              edl_sha256, event_revision, sync_map_revision, source_manifest_revision, profile_id, profile_revision,
              renderer_version, stale, retention_until, display_title, sample, created_at, verified_at)
  on public.artifacts to authenticated;

-- not granted: token_hash, invitee_email_hmac
grant select (id, kind, project_id, lesson_id, artifact_id, lesson_clip_id, grantee_user_id, created_by, redeem_by,
              expires_at, redeemed_at, revoked_at, created_at) on public.access_grants to authenticated;

-- 7. Gateway commands: clip share approval and withdrawal (security-model §4.1, §13.8; finding 20) -------------------
-- The project owner (p_actor, from the verified JWT) approves exactly the clip's current window; anyone else gets
-- P0404, as for a missing clip. The audit row (app_ops.audit_events) is added with S78.
create function app_gateway.approve_clip_share(p_actor uuid, p_clip uuid, p_request_id uuid)
returns timestamptz language plpgsql volatile security definer set search_path = '' as $$
declare
  v_clip public.lesson_clips;
  v_at   timestamptz := now();
begin
  select c.* into v_clip from public.lesson_clips c where c.id = p_clip for update;
  if not found or p_actor is null or not exists (
       select 1 from public.projects p
        where p.id = v_clip.project_id and p.owner_id = p_actor and p.deleted_at is null) then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  update public.lesson_clips
     set share_approved_at = v_at,
         share_approved_sha256 = app_private.clip_share_fingerprint(
           v_clip.project_id, v_clip.source_id, v_clip.match_start_us, v_clip.match_end_us, v_clip.keeper_ref,
           v_clip.sync_map_revision, v_clip.event_revision)
   where id = p_clip;
  return v_at;
end
$$;

-- revoke_clip_share: the same owner check; the viewer loses the clip at once (can_view_lesson_clip).
create function app_gateway.revoke_clip_share(p_actor uuid, p_clip uuid, p_request_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  v_project uuid;
begin
  select c.project_id into v_project from public.lesson_clips c where c.id = p_clip for update;
  if not found or p_actor is null or not exists (
       select 1 from public.projects p
        where p.id = v_project and p.owner_id = p_actor and p.deleted_at is null) then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  update public.lesson_clips set share_approved_at = null, share_approved_sha256 = null where id = p_clip;
end
$$;

-- 8. Function privileges ----------------------------------------------------------------------------------------------
revoke all on function
  app_private.grant_active(public.access_grants), app_private.lesson_access(uuid),
  app_private.clip_share_fingerprint(uuid, uuid, bigint, bigint, text, int, int), app_private.clip_is_shareable(uuid),
  app_private.can_view_lesson_clip_row(uuid, uuid, uuid, boolean), app_private.can_view_lesson_clip(uuid), app_private.viewer_can_see_artifact(uuid),
  app_private.is_own_live_camera_invite(uuid),
  app_private.can_insert_sync_maps(uuid, public.review_state),
  app_private.can_insert_calibration_versions(uuid, public.provenance),
  app_private.can_insert_point_event_revisions(uuid),
  app_private.can_insert_observations(uuid, uuid, public.provenance),
  app_private.can_insert_lessons(uuid), app_private.can_insert_lesson_clips(uuid, uuid),
  app_private.can_insert_story_plans(uuid), app_private.can_insert_story_plan_versions(uuid, public.planner_kind),
  app_private.check_len(text, int, text), app_private.check_json(jsonb, int, text),
  app_private.check_hash(bytea, text), app_private.check_required(boolean, text),
  app_private.check_valid(boolean, text),
  app_private.rls_guard(), app_private.set_parent_project(), app_private.validate_camera_sources(),
  app_private.validate_source_manifests(), app_private.validate_sync_maps(),
  app_private.validate_calibration_versions(), app_private.validate_point_event_revisions(),
  app_private.validate_observations(), app_private.validate_lessons(), app_private.validate_lesson_clips(),
  app_private.validate_artifacts(), app_private.validate_access_grants(), app_private.validate_story_plans(),
  app_private.validate_story_plan_versions(), app_private.enforce_quota(), app_private.force_actor_columns(),
  app_private.assign_next_revision(), app_private.check_event_parent(), app_private.mark_stale(),
  app_private.set_current_pointer(), app_private.check_story_plan_lessons(), app_private.check_clip_excerpt(),
  app_private.pin_shared_clip(), app_private.check_grant_clips(), app_private.review_observation(),
  app_gateway.approve_clip_share(uuid, uuid, uuid), app_gateway.revoke_clip_share(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;

-- Only what policies call. grant_active, can_view_lesson_clip (by id), clip_is_shareable, the check_* helpers and every trigger
-- function: no EXECUTE for any client role.
grant execute on function
  app_private.lesson_access(uuid), app_private.can_view_lesson_clip_row(uuid, uuid, uuid, boolean),
  app_private.clip_share_fingerprint(uuid, uuid, bigint, bigint, text, int, int), app_private.viewer_can_see_artifact(uuid),
  app_private.is_own_live_camera_invite(uuid),
  app_private.can_insert_sync_maps(uuid, public.review_state),
  app_private.can_insert_calibration_versions(uuid, public.provenance),
  app_private.can_insert_point_event_revisions(uuid),
  app_private.can_insert_observations(uuid, uuid, public.provenance),
  app_private.can_insert_lessons(uuid), app_private.can_insert_lesson_clips(uuid, uuid),
  app_private.can_insert_story_plans(uuid), app_private.can_insert_story_plan_versions(uuid, public.planner_kind)
  to authenticated;

-- User commands are the gateway's alone, never the orchestrator's (T-DB-57).
grant execute on function app_gateway.approve_clip_share(uuid, uuid, uuid),
  app_gateway.revoke_clip_share(uuid, uuid, uuid) to jovra_gateway;

-- 9. One owner (T-DB-66). Last, so every grant above was made by the migrating role. ---------------------------------
alter table public.camera_sources owner to jovra_owner;
alter table public.source_manifests owner to jovra_owner;
alter table public.sync_maps owner to jovra_owner;
alter table public.calibration_versions owner to jovra_owner;
alter table public.point_event_revisions owner to jovra_owner;
alter table public.observations owner to jovra_owner;
alter table public.lessons owner to jovra_owner;
alter table public.lesson_clips owner to jovra_owner;
alter table public.artifacts owner to jovra_owner;
alter table public.access_grants owner to jovra_owner;
alter table public.story_plans owner to jovra_owner;
alter table public.story_plan_versions owner to jovra_owner;
alter table app_ops.quota_limits owner to jovra_owner;
alter table app_ops.quota_counters owner to jovra_owner;

alter function app_private.grant_active(public.access_grants) owner to jovra_owner;
alter function app_private.lesson_access(uuid) owner to jovra_owner;
alter function app_private.clip_share_fingerprint(uuid, uuid, bigint, bigint, text, int, int) owner to jovra_owner;
alter function app_private.can_view_lesson_clip_row(uuid, uuid, uuid, boolean) owner to jovra_owner;
alter function app_private.clip_is_shareable(uuid) owner to jovra_owner;
alter function app_private.can_view_lesson_clip(uuid) owner to jovra_owner;
alter function app_private.viewer_can_see_artifact(uuid) owner to jovra_owner;
alter function app_private.is_own_live_camera_invite(uuid) owner to jovra_owner;
alter function app_private.can_insert_sync_maps(uuid, public.review_state) owner to jovra_owner;
alter function app_private.can_insert_calibration_versions(uuid, public.provenance) owner to jovra_owner;
alter function app_private.can_insert_point_event_revisions(uuid) owner to jovra_owner;
alter function app_private.can_insert_observations(uuid, uuid, public.provenance) owner to jovra_owner;
alter function app_private.can_insert_lessons(uuid) owner to jovra_owner;
alter function app_private.can_insert_lesson_clips(uuid, uuid) owner to jovra_owner;
alter function app_private.can_insert_story_plans(uuid) owner to jovra_owner;
alter function app_private.can_insert_story_plan_versions(uuid, public.planner_kind) owner to jovra_owner;
alter function app_private.check_len(text, int, text) owner to jovra_owner;
alter function app_private.check_json(jsonb, int, text) owner to jovra_owner;
alter function app_private.check_hash(bytea, text) owner to jovra_owner;
alter function app_private.check_required(boolean, text) owner to jovra_owner;
alter function app_private.check_valid(boolean, text) owner to jovra_owner;
alter function app_private.rls_guard() owner to jovra_owner;
alter function app_private.set_parent_project() owner to jovra_owner;
alter function app_private.validate_camera_sources() owner to jovra_owner;
alter function app_private.validate_source_manifests() owner to jovra_owner;
alter function app_private.validate_sync_maps() owner to jovra_owner;
alter function app_private.validate_calibration_versions() owner to jovra_owner;
alter function app_private.validate_point_event_revisions() owner to jovra_owner;
alter function app_private.validate_observations() owner to jovra_owner;
alter function app_private.validate_lessons() owner to jovra_owner;
alter function app_private.validate_lesson_clips() owner to jovra_owner;
alter function app_private.validate_artifacts() owner to jovra_owner;
alter function app_private.validate_access_grants() owner to jovra_owner;
alter function app_private.validate_story_plans() owner to jovra_owner;
alter function app_private.validate_story_plan_versions() owner to jovra_owner;
alter function app_private.enforce_quota() owner to jovra_owner;
alter function app_private.force_actor_columns() owner to jovra_owner;
alter function app_private.assign_next_revision() owner to jovra_owner;
alter function app_private.check_event_parent() owner to jovra_owner;
alter function app_private.mark_stale() owner to jovra_owner;
alter function app_private.set_current_pointer() owner to jovra_owner;
alter function app_private.check_story_plan_lessons() owner to jovra_owner;
alter function app_private.check_clip_excerpt() owner to jovra_owner;
alter function app_private.pin_shared_clip() owner to jovra_owner;
alter function app_private.check_grant_clips() owner to jovra_owner;
alter function app_private.review_observation() owner to jovra_owner;
alter function app_gateway.approve_clip_share(uuid, uuid, uuid) owner to jovra_owner;
alter function app_gateway.revoke_clip_share(uuid, uuid, uuid) owner to jovra_owner;
