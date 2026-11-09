-- S80 / B-06 (orchestrator half): the commands only jovra_orchestrator may execute (docs/backend/architecture.md
-- §4.3, §7.1-§7.6, §10; security-model.md §4.1, §8.4, §13.1, §13.6, §13.7, §13.9 (b); finding 13's database half):
--   * set_job_state: compare-and-set against the SQL copy of spec/studio/contracts/render-job-transitions.v1.json,
--     `ready` only with a verified delivered film (b10_check_job_state, T-DB-53), a stored resume_state that only
--     returns to a stage the contract allows, and the hold settled or released on every terminal state;
--   * reserve_stage: the estimate computed in SQL from the quote's rate card (app_ops.rate_cards / stage_rates) and the
--     quote's inputs, with a per-stage floor that is never zero (T-DB-55); the cap and the environment ceiling
--     (P0402, T-DB-36); input_refs limited to the job project's verified sources and this job's verified artifacts;
--     the output plan with a byte cap per output; planner_budget for the plan stage derived from what the stage
--     reservation covers (T-DB-72 SQL half); idempotent on (job, stage, attempt) and a replay for a charged stage;
--   * claim_attempt mints the jvl_ lease token and stores only its SHA-256; heartbeat_attempt and finish_attempt are
--     fenced by that hash and by leased_until (T-DB-37); expire_attempt_leases is the reconciler's sweep;
--   * finish_attempt: consumption once per (job, stage) (one succeeded attempt per stage, unique index), an actual cost
--     above the stage reservation committed as stage_overrun and the job stopped at budget_exceeded (T-DB-72), the
--     outputs registered as `verifying` artifacts only when they are in the attempt's output plan and within their
--     caps, and the plan stage of plan-by-job work moving the job and its hold to (plan, V, hash of V) in the same
--     transaction (T-DB-68);
--   * mark_artifact_verified: only the verify_output stage, under its lease;
--   * delete_lesson_rows: the lesson-scope deletion step on the server path keeps Progress plans consistent (T-DB-73);
--   * audit_denial_for_attempt: the orchestrator-only twin of audit_denial for refused host-route calls.
-- It also closes two gaps the ledger vectors (spec/studio/fixtures/vectors/ledger.json) exposed in the S79 money
-- commands: a redelivered original acceptance replays after a top-up superseded its quote, and no spend commitment is
-- made in the live environment until live charging has its own ADR (ADR-0013).
-- Every command is volatile, security definer, search_path '', owned by jovra_owner and executable by
-- jovra_orchestrator only, never by jovra_gateway or a client role (T-DB-04, T-DB-53, T-DB-57).

-- 1. Columns, rate cards and the audit actor kinds ------------------------------------------------------------------

-- The stage a paused, retryable or budget-stopped job returns to (contract `resumeTo`); null in every other state.
alter table public.render_jobs add column resume_state public.job_state;
-- What the stage charged the hold: min(actual, stage reservation). Written once, by the stage's one success.
alter table public.render_attempts add column charged_cost_micro_usd bigint
  check (charged_cost_micro_usd is null or charged_cost_micro_usd >= 0);
-- Consumption once per (job, stage): at most one succeeded attempt of a stage (architecture §7.4).
create unique index render_attempts_one_success on public.render_attempts (job_id, stage) where state = 'succeeded';

-- Orchestrator rows name their own actor kinds: 'orchestrator' (Workflow, reconciler and deletion steps) and
-- 'render_attempt' (host-route refusals recorded by audit_denial_for_attempt, security-model §4.1).
alter table app_ops.audit_events drop constraint audit_events_actor_kind_check;
alter table app_ops.audit_events add constraint audit_events_actor_kind_check
  check (actor_kind in ('user', 'camera_guest', 'render_host', 'gateway', 'cron', 'operator', 'orchestrator',
                        'render_attempt'));

-- Rate cards: operator data, versioned by quotes.rates_version (refreshed at activation). Container time and model
-- tokens price an attempt's measurements; the planner caps bound one model call (architecture §7.6).
create table app_ops.rate_cards (
  rates_version             text primary key check (rates_version ~ '^[a-z0-9][a-z0-9-]{0,39}$'),
  wall_second_micro_usd     bigint not null check (wall_second_micro_usd >= 0),
  input_mtok_micro_usd      bigint not null check (input_mtok_micro_usd >= 0),
  cache_mtok_micro_usd      bigint not null check (cache_mtok_micro_usd >= 0),
  output_mtok_micro_usd     bigint not null check (output_mtok_micro_usd >= 0),
  image_tokens              int not null check (image_tokens between 0 and 100000),
  planner_max_images        int not null check (planner_max_images between 0 and 64),
  planner_max_input_tokens  int not null check (planner_max_input_tokens between 0 and 1000000),
  planner_max_output_tokens int not null check (planner_max_output_tokens between 0 and 200000),
  planner_effort            text not null check (planner_effort ~ '^[a-z]{1,16}$'),
  created_at                timestamptz not null default now()
);
-- One row per (rate card, stage). The floor is positive, so a zero stage estimate is impossible (T-DB-55).
create table app_ops.stage_rates (
  rates_version                     text not null references app_ops.rate_cards (rates_version) on delete cascade,
  stage                             public.job_stage not null,
  floor_micro_usd                   bigint not null check (floor_micro_usd > 0),
  per_verified_mib_micro_usd        bigint not null default 0 check (per_verified_mib_micro_usd >= 0),
  per_output_angle_second_micro_usd bigint not null default 0 check (per_output_angle_second_micro_usd >= 0),
  primary key (rates_version, stage)
);
alter table app_ops.rate_cards enable row level security;
alter table app_ops.stage_rates enable row level security;
revoke all on app_ops.rate_cards, app_ops.stage_rates from public, anon, authenticated, service_role;
create trigger a05_refuse_secrets before insert or update on app_ops.rate_cards
  for each row execute function app_private.refuse_secrets();
create trigger a05_refuse_secrets before insert or update on app_ops.stage_rates
  for each row execute function app_private.refuse_secrets();

-- rates-v0-inferred (INFERRED starting values, as the quote rate card of migration 20261008041000): container time
-- 60 micro-USD per second, model tokens 3 / 0.30 / 15 USD per million (input / cache / output), 1,500 tokens per
-- image, a model planner call of at most 8 images, 8,000 input tokens and 2,000 output tokens. Stage rates mirror the
-- quote's components (ingest 20 per verified MiB, final render 1,500 per output second per angle, a preview at a
-- fifth of that), so the stages of a quoted job fit inside its cap.
insert into app_ops.rate_cards (rates_version, wall_second_micro_usd, input_mtok_micro_usd, cache_mtok_micro_usd,
                                output_mtok_micro_usd, image_tokens, planner_max_images, planner_max_input_tokens,
                                planner_max_output_tokens, planner_effort)
values ('rates-v0-inferred', 60, 3000000, 300000, 15000000, 1500, 8, 8000, 2000, 'medium');
insert into app_ops.stage_rates (rates_version, stage, floor_micro_usd, per_verified_mib_micro_usd,
                                 per_output_angle_second_micro_usd) values
  ('rates-v0-inferred', 'verify_sources', 1000, 0, 0),
  ('rates-v0-inferred', 'normalize', 5000, 20, 0),
  ('rates-v0-inferred', 'sync', 2000, 0, 0),
  ('rates-v0-inferred', 'analyze', 2000, 0, 0),
  ('rates-v0-inferred', 'plan', 1000, 0, 0),
  ('rates-v0-inferred', 'validate', 1000, 0, 0),
  ('rates-v0-inferred', 'preview_render', 5000, 0, 300),
  ('rates-v0-inferred', 'final_render', 10000, 0, 1500),
  ('rates-v0-inferred', 'remux_no_audio', 2000, 0, 0),
  ('rates-v0-inferred', 'verify_output', 2000, 0, 0),
  ('rates-v0-inferred', 'deliver', 1000, 0, 0),
  ('rates-v0-inferred', 'cleanup', 1000, 0, 0);

-- 2. Helpers -----------------------------------------------------------------------------------------------------------

