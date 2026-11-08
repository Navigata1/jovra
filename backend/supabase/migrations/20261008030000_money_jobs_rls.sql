-- S78 / B-05: migration 3. Quotes, usage reservations, render jobs and attempts, artifact links and artifact_sources,
-- provider status rows, deletion requests and the server-only app_ops tables, with RLS
-- (docs/backend/architecture.md §4.1, §4.3, §7, §10; security-model.md §3, §5.6, §5.7, §6, §8.1, §13.5-§13.7, §13.9,
-- §13.12, §13.15-§13.17):
--   * money and jobs are never written by a client: quotes, usage_reservations, render_jobs, render_attempts,
--     artifacts, artifact_sources, access_grants and deletion_requests have no INSERT/UPDATE/DELETE grant for any
--     client role, and jovra_gateway/jovra_orchestrator reach them only through app_gateway commands (S79, S80);
--   * owners read money (quotes, reservations; credits only, never the internal micro-USD cap); coaches read jobs and
--     attempts but never money or `measurements` (finding 32, T-DB-25);
--   * one hold and one live job per (project, plan, plan version, output) with NULLS NOT DISTINCT, so plan-by-job
--     work (version null) cannot open a second hold (finding 18, security-model §13.6);
--   * composite foreign keys bind every plan, version, quote, reservation, job, attempt, excerpt and artifact source to
--     its own project (findings 17 and 31, T-DB-59); `ready` needs a verified delivered film (T-DB-53);
--   * render_attempts.output_plan carries a byte cap per output, bounded per artifact kind (finding 32);
--   * provider_connections are status rows only: no token, secret, URL or endpoint column exists (T-DB-29, §13.17);
--   * app_ops: upload sessions and parts, the job outbox (ids only), redacted idempotency records, fail-closed spend
--     limits with a default owner row and no environment row (the operator sets it; §13.7), the append-only spend
--     ledger and audit log; no `jv[igslhc]_` token, JWT or email can be stored in any app_ops row (T-DB-47);
--   * the clip-share commands of migration 2 now write audit rows, and every unlinked excerpt gets a delete_object
--     outbox row (revoke_clip_share unlinks it too, so it has the same effect as a moved window, T-DB-62).
--
-- The command functions (create_quote, accept_quote, reserve_stage, set_job_state, finish_attempt, ...) are S79 and
-- S80. This migration ships the tables, guards and invariants those commands rely on.
-- Objects are created by the migrating role and handed to jovra_owner at the end (T-DB-66), as in migrations 1-2.

-- 1. Tables ------------------------------------------------------------------------------------------------------------
-- The CHECKs are a backstop; the a10_validate triggers raise coded errors first (section 3).

-- quotes: a server-computed preflight, never authored by a client. The consent captured at acceptance follows the
-- `consent` object of contract jovra.quote/1 (spec/schemas/studio/quote.schema.json).
create table public.quotes (
  id                           uuid primary key default gen_random_uuid(),
  project_id                   uuid not null references public.projects (id) on delete cascade,
  owner_id                     uuid not null references public.profiles (id) on delete cascade,
  story_plan_id                uuid not null,
  story_plan_version_id        uuid,   -- null: the plan is produced by the job (plan-by-job)
  output_spec_sha256           bytea not null check (octet_length(output_spec_sha256) = 32),
  supersedes_quote_id          uuid,
  inputs                       jsonb not null check (octet_length(inputs::text) <= 65536),
  inputs_sha256                bytea not null check (octet_length(inputs_sha256) = 32),
  rates_version                text not null check (char_length(rates_version) <= 40),
  line_items                   jsonb not null default '{}' check (octet_length(line_items::text) <= 16384),
  planner_choice               text not null check (planner_choice in ('heuristic', 'model')),
  retention_days               int not null check (retention_days in (1, 7, 30)),
  estimate_low_credits         int not null check (estimate_low_credits >= 0),
  estimate_high_credits        int not null,
  cap_credits                  int not null,
  estimate_high_cost_micro_usd bigint not null check (estimate_high_cost_micro_usd > 0),
  cap_cost_micro_usd           bigint not null,
  state                        text not null default 'open'
                                 check (state in ('open', 'accepted', 'expired', 'superseded', 'declined')),
  expires_at                   timestamptz not null,
  accepted_at                  timestamptz,
  consent                      jsonb check (octet_length(consent::text) <= 4096),
  sample                       boolean not null default false,
  created_at                   timestamptz not null default now(),
  unique (project_id, id),
  check (estimate_low_credits <= estimate_high_credits and estimate_high_credits <= cap_credits),
  check (estimate_high_cost_micro_usd <= cap_cost_micro_usd),
  check (expires_at > created_at),
  check ((accepted_at is null) = (consent is null)),
  check (state <> 'accepted' or accepted_at is not null),
  -- the plan is of this project and the version of this plan (finding 17, T-DB-59)
  foreign key (project_id, story_plan_id) references public.story_plans (project_id, id),
  foreign key (story_plan_id, story_plan_version_id) references public.story_plan_versions (story_plan_id, id),
  foreign key (project_id, supersedes_quote_id) references public.quotes (project_id, id)
);
create index quotes_owner_id_idx on public.quotes (owner_id);
create index quotes_project_plan_idx on public.quotes (project_id, story_plan_id);
create index quotes_plan_version_idx on public.quotes (story_plan_id, story_plan_version_id);
create index quotes_supersedes_idx on public.quotes (project_id, supersedes_quote_id);

-- usage_reservations: the idempotent hold that bounds a job's spend. quote_id is the current funding quote (a top-up
-- moves it); initial_quote_id is the quote whose acceptance opened the hold and never moves.
create table public.usage_reservations (
  id                      uuid primary key default gen_random_uuid(),
  project_id              uuid not null references public.projects (id) on delete cascade,
  owner_id                uuid not null references public.profiles (id) on delete cascade,
  quote_id                uuid not null unique,
  initial_quote_id        uuid not null unique,
  job_id                  uuid unique,   -- FK to render_jobs below
  story_plan_id           uuid not null,
  story_plan_version_id   uuid,
  output_spec_sha256      bytea not null check (octet_length(output_spec_sha256) = 32),
  cap_credits             int not null check (cap_credits >= 0),
  cap_cost_micro_usd      bigint not null check (cap_cost_micro_usd > 0),   -- always real micro-USD, also in test
  reserved_cost_micro_usd bigint not null default 0 check (reserved_cost_micro_usd >= 0),
  consumed_cost_micro_usd bigint not null default 0 check (consumed_cost_micro_usd >= 0),
  released_cost_micro_usd bigint not null default 0 check (released_cost_micro_usd >= 0),
  state                   text not null default 'held' check (state in ('held', 'settled', 'released')),
  sample                  boolean not null default false,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  unique (project_id, id),
  check (reserved_cost_micro_usd <= cap_cost_micro_usd),
  check (consumed_cost_micro_usd + released_cost_micro_usd <= reserved_cost_micro_usd),
  foreign key (project_id, quote_id) references public.quotes (project_id, id),
  foreign key (project_id, initial_quote_id) references public.quotes (project_id, id),
  foreign key (project_id, story_plan_id) references public.story_plans (project_id, id),
  foreign key (story_plan_id, story_plan_version_id) references public.story_plan_versions (story_plan_id, id)
);
-- The ADR-0019 domain key (project, plan revision, output spec): identical work never holds twice, also while the
-- version is still to be produced by the job (NULLS NOT DISTINCT, finding 18, §13.6). The quote id is not part of
-- it, so re-quoting identical work can never open a second hold.
create unique index usage_reservations_one_hold on public.usage_reservations
  (project_id, story_plan_id, story_plan_version_id, output_spec_sha256) nulls not distinct
  where state = 'held';
create index usage_reservations_owner_id_idx on public.usage_reservations (owner_id, state);
create index usage_reservations_project_quote_idx on public.usage_reservations (project_id, quote_id);
create index usage_reservations_project_initial_quote_idx on public.usage_reservations (project_id, initial_quote_id);
create index usage_reservations_plan_version_idx on public.usage_reservations (story_plan_id, story_plan_version_id);
create index usage_reservations_project_plan_idx on public.usage_reservations (project_id, story_plan_id);

