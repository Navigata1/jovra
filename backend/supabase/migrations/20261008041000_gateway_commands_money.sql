-- S79 / B-06 (gateway half), part 2: quotes, acceptance and review (docs/backend/architecture.md §4.3, §5.1, §7.1,
-- §7.2; security-model.md §4.1, §13.3, §13.5-§13.7; findings 18 and 19; user stories 185, 186, 199):
--   * create_quote computes everything from rows: sources resolve only through this project's current verified source
--     manifest, the plan and version must be this project's (T-DB-59), the inputs hash and the output-spec hash (the
--     contract's core.output_spec_sha256) are computed in SQL, and the estimate comes from a versioned rate card;
--   * accept_quote is one transaction: idempotent by its HTTP key, P0410 for an expired quote, P0409 for changed inputs
--     or a changed cap, the tester flag outside the local stack, the owner open-cap and environment daily ceilings
--     (fail closed on a missing row or a NULL limit, serialized by one advisory lock: T-DB-61, T-DB-71), and one held
--     reservation per (project, plan, plan version, output) also while the version is null (T-DB-56, T-DB-60), or a
--     top-up of that hold when the quote supersedes its quote after budget_exceeded;
--   * review_job approves, or revises within the remaining reservation and moves the job's and the hold's key together
--     (§13.6), else P0409 requote_required.
-- Conventions as in part 1 (20261008040000_gateway_commands_access.sql).

-- 1. Spend ledger (security-model §13.7) ----------------------------------------------------------------------------
-- Called by accept_quote ('cap_open' with the new cap, 'cap_topup' with the delta) and by S80's reserve_stage
-- ('stage_reserve') and finish_attempt ('stage_overrun'). A missing limits row makes the record NULL and a NULL limit
-- compares through coalesce(..., -1), so neither can ever pass: no row, no spend (finding 19). One transaction-scoped
-- advisory lock serializes every ceiling check, so two concurrent acceptances cannot both fit under one ceiling
-- (T-DB-71); after the lock each statement sees the other's committed commitment (read committed, volatile).
create function app_private.commit_spend(p_owner uuid, p_reservation uuid, p_kind text, p_amount bigint)
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

-- 2. Quote inputs, output hash and estimate ---------------------------------------------------------------------------
-- The output of route.quotes.create (backend/contracts): exactly fps {num, den}, width, height, aspect, container,
-- videoCodec, audioCodec, audioSampleRate and durationTargetSec, as JSON integers and enum strings.
create function app_private.output_spec_is_valid(p_output jsonb) returns boolean
language plpgsql immutable set search_path = '' as $$
declare
  v_int text;
begin
  if pg_catalog.jsonb_typeof(p_output) is distinct from 'object' or pg_catalog.octet_length(p_output::text) > 4096 then
    return false;
  end if;
  if (select pg_catalog.array_agg(k order by k collate "C") from pg_catalog.jsonb_object_keys(p_output) k)
     is distinct from array['aspect', 'audioCodec', 'audioSampleRate', 'container', 'durationTargetSec', 'fps',
                            'height', 'videoCodec', 'width'] then
    return false;
  end if;
  if pg_catalog.jsonb_typeof(p_output -> 'fps') is distinct from 'object'
     or (select pg_catalog.array_agg(k order by k collate "C") from pg_catalog.jsonb_object_keys(p_output -> 'fps') k)
        is distinct from array['den', 'num'] then
    return false;
  end if;
  foreach v_int in array array['width', 'height', 'durationTargetSec', 'audioSampleRate'] loop
    if pg_catalog.jsonb_typeof(p_output -> v_int) is distinct from 'number'
       or (p_output ->> v_int) !~ '^[1-9][0-9]{0,5}$' then
      return false;
    end if;
  end loop;
  if pg_catalog.jsonb_typeof(p_output -> 'fps' -> 'num') is distinct from 'number'
     or (p_output -> 'fps' ->> 'num') !~ '^[1-9][0-9]{0,5}$'
     or pg_catalog.jsonb_typeof(p_output -> 'fps' -> 'den') is distinct from 'number'
     or (p_output -> 'fps' ->> 'den') !~ '^[1-9][0-9]{0,3}$' then
    return false;
  end if;
  return (p_output ->> 'width')::int between 2 and 3840 and (p_output ->> 'width')::int % 2 = 0
     and (p_output ->> 'height')::int between 2 and 3840 and (p_output ->> 'height')::int % 2 = 0
     and (p_output ->> 'durationTargetSec')::int between 1 and 14400
     and (p_output -> 'fps' ->> 'num')::int <= 240000 and (p_output -> 'fps' ->> 'den')::int <= 1001
     and (p_output ->> 'audioSampleRate')::int = 48000
     and p_output -> 'aspect' in ('"16:9"'::jsonb, '"9:16"'::jsonb, '"1:1"'::jsonb, '"4:5"'::jsonb)
     and p_output -> 'container' = '"mp4"'::jsonb
     and p_output -> 'videoCodec' in ('"h264"'::jsonb, '"hevc"'::jsonb)
     and p_output -> 'audioCodec' = '"aac"'::jsonb;