-- The contract's state machine (render-job-transitions.v1.json) for job states: `forward`, pausableFrom (to paused,
-- back to the stored resume state), retryableFrom (to failed_retryable, back to the stored resume state),
-- terminalFailureFrom, budgetExceededFrom, cancelFrom (every non-terminal state) and deleteFrom (every state but
-- deleted). draft, quoted and quote_expired are quote states (architecture §4.2), and the resume from budget_exceeded
-- goes through a new quote (accept_quote's top-up), so neither is an orchestrator transition. The ledger replay
-- script checks this function against the contract file for every pair of states.
create function app_private.job_transition_allowed(p_from public.job_state, p_to public.job_state,
                                                   p_resume public.job_state)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(p_from is not null and p_to is not null and p_from <> p_to and (
       (p_from::text || '>' || p_to::text) = any (array[
         'consented>upload_pending', 'upload_pending>uploading', 'upload_pending>queued', 'uploading>queued',
         'queued>normalizing', 'normalizing>syncing', 'normalizing>analyzing', 'normalizing>planning',
         'syncing>analyzing', 'syncing>planning', 'analyzing>planning', 'planning>preview_rendering',
         'preview_rendering>awaiting_review', 'preview_rendering>final_rendering', 'awaiting_review>final_rendering',
         'final_rendering>verifying', 'verifying>ready', 'failed_retryable>failed_terminal'])
    or (p_to = 'paused' and p_from::text = any (array[
         'upload_pending', 'uploading', 'queued', 'normalizing', 'syncing', 'analyzing', 'planning', 'preview_rendering',
         'awaiting_review', 'final_rendering', 'verifying']))
    or (p_from = 'paused' and p_to = p_resume)
    or (p_to = 'failed_retryable' and p_from::text = any (array[
         'uploading', 'queued', 'normalizing', 'syncing', 'analyzing', 'planning', 'preview_rendering',
         'final_rendering', 'verifying']))
    or (p_from = 'failed_retryable' and p_to = p_resume)
    or (p_to = 'failed_terminal' and p_from::text = any (array[
         'uploading', 'queued', 'normalizing', 'syncing', 'analyzing', 'planning', 'preview_rendering',
         'final_rendering', 'verifying', 'failed_retryable']))
    or (p_to = 'budget_exceeded' and p_from::text = any (array[
         'normalizing', 'syncing', 'analyzing', 'planning', 'preview_rendering', 'final_rendering', 'verifying']))
    or (p_to = 'canceled' and p_from::text <> all (array['ready', 'canceled', 'failed_terminal', 'deleted']))
    or p_to = 'deleted'), false)
$$;

-- The job states in which a stage may be reserved and claimed (the Workflow moves the job first).
create function app_private.stage_job_states(p_stage public.job_stage) returns public.job_state[]
language sql immutable set search_path = '' as $$
  select (case p_stage
    when 'verify_sources' then array['queued']
    when 'normalize' then array['normalizing']
    when 'sync' then array['syncing']
    when 'analyze' then array['analyzing']
    when 'plan' then array['planning']
    when 'validate' then array['planning']
    when 'preview_render' then array['preview_rendering']
    when 'final_render' then array['final_rendering']
    when 'remux_no_audio' then array['final_rendering', 'verifying']
    when 'verify_output' then array['verifying']
    when 'deliver' then array['verifying']
    when 'cleanup' then array['consented', 'upload_pending', 'uploading', 'queued', 'normalizing', 'syncing',
                              'analyzing', 'planning', 'preview_rendering', 'awaiting_review', 'final_rendering',
                              'verifying', 'paused', 'failed_retryable', 'budget_exceeded']
  end)::public.job_state[]
$$;

-- The outputs a stage may write, each with the byte cap of its kind (security-model §13.15). Normalization writes an
-- analysis proxy, a render proxy and a PTS table per angle.
create function app_private.stage_output_plan(p_stage public.job_stage, p_angles int) returns jsonb
language sql immutable set search_path = '' as $$
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
           'outputRef', o.ref, 'kind', o.kind, 'maxBytes', app_private.output_byte_ceiling(o.kind)) order by o.ord),
         '[]'::jsonb)
    from (select n * 10 + v.k as ord, v.r || '-' || n as ref, v.kind
            from pg_catalog.generate_series(1, pg_catalog.greatest(1, pg_catalog.least(coalesce(p_angles, 1), 6))) n
           cross join (values (1, 'analysis-proxy', 'analysis_proxy'), (2, 'render-proxy', 'render_proxy'),
                              (3, 'pts-table', 'pts_table')) v(k, r, kind)
           where p_stage = 'normalize'
          union all
          select v.ord, v.ref, v.kind
            from (values ('verify_sources', 1, 'source-report', 'edit_manifest'),
                         ('sync', 1, 'sync-frames', 'frame_set'),
                         ('analyze', 1, 'contact-sheet', 'contact_sheet'),
                         ('plan', 1, 'edit-manifest', 'edit_manifest'),
                         ('validate', 1, 'validation-report', 'edit_manifest'),
                         ('preview_render', 1, 'preview', 'preview'),
                         ('preview_render', 2, 'preview-thumbnail', 'thumbnail'),
                         ('final_render', 1, 'film', 'film'),
                         ('final_render', 2, 'thumbnail', 'thumbnail'),
                         ('final_render', 3, 'captions', 'captions'),
                         ('final_render', 4, 'chapters', 'chapters'),
                         ('remux_no_audio', 1, 'film-no-audio', 'film'),
                         ('verify_output', 1, 'verify-report', 'edit_manifest'),
                         ('deliver', 1, 'delivery-manifest', 'edit_manifest'),
                         ('cleanup', 1, 'cleanup-report', 'edit_manifest')) v(stage, ord, ref, kind)
           where v.stage = p_stage::text) o
$$;

-- Server-generated keys from UUIDs only (security-model §7): delivered media in the films bucket under the
-- artifact id, everything else under the job and attempt in the work bucket.
create function app_private.output_bucket(p_kind text) returns text
language sql immutable set search_path = '' as $$
  select case when p_kind in ('film', 'thumbnail', 'captions', 'chapters') then 'films' else 'work' end
$$;

create function app_private.output_r2_key(p_kind text, p_project uuid, p_job uuid, p_attempt uuid, p_ref text,
                                          p_artifact uuid)
returns text language sql immutable set search_path = '' as $$
  select case
    when p_kind in ('film', 'thumbnail', 'captions', 'chapters') then 'films/p/' || p_project || '/a/' || p_artifact
    when p_kind = 'preview' then 'previews/p/' || p_project || '/j/' || p_job || '/' || p_attempt || '/' || p_ref
    when p_kind in ('analysis_proxy', 'render_proxy', 'pts_table') then
      'proxies/p/' || p_project || '/j/' || p_job || '/' || p_attempt || '/' || p_ref
    else 'frames/p/' || p_project || '/j/' || p_job || '/' || p_attempt || '/' || p_ref
  end
$$;

-- The host's measurements (backend/contracts common.schema.json `measurements`): wallMs, cpuMs, bytesIn, bytesOut and
-- optional plannerTokens {input, cache, output}, integers only. Bounded so pricing cannot overflow.
create function app_private.measurements_are_valid(p_m jsonb) returns boolean
language plpgsql immutable set search_path = '' as $$
declare
  v_key text;
begin
  if pg_catalog.jsonb_typeof(p_m) is distinct from 'object' then
    return false;
  end if;
  if exists (select 1 from pg_catalog.jsonb_object_keys(p_m) k
              where k not in ('wallMs', 'cpuMs', 'bytesIn', 'bytesOut', 'plannerTokens')) then
    return false;
  end if;
  foreach v_key in array array['wallMs', 'cpuMs', 'bytesIn', 'bytesOut'] loop
    if pg_catalog.jsonb_typeof(p_m -> v_key) is distinct from 'number'
       or coalesce((p_m ->> v_key) !~ '^(0|[1-9][0-9]{0,11})$', true) then
      return false;
    end if;
  end loop;
  if p_m ? 'plannerTokens' then
    if pg_catalog.jsonb_typeof(p_m -> 'plannerTokens') is distinct from 'object' then
      return false;
    end if;
    if (select pg_catalog.array_agg(k order by k collate "C") from pg_catalog.jsonb_object_keys(p_m -> 'plannerTokens') k)
       is distinct from array['cache', 'input', 'output'] then
      return false;
    end if;
    foreach v_key in array array['input', 'cache', 'output'] loop
      if pg_catalog.jsonb_typeof(p_m -> 'plannerTokens' -> v_key) is distinct from 'number'
         or coalesce((p_m -> 'plannerTokens' ->> v_key) !~ '^(0|[1-9][0-9]{0,8})$', true) then
        return false;
      end if;
    end loop;
  end if;
  return true;
end
$$;

-- An attempt's actual cost from its measurements and the rate card, rounded up to whole micro-USD.
create function app_private.attempt_actual_cost(p_card app_ops.rate_cards, p_m jsonb) returns bigint
language sql immutable set search_path = '' as $$
  select ((p_m ->> 'wallMs')::bigint * p_card.wall_second_micro_usd + 999) / 1000
       + (coalesce((p_m -> 'plannerTokens' ->> 'input')::bigint, 0) * p_card.input_mtok_micro_usd
          + coalesce((p_m -> 'plannerTokens' ->> 'cache')::bigint, 0) * p_card.cache_mtok_micro_usd
          + coalesce((p_m -> 'plannerTokens' ->> 'output')::bigint, 0) * p_card.output_mtok_micro_usd
          + 999999) / 1000000
$$;