create table public.render_jobs (
  id                    uuid primary key default gen_random_uuid(),   -- also the Workflow instance id
  project_id            uuid not null references public.projects (id) on delete cascade,
  story_plan_id         uuid not null,
  story_plan_version_id uuid,
  parent_job_id         uuid,
  quote_id              uuid not null,
  reservation_id        uuid not null unique,
  requested_by          uuid references public.profiles (id) on delete set null,
  output_spec_sha256    bytea not null check (octet_length(output_spec_sha256) = 32),
  idempotency_key       text check (char_length(idempotency_key) <= 255),   -- HTTP retries only, never the domain key
  state                 public.job_state not null default 'consented',
  stage                 public.job_stage,
  stage_progress_milli  int check (stage_progress_milli between 0 and 1000),
  output_spec           jsonb not null check (octet_length(output_spec::text) <= 4096),
  error_code            text check (char_length(error_code) <= 64),
  cancel_requested_at   timestamptz,
  paused_at             timestamptz,
  review_requested_at   timestamptz,
  reviewed_at           timestamptz,
  sample                boolean not null default false,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  finished_at           timestamptz,
  unique (project_id, id),
  foreign key (project_id, story_plan_id) references public.story_plans (project_id, id),
  foreign key (story_plan_id, story_plan_version_id) references public.story_plan_versions (story_plan_id, id),
  foreign key (project_id, quote_id) references public.quotes (project_id, id),
  foreign key (project_id, reservation_id) references public.usage_reservations (project_id, id),
  foreign key (project_id, parent_job_id) references public.render_jobs (project_id, id)
);
-- Identical work never runs as two jobs (§13.6): the terminal states of the brief plus quote_expired.
create unique index render_jobs_one_live on public.render_jobs
  (project_id, story_plan_id, story_plan_version_id, output_spec_sha256) nulls not distinct
  where state not in ('ready', 'canceled', 'failed_terminal', 'quote_expired', 'deleted');
create index render_jobs_project_plan_idx on public.render_jobs (project_id, story_plan_id);
create index render_jobs_plan_version_idx on public.render_jobs (story_plan_id, story_plan_version_id);
create index render_jobs_project_quote_idx on public.render_jobs (project_id, quote_id);
create index render_jobs_project_reservation_idx on public.render_jobs (project_id, reservation_id);
create index render_jobs_project_parent_idx on public.render_jobs (project_id, parent_job_id);
create index render_jobs_requested_by_idx on public.render_jobs (requested_by);

alter table public.usage_reservations add foreign key (project_id, job_id)
  references public.render_jobs (project_id, id) on delete set null (job_id);
create index usage_reservations_project_job_idx on public.usage_reservations (project_id, job_id);

-- render_attempts: one row per (job, stage, attempt): leases, fencing, the SQL-computed reservation, inputs and the
-- output plan with a byte cap per output. Leases, inputs, outputs and measurements are never granted to clients.
create table public.render_attempts (
  id                      uuid primary key default gen_random_uuid(),
  job_id                  uuid not null references public.render_jobs (id) on delete cascade,
  stage                   public.job_stage not null,
  attempt                 int not null check (attempt between 1 and 10),
  state                   text not null default 'reserved'
                            check (state in ('reserved', 'dispatched', 'running', 'succeeded', 'failed',
                                             'lease_expired', 'canceled', 'dead_lettered')),
  lease_token_hash        bytea check (octet_length(lease_token_hash) = 32),   -- SHA-256 of the jvl_ token
  claimed_by_host         text check (char_length(claimed_by_host) <= 64),
  leased_until            timestamptz,
  heartbeat_at            timestamptz,
  host_kind               text check (host_kind in ('cf-container', 'cloud-run', 'local-test')),
  input_refs              jsonb not null default '[]'
                            check (jsonb_typeof(input_refs) = 'array' and octet_length(input_refs::text) <= 65536),
  output_plan             jsonb not null default '[]'
                            check (jsonb_typeof(output_plan) = 'array' and octet_length(output_plan::text) <= 16384),
  input_hash              bytea check (octet_length(input_hash) = 32),
  output_refs             jsonb not null default '[]'
                            check (jsonb_typeof(output_refs) = 'array' and octet_length(output_refs::text) <= 65536),
  measurements            jsonb check (octet_length(measurements::text) <= 65536),
  reserved_cost_micro_usd bigint not null check (reserved_cost_micro_usd > 0),   -- a zero estimate is impossible
  actual_cost_micro_usd   bigint check (actual_cost_micro_usd >= 0),
  planner_budget          jsonb check (octet_length(planner_budget::text) <= 4096),
  error_code              text check (char_length(error_code) <= 64),
  retryable               boolean,
  created_at              timestamptz not null default now(),
  started_at              timestamptz,
  finished_at             timestamptz,
  unique (job_id, stage, attempt),
  unique (job_id, id),   -- the target of artifacts (job_id, attempt_id)
  check (planner_budget is null or stage = 'plan'),
  check (lease_token_hash is null or (claimed_by_host is not null and leased_until is not null))
);

-- artifacts (migration 2) gain their job and attempt links, both bound to the artifact's own project and job.
alter table public.artifacts add foreign key (project_id, job_id)
  references public.render_jobs (project_id, id) on delete set null (job_id);
alter table public.artifacts add foreign key (job_id, attempt_id)
  references public.render_attempts (job_id, id) on delete set null (attempt_id);
create index artifacts_project_job_idx on public.artifacts (project_id, job_id);
create index artifacts_job_attempt_idx on public.artifacts (job_id, attempt_id);

-- Excerpt links in both directions are project-constrained (finding 31): an excerpt artifact names a clip of its own
-- project and a clip links an excerpt of its own project. The single-column FKs of migration 2 are replaced.
alter table public.lesson_clips add constraint lesson_clips_project_id_id_key unique (project_id, id);
do $$
declare
  v_name text;
begin
  select c.conname into v_name from pg_catalog.pg_constraint c
   where c.conrelid = 'public.artifacts'::regclass and c.contype = 'f'
     and c.conkey = array[(select a.attnum from pg_catalog.pg_attribute a
                            where a.attrelid = 'public.artifacts'::regclass and a.attname = 'lesson_clip_id')];
  if v_name is null then
    raise exception 'migration 3: the single-column FK artifacts.lesson_clip_id was not found';
  end if;
  execute pg_catalog.format('alter table public.artifacts drop constraint %I', v_name);

  select c.conname into v_name from pg_catalog.pg_constraint c
   where c.conrelid = 'public.lesson_clips'::regclass and c.contype = 'f'
     and c.conkey = array[(select a.attnum from pg_catalog.pg_attribute a
                            where a.attrelid = 'public.lesson_clips'::regclass and a.attname = 'excerpt_artifact_id')];
  if v_name is null then
    raise exception 'migration 3: the single-column FK lesson_clips.excerpt_artifact_id was not found';
  end if;
  execute pg_catalog.format('alter table public.lesson_clips drop constraint %I', v_name);
end
$$;
alter table public.artifacts add foreign key (project_id, lesson_clip_id)
  references public.lesson_clips (project_id, id) on delete cascade;
alter table public.lesson_clips add foreign key (project_id, excerpt_artifact_id)
  references public.artifacts (project_id, id) on delete set null (excerpt_artifact_id);
create index artifacts_project_lesson_clip_idx on public.artifacts (project_id, lesson_clip_id);
create index lesson_clips_project_excerpt_idx on public.lesson_clips (project_id, excerpt_artifact_id);

-- artifact_sources: every artifact derived from a source, so a source-scope deletion finds every film, preview and
-- excerpt holding its frames (§13.9 (a)). Written only by register_artifact (S80) from the attempt's input_refs.
create table public.artifact_sources (
  artifact_id uuid not null,
  project_id  uuid not null,
  source_id   uuid not null,
  created_at  timestamptz not null default now(),
  primary key (artifact_id, source_id),
  foreign key (project_id, artifact_id) references public.artifacts (project_id, id) on delete cascade,
  foreign key (project_id, source_id) references public.camera_sources (project_id, id) on delete cascade
);
create index artifact_sources_project_artifact_idx on public.artifact_sources (project_id, artifact_id);
create index artifact_sources_project_source_idx on public.artifact_sources (project_id, source_id);