end
$$;

-- The contract's output_spec_sha256 (spec/reference/studio/core.py): SHA-256 of the canonical JSON (sorted keys, no
-- whitespace) of {projectId, planRevision, output}. Only called on an output that passed output_spec_is_valid, whose
-- strings are fixed enum values, so no JSON escaping is ever needed. planRevision is null for plan-by-job work.
create function app_private.output_spec_sha256(p_project uuid, p_plan_revision int, p_output jsonb) returns bytea
language sql immutable set search_path = '' as $$
  select pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.format(
    '{"output":{"aspect":"%s","audioCodec":"%s","audioSampleRate":%s,"container":"%s","durationTargetSec":%s,'
    '"fps":{"den":%s,"num":%s},"height":%s,"videoCodec":"%s","width":%s},"planRevision":%s,"projectId":"%s"}',
    p_output ->> 'aspect', p_output ->> 'audioCodec', p_output ->> 'audioSampleRate', p_output ->> 'container',
    p_output ->> 'durationTargetSec', p_output -> 'fps' ->> 'den', p_output -> 'fps' ->> 'num',
    p_output ->> 'height', p_output ->> 'videoCodec', p_output ->> 'width',
    coalesce(p_plan_revision::text, 'null'), p_project::text), 'UTF8'))
$$;

-- The quote's inputs, from rows only: the plan (and version) of this project, every source verified and listed in the
-- project's current source manifest (a foreign or unknown id is P0404, like a missing one), the verified bytes, the
-- angle count, the profile, the output, the retention and the planner choice. accept_quote recomputes it, so a
-- source deleted or a newer manifest since the quote reads as changed inputs.
create function app_private.quote_inputs(p_project uuid, p_plan uuid, p_version uuid, p_planner text, p_output jsonb,
                                         p_sources uuid[], p_retention int)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_plan     public.story_plans;
  v_rev      int;
  v_state    text;
  v_ids      uuid[];
  v_manifest int;
  v_count    int;
  v_bytes    bigint;
begin
  select sp.* into v_plan from public.story_plans sp where sp.id = p_plan and sp.project_id = p_project;
  if not found then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  if p_version is not null then
    select v.version, v.validation_state into v_rev, v_state from public.story_plan_versions v
     where v.id = p_version and v.story_plan_id = p_plan and v.project_id = p_project;
    if v_rev is null then
      raise exception using errcode = 'P0404', message = 'not_found';
    end if;
    if v_state = 'invalid' then
      raise exception using errcode = 'P0409', message = 'plan_invalid';
    end if;
  end if;
  if p_sources is null or pg_catalog.cardinality(p_sources) not between 1 and 6
     or pg_catalog.array_position(p_sources, null) is not null
     or (select pg_catalog.count(distinct x) from pg_catalog.unnest(p_sources) x) <> pg_catalog.cardinality(p_sources)
  then
    raise exception using errcode = 'P0422', message = 'invalid_value:source_ids';
  end if;
  select pg_catalog.array_agg(x order by x) into v_ids from pg_catalog.unnest(p_sources) x;
  select p.current_source_manifest_revision into v_manifest from public.projects p where p.id = p_project;
  select pg_catalog.count(*), coalesce(pg_catalog.sum(s.declared_bytes), 0) into v_count, v_bytes
    from public.camera_sources s
    join public.source_manifests m on m.project_id = s.project_id and m.revision = v_manifest
   where s.project_id = p_project and s.id = any (v_ids) and s.state = 'verified'
     and m.manifest -> 'sources' @> pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('sourceId', s.id::text));
  if v_count <> pg_catalog.cardinality(v_ids) then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  return pg_catalog.jsonb_build_object(
    'storyPlanId', p_plan, 'storyPlanVersionId', p_version, 'planRevision', v_rev,
    'profileId', v_plan.profile_id, 'profileRevision', v_plan.profile_revision, 'plannerChoice', p_planner,
    'outputSpec', p_output, 'sourceIds', pg_catalog.to_jsonb(v_ids), 'angleCount', pg_catalog.cardinality(v_ids),
    'verifiedBytes', v_bytes, 'sourceManifestRevision', v_manifest, 'retentionDays', p_retention,
    'ratesVersion', 'rates-v0-inferred');