-- The worst case of one model planner call under the card's caps: every image and every input token, plus
-- max_tokens of output (architecture §7.6). The repair call costs the same again.
create function app_private.planner_call_cost(p_card app_ops.rate_cards) returns bigint
language sql immutable set search_path = '' as $$
  select ((p_card.planner_max_images::bigint * p_card.image_tokens + p_card.planner_max_input_tokens)
          * p_card.input_mtok_micro_usd
          + p_card.planner_max_output_tokens::bigint * p_card.output_mtok_micro_usd + 999999) / 1000000
$$;

-- Outputs reported by finish_attempt: [{outputRef, bytes, sha256}], each named once, each in the attempt's stored
-- output plan and within that output's byte cap (finding 32).
create function app_private.attempt_outputs_are_valid(p_outputs jsonb, p_plan jsonb) returns boolean
language plpgsql immutable set search_path = '' as $$
declare
  e     jsonb;
  v_cap jsonb;
begin
  if pg_catalog.jsonb_typeof(p_outputs) is distinct from 'array' or pg_catalog.jsonb_array_length(p_outputs) > 32 then
    return false;
  end if;
  for e in select x from pg_catalog.jsonb_array_elements(p_outputs) x loop
    if pg_catalog.jsonb_typeof(e) is distinct from 'object' then
      return false;
    end if;
    if (select pg_catalog.array_agg(k order by k collate "C") from pg_catalog.jsonb_object_keys(e) k)
       is distinct from array['bytes', 'outputRef', 'sha256'] then
      return false;
    end if;
    if pg_catalog.jsonb_typeof(e -> 'outputRef') is distinct from 'string'
       or pg_catalog.jsonb_typeof(e -> 'bytes') is distinct from 'number'
       or coalesce((e ->> 'bytes') !~ '^[1-9][0-9]{0,18}$', true)
       or pg_catalog.jsonb_typeof(e -> 'sha256') is distinct from 'string'
       or coalesce((e ->> 'sha256') !~ '^[0-9a-f]{64}$', true) then
      return false;
    end if;
    v_cap := null;
    select p into v_cap from pg_catalog.jsonb_array_elements(p_plan) p where p ->> 'outputRef' = e ->> 'outputRef';
    if v_cap is null or (e ->> 'bytes')::numeric > (v_cap ->> 'maxBytes')::numeric then
      return false;
    end if;
  end loop;
  return (select pg_catalog.count(distinct x ->> 'outputRef') from pg_catalog.jsonb_array_elements(p_outputs) x)
         = pg_catalog.jsonb_array_length(p_outputs);
end
$$;

-- The attempt, locked, when the presented lease hash is its current one: P0404 for an unknown attempt, P0409
-- stale_lease otherwise (fencing, architecture §7.3). State and expiry are the caller's checks.
create function app_private.lock_attempt(p_attempt uuid, p_lease_hash bytea) returns public.render_attempts
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_try public.render_attempts;
begin
  select a.* into v_try from public.render_attempts a where a.id = p_attempt for update;
  if not found then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  if p_lease_hash is null or v_try.lease_token_hash is null or v_try.lease_token_hash <> p_lease_hash then
    raise exception using errcode = 'P0409', message = 'stale_lease';
  end if;
  return v_try;
end
$$;

-- The rate card the hold's current quote names (a top-up moves the quote, never the work).
create function app_private.hold_rate_card(p_hold public.usage_reservations) returns app_ops.rate_cards
language plpgsql stable security definer set search_path = '' as $$
declare
  v_card app_ops.rate_cards;
begin
  select c.* into v_card from app_ops.rate_cards c
    join public.quotes q on q.rates_version = c.rates_version
   where q.id = p_hold.quote_id and q.project_id = p_hold.project_id;
  if not found then
    raise exception using errcode = 'P0409', message = 'rate_card_missing';
  end if;
  return v_card;
end
$$;

-- b10 on render_jobs (migration 3), plus resume_state: kept only in paused, failed_retryable and budget_exceeded and
-- only naming a state the job can have entered them from (pausableFrom, retryableFrom, budgetExceededFrom); cleared
-- in every other state.
create or replace function app_private.check_job_state() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.state = 'ready' and (tg_op = 'INSERT' or old.state is distinct from 'ready')
     and not exists (select 1 from public.artifacts a
                      where a.job_id = new.id and a.project_id = new.project_id and a.kind = 'film'
                        and a.state = 'ready' and a.verified_at is not null and a.verification is not null
                        and a.deleted_at is null) then
    raise exception using errcode = 'P0409', message = 'artifact_not_verified';
  end if;
  if new.state not in ('paused', 'failed_retryable', 'budget_exceeded') then
    new.resume_state := null;
  elsif new.resume_state is not null
        and not app_private.job_transition_allowed(new.resume_state, new.state, null) then   -- could it have come from there
    raise exception using errcode = 'P0422', message = 'invalid_value:resume_state';
  end if;
  if new.state in ('ready', 'canceled', 'failed_terminal', 'quote_expired', 'deleted') and new.finished_at is null then
    new.finished_at := now();
  end if;
  return new;
end
$$;

-- The spend ledger (migration 20261008041000), with one more fail-closed rule: no commitment in the live environment
-- until live charging has its own ADR (ADR-0013; the ledger vector live-not-activated).
create or replace function app_private.commit_spend(p_owner uuid, p_reservation uuid, p_kind text, p_amount bigint)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  v_day_start timestamptz := pg_catalog.date_trunc('day', now(), 'UTC');
  v_owner     app_ops.spend_limits;
  v_env       app_ops.spend_limits;
  v_open      bigint;
  v_today     bigint;
begin
  if p_kind is null or p_kind not in ('cap_open', 'cap_topup', 'stage_reserve', 'stage_overrun')
     or p_amount is null or p_amount <= 0 or p_owner is null or p_reservation is null then
    raise exception using errcode = 'P0422', message = 'invalid_value:spend';
  end if;
  if app_private.jovra_env() = 'live' then
    raise exception using errcode = 'P0409', message = 'live_charging_not_activated';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('jovra:spend'));
  select l.* into v_owner from app_ops.spend_limits l
   where l.scope = 'owner' and (l.owner_id = p_owner or l.owner_id is null)
   order by l.owner_id nulls last limit 1;                         -- the owner's own row first, else the default row
  select l.* into v_env from app_ops.spend_limits l where l.scope = 'environment';
  select coalesce(pg_catalog.sum(c.amount_micro_usd), 0) into v_today from app_ops.spend_commitments c
   where c.at >= v_day_start
     and (case when p_kind in ('stage_reserve', 'stage_overrun') then c.kind in ('stage_reserve', 'stage_overrun')
               else c.kind in ('cap_open', 'cap_topup') end);
  if p_kind not in ('stage_reserve', 'stage_overrun') then
    select coalesce(pg_catalog.sum(r.cap_cost_micro_usd), 0) into v_open from public.usage_reservations r
     where r.owner_id = p_owner and r.state = 'held';                -- a top-up's own cap is already in here
    if v_open + p_amount > coalesce(v_owner.max_open_cap_micro_usd, -1) then
      raise exception using errcode = 'P0402', message = 'budget_exceeded';
    end if;
  end if;
  -- An overrun is already spent: it is recorded (so the next reservation sees it) and the caller stops the job.
  if p_kind <> 'stage_overrun' and v_today + p_amount > coalesce(v_env.daily_ceiling_micro_usd, -1) then
    raise exception using errcode = 'P0402', message = 'budget_exceeded';
  end if;
  insert into app_ops.spend_commitments (owner_id, reservation_id, kind, amount_micro_usd)
  values (p_owner, p_reservation, p_kind, p_amount);
end
$$;