-- provider_connections: capability status of optional archives. Tokens never leave the device (ADR-0008); there is
-- no token, secret, URL or endpoint column (T-DB-29, §13.17), and scopes cannot hold a URL.
create table public.provider_connections (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  provider      public.provider_kind not null,
  state         text not null default 'planned'
                  check (state in ('planned', 'awaiting_setup', 'not_connected', 'connected', 'expired', 'revoked')),
  account_label text check (char_length(account_label) <= 120),   -- user-visible label; no email copied here
  scopes        text[] not null default '{}' check (cardinality(scopes) <= 16),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  revision      bigint not null default 1,
  unique (user_id, provider)
);

create table public.deletion_requests (
  id           uuid primary key default gen_random_uuid(),
  requested_by uuid references public.profiles (id) on delete set null,   -- null after an account deletion completes
  scope        public.deletion_scope not null,
  target_id    uuid not null,
  state        text not null default 'requested'
                 check (state in ('requested', 'canceling_jobs', 'deleting_objects', 'deleting_rows',
                                  'revoking_apple', 'done', 'failed')),
  counts       jsonb not null default '{}' check (octet_length(counts::text) <= 4096),   -- numbers only
  error_code   text check (char_length(error_code) <= 64),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  finished_at  timestamptz,
  check (finished_at is null or state in ('done', 'failed'))
);
create index deletion_requests_requested_by_idx on public.deletion_requests (requested_by);
-- A double tap or a retry never starts a second deletion of the same target (story 199).
create unique index deletion_requests_one_open on public.deletion_requests (scope, target_id) where state <> 'done';

-- app_ops: server-only, reached only by app_gateway definer functions (security-model §5.7) -------------------------
-- Upload expectations held by the server (architecture §6.3). A session uploads one source original, or one render
-- output of an attempt (the *_for_attempt variants, S80).
create table app_ops.upload_sessions (
  id              uuid primary key default gen_random_uuid(),
  project_id      uuid not null,
  source_id       uuid,
  artifact_id     uuid,
  actor_kind      text not null check (actor_kind in ('owner', 'camera_guest', 'render_host')),
  actor_id        uuid,
  r2_key          text not null unique check (char_length(r2_key) <= 512),
  r2_upload_id    text check (char_length(r2_upload_id) <= 1024),
  expected_bytes  bigint not null check (expected_bytes > 0),
  expected_sha256 bytea not null check (octet_length(expected_sha256) = 32),
  part_size       int not null default 33554432 check (part_size = 33554432),   -- fixed 32 MiB
  part_count      int not null check (part_count between 1 and 10000),
  state           text not null default 'opening'
                    check (state in ('opening', 'open', 'completing', 'completed', 'aborted', 'expired')),
  capability_hash bytea unique check (octet_length(capability_hash) = 32),   -- SHA-256 of the jvs_ capability
  created_at      timestamptz not null default now(),
  expires_at      timestamptz not null,
  hard_expires_at timestamptz not null,
  completed_at    timestamptz,
  check (num_nonnulls(source_id, artifact_id) = 1),
  check ((actor_kind = 'render_host') = (artifact_id is not null)),
  check (part_count = (expected_bytes + part_size - 1) / part_size),
  check (hard_expires_at = created_at + interval '48 hours'),   -- absolute ceiling, never extended
  check (expires_at <= hard_expires_at),
  foreign key (project_id, source_id) references public.camera_sources (project_id, id) on delete cascade,
  foreign key (project_id, artifact_id) references public.artifacts (project_id, id) on delete cascade
);
-- One open session per source (or output): opening a new one aborts the old in the same transaction.
create unique index upload_sessions_one_open_source on app_ops.upload_sessions (source_id)
  where state in ('opening', 'open', 'completing');
create unique index upload_sessions_one_open_artifact on app_ops.upload_sessions (artifact_id)
  where state in ('opening', 'open', 'completing');
create index upload_sessions_project_source_idx on app_ops.upload_sessions (project_id, source_id);
create index upload_sessions_project_artifact_idx on app_ops.upload_sessions (project_id, artifact_id);

create table app_ops.upload_parts (
  session_id  uuid not null references app_ops.upload_sessions (id) on delete cascade,
  part_number int not null check (part_number between 1 and 10000),
  bytes       int not null check (bytes > 0 and bytes <= 33554432),
  etag        text not null check (char_length(etag) <= 128),
  sha256      bytea not null check (octet_length(sha256) = 32),
  received_at timestamptz not null default now(),
  primary key (session_id, part_number)
);

-- The outbox, written in the same transaction as the job, attempt or excerpt change and re-dispatched by the
-- reconciler. The payload holds ids only ({jobId}, {attemptId} or {artifactId}); never a lease token or any secret.
create table app_ops.job_outbox (
  id            bigint generated always as identity primary key,
  job_id        uuid references public.render_jobs (id) on delete cascade,
  kind          text not null check (kind in ('start_workflow', 'dispatch_attempt', 'delete_object')),
  payload       jsonb not null check (octet_length(payload::text) <= 8192),
  created_at    timestamptz not null default now(),
  dispatched_at timestamptz,
  attempts      int not null default 0 check (attempts >= 0)
);
create index job_outbox_job_id_idx on app_ops.job_outbox (job_id);
create index job_outbox_undispatched_idx on app_ops.job_outbox (created_at) where dispatched_at is null;

-- Redacted idempotency records (architecture §4.3): routes that mint a bearer secret store ids and expiry only; a
-- replay is 409 secret_not_replayable. The a05 guard refuses any secret-shaped value (T-DB-47).
create table app_ops.idempotency_records (
  actor_id        uuid not null,
  route           text not null check (char_length(route) <= 120),
  key             text not null check (char_length(key) <= 255),
  request_sha256  bytea not null check (octet_length(request_sha256) = 32),
  response_status int not null check (response_status between 100 and 599),
  response_body   jsonb check (octet_length(response_body::text) <= 16384),
  redacted        boolean not null default false,
  created_at      timestamptz not null default now(),
  expires_at      timestamptz not null default (now() + interval '7 days'),
  primary key (actor_id, route, key),
  check (expires_at <= created_at + interval '7 days')
);
create index idempotency_records_expires_at_idx on app_ops.idempotency_records (expires_at);

-- Spend limits fail closed (§13.7, finding 19): NOT NULL limits, one environment row, one default owner row, one row
-- per owner. The environment row is set by the operator (Jon) per environment and is deliberately not seeded, so
-- every acceptance and stage reservation is refused (P0402) until it exists.
create table app_ops.spend_limits (
  id                      bigint generated always as identity primary key,
  scope                   text not null check (scope in ('owner', 'environment')),
  owner_id                uuid references public.profiles (id) on delete cascade,
  max_open_cap_micro_usd  bigint not null check (max_open_cap_micro_usd > 0),
  daily_ceiling_micro_usd bigint not null check (daily_ceiling_micro_usd > 0),
  updated_by_operator_at  timestamptz not null default now(),
  check (scope = 'owner' or owner_id is null)
);
create unique index spend_limits_env on app_ops.spend_limits ((true)) where scope = 'environment';
create unique index spend_limits_default on app_ops.spend_limits ((true)) where scope = 'owner' and owner_id is null;
create unique index spend_limits_owner on app_ops.spend_limits (owner_id) where scope = 'owner' and owner_id is not null;
create index spend_limits_owner_id_idx on app_ops.spend_limits (owner_id);   -- covers the FK for profile deletion
-- INFERRED starting values (5 USD open caps per owner, 10 USD of new caps per owner per day); tune after measurement.
insert into app_ops.spend_limits (scope, owner_id, max_open_cap_micro_usd, daily_ceiling_micro_usd)
values ('owner', null, 5000000, 10000000);

-- The append-only spend ledger: written in the same transaction as the reservation change it records.
create table app_ops.spend_commitments (
  id               bigint generated always as identity primary key,
  at               timestamptz not null default now(),
  owner_id         uuid not null,
  reservation_id   uuid not null,   -- no FK: the ledger outlives project deletion for the day's ceiling
  kind             text not null check (kind in ('cap_open', 'cap_topup', 'stage_reserve', 'stage_overrun')),
  amount_micro_usd bigint not null check (amount_micro_usd > 0)
);
create index spend_commitments_at_idx on app_ops.spend_commitments (at);
create index spend_commitments_reservation_idx on app_ops.spend_commitments (reservation_id);