end
$$;

-- Rate card rates-v0-inferred (INFERRED starting values, refreshed at activation; docs/research/studio/
-- pricing-and-premium.md): storage 500 micro-USD per GiB-day of verified bytes, ingest 20 micro-USD per MiB,
-- rendering 1,500 micro-USD per output second per angle, a model plan 200,000 micro-USD, a floor of 100,000, and a cap
-- 25% above the high estimate. Credits follow spec/studio/contracts/credit-classes.v1.json:
-- capCredits = max(classMinimum, ceil(capCostMicroUsd / 800000)).
create function app_private.quote_estimate(p_inputs jsonb) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare
  v_budget  constant bigint := 800000;
  v_bytes   bigint := (p_inputs ->> 'verifiedBytes')::bigint;
  v_angles  int := (p_inputs ->> 'angleCount')::int;
  v_secs    int := (p_inputs -> 'outputSpec' ->> 'durationTargetSec')::int;
  v_days    int := (p_inputs ->> 'retentionDays')::int;
  v_model   boolean := p_inputs ->> 'plannerChoice' = 'model';
  v_render  bigint;
  v_high    bigint;
  v_cap     bigint;
  v_class   text;
  v_min     int;
  v_hi_cr   int;
begin
  v_render := v_secs::bigint * v_angles * 1500;
  v_high := greatest((v_bytes * v_days * 500 + 1073741823) / 1073741824      -- storage, rounded up
                     + (v_bytes * 20 + 1048575) / 1048576                     -- ingest and normalize
                     + v_render
                     + case when v_model then 200000 else 0 end, 100000);
  v_cap := (v_high * 5 + 3) / 4;
  v_class := case when p_inputs ->> 'profileId' = 'match-broadcast' then 'broadcast-' else 'story-' end
             || case when v_angles = 1 then '1' when v_angles <= 3 then '2-3' else '4-6' end;
  v_min := case v_class when 'story-1' then 2 when 'story-2-3' then 4 when 'story-4-6' then 6
                        when 'broadcast-1' then 3 when 'broadcast-2-3' then 5 else 8 end;
  v_hi_cr := greatest(v_min, ((v_high + v_budget - 1) / v_budget)::int);
  return pg_catalog.jsonb_build_object(
    'filmClass', v_class,
    'estimateHighCostMicroUsd', v_high,
    'capCostMicroUsd', v_cap,
    'estimateLowCredits', least(v_hi_cr, greatest(1, ((v_high * 6 / 10 + v_budget - 1) / v_budget)::int)),
    'estimateHighCredits', v_hi_cr,
    'capCredits', greatest(v_min, ((v_cap + v_budget - 1) / v_budget)::int),
    'revisionCostMicroUsd', v_render,
    'lineItems', pg_catalog.jsonb_build_object(
      'sourceCount', v_angles, 'uploadBytes', v_bytes, 'storageDays', v_days, 'outputSeconds', v_secs,
      'renderMinutesEstimate', (v_secs * v_angles * 2 + 59) / 60,
      'plannerTokensEstimate', case when v_model then 60000 else 0 end));
end
$$;