-- 3. set_job_state (architecture §7.2 step 4) ------------------------------------------------------------------------
-- Compare-and-set: the job must be in p_expected; a redelivered step whose target the job already reached replays.
-- Entering paused, failed_retryable or budget_exceeded stores the state left as resume_state; leaving paused or
-- failed_retryable is allowed only back to it. A terminal state cancels the open attempts and closes the hold: settled
-- on ready, released otherwise; every unconsumed micro-USD of the stage reservations is released.
create function app_gateway.set_job_state(p_job uuid, p_expected public.job_state, p_new public.job_state,
                                          p_error_code text, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_job public.render_jobs;
begin
  if p_expected is null or p_new is null then
    raise exception using errcode = 'P0422', message = 'invalid_value:state';
  end if;
  if p_error_code is not null and p_error_code !~ '^[a-z][a-z0-9_]{0,63}$' then
    raise exception using errcode = 'P0422', message = 'invalid_value:error_code';
  end if;
  select j.* into v_job from public.render_jobs j where j.id = p_job for update;
  if not found then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  if v_job.state = p_new and p_expected <> p_new then
    return pg_catalog.jsonb_build_object('state', v_job.state, 'replayed', true);
  end if;
  if v_job.state <> p_expected then
    raise exception using errcode = 'P0409', message = 'state_conflict';
  end if;
  if not app_private.job_transition_allowed(v_job.state, p_new, v_job.resume_state) then
    raise exception using errcode = 'P0409', message = 'transition_not_allowed';
  end if;
  update public.render_jobs
     set state = p_new,
         resume_state = case when p_new in ('paused', 'failed_retryable', 'budget_exceeded') then v_job.state end,
         paused_at = case when p_new = 'paused' then now() when v_job.state = 'paused' then null else paused_at end,
         error_code = case when p_new in ('failed_retryable', 'failed_terminal', 'budget_exceeded') then p_error_code end
   where id = v_job.id;   -- b10_check_job_state refuses ready without a verified film (P0409 artifact_not_verified)
  if p_new in ('ready', 'canceled', 'failed_terminal', 'deleted') then
    update public.render_attempts set state = 'canceled', finished_at = now()
     where job_id = v_job.id and state in ('reserved', 'dispatched', 'running');
    update public.usage_reservations
       set state = case when p_new = 'ready' then 'settled' else 'released' end,
           released_cost_micro_usd = reserved_cost_micro_usd - consumed_cost_micro_usd
     where id = v_job.reservation_id and project_id = v_job.project_id and state = 'held';
  end if;
  perform app_private.write_audit('orchestrator', null, v_job.project_id, 'job.set_state', 'render_job', v_job.id,
                                  'allowed', null, p_request_id,
                                  pg_catalog.jsonb_build_object('from', v_job.state, 'to', p_new));
  return pg_catalog.jsonb_build_object('state', p_new, 'replayed', false);
end
$$;

-- 4. reserve_stage (architecture §7.3 step 1, §7.4, §7.6; security-model §13.7) --------------------------------------
-- The hold's reserved total is what is committed against it now: consumed stages plus open stage reservations. A
-- stage ends by turning its reservation into its charge (finish_attempt) or returning it (failure, lease expiry).
create function app_gateway.reserve_stage(p_job uuid, p_stage public.job_stage, p_attempt int, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_job     public.render_jobs;
  v_hold    public.usage_reservations;
  v_quote   public.quotes;
  v_try     public.render_attempts;
  v_card    app_ops.rate_cards;
  v_rate    app_ops.stage_rates;
  v_sources uuid[];
  v_count   int;
  v_refs    jsonb;
  v_mib     bigint;
  v_est     bigint;
  v_call    bigint;
  v_free    bigint;
  v_budget  jsonb;
  v_id      uuid := gen_random_uuid();
begin
  if p_stage is null or p_attempt is null or p_attempt not between 1 and 10 then
    raise exception using errcode = 'P0422', message = 'invalid_value:attempt';
  end if;
  select j.* into v_job from public.render_jobs j where j.id = p_job for update;
  if not found then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  -- idempotent on (job, stage, attempt): a redelivered reservation returns the same attempt and reserves nothing
  select a.* into v_try from public.render_attempts a
   where a.job_id = v_job.id and a.stage = p_stage and a.attempt = p_attempt;
  if found then
    return pg_catalog.jsonb_build_object('attemptId', v_try.id, 'state', v_try.state, 'replayed', true,
                                         'alreadyCharged', v_try.state = 'succeeded');
  end if;
  select r.* into v_hold from public.usage_reservations r
   where r.id = v_job.reservation_id and r.project_id = v_job.project_id
   for update;
  if not found or v_hold.state <> 'held' then
    raise exception using errcode = 'P0409', message = 'reservation_closed';
  end if;
  -- consumption once per (job, stage): a later attempt of a charged stage is a replay of the charged one
  select a.* into v_try from public.render_attempts a
   where a.job_id = v_job.id and a.stage = p_stage and a.state = 'succeeded';
  if found then
    return pg_catalog.jsonb_build_object('attemptId', v_try.id, 'state', v_try.state, 'replayed', true,
                                         'alreadyCharged', true);
  end if;
  if v_job.cancel_requested_at is not null or not (v_job.state = any (app_private.stage_job_states(p_stage))) then
    raise exception using errcode = 'P0409', message = 'job_state_mismatch';
  end if;
  if exists (select 1 from public.projects p where p.id = v_job.project_id and p.deleted_at is not null) then
    raise exception using errcode = 'P0410', message = 'gone';
  end if;
  select q.* into v_quote from public.quotes q where q.id = v_hold.quote_id and q.project_id = v_job.project_id;
  v_card := app_private.hold_rate_card(v_hold);
  select s.* into v_rate from app_ops.stage_rates s where s.rates_version = v_card.rates_version and s.stage = p_stage;
  if not found then
    raise exception using errcode = 'P0409', message = 'rate_card_missing';
  end if;

  -- Inputs: every source the quote named, still verified and listed in the project's current source manifest (a
  -- changed source set never runs under the old consent), and this job's verified, delivered-or-intermediate artifacts.
  v_sources := array(select pg_catalog.jsonb_array_elements_text(v_quote.inputs -> 'sourceIds')::uuid);
  select pg_catalog.count(*) into v_count from public.camera_sources s
    join public.projects p on p.id = s.project_id
    join public.source_manifests m on m.project_id = s.project_id and m.revision = p.current_source_manifest_revision
   where s.project_id = v_job.project_id and s.id = any (v_sources) and s.state = 'verified'
     and m.manifest -> 'sources' @> pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('sourceId', s.id::text));
  if pg_catalog.cardinality(v_sources) = 0 or v_count <> pg_catalog.cardinality(v_sources) then
    raise exception using errcode = 'P0409', message = 'inputs_changed';
  end if;
  select coalesce(pg_catalog.jsonb_agg(x.ref order by x.ord, x.id), '[]'::jsonb) into v_refs
    from (select 1 as ord, s.id,
                 pg_catalog.jsonb_build_object('kind', 'source', 'id', s.id, 'bytes', s.declared_bytes,
                   'sha256', pg_catalog.encode(coalesce(s.verified_sha256, s.declared_sha256), 'hex')) as ref
            from public.camera_sources s
           where s.project_id = v_job.project_id and s.id = any (v_sources)
          union all
          select 2, a.id,
                 pg_catalog.jsonb_build_object('kind', 'artifact', 'id', a.id, 'bytes', a.bytes,
                   'sha256', pg_catalog.encode(a.sha256, 'hex'))
            from public.artifacts a
           where a.project_id = v_job.project_id and a.job_id = v_job.id and a.state = 'ready'
             and a.verified_at is not null and a.deleted_at is null) x;

  -- The estimate, in SQL from the rate card and the quote's inputs, never below the stage's positive floor (T-DB-55).
  v_mib := ((v_quote.inputs ->> 'verifiedBytes')::bigint + 1048575) / 1048576;
  v_est := pg_catalog.greatest(v_rate.floor_micro_usd,
             v_rate.per_verified_mib_micro_usd * v_mib
             + v_rate.per_output_angle_second_micro_usd
               * (v_quote.inputs -> 'outputSpec' ->> 'durationTargetSec')::bigint
               * (v_quote.inputs ->> 'angleCount')::bigint);
  -- The planner's budget is derived from what this stage reservation covers (T-DB-72 SQL half): the first model call
  -- and its one repair, else the first call only (no repair), else no model call at all (the heuristic planner).
  if p_stage = 'plan' then
    v_budget := '{"effort": "none", "maxImages": 0, "maxInputTokens": 0, "maxOutputTokens": 0,
                  "repairAllowed": false}'::jsonb;
    if v_quote.planner_choice = 'model' then
      v_call := app_private.planner_call_cost(v_card);
      v_free := v_hold.cap_cost_micro_usd - v_hold.reserved_cost_micro_usd;
      if v_call > 0 and pg_catalog.greatest(v_est, 2 * v_call) <= v_free then
        v_est := pg_catalog.greatest(v_est, 2 * v_call);
        v_budget := pg_catalog.jsonb_build_object('maxImages', v_card.planner_max_images,
          'maxInputTokens', v_card.planner_max_input_tokens, 'maxOutputTokens', v_card.planner_max_output_tokens,
          'effort', v_card.planner_effort, 'repairAllowed', true);
      elsif v_call > 0 and pg_catalog.greatest(v_est, v_call) <= v_free then
        v_est := pg_catalog.greatest(v_est, v_call);
        v_budget := pg_catalog.jsonb_build_object('maxImages', v_card.planner_max_images,
          'maxInputTokens', v_card.planner_max_input_tokens, 'maxOutputTokens', v_card.planner_max_output_tokens,
          'effort', v_card.planner_effort, 'repairAllowed', false);
      end if;
    end if;
  end if;
  -- The cap (T-DB-36), then the environment ceiling through the spend ledger (fail closed, T-DB-61).
  if v_hold.reserved_cost_micro_usd + v_est > v_hold.cap_cost_micro_usd then
    raise exception using errcode = 'P0402', message = 'budget_exceeded';
  end if;
  perform app_private.commit_spend(v_hold.owner_id, v_hold.id, 'stage_reserve', v_est);
  insert into public.render_attempts (id, job_id, stage, attempt, state, input_refs, output_plan,
                                      reserved_cost_micro_usd, planner_budget)
  values (v_id, v_job.id, p_stage, p_attempt, 'reserved', v_refs,
          app_private.stage_output_plan(p_stage, (v_quote.inputs ->> 'angleCount')::int), v_est, v_budget);
  update public.usage_reservations set reserved_cost_micro_usd = reserved_cost_micro_usd + v_est where id = v_hold.id;
  update public.render_jobs set stage = p_stage, stage_progress_milli = 0 where id = v_job.id;
  insert into app_ops.job_outbox (job_id, kind, payload)
  values (v_job.id, 'dispatch_attempt', pg_catalog.jsonb_build_object('attemptId', v_id));
  perform app_private.write_audit('orchestrator', null, v_job.project_id, 'attempt.reserve', 'render_attempt', v_id,
                                  'allowed', null, p_request_id,
                                  pg_catalog.jsonb_build_object('stage', p_stage, 'attempt', p_attempt));
  return pg_catalog.jsonb_build_object('attemptId', v_id, 'state', 'reserved', 'replayed', false,
                                       'alreadyCharged', false);