-- Audit log: append-only, no client access; ids, hashes, counts and coded reasons only. project_id is not a FK, so
-- tombstones survive project deletion. Purged after 400 days (architecture §10).
create table app_ops.audit_events (
  id          bigint generated always as identity primary key,
  at          timestamptz not null default now(),
  env         text not null check (env in ('local', 'test', 'live')),
  actor_kind  text not null check (actor_kind in ('user', 'camera_guest', 'render_host', 'gateway', 'cron',
                                                  'operator')),
  actor_id    uuid,   -- user id, invite id or attempt id; never an email
  project_id  uuid,
  action      text not null check (char_length(action) <= 64 and action ~ '^[a-z_]+(\.[a-z_]+)+$'),
  target_kind text check (char_length(target_kind) <= 40),
  target_id   uuid,
  outcome     text not null check (outcome in ('allowed', 'denied', 'error')),
  reason_code text check (char_length(reason_code) <= 64),
  request_id  uuid,
  detail      jsonb not null default '{}' check (octet_length(detail::text) <= 4096)
);
create index audit_events_at_idx on app_ops.audit_events (at);
create index audit_events_project_idx on app_ops.audit_events (project_id, at);

alter table app_ops.upload_sessions enable row level security;
alter table app_ops.upload_parts enable row level security;
alter table app_ops.job_outbox enable row level security;
alter table app_ops.idempotency_records enable row level security;
alter table app_ops.spend_limits enable row level security;
alter table app_ops.spend_commitments enable row level security;
alter table app_ops.audit_events enable row level security;
revoke all on app_ops.upload_sessions, app_ops.upload_parts, app_ops.job_outbox, app_ops.idempotency_records,
  app_ops.spend_limits, app_ops.spend_commitments, app_ops.audit_events
  from public, anon, authenticated, service_role;

-- provider_connections is client-insertable, so it has a quota like every other such table (finding 23).
insert into app_ops.quota_limits (table_name, subject, max_rows_per_day, max_bytes_per_day, max_bytes_total) values
  ('provider_connections', 'user', 20, 65536, 1048576);

-- 2. Helpers -----------------------------------------------------------------------------------------------------------

-- Byte ceiling per output kind (security-model §13.15, finding 32; INFERRED values). output_plan caps and artifact
-- sizes are bounded by it; authorize_output_upload_for_attempt (S80) refuses declaredBytes above the plan's cap.
create function app_private.output_byte_ceiling(p_kind text) returns bigint
language sql immutable set search_path = '' as $$
  select case p_kind
    when 'film'           then 4294967296    -- 4 GiB
    when 'preview'        then 1073741824    -- 1 GiB
    when 'thumbnail'      then 2097152       -- 2 MiB
    when 'captions'       then 1048576
    when 'chapters'       then 1048576
    when 'edit_manifest'  then 1048576
    when 'clip_excerpt'   then 536870912     -- 512 MiB (a clip is at most 10 minutes)
    when 'contact_sheet'  then 16777216
    when 'pts_table'      then 67108864
    when 'frame_set'      then 536870912
    when 'analysis_proxy' then 4294967296
    when 'render_proxy'   then 8589934592
    when 'project_bundle' then 17179869184
  end
$$;