-- 3. create_quote ----------------------------------------------------------------------------------------------------
-- The owner asks for a preflight of a plan (and version, or plan-by-job when null) and output. A re-quote of the
-- held work of a job that stopped at budget_exceeded supersedes that hold's quote, so its acceptance tops the hold up
-- instead of opening a second one (story 186). Quotes are Sample until a paid ADR exists (ADR-0013).
create function app_gateway.create_quote(p_actor uuid, p_project uuid, p_plan uuid, p_plan_version uuid,
                                         p_planner_choice text, p_output_spec jsonb, p_sources uuid[],
                                         p_retention_days int, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_project    public.projects := app_private.lock_owned_project(p_actor, p_project);
  v_inputs     jsonb;
  v_estimate   jsonb;
  v_hash       bytea;
  v_supersedes uuid;
  v_quote      public.quotes;
begin
  if p_planner_choice is null or p_planner_choice not in ('heuristic', 'model') then
    raise exception using errcode = 'P0422', message = 'invalid_value:planner_choice';
  end if;
  if p_retention_days is null or p_retention_days not in (1, 7, 30) then
    raise exception using errcode = 'P0422', message = 'invalid_value:retention_days';
  end if;
  if not app_private.output_spec_is_valid(p_output_spec) then
    raise exception using errcode = 'P0422', message = 'invalid_value:output_spec';
  end if;
  v_inputs := app_private.quote_inputs(v_project.id, p_plan, p_plan_version, p_planner_choice, p_output_spec,
                                       p_sources, p_retention_days);
  v_hash := app_private.output_spec_sha256(v_project.id, (v_inputs ->> 'planRevision')::int, p_output_spec);
  v_estimate := app_private.quote_estimate(v_inputs);
  select r.quote_id into v_supersedes from public.usage_reservations r
    join public.render_jobs j on j.id = r.job_id and j.project_id = r.project_id
   where r.project_id = v_project.id and r.story_plan_id = p_plan
     and r.story_plan_version_id is not distinct from p_plan_version and r.output_spec_sha256 = v_hash
     and r.state = 'held' and j.state = 'budget_exceeded';
  insert into public.quotes (project_id, owner_id, story_plan_id, story_plan_version_id, output_spec_sha256,
                             supersedes_quote_id, inputs, inputs_sha256, rates_version, line_items, planner_choice,
                             retention_days, estimate_low_credits, estimate_high_credits, cap_credits,
                             estimate_high_cost_micro_usd, cap_cost_micro_usd, expires_at, sample)
  values (v_project.id, p_actor, p_plan, p_plan_version, v_hash, v_supersedes, v_inputs,
          pg_catalog.sha256(pg_catalog.convert_to(v_inputs::text, 'UTF8')), v_inputs ->> 'ratesVersion',
          v_estimate -> 'lineItems', p_planner_choice, p_retention_days,
          (v_estimate ->> 'estimateLowCredits')::int, (v_estimate ->> 'estimateHighCredits')::int,
          (v_estimate ->> 'capCredits')::int, (v_estimate ->> 'estimateHighCostMicroUsd')::bigint,
          (v_estimate ->> 'capCostMicroUsd')::bigint, now() + interval '30 minutes', true)
  returning * into v_quote;
  perform app_private.write_audit('user', p_actor, v_project.id, 'quote.create', 'quote', v_quote.id, 'allowed', null,
                                  p_request_id, pg_catalog.jsonb_build_object('capCredits', v_quote.cap_credits));
  -- everything the owner may see; never the internal micro-USD cost
  return pg_catalog.jsonb_build_object(
    'quoteId', v_quote.id, 'state', v_quote.state, 'sample', v_quote.sample, 'filmClass', v_estimate ->> 'filmClass',
    'inputsSha256', pg_catalog.encode(v_quote.inputs_sha256, 'hex'),
    'estimate', pg_catalog.jsonb_build_object('minCredits', v_quote.estimate_low_credits,
                                              'maxCredits', v_quote.estimate_high_credits),
    'capCredits', v_quote.cap_credits, 'lineItems', v_quote.line_items, 'retentionDays', v_quote.retention_days,
    'plannerChoice', v_quote.planner_choice, 'expiresAt', v_quote.expires_at,
    'supersedesQuoteId', v_quote.supersedes_quote_id);
end
$$;

-- 4. accept_quote (architecture §7.2) ----------------------------------------------------------------------------------
create function app_gateway.accept_quote(p_actor uuid, p_quote uuid, p_inputs_sha256 bytea, p_consent jsonb,
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
  -- 3. a retry of this acceptance returns what it made (story 199); another key for the same quote is a conflict
  if v_quote.state = 'accepted' then
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

-- 5. review_job (architecture §7.1, security-model §13.6) ------------------------------------------------------------
-- Approve: the job goes on to the final render. Revise: a version of this job's own plan (else P0404, T-DB-59) that
-- fits in the hold's remaining reservation moves the job's and the hold's key (version and output hash) in one
-- transaction, so a later quote for the new version and the same output meets the existing hold; otherwise P0409
-- requote_required (a new quote and job with parent_job_id).
create function app_gateway.review_job(p_actor uuid, p_job uuid, p_decision text, p_plan_version uuid,
                                       p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_job   public.render_jobs;
  v_hold  public.usage_reservations;
  v_rev   int;
  v_state text;
  v_cost  bigint;
  v_hash  bytea;
begin
  select j.* into v_job from public.render_jobs j
    join public.projects p on p.id = j.project_id and p.owner_id = p_actor and p.deleted_at is null
   where j.id = p_job
   for update of j;
  if not found then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  if p_decision is null or p_decision not in ('approve', 'revise') then
    raise exception using errcode = 'P0422', message = 'invalid_value:decision';
  end if;
  if v_job.state <> 'awaiting_review' then
    raise exception using errcode = 'P0409', message = 'not_awaiting_review';
  end if;
  if p_decision = 'approve' then
    if p_plan_version is not null then
      raise exception using errcode = 'P0422', message = 'invalid_value:story_plan_version_id';
    end if;
    update public.render_jobs set state = 'final_rendering', reviewed_at = now() where id = v_job.id;
    perform app_private.write_audit('user', p_actor, v_job.project_id, 'job.review', 'render_job', v_job.id,
                                    'allowed', null, p_request_id, '{"decision": "approve"}'::jsonb);
    return pg_catalog.jsonb_build_object('state', 'final_rendering');
  end if;
  select v.version, v.validation_state into v_rev, v_state from public.story_plan_versions v
   where v.id = p_plan_version and v.story_plan_id = v_job.story_plan_id and v.project_id = v_job.project_id;
  if v_rev is null then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  if v_state = 'invalid' then
    raise exception using errcode = 'P0409', message = 'plan_invalid';
  end if;
  select r.* into v_hold from public.usage_reservations r
   where r.id = v_job.reservation_id and r.state = 'held'
   for update;
  if not found then
    raise exception using errcode = 'P0409', message = 'requote_required';
  end if;
  v_cost := (app_private.quote_estimate((select q.inputs from public.quotes q where q.id = v_hold.quote_id))
             ->> 'revisionCostMicroUsd')::bigint;
  if v_cost is null or v_cost > v_hold.cap_cost_micro_usd - v_hold.reserved_cost_micro_usd then
    raise exception using errcode = 'P0409', message = 'requote_required';
  end if;
  v_hash := app_private.output_spec_sha256(v_job.project_id, v_rev, v_job.output_spec);
  begin
    update public.render_jobs
       set story_plan_version_id = p_plan_version, output_spec_sha256 = v_hash, state = 'planning',
           reviewed_at = now()
     where id = v_job.id;
    update public.usage_reservations
       set story_plan_version_id = p_plan_version, output_spec_sha256 = v_hash
     where id = v_hold.id;
  exception when unique_violation then
    raise exception using errcode = 'P0409', message = 'requote_conflict';
  end;
  perform app_private.write_audit('user', p_actor, v_job.project_id, 'job.review', 'render_job', v_job.id, 'allowed',
                                  null, p_request_id, '{"decision": "revise"}'::jsonb);
  return pg_catalog.jsonb_build_object('state', 'planning');
end
$$;

-- 6. Function privileges ----------------------------------------------------------------------------------------------
revoke all on function
  app_private.commit_spend(uuid, uuid, text, bigint), app_private.output_spec_is_valid(jsonb),
  app_private.output_spec_sha256(uuid, int, jsonb),
  app_private.quote_inputs(uuid, uuid, uuid, text, jsonb, uuid[], int), app_private.quote_estimate(jsonb),
  app_gateway.create_quote(uuid, uuid, uuid, uuid, text, jsonb, uuid[], int, uuid),
  app_gateway.accept_quote(uuid, uuid, bytea, jsonb, int, text, uuid),
  app_gateway.review_job(uuid, uuid, text, uuid, uuid)
  from public, anon, authenticated, service_role;

grant execute on function
  app_gateway.create_quote(uuid, uuid, uuid, uuid, text, jsonb, uuid[], int, uuid),
  app_gateway.accept_quote(uuid, uuid, bytea, jsonb, int, text, uuid),
  app_gateway.review_job(uuid, uuid, text, uuid, uuid)
  to jovra_gateway;

-- 7. One owner (T-DB-66) ----------------------------------------------------------------------------------------------
alter function app_private.commit_spend(uuid, uuid, text, bigint) owner to jovra_owner;
alter function app_private.output_spec_is_valid(jsonb) owner to jovra_owner;
alter function app_private.output_spec_sha256(uuid, int, jsonb) owner to jovra_owner;
alter function app_private.quote_inputs(uuid, uuid, uuid, text, jsonb, uuid[], int) owner to jovra_owner;
alter function app_private.quote_estimate(jsonb) owner to jovra_owner;
alter function app_gateway.create_quote(uuid, uuid, uuid, uuid, text, jsonb, uuid[], int, uuid) owner to jovra_owner;
alter function app_gateway.accept_quote(uuid, uuid, bytea, jsonb, int, text, uuid) owner to jovra_owner;
alter function app_gateway.review_job(uuid, uuid, text, uuid, uuid) owner to jovra_owner;