end
$$;

-- 5. claim_attempt and heartbeat_attempt (architecture §7.3 steps 3-4; security-model §8.4) --------------------------
-- The lease token (jvl_ + 32 bytes of two gen_random_uuid() values, base64url: 244 random bits from the server's
-- strong random source) is returned once and stored only as its SHA-256. A second claim is refused.
create function app_gateway.claim_attempt(p_attempt uuid, p_host text, p_host_kind text, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_try   public.render_attempts;
  v_job   public.render_jobs;
  v_token text;
  v_until timestamptz := now() + interval '5 minutes';
begin
  if p_host is null or p_host !~ '^[a-z0-9][a-z0-9-]{0,63}$' then
    raise exception using errcode = 'P0422', message = 'invalid_value:host';
  end if;
  if p_host_kind is null or p_host_kind not in ('cf-container', 'cloud-run', 'local-test')
     or (p_host_kind = 'local-test' and app_private.jovra_env() <> 'local') then
    raise exception using errcode = 'P0422', message = 'invalid_value:host_kind';
  end if;
  select a.* into v_try from public.render_attempts a where a.id = p_attempt for update;
  if not found then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  if v_try.lease_token_hash is not null or v_try.state not in ('reserved', 'dispatched') then
    raise exception using errcode = 'P0409', message = 'already_claimed';
  end if;
  select j.* into v_job from public.render_jobs j where j.id = v_try.job_id;
  if v_job.cancel_requested_at is not null or not (v_job.state = any (app_private.stage_job_states(v_try.stage))) then
    raise exception using errcode = 'P0409', message = 'job_state_mismatch';
  end if;
  v_token := 'jvl_' || pg_catalog.translate(pg_catalog.rtrim(pg_catalog.encode(
               pg_catalog.uuid_send(gen_random_uuid()) || pg_catalog.uuid_send(gen_random_uuid()), 'base64'), '='),
               '+/', '-_');
  update public.render_attempts
     set state = 'running', lease_token_hash = pg_catalog.sha256(pg_catalog.convert_to(v_token, 'UTF8')),
         claimed_by_host = p_host, host_kind = p_host_kind, leased_until = v_until, heartbeat_at = now(),
         started_at = now()
   where id = v_try.id;
  perform app_private.write_audit('orchestrator', null, v_job.project_id, 'attempt.claim', 'render_attempt', v_try.id,
                                  'allowed', null, p_request_id,
                                  pg_catalog.jsonb_build_object('stage', v_try.stage, 'attempt', v_try.attempt));
  return pg_catalog.jsonb_build_object('leaseToken', v_token, 'leasedUntil', v_until, 'inputRefs', v_try.input_refs,
                                       'outputPlan', v_try.output_plan);
end
$$;

-- Extends the lease only for the current token of a running, unexpired attempt; answers cancel when the job is being
-- canceled (architecture §7.3, §7.5).
create function app_gateway.heartbeat_attempt(p_attempt uuid, p_lease_hash bytea, p_progress_milli int,
                                              p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_try   public.render_attempts := app_private.lock_attempt(p_attempt, p_lease_hash);
  v_job   public.render_jobs;
  v_until timestamptz := now() + interval '5 minutes';
begin
  if v_try.state <> 'running' then
    raise exception using errcode = 'P0409', message = 'not_running';
  end if;
  if v_try.leased_until <= now() then
    raise exception using errcode = 'P0409', message = 'lease_expired';
  end if;
  if p_progress_milli is null or p_progress_milli not between 0 and 1000 then
    raise exception using errcode = 'P0422', message = 'invalid_value:progress_milli';
  end if;
  update public.render_attempts set leased_until = v_until, heartbeat_at = now() where id = v_try.id;
  update public.render_jobs set stage_progress_milli = p_progress_milli where id = v_try.job_id
  returning * into v_job;
  return pg_catalog.jsonb_build_object('leasedUntil', v_until, 'cancel', v_job.cancel_requested_at is not null);
end
$$;

-- 6. finish_attempt (architecture §7.3, §7.4, §7.6; security-model §13.6, §13.7) --------------------------------------
create function app_gateway.finish_attempt(p_attempt uuid, p_lease_hash bytea, p_outcome text, p_outputs jsonb,
                                           p_measurements jsonb, p_error_code text, p_retryable boolean,
                                           p_plan_version uuid, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_try    public.render_attempts;
  v_job    public.render_jobs;
  v_hold   public.usage_reservations;
  v_card   app_ops.rate_cards;
  v_cost   bigint;
  v_charge bigint;
  v_out    jsonb;
  v_kind   text;
  v_art    uuid;
  v_film   uuid;
  v_refs   jsonb := '[]'::jsonb;
  v_rev    int;
  v_vstate text;
  v_hash   bytea;
begin
  -- 1. fencing: only the current lease of this attempt (T-DB-37)
  v_try := app_private.lock_attempt(p_attempt, p_lease_hash);
  if p_outcome is null or p_outcome not in ('succeeded', 'failed') then
    raise exception using errcode = 'P0422', message = 'invalid_value:outcome';
  end if;
  if not app_private.measurements_are_valid(p_measurements) then
    raise exception using errcode = 'P0422', message = 'invalid_value:measurements';
  end if;
  -- 2. a redelivered result replays; any other result for a finished attempt is a conflict
  if v_try.state in ('succeeded', 'failed') then
    if v_try.state = p_outcome and v_try.measurements = p_measurements then
      return pg_catalog.jsonb_build_object('accepted', true, 'replayed', true, 'state', v_try.state);
    end if;
    raise exception using errcode = 'P0409', message = 'already_finished';
  end if;
  if v_try.state = 'lease_expired' or (v_try.state = 'running' and v_try.leased_until <= now()) then
    raise exception using errcode = 'P0409', message = 'lease_expired';
  end if;
  if v_try.state <> 'running' then
    raise exception using errcode = 'P0409', message = 'not_running';
  end if;
  -- 3. the result's shape against what the server stored for this attempt
  if p_outcome = 'failed' then
    if p_error_code is null or p_error_code !~ '^[a-z][a-z0-9_]{0,63}$' or p_retryable is null then
      raise exception using errcode = 'P0422', message = 'invalid_value:error_code';
    end if;
    if p_outputs is distinct from '[]'::jsonb then
      raise exception using errcode = 'P0422', message = 'invalid_value:outputs';
    end if;
  else
    if p_error_code is not null or p_retryable is not null then
      raise exception using errcode = 'P0422', message = 'invalid_value:error_code';
    end if;
    if not app_private.attempt_outputs_are_valid(p_outputs, v_try.output_plan) then
      raise exception using errcode = 'P0422', message = 'invalid_value:outputs';
    end if;
  end if;
  if p_plan_version is not null and (p_outcome = 'failed' or v_try.stage <> 'plan') then
    raise exception using errcode = 'P0422', message = 'invalid_value:story_plan_version_id';
  end if;
  select j.* into v_job from public.render_jobs j where j.id = v_try.job_id for update;
  select r.* into v_hold from public.usage_reservations r
   where r.id = v_job.reservation_id and r.project_id = v_job.project_id
   for update;
  if v_hold.state is distinct from 'held' then
    raise exception using errcode = 'P0409', message = 'reservation_closed';
  end if;
  v_card := app_private.hold_rate_card(v_hold);
  v_cost := app_private.attempt_actual_cost(v_card, p_measurements);

  -- 4a. failure: nothing is charged; the stage's reservation returns to the hold (architecture §7.4)
  if p_outcome = 'failed' then
    update public.render_attempts
       set state = 'failed', error_code = p_error_code, retryable = p_retryable, measurements = p_measurements,
           actual_cost_micro_usd = v_cost, finished_at = now()
     where id = v_try.id;
    update public.usage_reservations
       set reserved_cost_micro_usd = reserved_cost_micro_usd - v_try.reserved_cost_micro_usd
     where id = v_hold.id;
    perform app_private.write_audit('orchestrator', null, v_job.project_id, 'attempt.finish', 'render_attempt',
                                    v_try.id, 'allowed', null, p_request_id,
                                    pg_catalog.jsonb_build_object('outcome', 'failed', 'errorCode', p_error_code));
    return pg_catalog.jsonb_build_object('accepted', true, 'replayed', false, 'state', 'failed',
                                         'jobState', v_job.state);
  end if;

  -- 4b. success: the stage's one charge, at most its reservation (once per (job, stage), unique index)
  v_charge := pg_catalog.least(v_cost, v_try.reserved_cost_micro_usd);
  begin
    update public.render_attempts
       set state = 'succeeded', measurements = p_measurements, actual_cost_micro_usd = v_cost,
           charged_cost_micro_usd = v_charge, finished_at = now()
     where id = v_try.id;
  exception when unique_violation then
    raise exception using errcode = 'P0409', message = 'stage_already_charged';
  end;
  update public.usage_reservations
     set reserved_cost_micro_usd = reserved_cost_micro_usd - v_try.reserved_cost_micro_usd + v_charge,
         consumed_cost_micro_usd = consumed_cost_micro_usd + v_charge
   where id = v_hold.id;

  -- 5. outputs: registered as verifying, never ready, under server-generated keys; their sources are recorded so a
  -- source-scope deletion finds them (security-model §13.9 (a)); a film's thumbnail, captions and chapters are its
  -- children (§13.9 (f))
  for v_out in select x from pg_catalog.jsonb_array_elements(p_outputs) x loop
    v_kind := (select e ->> 'kind' from pg_catalog.jsonb_array_elements(v_try.output_plan) e
                where e ->> 'outputRef' = v_out ->> 'outputRef');
    v_art := gen_random_uuid();
    insert into public.artifacts (id, project_id, job_id, attempt_id, kind, bucket_class, r2_key, bytes, sha256, state,
                                  sample)
    values (v_art, v_job.project_id, v_job.id, v_try.id, v_kind::public.artifact_kind, app_private.output_bucket(v_kind),
            app_private.output_r2_key(v_kind, v_job.project_id, v_job.id, v_try.id, v_out ->> 'outputRef', v_art),
            (v_out ->> 'bytes')::bigint, pg_catalog.decode(v_out ->> 'sha256', 'hex'), 'verifying', v_job.sample);
    insert into public.artifact_sources (artifact_id, project_id, source_id)
    select v_art, v_job.project_id, (e ->> 'id')::uuid
      from pg_catalog.jsonb_array_elements(v_try.input_refs) e
     where e ->> 'kind' = 'source';
    v_refs := v_refs || pg_catalog.jsonb_build_array(v_art);
    if v_kind = 'film' and v_film is null then
      v_film := v_art;
    end if;
  end loop;
  if v_film is not null then
    update public.artifacts set parent_artifact_id = v_film
     where attempt_id = v_try.id and job_id = v_job.id and kind in ('thumbnail', 'captions', 'chapters');
  end if;
  update public.render_attempts set output_refs = v_refs where id = v_try.id;

  -- 6. the plan stage of plan-by-job work moves the job and its hold from (plan, NULL, hash of the unplanned output) to
  -- (plan, V, hash of V) in this same transaction (security-model §13.6, T-DB-68)
  if p_plan_version is not null then
    select v.version, v.validation_state into v_rev, v_vstate from public.story_plan_versions v
     where v.id = p_plan_version and v.story_plan_id = v_job.story_plan_id and v.project_id = v_job.project_id;
    if v_rev is null then
      raise exception using errcode = 'P0404', message = 'not_found';
    end if;
    if v_vstate = 'invalid' then
      raise exception using errcode = 'P0409', message = 'plan_invalid';
    end if;
    if v_job.story_plan_version_id is null then
      v_hash := app_private.output_spec_sha256(v_job.project_id, v_rev, v_job.output_spec);
      begin
        update public.render_jobs set story_plan_version_id = p_plan_version, output_spec_sha256 = v_hash
         where id = v_job.id;
        update public.usage_reservations set story_plan_version_id = p_plan_version, output_spec_sha256 = v_hash
         where id = v_hold.id;
      exception when unique_violation then
        raise exception using errcode = 'P0409', message = 'requote_conflict';
      end;
    elsif v_job.story_plan_version_id <> p_plan_version then
      raise exception using errcode = 'P0422', message = 'invalid_value:story_plan_version_id';
    end if;
  end if;

  -- 7. an actual cost above the stage reservation is already spent: it is committed as stage_overrun (so the next
  -- reservation sees it in the day's total) and the job stops at budget_exceeded (security-model §13.7, T-DB-72 (c))
  if v_cost > v_try.reserved_cost_micro_usd then
    perform app_private.commit_spend(v_hold.owner_id, v_hold.id, 'stage_overrun', v_cost - v_try.reserved_cost_micro_usd);
    if app_private.job_transition_allowed(v_job.state, 'budget_exceeded', null) then
      update public.render_jobs set state = 'budget_exceeded', resume_state = v_job.state, error_code = 'stage_overrun'
       where id = v_job.id;
    end if;
  end if;
  perform app_private.write_audit('orchestrator', null, v_job.project_id, 'attempt.finish', 'render_attempt', v_try.id,
                                  'allowed', null, p_request_id,
                                  pg_catalog.jsonb_build_object('outcome', 'succeeded',
                                                                'outputs', pg_catalog.jsonb_array_length(v_refs),
                                                                'overrun', v_cost > v_try.reserved_cost_micro_usd));
  return pg_catalog.jsonb_build_object('accepted', true, 'replayed', false, 'state', 'succeeded',
                                       'jobState', (select j.state from public.render_jobs j where j.id = v_job.id),
                                       'outputRefs', v_refs);
end
$$;

-- 7. mark_artifact_verified: the verify_output stage, under its own lease, verifies an output another attempt of the
-- same job wrote (full decode, frame count, audio, provenance are the host's checks; architecture §7.1).
create function app_gateway.mark_artifact_verified(p_attempt uuid, p_lease_hash bytea, p_artifact uuid,
                                                   p_verification jsonb, p_request_id uuid)
returns timestamptz language plpgsql volatile security definer set search_path = '' as $$
declare
  v_try public.render_attempts := app_private.lock_attempt(p_attempt, p_lease_hash);
  v_art public.artifacts;
  v_at  timestamptz := now();
begin
  if v_try.state <> 'running' then
    raise exception using errcode = 'P0409', message = 'not_running';
  end if;
  if v_try.leased_until <= now() then
    raise exception using errcode = 'P0409', message = 'lease_expired';
  end if;
  if v_try.stage <> 'verify_output' then
    raise exception using errcode = 'P0409', message = 'not_verify_stage';
  end if;
  if pg_catalog.jsonb_typeof(p_verification) is distinct from 'object' or p_verification = '{}'::jsonb
     or pg_catalog.octet_length(p_verification::text) > 65536 then
    raise exception using errcode = 'P0422', message = 'invalid_value:verification';
  end if;
  select a.* into v_art from public.artifacts a where a.id = p_artifact and a.job_id = v_try.job_id for update;
  if not found or v_art.deleted_at is not null or v_art.attempt_id is not distinct from v_try.id then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  if v_art.state <> 'verifying' then
    raise exception using errcode = 'P0409', message = 'not_verifying';
  end if;
  update public.artifacts set state = 'ready', verified_at = v_at, verification = p_verification where id = v_art.id;
  perform app_private.write_audit('orchestrator', null, v_art.project_id, 'artifact.verify', 'artifact', v_art.id,
                                  'allowed', null, p_request_id, pg_catalog.jsonb_build_object('kind', v_art.kind));
  return v_at;
end
$$;

-- 8. expire_attempt_leases: the reconciler's sweep (architecture §7.3). Running attempts past leased_until become
-- lease_expired and their stage reservation returns to the hold; the Workflow then retries or fails the stage.
create function app_gateway.expire_attempt_leases(p_request_id uuid)
returns int language plpgsql volatile security definer set search_path = '' as $$
declare
  v_try   public.render_attempts;
  v_count int := 0;
begin
  for v_try in select a.* from public.render_attempts a
                where a.state = 'running' and a.leased_until <= now()
                for update skip locked loop
    update public.render_attempts
       set state = 'lease_expired', error_code = 'lease_expired', retryable = true, finished_at = now()
     where id = v_try.id;
    update public.usage_reservations r
       set reserved_cost_micro_usd = r.reserved_cost_micro_usd - v_try.reserved_cost_micro_usd
      from public.render_jobs j
     where j.id = v_try.job_id and r.id = j.reservation_id and r.project_id = j.project_id and r.state = 'held';
    v_count := v_count + 1;
  end loop;
  if v_count > 0 then
    perform app_private.write_audit('orchestrator', null, null, 'attempt.expire_leases', null, null, 'allowed', null,
                                    p_request_id, pg_catalog.jsonb_build_object('count', v_count));
  end if;
  return v_count;
end
$$;

-- 9. delete_lesson_rows: the row step of a lesson-scope deletion (architecture §10, security-model §13.9 (b)). The
-- deletion Workflow (S94) removes the objects lesson_deletion_artifacts lists first; this step then removes the
-- lesson from every Progress plan that holds it, marks those plans' versions invalid and stale and their films and
-- previews stale, and deletes the lesson (its clips, lesson-only observations and excerpt rows cascade). On this
-- server path auth.uid() is null, so check_story_plan_lessons skips its per-caller check and keeps the same-owner check:
-- a plan that keeps another lesson no longer stalls the request (T-DB-73).
create function app_gateway.delete_lesson_rows(p_request uuid, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_req      public.deletion_requests;
  v_plans    uuid[];
  v_versions int;
  v_media    int;
  v_lessons  int;
  v_counts   jsonb;
begin
  select d.* into v_req from public.deletion_requests d where d.id = p_request for update;
  if not found or v_req.scope <> 'lesson' then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  if v_req.state = 'done' then
    return pg_catalog.jsonb_build_object('state', 'done', 'replayed', true, 'counts', v_req.counts);
  end if;
  if v_req.state = 'failed' then
    raise exception using errcode = 'P0409', message = 'request_failed';
  end if;
  with affected as (
    update public.story_plans set lesson_ids = pg_catalog.array_remove(lesson_ids, v_req.target_id)
     where v_req.target_id = any (lesson_ids)
    returning id)
  select coalesce(pg_catalog.array_agg(a.id), '{}'::uuid[]) into v_plans from affected a;
  update public.story_plan_versions v set validation_state = 'invalid', stale = true
   where v.story_plan_id = any (v_plans);
  get diagnostics v_versions = row_count;
  update public.artifacts a set stale = true
   where a.kind in ('film', 'preview') and a.deleted_at is null and a.edl_sha256 is not null
     and a.edl_sha256 in (select v.edl_sha256 from public.story_plan_versions v
                           where v.story_plan_id = any (v_plans) and v.edl_sha256 is not null);
  get diagnostics v_media = row_count;
  delete from public.lessons l where l.id = v_req.target_id;
  get diagnostics v_lessons = row_count;
  v_counts := pg_catalog.jsonb_build_object('lessons', v_lessons, 'plans', pg_catalog.cardinality(v_plans),
                                            'planVersions', v_versions, 'staleMedia', v_media);
  update public.deletion_requests set state = 'done', finished_at = now(), counts = v_counts where id = v_req.id;
  perform app_private.write_audit('orchestrator', null, null, 'deletion.lesson_rows', 'deletion_request', v_req.id,
                                  'allowed', null, p_request_id, v_counts);
  return pg_catalog.jsonb_build_object('state', 'done', 'replayed', false, 'counts', v_counts);
end
$$;

-- 10. audit_denial_for_attempt (security-model §4.1): the jovra-internal host routes' second call after a refusal
-- (forged or stale lease, second claim, unlisted input, output over its cap, unknown attempt). Append only: one denied
-- row with actor_kind render_attempt and the attempt id, or null when the id does not resolve; it takes no lease token,
-- so a refused caller cannot use it to probe one.
create function app_gateway.audit_denial_for_attempt(p_attempt uuid, p_action text, p_reason text, p_request_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
declare
  v_attempt uuid;
begin
  if p_action is null or pg_catalog.char_length(p_action) > 64 or p_action !~ '^[a-z_]+(\.[a-z_]+)+$' then
    raise exception using errcode = 'P0422', message = 'invalid_value:action';
  end if;
  if p_reason is null or p_reason !~ '^[a-z0-9_]{1,64}$' then
    raise exception using errcode = 'P0422', message = 'invalid_value:reason';
  end if;
  select a.id into v_attempt from public.render_attempts a where a.id = p_attempt;
  perform app_private.write_audit('render_attempt', v_attempt, null, p_action, 'render_attempt', v_attempt, 'denied',
                                  p_reason, p_request_id);
end
$$;

-- 11. accept_quote (migration 20261008041000) with one fix found by the ledger replay: a redelivered acceptance of a
-- quote that a top-up has since superseded is still a replay of what it made (ledger vector
-- retries-after-topup-replay), never quote_closed. Everything else is unchanged.
create or replace function app_gateway.accept_quote(p_actor uuid, p_quote uuid, p_inputs_sha256 bytea, p_consent jsonb,
                                                    p_cap_credits int, p_idempotency_key text, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_quote  public.quotes;
  v_hold   public.usage_reservations;
  v_job    public.render_jobs;
  v_inputs jsonb;
  v_delta  bigint;
  v_res_id uuid := gen_random_uuid();
  v_job_id uuid := gen_random_uuid();
begin
  -- 1. the owner, now: the quote's owner still owns the live project
  select q.* into v_quote from public.quotes q
    join public.projects p on p.id = q.project_id and p.owner_id = p_actor and p.deleted_at is null
   where q.id = p_quote and q.owner_id = p_actor
   for update of q;
  if not found then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  -- 2. a real user; outside the local stack, a tester (set only by the operator, security-model §13.3)
  perform app_private.require_real_user(p_actor);
  if app_private.jovra_env() <> 'local'
     and not exists (select 1 from public.profiles pr where pr.id = p_actor and pr.is_tester) then
    raise exception using errcode = 'P0401', message = 'unauthorized';
  end if;
  if p_idempotency_key is null or pg_catalog.char_length(p_idempotency_key) not between 1 and 255 then
    raise exception using errcode = 'P0422', message = 'invalid_value:idempotency_key';
  end if;
  -- 3. a retry of this acceptance returns what it made (story 199), also after a top-up superseded the quote; another
  -- key for the same quote is a conflict
  if v_quote.state in ('accepted', 'superseded') then
    select r.* into v_hold from public.usage_reservations r
     where r.quote_id = v_quote.id or r.initial_quote_id = v_quote.id
     order by (r.quote_id = v_quote.id) desc limit 1;
    select j.* into v_job from public.render_jobs j where j.id = v_hold.job_id;
    if v_hold.id is null or v_job.id is null or p_inputs_sha256 is distinct from v_quote.inputs_sha256
       or (v_hold.initial_quote_id = v_quote.id and v_job.idempotency_key is distinct from p_idempotency_key) then
      raise exception using errcode = 'P0409', message = 'already_accepted';
    end if;
    return pg_catalog.jsonb_build_object('jobId', v_job.id, 'reservationId', v_hold.id, 'state', v_job.state,
                                         'replayed', true);
  end if;
  -- 4. open, unexpired, the same inputs and cap the owner saw (story 185: a price never changes behind their back)
  if v_quote.state = 'expired' or v_quote.expires_at <= now() then
    raise exception using errcode = 'P0410', message = 'quote_expired';
  end if;
  if v_quote.state <> 'open' then
    raise exception using errcode = 'P0409', message = 'quote_closed';
  end if;
  if p_inputs_sha256 is distinct from v_quote.inputs_sha256 then
    raise exception using errcode = 'P0409', message = 'inputs_changed';
  end if;
  begin
    v_inputs := app_private.quote_inputs(v_quote.project_id, v_quote.story_plan_id, v_quote.story_plan_version_id,
                                         v_quote.planner_choice, v_quote.inputs -> 'outputSpec',
                                         array(select pg_catalog.jsonb_array_elements_text(v_quote.inputs -> 'sourceIds')::uuid),
                                         v_quote.retention_days);
  exception when sqlstate 'P0404' or sqlstate 'P0409' or sqlstate 'P0422' then
    raise exception using errcode = 'P0409', message = 'inputs_changed';
  end;
  if pg_catalog.sha256(pg_catalog.convert_to(v_inputs::text, 'UTF8')) is distinct from v_quote.inputs_sha256 then
    raise exception using errcode = 'P0409', message = 'inputs_changed';
  end if;
  if p_cap_credits is distinct from v_quote.cap_credits then
    raise exception using errcode = 'P0409', message = 'cap_mismatch';
  end if;
  if not app_private.consent_is_valid(p_consent, v_quote.planner_choice, v_quote.retention_days) then
    raise exception using errcode = 'P0422', message = 'invalid_value:consent';
  end if;
  -- 5. one hold per (project, plan, plan version, output), NULLS NOT DISTINCT (finding 18)
  select r.* into v_hold from public.usage_reservations r
   where r.project_id = v_quote.project_id and r.story_plan_id = v_quote.story_plan_id
     and r.story_plan_version_id is not distinct from v_quote.story_plan_version_id
     and r.output_spec_sha256 = v_quote.output_spec_sha256 and r.state = 'held'
   for update;
  if found then
    select j.* into v_job from public.render_jobs j where j.id = v_hold.job_id for update;
    if v_quote.supersedes_quote_id is distinct from v_hold.quote_id or v_job.state is distinct from 'budget_exceeded'
    then
      raise exception using errcode = 'P0409', message = 'duplicate_work';
    end if;
    -- a top-up of the held reservation (story 186: the job stopped and asked; the owner raised it)
    v_delta := v_quote.cap_cost_micro_usd - v_hold.cap_cost_micro_usd;
    if v_delta <= 0 then
      raise exception using errcode = 'P0409', message = 'topup_not_larger';
    end if;
    perform app_private.commit_spend(p_actor, v_hold.id, 'cap_topup', v_delta);
    update public.usage_reservations
       set quote_id = v_quote.id, cap_credits = v_quote.cap_credits, cap_cost_micro_usd = v_quote.cap_cost_micro_usd
     where id = v_hold.id;
    update public.quotes set state = 'superseded' where id = v_hold.quote_id;
    update public.quotes set state = 'accepted', accepted_at = now(), consent = p_consent where id = v_quote.id;
    update public.render_jobs set state = 'consented', error_code = null where id = v_job.id;
    perform app_private.write_audit('user', p_actor, v_quote.project_id, 'quote.accept', 'quote', v_quote.id,
                                    'allowed', null, p_request_id,
                                    pg_catalog.jsonb_build_object('topUp', true, 'capCredits', v_quote.cap_credits));
    return pg_catalog.jsonb_build_object('jobId', v_job.id, 'reservationId', v_hold.id, 'state', 'consented',
                                         'replayed', false, 'toppedUp', true);
  end if;
  if exists (select 1 from public.render_jobs j
              where j.project_id = v_quote.project_id and j.story_plan_id = v_quote.story_plan_id
                and j.story_plan_version_id is not distinct from v_quote.story_plan_version_id
                and j.output_spec_sha256 = v_quote.output_spec_sha256
                and j.state not in ('ready', 'canceled', 'failed_terminal', 'quote_expired', 'deleted')) then
    raise exception using errcode = 'P0409', message = 'duplicate_work';
  end if;
  -- 6. the ceilings, then the hold, the job and the outbox row, in this one transaction
  perform app_private.commit_spend(p_actor, v_res_id, 'cap_open', v_quote.cap_cost_micro_usd);
  begin
    insert into public.usage_reservations (id, project_id, owner_id, quote_id, initial_quote_id, story_plan_id,
                                           story_plan_version_id, output_spec_sha256, cap_credits,
                                           cap_cost_micro_usd, sample)
    values (v_res_id, v_quote.project_id, p_actor, v_quote.id, v_quote.id, v_quote.story_plan_id,
            v_quote.story_plan_version_id, v_quote.output_spec_sha256, v_quote.cap_credits,
            v_quote.cap_cost_micro_usd, v_quote.sample);
    insert into public.render_jobs (id, project_id, story_plan_id, story_plan_version_id, quote_id, reservation_id,
                                    requested_by, output_spec_sha256, idempotency_key, state, output_spec, sample)
    values (v_job_id, v_quote.project_id, v_quote.story_plan_id, v_quote.story_plan_version_id, v_quote.id, v_res_id,
            p_actor, v_quote.output_spec_sha256, p_idempotency_key, 'consented', v_quote.inputs -> 'outputSpec',
            v_quote.sample);
  exception when unique_violation then
    raise exception using errcode = 'P0409', message = 'duplicate_work';
  end;
  update public.usage_reservations set job_id = v_job_id where id = v_res_id;
  update public.quotes set state = 'accepted', accepted_at = now(), consent = p_consent where id = v_quote.id;
  insert into app_ops.job_outbox (job_id, kind, payload)
  values (v_job_id, 'start_workflow', pg_catalog.jsonb_build_object('jobId', v_job_id));
  perform app_private.write_audit('user', p_actor, v_quote.project_id, 'quote.accept', 'quote', v_quote.id, 'allowed',
                                  null, p_request_id, pg_catalog.jsonb_build_object('capCredits', v_quote.cap_credits));
  return pg_catalog.jsonb_build_object('jobId', v_job_id, 'reservationId', v_res_id, 'state', 'consented',
                                       'replayed', false);
end
$$;

-- 12. Function privileges --------------------------------------------------------------------------------------------
revoke all on function
  app_private.job_transition_allowed(public.job_state, public.job_state, public.job_state),
  app_private.stage_job_states(public.job_stage), app_private.stage_output_plan(public.job_stage, int),
  app_private.output_bucket(text), app_private.output_r2_key(text, uuid, uuid, uuid, text, uuid),
  app_private.measurements_are_valid(jsonb), app_private.attempt_actual_cost(app_ops.rate_cards, jsonb),
  app_private.planner_call_cost(app_ops.rate_cards), app_private.attempt_outputs_are_valid(jsonb, jsonb),
  app_private.lock_attempt(uuid, bytea), app_private.hold_rate_card(public.usage_reservations),
  app_gateway.set_job_state(uuid, public.job_state, public.job_state, text, uuid),
  app_gateway.reserve_stage(uuid, public.job_stage, int, uuid),
  app_gateway.claim_attempt(uuid, text, text, uuid),
  app_gateway.heartbeat_attempt(uuid, bytea, int, uuid),
  app_gateway.finish_attempt(uuid, bytea, text, jsonb, jsonb, text, boolean, uuid, uuid),
  app_gateway.mark_artifact_verified(uuid, bytea, uuid, jsonb, uuid),
  app_gateway.expire_attempt_leases(uuid),
  app_gateway.delete_lesson_rows(uuid, uuid),
  app_gateway.audit_denial_for_attempt(uuid, text, text, uuid)
  from public, anon, authenticated, service_role;

-- Orchestration is the orchestrator's alone, never the gateway's (T-DB-53, T-DB-57).
grant execute on function
  app_gateway.set_job_state(uuid, public.job_state, public.job_state, text, uuid),
  app_gateway.reserve_stage(uuid, public.job_stage, int, uuid),
  app_gateway.claim_attempt(uuid, text, text, uuid),
  app_gateway.heartbeat_attempt(uuid, bytea, int, uuid),
  app_gateway.finish_attempt(uuid, bytea, text, jsonb, jsonb, text, boolean, uuid, uuid),
  app_gateway.mark_artifact_verified(uuid, bytea, uuid, jsonb, uuid),
  app_gateway.expire_attempt_leases(uuid),
  app_gateway.delete_lesson_rows(uuid, uuid),
  app_gateway.audit_denial_for_attempt(uuid, text, text, uuid)
  to jovra_orchestrator;

-- 13. One owner (T-DB-66) --------------------------------------------------------------------------------------------
alter table app_ops.rate_cards owner to jovra_owner;
alter table app_ops.stage_rates owner to jovra_owner;
alter function app_private.job_transition_allowed(public.job_state, public.job_state, public.job_state)
  owner to jovra_owner;
alter function app_private.stage_job_states(public.job_stage) owner to jovra_owner;
alter function app_private.stage_output_plan(public.job_stage, int) owner to jovra_owner;
alter function app_private.output_bucket(text) owner to jovra_owner;
alter function app_private.output_r2_key(text, uuid, uuid, uuid, text, uuid) owner to jovra_owner;
alter function app_private.measurements_are_valid(jsonb) owner to jovra_owner;
alter function app_private.attempt_actual_cost(app_ops.rate_cards, jsonb) owner to jovra_owner;
alter function app_private.planner_call_cost(app_ops.rate_cards) owner to jovra_owner;
alter function app_private.attempt_outputs_are_valid(jsonb, jsonb) owner to jovra_owner;
alter function app_private.lock_attempt(uuid, bytea) owner to jovra_owner;
alter function app_private.hold_rate_card(public.usage_reservations) owner to jovra_owner;
alter function app_gateway.set_job_state(uuid, public.job_state, public.job_state, text, uuid) owner to jovra_owner;
alter function app_gateway.reserve_stage(uuid, public.job_stage, int, uuid) owner to jovra_owner;
alter function app_gateway.claim_attempt(uuid, text, text, uuid) owner to jovra_owner;
alter function app_gateway.heartbeat_attempt(uuid, bytea, int, uuid) owner to jovra_owner;
alter function app_gateway.finish_attempt(uuid, bytea, text, jsonb, jsonb, text, boolean, uuid, uuid)
  owner to jovra_owner;
alter function app_gateway.mark_artifact_verified(uuid, bytea, uuid, jsonb, uuid) owner to jovra_owner;
alter function app_gateway.expire_attempt_leases(uuid) owner to jovra_owner;
alter function app_gateway.delete_lesson_rows(uuid, uuid) owner to jovra_owner;
alter function app_gateway.audit_denial_for_attempt(uuid, text, text, uuid) owner to jovra_owner;