-- A JSON string holding a canonical lower-case UUID.
create function app_private.is_uuid_text(p_value jsonb) returns boolean
language sql immutable set search_path = '' as $$
  select coalesce(pg_catalog.jsonb_typeof(p_value) = 'string'
                  and (p_value #>> '{}') ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', false)
$$;

-- The consent object of contract jovra.quote/1, checked without casts that could raise on malformed input.
create function app_private.consent_is_valid(p_consent jsonb, p_planner_choice text, p_retention_days int)
returns boolean language plpgsql immutable set search_path = '' as $$
declare
  v_classes jsonb;
begin
  if p_consent is null or pg_catalog.jsonb_typeof(p_consent) <> 'object' then
    return false;
  end if;
  if (select pg_catalog.array_agg(k order by k collate "C") from pg_catalog.jsonb_object_keys(p_consent) k)
     is distinct from array['at', 'consentRecordId', 'consentTextVersion', 'modelProvider', 'retentionDays',
                            'textClasses', 'uploadSelectedSources'] then
    return false;
  end if;
  if p_consent -> 'uploadSelectedSources' is distinct from 'true'::jsonb
     or p_consent -> 'modelProvider' is distinct from pg_catalog.to_jsonb(p_planner_choice = 'model')
     or p_consent -> 'retentionDays' is distinct from pg_catalog.to_jsonb(p_retention_days) then
    return false;
  end if;
  v_classes := p_consent -> 'textClasses';
  if pg_catalog.jsonb_typeof(v_classes) <> 'array' or pg_catalog.jsonb_array_length(v_classes) > 3
     -- note text reaches a model only with modelProvider consent (security-model §13.14)
     or (pg_catalog.jsonb_array_length(v_classes) > 0 and p_planner_choice <> 'model')
     or exists (select 1 from pg_catalog.jsonb_array_elements(v_classes) e
                 where pg_catalog.jsonb_typeof(e) <> 'string'
                    or (e #>> '{}') not in ('ownerNotes', 'ownerLessonNotes', 'coachNotes'))
     or (select pg_catalog.count(distinct e) from pg_catalog.jsonb_array_elements(v_classes) e)
        <> pg_catalog.jsonb_array_length(v_classes) then
    return false;
  end if;
  return pg_catalog.jsonb_typeof(p_consent -> 'consentTextVersion') = 'string'
     and (p_consent ->> 'consentTextVersion') ~ '^[a-z0-9-]+@[0-9]+\.[0-9]+\.[0-9]+$'
     and pg_catalog.jsonb_typeof(p_consent -> 'consentRecordId') = 'string'
     and pg_catalog.char_length(p_consent ->> 'consentRecordId') between 1 and 64
     and pg_catalog.jsonb_typeof(p_consent -> 'at') = 'string'
     and pg_catalog.char_length(p_consent ->> 'at') between 1 and 40;
end
$$;

-- output_plan: [{outputRef, kind, maxBytes}], each cap positive and within the kind's ceiling (finding 32).
create function app_private.output_plan_is_valid(p_plan jsonb) returns boolean
language plpgsql immutable set search_path = '' as $$
declare
  e jsonb;
begin
  if pg_catalog.jsonb_typeof(p_plan) <> 'array' or pg_catalog.jsonb_array_length(p_plan) > 64 then
    return false;
  end if;
  for e in select x from pg_catalog.jsonb_array_elements(p_plan) x loop
    -- `is distinct from`: a missing key is a refusal, never a NULL that slips through
    if pg_catalog.jsonb_typeof(e) is distinct from 'object'
       or pg_catalog.jsonb_typeof(e -> 'outputRef') is distinct from 'string'
       or pg_catalog.char_length(e ->> 'outputRef') not between 1 and 96
       or pg_catalog.jsonb_typeof(e -> 'kind') is distinct from 'string'
       or app_private.output_byte_ceiling(e ->> 'kind') is null
       or pg_catalog.jsonb_typeof(e -> 'maxBytes') is distinct from 'number'
       or (e ->> 'maxBytes') !~ '^[1-9][0-9]{0,18}$' then
      return false;
    end if;
    if (e ->> 'maxBytes')::numeric > app_private.output_byte_ceiling(e ->> 'kind') then
      return false;
    end if;
  end loop;
  return true;
end
$$;

-- input_refs: [{kind: 'source'|'artifact', id}] (reserve_stage, S80, limits them to the job project's verified
-- sources and artifacts; this is the shape check). output_refs: artifact ids.
create function app_private.refs_are_valid(p_refs jsonb, p_kind text) returns boolean
language sql immutable set search_path = '' as $$
  select coalesce(pg_catalog.jsonb_typeof(p_refs) = 'array'
     and pg_catalog.jsonb_array_length(p_refs) <= 512
     and not exists (
       select 1 from pg_catalog.jsonb_array_elements(p_refs) e
        where case p_kind
                when 'input' then not (pg_catalog.jsonb_typeof(e) = 'object'
                                       and coalesce(e ->> 'kind' in ('source', 'artifact'), false)
                                       and app_private.is_uuid_text(e -> 'id'))
                else not app_private.is_uuid_text(e)
              end), false)
$$;

-- planner_budget: exactly {maxImages, maxInputTokens, maxOutputTokens, effort, repairAllowed} (architecture §4.3).
create function app_private.planner_budget_is_valid(p_budget jsonb) returns boolean
language plpgsql immutable set search_path = '' as $$
begin
  if pg_catalog.jsonb_typeof(p_budget) is distinct from 'object' then
    return false;   -- jsonb_object_keys below would raise on a scalar or array
  end if;
  return coalesce((select pg_catalog.array_agg(k order by k collate "C") from pg_catalog.jsonb_object_keys(p_budget) k)
         = array['effort', 'maxImages', 'maxInputTokens', 'maxOutputTokens', 'repairAllowed']
     and pg_catalog.jsonb_typeof(p_budget -> 'maxImages') = 'number'
     and (p_budget ->> 'maxImages') ~ '^[0-9]{1,4}$'
     and pg_catalog.jsonb_typeof(p_budget -> 'maxInputTokens') = 'number'
     and (p_budget ->> 'maxInputTokens') ~ '^[0-9]{1,9}$'
     and pg_catalog.jsonb_typeof(p_budget -> 'maxOutputTokens') = 'number'
     and (p_budget ->> 'maxOutputTokens') ~ '^[0-9]{1,9}$'
     and pg_catalog.jsonb_typeof(p_budget -> 'effort') = 'string'
     and (p_budget ->> 'effort') ~ '^[a-z]{1,16}$'
     and pg_catalog.jsonb_typeof(p_budget -> 'repairAllowed') = 'boolean', false);
end
$$;

-- Outbox payloads name ids only, one shape per kind.
create function app_private.outbox_payload_is_valid(p_kind text, p_payload jsonb, p_job uuid) returns boolean
language plpgsql immutable set search_path = '' as $$
begin
  if pg_catalog.jsonb_typeof(p_payload) is distinct from 'object' then
    return false;
  end if;
  return coalesce(case p_kind
           when 'start_workflow' then
             (select pg_catalog.array_agg(k order by k collate "C") from pg_catalog.jsonb_object_keys(p_payload) k) = array['jobId']
             and app_private.is_uuid_text(p_payload -> 'jobId') and p_payload ->> 'jobId' = p_job::text
           when 'dispatch_attempt' then
             (select pg_catalog.array_agg(k order by k collate "C") from pg_catalog.jsonb_object_keys(p_payload) k)
               = array['attemptId']
             and app_private.is_uuid_text(p_payload -> 'attemptId') and p_job is not null
           when 'delete_object' then
             (select pg_catalog.array_agg(k order by k collate "C") from pg_catalog.jsonb_object_keys(p_payload) k)
               = array['artifactId']
             and app_private.is_uuid_text(p_payload -> 'artifactId')
           else false
         end, false);
end
$$;

-- T-DB-47: no bearer token (jv[igslhc]_), JWT or email address is storable in app_ops. Applied to whole rows.
create function app_private.has_secret(p_text text) returns boolean
language sql immutable set search_path = '' as $$
  -- A token starts at a boundary (start, quote, slash, space...), so a random base64url run such as an R2 upload
  -- id cannot match by chance; a real token (prefix + 43 base64url characters) always does.
  select coalesce(p_text ~ '(^|[^A-Za-z0-9_-])jv[igslhc]_[A-Za-z0-9_-]{16,}'
               or p_text ~ '(^|[^A-Za-z0-9_-])eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}'
               or p_text ~ '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}', false)
$$;

-- Members read a job's attempts through the job's project (owner or approved, active coach).
create function app_private.can_read_job(p_job uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select app_private.has_project_role(j.project_id, '{owner,coach}')
                     from public.render_jobs j where j.id = p_job), false)
$$;

-- The INSERT predicate for provider_connections, shared by the policy and a00_rls_guard (§13.11).
create function app_private.can_insert_provider_connections(p_user uuid) returns boolean
language sql stable set search_path = '' as $$
  select app_private.is_real_user() and coalesce(p_user = app_private.current_actor(), false)
$$;

-- A grant's target is still live: the project (artifact-targeted and coach grants) or the clip's project (clip
-- grants) is not being deleted. Viewers and creators lose the grant rows when deletion starts (T-DB-50, T-DB-31).
create function app_private.grant_target_live(p_project uuid, p_clip uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select (p_project is null or exists (select 1 from public.projects p
                                         where p.id = p_project and p.deleted_at is null))
     and (p_clip is null or exists (select 1 from public.lesson_clips c
                                      join public.projects p on p.id = c.project_id
                                     where c.id = p_clip and p.deleted_at is null))
$$;

-- Audit rows (app_ops.audit_events) for commands; the environment name comes from the database setting app.jovra_env.
create function app_private.write_audit(p_actor_kind text, p_actor_id uuid, p_project uuid, p_action text,
                                        p_target_kind text, p_target_id uuid, p_outcome text, p_reason text,
                                        p_request uuid, p_detail jsonb default '{}')
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  insert into app_ops.audit_events (env, actor_kind, actor_id, project_id, action, target_kind, target_id, outcome,
                                    reason_code, request_id, detail)
  values (coalesce(nullif(pg_catalog.current_setting('app.jovra_env', true), ''), 'local'), p_actor_kind, p_actor_id,
          p_project, p_action, p_target_kind, p_target_id, p_outcome, p_reason, p_request, coalesce(p_detail, '{}'));
end
$$;

-- Hide an excerpt at once and queue the deletion of its object (finding 20; migration 2 left the outbox row here).
create function app_private.retire_excerpt(p_artifact uuid) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  update public.artifacts set deleted_at = now() where id = p_artifact and deleted_at is null;
  if found then
    insert into app_ops.job_outbox (kind, payload)
    values ('delete_object', pg_catalog.jsonb_build_object('artifactId', p_artifact));
  end if;
end
$$;

-- Lesson-scope deletion, objects first (architecture §10 step 5, security-model §13.9 (b), (f)): every excerpt of the
-- lesson's clips and the excerpts' children (thumbnails, captions), whose objects the deletion step removes before
-- the row cascade takes the clips, lesson-only observations and excerpt rows. Server path only; no client EXECUTE.
create function app_private.lesson_deletion_artifacts(p_lesson uuid) returns setof uuid
language sql stable security definer set search_path = '' as $$
  with excerpts as (
    select a.id from public.artifacts a
      join public.lesson_clips c on c.id = a.lesson_clip_id and c.project_id = a.project_id
     where c.lesson_id = p_lesson and a.kind = 'clip_excerpt'
  )
  select id from excerpts
  union
  select ch.id from public.artifacts ch join excerpts e on ch.parent_artifact_id = e.id
$$;

-- 3. Trigger functions ---------------------------------------------------------------------------------------------

-- a00 (migration 2's single guard) learns provider_connections; a table it does not know is still refused.
create or replace function app_private.rls_guard() returns trigger
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
    when 'provider_connections' then
      v_ok := app_private.can_insert_provider_connections(new.user_id);
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

-- a05 on every app_ops table with a text or JSON column: refuse secret-shaped values with a coded error, before any
-- CHECK could print the row (T-DB-47, security-model §8.1, §9).
create function app_private.refuse_secrets() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if app_private.has_secret(pg_catalog.to_jsonb(new)::text) then
    raise exception using errcode = 'P0422', message = 'secret_not_storable';
  end if;
  return new;
end
$$;

-- Append-only ledgers: no update; no delete, except the audit purge after 400 days (architecture §10).
create function app_private.refuse_rewrite() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'DELETE' and tg_table_name = 'audit_events' and old.at < now() - interval '400 days' then
    return old;
  end if;
  raise exception using errcode = 'P0409', message = 'append_only';
end
$$;

create function app_private.touch_updated_at() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end
$$;

create function app_private.validate_quotes() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.check_required(new.project_id is null or new.owner_id is null or new.story_plan_id is null,
                                     'quote');
  perform app_private.check_valid(new.owner_id = (select p.owner_id from public.projects p where p.id = new.project_id),
                                  'owner_id');
  perform app_private.check_required(new.output_spec_sha256 is null, 'output_spec_sha256');
  perform app_private.check_hash(new.output_spec_sha256, 'output_spec_sha256');
  perform app_private.check_required(new.inputs is null, 'inputs');
  perform app_private.check_json(new.inputs, 65536, 'inputs');
  perform app_private.check_required(new.inputs_sha256 is null, 'inputs_sha256');
  perform app_private.check_hash(new.inputs_sha256, 'inputs_sha256');
  perform app_private.check_required(new.rates_version is null, 'rates_version');
  perform app_private.check_len(new.rates_version, 40, 'rates_version');
  perform app_private.check_json(new.line_items, 16384, 'line_items');
  perform app_private.check_valid(new.planner_choice in ('heuristic', 'model'), 'planner_choice');
  perform app_private.check_valid(new.retention_days in (1, 7, 30), 'retention_days');
  perform app_private.check_valid(new.estimate_low_credits >= 0
                                  and new.estimate_low_credits <= new.estimate_high_credits
                                  and new.estimate_high_credits <= new.cap_credits, 'cap_credits');
  perform app_private.check_valid(new.estimate_high_cost_micro_usd > 0
                                  and new.estimate_high_cost_micro_usd <= new.cap_cost_micro_usd,
                                  'cap_cost_micro_usd');
  perform app_private.check_valid(new.state in ('open', 'accepted', 'expired', 'superseded', 'declined'), 'state');
  perform app_private.check_valid(new.expires_at > coalesce(new.created_at, now()), 'expires_at');
  perform app_private.check_json(new.consent, 4096, 'consent');
  perform app_private.check_valid((new.accepted_at is null) = (new.consent is null)
                                  and (new.state <> 'accepted' or new.accepted_at is not null), 'accepted_at');
  perform app_private.check_valid(new.consent is null
    or app_private.consent_is_valid(new.consent, new.planner_choice, new.retention_days), 'consent');
  return new;
end
$$;

create function app_private.validate_usage_reservations() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.check_required(new.project_id is null or new.owner_id is null or new.quote_id is null
                                     or new.initial_quote_id is null or new.story_plan_id is null, 'reservation');
  perform app_private.check_valid(new.owner_id = (select p.owner_id from public.projects p where p.id = new.project_id),
                                  'owner_id');
  perform app_private.check_required(new.output_spec_sha256 is null, 'output_spec_sha256');
  perform app_private.check_hash(new.output_spec_sha256, 'output_spec_sha256');
  perform app_private.check_valid(new.state in ('held', 'settled', 'released'), 'state');
  -- never an unbounded hold (T-DB-26): a positive cap, and reserved/consumed/released stay inside it
  perform app_private.check_valid(new.cap_credits >= 0, 'cap_credits');
  perform app_private.check_valid(new.cap_cost_micro_usd > 0, 'cap_cost_micro_usd');
  perform app_private.check_valid(new.reserved_cost_micro_usd >= 0
                                  and new.reserved_cost_micro_usd <= new.cap_cost_micro_usd,
                                  'reserved_cost_micro_usd');
  perform app_private.check_valid(new.consumed_cost_micro_usd >= 0 and new.released_cost_micro_usd >= 0
    and new.consumed_cost_micro_usd + new.released_cost_micro_usd <= new.reserved_cost_micro_usd,
    'consumed_cost_micro_usd');
  return new;
end
$$;

create function app_private.validate_render_jobs() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.check_required(new.project_id is null or new.story_plan_id is null or new.quote_id is null
                                     or new.reservation_id is null, 'job');
  -- the requester is the project owner at request time
  if tg_op = 'INSERT' then
    perform app_private.check_valid(new.requested_by is null or new.requested_by
                                      = (select p.owner_id from public.projects p where p.id = new.project_id),
                                    'requested_by');
  end if;
  perform app_private.check_required(new.output_spec_sha256 is null, 'output_spec_sha256');
  perform app_private.check_hash(new.output_spec_sha256, 'output_spec_sha256');
  perform app_private.check_len(new.idempotency_key, 255, 'idempotency_key');
  perform app_private.check_valid(new.stage_progress_milli is null or new.stage_progress_milli between 0 and 1000,
                                  'stage_progress_milli');
  perform app_private.check_required(new.output_spec is null, 'output_spec');
  perform app_private.check_json(new.output_spec, 4096, 'output_spec');
  perform app_private.check_len(new.error_code, 64, 'error_code');
  return new;
end
$$;

-- b10 on render_jobs: `ready` only with a verified, delivered film of this job (architecture §7.1, T-DB-53). This is
-- the table-level half: set_job_state (S80) inherits it, and so does any other path. Terminal states stamp
-- finished_at.
create function app_private.check_job_state() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.state = 'ready' and (tg_op = 'INSERT' or old.state is distinct from 'ready')
     and not exists (select 1 from public.artifacts a
                      where a.job_id = new.id and a.project_id = new.project_id and a.kind = 'film'
                        and a.state = 'ready' and a.verified_at is not null and a.verification is not null
                        and a.deleted_at is null) then
    raise exception using errcode = 'P0409', message = 'artifact_not_verified';
  end if;
  if new.state in ('ready', 'canceled', 'failed_terminal', 'quote_expired', 'deleted') and new.finished_at is null then
    new.finished_at := now();
  end if;
  return new;
end
$$;

create function app_private.validate_render_attempts() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.check_required(new.job_id is null or new.stage is null or new.attempt is null, 'attempt');
  perform app_private.check_valid(new.attempt between 1 and 10, 'attempt');
  perform app_private.check_valid(new.state in ('reserved', 'dispatched', 'running', 'succeeded', 'failed',
                                                'lease_expired', 'canceled', 'dead_lettered'), 'state');
  perform app_private.check_hash(new.lease_token_hash, 'lease_token_hash');
  perform app_private.check_len(new.claimed_by_host, 64, 'claimed_by_host');
  perform app_private.check_valid(new.lease_token_hash is null
                                  or (new.claimed_by_host is not null and new.leased_until is not null), 'lease');
  perform app_private.check_valid(new.host_kind is null or new.host_kind in ('cf-container', 'cloud-run', 'local-test'),
                                  'host_kind');
  perform app_private.check_json(new.input_refs, 65536, 'input_refs');
  perform app_private.check_valid(app_private.refs_are_valid(new.input_refs, 'input'), 'input_refs');
  perform app_private.check_json(new.output_plan, 16384, 'output_plan');
  perform app_private.check_valid(app_private.output_plan_is_valid(new.output_plan), 'output_plan');
  perform app_private.check_json(new.output_refs, 65536, 'output_refs');
  perform app_private.check_valid(app_private.refs_are_valid(new.output_refs, 'output'), 'output_refs');
  perform app_private.check_hash(new.input_hash, 'input_hash');
  perform app_private.check_json(new.measurements, 65536, 'measurements');
  perform app_private.check_valid(new.reserved_cost_micro_usd > 0, 'reserved_cost_micro_usd');
  perform app_private.check_valid(new.actual_cost_micro_usd is null or new.actual_cost_micro_usd >= 0,
                                  'actual_cost_micro_usd');
  perform app_private.check_json(new.planner_budget, 4096, 'planner_budget');
  perform app_private.check_valid(new.planner_budget is null
    or (new.stage = 'plan' and app_private.planner_budget_is_valid(new.planner_budget)), 'planner_budget');
  perform app_private.check_len(new.error_code, 64, 'error_code');
  return new;
end
$$;

-- Migration 2's artifact validation, plus the per-kind byte ceiling (finding 32).
create or replace function app_private.validate_artifacts() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.check_required(new.project_id is null or new.kind is null, 'artifact');
  perform app_private.check_valid(new.bucket_class in ('work', 'films'), 'bucket_class');
  perform app_private.check_required(new.r2_key is null, 'r2_key');
  perform app_private.check_len(new.r2_key, 512, 'r2_key');
  perform app_private.check_valid(new.state in ('writing', 'verifying', 'ready', 'failed', 'deleted'), 'state');
  perform app_private.check_valid(new.bytes is null
    or (new.bytes >= 0 and new.bytes <= app_private.output_byte_ceiling(new.kind::text)), 'bytes');
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

create function app_private.validate_provider_connections() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.check_required(new.user_id is null or new.provider is null, 'provider');
  perform app_private.check_valid(new.state in ('planned', 'awaiting_setup', 'not_connected', 'connected', 'expired',
                                                'revoked'), 'state');
  perform app_private.check_len(new.account_label, 120, 'account_label');
  -- a label, never an email address (no email is copied here)
  perform app_private.check_valid(new.account_label is null or new.account_label !~ '[^[:space:]@]+@[^[:space:]@]+',
                                  'account_label');
  perform app_private.check_required(new.scopes is null, 'scopes');
  -- scope names only (e.g. drive.file): never a URL, endpoint or callback (§13.17)
  perform app_private.check_valid(pg_catalog.cardinality(new.scopes) <= 16
    and pg_catalog.array_position(new.scopes, null) is null
    and not exists (select 1 from pg_catalog.unnest(new.scopes) s where s !~ '^[A-Za-z0-9._:-]{1,64}$'), 'scopes');
  if tg_op = 'INSERT' and exists (select 1 from public.provider_connections c
                                   where c.user_id = new.user_id and c.provider = new.provider) then
    raise exception using errcode = 'P0409', message = 'already_exists';   -- coded, before the unique index
  end if;
  return new;
end
$$;

create function app_private.validate_deletion_requests() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.check_required(new.scope is null or new.target_id is null, 'deletion');
  perform app_private.check_valid(new.state in ('requested', 'canceling_jobs', 'deleting_objects', 'deleting_rows',
                                                'revoking_apple', 'done', 'failed'), 'state');
  -- an account deletion is always the requester's own account
  perform app_private.check_valid(new.scope <> 'account' or new.target_id = new.requested_by
                                  or (tg_op = 'UPDATE' and new.requested_by is null), 'target_id');
  perform app_private.check_required(new.counts is null, 'counts');
  perform app_private.check_json(new.counts, 4096, 'counts');
  perform app_private.check_valid(pg_catalog.jsonb_typeof(new.counts) = 'object'
    and not exists (select 1 from pg_catalog.jsonb_each(new.counts) e
                     where pg_catalog.jsonb_typeof(e.value) <> 'number' or (e.value #>> '{}') !~ '^[0-9]{1,15}$'),
    'counts');
  perform app_private.check_len(new.error_code, 64, 'error_code');
  perform app_private.check_valid(new.finished_at is null or new.state in ('done', 'failed'), 'finished_at');
  return new;
end
$$;

create function app_private.validate_job_outbox() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform app_private.check_valid(new.kind in ('start_workflow', 'dispatch_attempt', 'delete_object'), 'kind');
  perform app_private.check_json(new.payload, 8192, 'payload');
  perform app_private.check_valid(app_private.outbox_payload_is_valid(new.kind, new.payload, new.job_id), 'payload');
  return new;
end
$$;

-- b20 on lesson_clips (migration 2): a moved window also queues the excerpt object's deletion.
create or replace function app_private.pin_shared_clip() returns trigger
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
      perform app_private.retire_excerpt(old.excerpt_artifact_id);
    end if;
  end if;
  return new;
end
$$;

-- 4. Triggers (names sort in the §13.0 order; same-event triggers fire alphabetically) ---------------------------
create trigger a10_validate before insert or update on public.quotes
  for each row execute function app_private.validate_quotes();

create trigger a10_validate before insert or update on public.usage_reservations
  for each row execute function app_private.validate_usage_reservations();
create trigger b50_touch before update on public.usage_reservations
  for each row execute function app_private.touch_updated_at();

create trigger a10_validate before insert or update on public.render_jobs
  for each row execute function app_private.validate_render_jobs();
create trigger b10_check_job_state before insert or update on public.render_jobs
  for each row execute function app_private.check_job_state();
create trigger b50_touch before update on public.render_jobs
  for each row execute function app_private.touch_updated_at();

create trigger a10_validate before insert or update on public.render_attempts
  for each row execute function app_private.validate_render_attempts();

create trigger a00_rls_guard before insert on public.provider_connections
  for each row execute function app_private.rls_guard();
create trigger a10_validate before insert or update on public.provider_connections
  for each row execute function app_private.validate_provider_connections();
create trigger a20_enforce_quota before insert on public.provider_connections
  for each row execute function app_private.enforce_quota();
create trigger b50_bump_revision before update on public.provider_connections
  for each row execute function app_private.bump_revision();

create trigger a10_validate before insert or update on public.deletion_requests
  for each row execute function app_private.validate_deletion_requests();
create trigger b50_touch before update on public.deletion_requests
  for each row execute function app_private.touch_updated_at();

create trigger a10_validate before insert or update on app_ops.job_outbox
  for each row execute function app_private.validate_job_outbox();
create trigger b00_append_only before update or delete on app_ops.spend_commitments
  for each row execute function app_private.refuse_rewrite();
create trigger b00_append_only before update or delete on app_ops.audit_events
  for each row execute function app_private.refuse_rewrite();

-- a05_refuse_secrets on every app_ops table that has a text, JSON or array column (identity_01/money_01 lint it).
do $$
declare
  v_table regclass;
begin
  for v_table in
    select c.oid::regclass from pg_catalog.pg_class c
     where c.relnamespace = 'app_ops'::regnamespace and c.relkind = 'r'
       and exists (select 1 from pg_catalog.pg_attribute a
                    where a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
                      and (a.atttypid in ('text'::regtype, 'jsonb'::regtype, 'json'::regtype, 'text[]'::regtype,
                                          'varchar'::regtype)))
  loop
    execute pg_catalog.format('create trigger a05_refuse_secrets before insert or update on %s '
                              'for each row execute function app_private.refuse_secrets()', v_table);
  end loop;
end
$$;

-- 5. Row level security (security-model §5.1, §5.6, §5.7) ----------------------------------------------------------
alter table public.quotes enable row level security;
alter table public.usage_reservations enable row level security;
alter table public.render_jobs enable row level security;
alter table public.render_attempts enable row level security;
alter table public.artifact_sources enable row level security;
alter table public.provider_connections enable row level security;
alter table public.deletion_requests enable row level security;

-- Anonymous Supabase users (test-only lobby experiments) never touch Studio tables (T-DB-28).
create policy quotes_real_users_only on public.quotes as restrictive for all to authenticated
  using (app_private.is_real_user()) with check (app_private.is_real_user());
create policy usage_reservations_real_users_only on public.usage_reservations as restrictive for all
  to authenticated using (app_private.is_real_user()) with check (app_private.is_real_user());
create policy render_jobs_real_users_only on public.render_jobs as restrictive for all to authenticated
  using (app_private.is_real_user()) with check (app_private.is_real_user());
create policy render_attempts_real_users_only on public.render_attempts as restrictive for all to authenticated
  using (app_private.is_real_user()) with check (app_private.is_real_user());
create policy artifact_sources_real_users_only on public.artifact_sources as restrictive for all to authenticated
  using (app_private.is_real_user()) with check (app_private.is_real_user());
create policy provider_connections_real_users_only on public.provider_connections as restrictive for all
  to authenticated using (app_private.is_real_user()) with check (app_private.is_real_user());
create policy deletion_requests_real_users_only on public.deletion_requests as restrictive for all
  to authenticated using (app_private.is_real_user()) with check (app_private.is_real_user());

-- Money: the owner of the project, as the quote's or hold's owner; coaches never (T-DB-25).
create policy quotes_select on public.quotes for select to authenticated
  using (owner_id = (select auth.uid()) and app_private.has_project_role(project_id, '{owner}'));
create policy usage_reservations_select on public.usage_reservations for select to authenticated
  using (owner_id = (select auth.uid()) and app_private.has_project_role(project_id, '{owner}'));

-- Jobs and attempts: members read (granted columns only); no client writes.
create policy render_jobs_select on public.render_jobs for select to authenticated
  using (app_private.has_project_role(project_id, '{owner,coach}'));
create policy render_attempts_select on public.render_attempts for select to authenticated
  using (app_private.can_read_job(job_id));

-- artifact_sources: no client access at all (the restrictive policy above and no grants).

-- provider_connections: own rows only, one permissive policy per command.
create policy provider_connections_select on public.provider_connections for select to authenticated
  using (user_id = (select auth.uid()));
create policy provider_connections_insert on public.provider_connections for insert to authenticated
  with check (app_private.can_insert_provider_connections(user_id));
create policy provider_connections_update on public.provider_connections for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy provider_connections_delete on public.provider_connections for delete to authenticated
  using (user_id = (select auth.uid()));

create policy deletion_requests_select on public.deletion_requests for select to authenticated
  using (requested_by = (select auth.uid()));

-- access_grants (migration 2): the creator and grantee read, while the grant's project is not being deleted.
drop policy access_grants_select on public.access_grants;
create policy access_grants_select on public.access_grants for select to authenticated
  using ((created_by = (select auth.uid()) or grantee_user_id = (select auth.uid()))
         and app_private.grant_target_live(project_id, lesson_clip_id));

-- 6. Grants -----------------------------------------------------------------------------------------------------------
revoke all on public.quotes, public.usage_reservations, public.render_jobs, public.render_attempts,
  public.artifact_sources, public.provider_connections, public.deletion_requests
  from public, anon, authenticated;

-- not granted: owner_id, output_spec_sha256, estimate_high_cost_micro_usd, cap_cost_micro_usd (internal cost)
grant select (id, project_id, story_plan_id, story_plan_version_id, supersedes_quote_id, inputs, inputs_sha256,
              rates_version, line_items, planner_choice, retention_days, estimate_low_credits, estimate_high_credits,
              cap_credits, state, expires_at, accepted_at, consent, sample, created_at)
  on public.quotes to authenticated;

-- credits only: not owner_id, initial_quote_id, the plan key or any *_micro_usd column
grant select (id, project_id, quote_id, job_id, cap_credits, state, sample, created_at, updated_at)
  on public.usage_reservations to authenticated;

-- not granted: requested_by, idempotency_key, quote_id, reservation_id, output_spec_sha256
grant select (id, project_id, story_plan_id, story_plan_version_id, parent_job_id, state, stage,
              stage_progress_milli, output_spec, error_code, cancel_requested_at, paused_at, review_requested_at,
              reviewed_at, sample, created_at, updated_at, finished_at) on public.render_jobs to authenticated;

-- not granted: lease_token_hash, claimed_by_host, leased_until, input_refs, output_plan, input_hash, output_refs,
-- measurements (planner tokens and CPU/wall time let a reader derive cost; finding 32), the cost columns and
-- planner_budget
grant select (id, job_id, stage, attempt, state, heartbeat_at, host_kind, error_code, retryable, created_at,
              started_at, finished_at) on public.render_attempts to authenticated;

grant select, delete on public.provider_connections to authenticated;
grant insert (provider, state, account_label, scopes) on public.provider_connections to authenticated;
grant update (state, account_label, scopes) on public.provider_connections to authenticated;

-- not granted: requested_by (the requester reads their own requests)
grant select (id, scope, target_id, state, counts, error_code, created_at, updated_at, finished_at)
  on public.deletion_requests to authenticated;

-- 7. Gateway commands: clip share approval and withdrawal now write audit rows; a withdrawal also unlinks the
-- excerpt and queues its object's deletion, so it has the same effect as a moved window (T-DB-62). Denials are
-- audited by the gateway through audit_denial (S79), since a raising command rolls its own rows back.
create or replace function app_gateway.approve_clip_share(p_actor uuid, p_clip uuid, p_request_id uuid)
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
  perform app_private.write_audit('user', p_actor, v_clip.project_id, 'clip_share.approve', 'lesson_clip', p_clip,
                                  'allowed', null, p_request_id);
  return v_at;
end
$$;

create or replace function app_gateway.revoke_clip_share(p_actor uuid, p_clip uuid, p_request_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  v_clip public.lesson_clips;
begin
  select c.* into v_clip from public.lesson_clips c where c.id = p_clip for update;
  if not found or p_actor is null or not exists (
       select 1 from public.projects p
        where p.id = v_clip.project_id and p.owner_id = p_actor and p.deleted_at is null) then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  update public.lesson_clips
     set share_approved_at = null, share_approved_sha256 = null, excerpt_artifact_id = null
   where id = p_clip;
  if v_clip.excerpt_artifact_id is not null then
    perform app_private.retire_excerpt(v_clip.excerpt_artifact_id);
  end if;
  perform app_private.write_audit('user', p_actor, v_clip.project_id, 'clip_share.revoke', 'lesson_clip', p_clip,
                                  'allowed', null, p_request_id);
end
$$;

-- 8. Function privileges ----------------------------------------------------------------------------------------------
revoke all on function
  app_private.output_byte_ceiling(text), app_private.is_uuid_text(jsonb),
  app_private.consent_is_valid(jsonb, text, int), app_private.output_plan_is_valid(jsonb),
  app_private.refs_are_valid(jsonb, text), app_private.planner_budget_is_valid(jsonb),
  app_private.outbox_payload_is_valid(text, jsonb, uuid), app_private.has_secret(text),
  app_private.can_read_job(uuid), app_private.can_insert_provider_connections(uuid),
  app_private.grant_target_live(uuid, uuid),
  app_private.write_audit(text, uuid, uuid, text, text, uuid, text, text, uuid, jsonb),
  app_private.retire_excerpt(uuid), app_private.lesson_deletion_artifacts(uuid),
  app_private.refuse_secrets(), app_private.refuse_rewrite(), app_private.touch_updated_at(),
  app_private.validate_quotes(), app_private.validate_usage_reservations(), app_private.validate_render_jobs(),
  app_private.check_job_state(), app_private.validate_render_attempts(), app_private.validate_provider_connections(),
  app_private.validate_deletion_requests(), app_private.validate_job_outbox()
  from public, anon, authenticated, service_role;

-- Only what policies call.
grant execute on function app_private.can_read_job(uuid), app_private.can_insert_provider_connections(uuid),
  app_private.grant_target_live(uuid, uuid) to authenticated;

-- 9. One owner (T-DB-66). Last, so every grant above was made by the migrating role. ---------------------------------
alter table public.quotes owner to jovra_owner;
alter table public.usage_reservations owner to jovra_owner;
alter table public.render_jobs owner to jovra_owner;
alter table public.render_attempts owner to jovra_owner;
alter table public.artifact_sources owner to jovra_owner;
alter table public.provider_connections owner to jovra_owner;
alter table public.deletion_requests owner to jovra_owner;
alter table app_ops.upload_sessions owner to jovra_owner;
alter table app_ops.upload_parts owner to jovra_owner;
alter table app_ops.job_outbox owner to jovra_owner;
alter table app_ops.idempotency_records owner to jovra_owner;
alter table app_ops.spend_limits owner to jovra_owner;
alter table app_ops.spend_commitments owner to jovra_owner;
alter table app_ops.audit_events owner to jovra_owner;

alter function app_private.output_byte_ceiling(text) owner to jovra_owner;
alter function app_private.is_uuid_text(jsonb) owner to jovra_owner;
alter function app_private.consent_is_valid(jsonb, text, int) owner to jovra_owner;
alter function app_private.output_plan_is_valid(jsonb) owner to jovra_owner;
alter function app_private.refs_are_valid(jsonb, text) owner to jovra_owner;
alter function app_private.planner_budget_is_valid(jsonb) owner to jovra_owner;
alter function app_private.outbox_payload_is_valid(text, jsonb, uuid) owner to jovra_owner;
alter function app_private.has_secret(text) owner to jovra_owner;
alter function app_private.can_read_job(uuid) owner to jovra_owner;
alter function app_private.can_insert_provider_connections(uuid) owner to jovra_owner;
alter function app_private.grant_target_live(uuid, uuid) owner to jovra_owner;
alter function app_private.write_audit(text, uuid, uuid, text, text, uuid, text, text, uuid, jsonb)
  owner to jovra_owner;
alter function app_private.retire_excerpt(uuid) owner to jovra_owner;
alter function app_private.lesson_deletion_artifacts(uuid) owner to jovra_owner;
alter function app_private.refuse_secrets() owner to jovra_owner;
alter function app_private.refuse_rewrite() owner to jovra_owner;
alter function app_private.touch_updated_at() owner to jovra_owner;
alter function app_private.validate_quotes() owner to jovra_owner;
alter function app_private.validate_usage_reservations() owner to jovra_owner;
alter function app_private.validate_render_jobs() owner to jovra_owner;
alter function app_private.check_job_state() owner to jovra_owner;
alter function app_private.validate_render_attempts() owner to jovra_owner;
alter function app_private.validate_provider_connections() owner to jovra_owner;
alter function app_private.validate_deletion_requests() owner to jovra_owner;
alter function app_private.validate_job_outbox() owner to jovra_owner;
