-- S80 / B-06 (orchestrator half, part 2): the render host's lease-fenced reads and writes (docs/backend/architecture.md
-- §5.1 internal routes, §6.1-§6.3; security-model.md §4.1 command table, §8.4, §13.1, §13.15; finding 13's database
-- half). The jovra-internal Worker calls these for a render host that presents an attempt's current lease token:
--   * authorize_output_upload_for_attempt: one upload session per planned output, only for an output ref in the
--     attempt's stored output_plan and never above that output's byte cap (finding 32); the output is a `writing`
--     artifact under its server-generated key until finish_attempt reports it;
--   * attach_upload_id_for_attempt, record_part_for_attempt, complete_upload_check_for_attempt and
--     mark_output_written_for_attempt: the session protocol of architecture §6.2-§6.3, with step 1 "the attempt's lease
--     is current" instead of a user or guest re-check; a session belongs to the attempt that opened it;
--   * authorize_attempt_input: a stage reads only what its attempt's stored input_refs list (computed by reserve_stage
--     from the job's own project), and a source only under the etag it was verified at (T-R2-15);
--   * authorize_artifact_read_for_attempt: the verify_output stage reads its listed inputs and the job's outputs that
--     wait for it to verify them, nothing else.
-- The user commands (authorize_upload, record_part, complete_upload_check, mark_uploaded_unverified) refuse these
-- sessions: they only ever lock a session of a source. Every command here is volatile, security definer, search_path
-- '', owned by jovra_owner and executable by jovra_orchestrator only (T-DB-04, T-DB-57). Refusals raise; the host
-- route then records them with audit_denial_for_attempt.

-- 1. Helpers -----------------------------------------------------------------------------------------------------------

-- The attempt, locked, when the lease hash is current, the attempt is running and its lease has not run out, its job
-- is not being canceled and its project is not deleted (architecture §7.3, §7.5).
create function app_private.lock_running_attempt(p_attempt uuid, p_lease_hash bytea) returns public.render_attempts
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_try public.render_attempts := app_private.lock_attempt(p_attempt, p_lease_hash);
begin
  if v_try.state <> 'running' then
    raise exception using errcode = 'P0409', message = 'not_running';
  end if;
  if v_try.leased_until <= now() then
    raise exception using errcode = 'P0409', message = 'lease_expired';
  end if;
  if exists (select 1 from public.render_jobs j where j.id = v_try.job_id and j.cancel_requested_at is not null) then
    raise exception using errcode = 'P0409', message = 'job_canceling';
  end if;
  if exists (select 1 from public.render_jobs j join public.projects p on p.id = j.project_id
              where j.id = v_try.job_id and p.deleted_at is not null) then
    raise exception using errcode = 'P0410', message = 'gone';
  end if;
  return v_try;
end
$$;

-- The upload session the attempt opened, locked; a session of a source or of another attempt is P0404.
create function app_private.lock_attempt_session(p_attempt uuid, p_session uuid) returns app_ops.upload_sessions
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_session app_ops.upload_sessions;
begin
  select u.* into v_session from app_ops.upload_sessions u
   where u.id = p_session and u.attempt_id = p_attempt and u.actor_kind = 'render_host'
   for update;
  if not found then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  return v_session;
end
$$;

-- Architecture §6.3 steps 3-4 for a session: parts exactly 1..part_count, full size except the last, summing to the
-- expected bytes, and the request's list equal to the stored one. Returns the stored list ({n, etag}), the only one
-- R2's complete() is given.
create function app_private.check_upload_parts(p_session app_ops.upload_sessions, p_parts jsonb) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_last  bigint := p_session.expected_bytes - (p_session.part_count - 1)::bigint * p_session.part_size;
  v_parts jsonb;
begin
  if (select pg_catalog.count(*) from app_ops.upload_parts up where up.session_id = p_session.id)
       <> p_session.part_count
     or exists (select 1 from pg_catalog.generate_series(1, p_session.part_count) n
                 where not exists (select 1 from app_ops.upload_parts up
                                    where up.session_id = p_session.id and up.part_number = n)) then
    raise exception using errcode = 'P0409', message = 'parts_incomplete';
  end if;
  if exists (select 1 from app_ops.upload_parts up
              where up.session_id = p_session.id
                and up.bytes <> case when up.part_number < p_session.part_count then p_session.part_size
                                     else v_last end)
     or (select pg_catalog.sum(up.bytes) from app_ops.upload_parts up where up.session_id = p_session.id)
        <> p_session.expected_bytes then
    raise exception using errcode = 'P0409', message = 'part_size_mismatch';
  end if;
  select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('n', up.part_number, 'etag', up.etag)
                              order by up.part_number)
    into v_parts from app_ops.upload_parts up where up.session_id = p_session.id;
  if pg_catalog.jsonb_typeof(p_parts) is distinct from 'array' or pg_catalog.jsonb_array_length(p_parts) > 10000
     or exists (select 1 from pg_catalog.jsonb_array_elements(p_parts) e
                 where pg_catalog.jsonb_typeof(e) is distinct from 'object'
                    or pg_catalog.jsonb_typeof(e -> 'n') is distinct from 'number'
                    or pg_catalog.jsonb_typeof(e -> 'etag') is distinct from 'string') then
    raise exception using errcode = 'P0422', message = 'invalid_value:parts';
  end if;
  if (select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('n', e -> 'n', 'etag', e -> 'etag')
                                  order by (e ->> 'n')::numeric)
        from pg_catalog.jsonb_array_elements(p_parts) e) is distinct from v_parts then
    raise exception using errcode = 'P0409', message = 'parts_mismatch';
  end if;
  return v_parts;
end
$$;

-- What a session returns to the host route: never a capability (the lease token is the host's only credential).
create function app_private.output_session_json(p_session app_ops.upload_sessions, p_bucket text, p_replayed boolean)
returns jsonb language sql immutable set search_path = '' as $$
  select pg_catalog.jsonb_build_object('sessionId', p_session.id, 'artifactId', p_session.artifact_id,
           'outputRef', p_session.output_ref, 'bucketClass', p_bucket, 'r2Key', p_session.r2_key,
           'partSize', p_session.part_size, 'partCount', p_session.part_count, 'state', p_session.state,
           'expiresAt', p_session.expires_at, 'hardExpiresAt', p_session.hard_expires_at, 'replayed', p_replayed)
$$;

-- 2. authorize_output_upload_for_attempt (architecture §5.1 POST /internal/v1/attempts/{id}/outputs) ----------------
-- The output ref must be in the attempt's stored output_plan and the declared bytes within that entry's maxBytes; the
-- kind, bucket and key come from the plan and the server, never from the host. The same declaration again returns the
-- same open session (a redelivered request); a different one, or one for an output already written or whose session
-- was closed, is refused: the next attempt of the stage writes under its own keys.
create function app_gateway.authorize_output_upload_for_attempt(p_attempt uuid, p_lease_hash bytea, p_output_ref text,
                                                                p_bytes bigint, p_sha256 bytea, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_try     public.render_attempts := app_private.lock_running_attempt(p_attempt, p_lease_hash);
  v_job     public.render_jobs;
  v_plan    jsonb;
  v_kind    text;
  v_session app_ops.upload_sessions;
  v_art     uuid := gen_random_uuid();
  v_id      uuid := gen_random_uuid();
begin
  select e into v_plan from pg_catalog.jsonb_array_elements(v_try.output_plan) e
   where e ->> 'outputRef' = p_output_ref;
  if p_output_ref is null or v_plan is null then
    raise exception using errcode = 'P0422', message = 'output_not_in_plan';
  end if;
  if p_bytes is null or p_bytes <= 0 then
    raise exception using errcode = 'P0422', message = 'invalid_value:declared_bytes';
  end if;
  if p_bytes > (v_plan ->> 'maxBytes')::bigint then
    raise exception using errcode = 'P0422', message = 'output_over_cap';
  end if;
  perform app_private.check_sha256(p_sha256, 'declared_sha256');
  v_kind := v_plan ->> 'kind';

  select u.* into v_session from app_ops.upload_sessions u
   where u.attempt_id = v_try.id and u.output_ref = p_output_ref
   for update;
  if found then
    if v_session.expected_bytes <> p_bytes or v_session.expected_sha256 <> p_sha256 then
      raise exception using errcode = 'P0409', message = 'declaration_mismatch';
    end if;
    if v_session.state in ('completing', 'completed') then
      raise exception using errcode = 'P0409', message = 'output_already_written';
    end if;
    if v_session.state not in ('opening', 'open') then
      raise exception using errcode = 'P0409', message = 'output_session_closed';
    end if;
    return app_private.output_session_json(v_session, app_private.output_bucket(v_kind), true);
  end if;

  select j.* into v_job from public.render_jobs j where j.id = v_try.job_id;
  insert into public.artifacts (id, project_id, job_id, attempt_id, kind, bucket_class, r2_key, state, sample)
  values (v_art, v_job.project_id, v_job.id, v_try.id, v_kind::public.artifact_kind, app_private.output_bucket(v_kind),
          app_private.output_r2_key(v_kind, v_job.project_id, v_job.id, v_try.id, p_output_ref, v_art), 'writing',
          v_job.sample);
  insert into app_ops.upload_sessions (id, project_id, artifact_id, attempt_id, output_ref, actor_kind, actor_id, r2_key,
                                       expected_bytes, expected_sha256, part_count, state, expires_at, hard_expires_at)
  select v_id, a.project_id, a.id, v_try.id, p_output_ref, 'render_host', v_try.id, a.r2_key, p_bytes, p_sha256,
         (p_bytes + 33554431) / 33554432, 'opening', now() + interval '24 hours', now() + interval '48 hours'
    from public.artifacts a where a.id = v_art
  returning * into v_session;
  perform app_private.write_audit('orchestrator', null, v_job.project_id, 'attempt.output_authorize', 'upload_session',
                                  v_session.id, 'allowed', null, p_request_id,
                                  pg_catalog.jsonb_build_object('attemptId', v_try.id, 'outputRef', p_output_ref,
                                                                'kind', v_kind));
  return app_private.output_session_json(v_session, app_private.output_bucket(v_kind), false);
end
$$;

-- 3. attach_upload_id_for_attempt: after createMultipartUpload on the output's key, the route records the upload id.
create function app_gateway.attach_upload_id_for_attempt(p_attempt uuid, p_lease_hash bytea, p_session uuid,
                                                         p_r2_upload_id text, p_request_id uuid)
returns timestamptz language plpgsql volatile security definer set search_path = '' as $$
declare
  v_try     public.render_attempts := app_private.lock_running_attempt(p_attempt, p_lease_hash);
  v_session app_ops.upload_sessions := app_private.lock_attempt_session(v_try.id, p_session);
begin
  if v_session.state <> 'opening' then
    raise exception using errcode = 'P0409', message = 'session_not_opening';
  end if;
  if p_r2_upload_id is null or pg_catalog.char_length(p_r2_upload_id) not between 1 and 1024 then
    raise exception using errcode = 'P0422', message = 'invalid_value:r2_upload_id';
  end if;
  update app_ops.upload_sessions set r2_upload_id = p_r2_upload_id, state = 'open' where id = v_session.id;
  return v_session.expires_at;
end
$$;

-- 4. record_part_for_attempt: as record_part (architecture §6.3 step 5), under the attempt's lease.
create function app_gateway.record_part_for_attempt(p_attempt uuid, p_lease_hash bytea, p_session uuid,
                                                    p_part_number int, p_bytes int, p_etag text, p_sha256 bytea,
                                                    p_client_sha256 bytea, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_try     public.render_attempts := app_private.lock_running_attempt(p_attempt, p_lease_hash);
  v_session app_ops.upload_sessions := app_private.lock_attempt_session(v_try.id, p_session);
  v_expect  bigint;
begin
  if v_session.state <> 'open' then
    raise exception using errcode = 'P0409', message = 'session_not_open';
  end if;
  if v_session.expires_at <= now() or v_session.hard_expires_at <= now() then
    raise exception using errcode = 'P0410', message = 'session_expired';
  end if;
  if p_part_number is null or p_part_number < 1 or p_part_number > v_session.part_count then
    raise exception using errcode = 'P0422', message = 'invalid_value:part_number';
  end if;
  v_expect := case when p_part_number < v_session.part_count then v_session.part_size
                   else v_session.expected_bytes - (v_session.part_count - 1)::bigint * v_session.part_size end;
  if p_bytes is distinct from v_expect then
    raise exception using errcode = 'P0422', message = 'invalid_value:part_bytes';
  end if;
  perform app_private.check_sha256(p_sha256, 'part_sha256');
  if p_client_sha256 is distinct from p_sha256 then
    raise exception using errcode = 'P0422', message = 'part_digest_mismatch';
  end if;
  if p_etag is null or pg_catalog.char_length(p_etag) not between 1 and 128 then
    raise exception using errcode = 'P0422', message = 'invalid_value:etag';
  end if;
  insert into app_ops.upload_parts as up (session_id, part_number, bytes, etag, sha256)
  values (v_session.id, p_part_number, p_bytes, p_etag, p_sha256)
  on conflict (session_id, part_number)
  do update set bytes = excluded.bytes, etag = excluded.etag, sha256 = excluded.sha256, received_at = now();
  update app_ops.upload_sessions
     set expires_at = least(now() + interval '24 hours', hard_expires_at)
   where id = v_session.id;
  return pg_catalog.jsonb_build_object('n', p_part_number, 'bytes', p_bytes, 'etag', p_etag);
end
$$;

-- 5. complete_upload_check_for_attempt (architecture §6.3, step 1 "attempt lease current"): the output is still this
-- attempt's writing artifact in the session's own live project; then steps 3-4 on the stored parts.
create function app_gateway.complete_upload_check_for_attempt(p_attempt uuid, p_lease_hash bytea, p_session uuid,
                                                              p_parts jsonb, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_try     public.render_attempts := app_private.lock_running_attempt(p_attempt, p_lease_hash);
  v_session app_ops.upload_sessions := app_private.lock_attempt_session(v_try.id, p_session);
  v_parts   jsonb;
begin
  if v_session.state <> 'open' then
    raise exception using errcode = 'P0409', message = 'session_not_open';
  end if;
  if v_session.expires_at <= now() or v_session.hard_expires_at <= now() then
    raise exception using errcode = 'P0410', message = 'session_expired';
  end if;
  perform 1 from public.artifacts a
   where a.id = v_session.artifact_id and a.project_id = v_session.project_id and a.job_id = v_try.job_id
     and a.attempt_id = v_try.id and a.state = 'writing' and a.deleted_at is null
   for update;
  if not found then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  v_parts := app_private.check_upload_parts(v_session, p_parts);
  update app_ops.upload_sessions set state = 'completing' where id = v_session.id;
  return pg_catalog.jsonb_build_object('r2Key', v_session.r2_key, 'uploadId', v_session.r2_upload_id,
                                       'parts', v_parts);
end
$$;

-- 6. mark_output_written_for_attempt (step 7): R2's head size equals the declaration. The artifact keeps state
-- writing, now with its bytes and declared SHA-256, until finish_attempt reports it (then verifying; the
-- verify_output stage decodes it and only mark_artifact_verified makes it ready).
create function app_gateway.mark_output_written_for_attempt(p_attempt uuid, p_lease_hash bytea, p_session uuid,
                                                            p_object_bytes bigint, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_try     public.render_attempts := app_private.lock_running_attempt(p_attempt, p_lease_hash);
  v_session app_ops.upload_sessions := app_private.lock_attempt_session(v_try.id, p_session);
begin
  if v_session.state <> 'completing' then
    raise exception using errcode = 'P0409', message = 'session_not_completing';
  end if;
  if p_object_bytes is distinct from v_session.expected_bytes then
    raise exception using errcode = 'P0409', message = 'size_mismatch';
  end if;
  update public.artifacts set bytes = v_session.expected_bytes, sha256 = v_session.expected_sha256
   where id = v_session.artifact_id and attempt_id = v_try.id and state = 'writing';
  if not found then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  update app_ops.upload_sessions set state = 'completed', completed_at = now() where id = v_session.id;
  perform app_private.write_audit('orchestrator', null, v_session.project_id, 'attempt.output_written', 'artifact',
                                  v_session.artifact_id, 'allowed', null, p_request_id,
                                  pg_catalog.jsonb_build_object('attemptId', v_try.id,
                                                                'outputRef', v_session.output_ref));
  return pg_catalog.jsonb_build_object('artifactId', v_session.artifact_id, 'outputRef', v_session.output_ref,
                                       'bytes', v_session.expected_bytes, 'state', 'writing');
end
$$;

-- 7. authorize_attempt_input (architecture §5.1 GET /internal/v1/attempts/{id}/inputs/{inputRef}): the input must be
-- listed in the attempt's stored input_refs (nothing from the queue message or the host is consulted) and still be
-- what it was when listed: a source still verified, read under its verified etag (T-R2-15); an artifact of this job
-- still ready. Returned only to jovra-internal.
create function app_gateway.authorize_attempt_input(p_attempt uuid, p_lease_hash bytea, p_input_ref uuid,
                                                    p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_try    public.render_attempts := app_private.lock_running_attempt(p_attempt, p_lease_hash);
  v_ref    jsonb;
  v_source public.camera_sources;
  v_art    public.artifacts;
begin
  select e into v_ref from pg_catalog.jsonb_array_elements(v_try.input_refs) e where e ->> 'id' = p_input_ref::text;
  if p_input_ref is null or v_ref is null then
    raise exception using errcode = 'P0404', message = 'input_not_listed';
  end if;
  if v_ref ->> 'kind' = 'source' then
    select s.* into v_source from public.camera_sources s
      join public.render_jobs j on j.project_id = s.project_id and j.id = v_try.job_id
     where s.id = p_input_ref;
    if not found or v_source.state <> 'verified' or v_source.r2_key is null or v_source.verified_etag is null then
      raise exception using errcode = 'P0410', message = 'gone';
    end if;
    return pg_catalog.jsonb_build_object('inputRef', v_source.id, 'kind', 'source', 'bucketClass', 'work',
                                         'r2Key', v_source.r2_key, 'verifiedEtag', v_source.verified_etag,
                                         'bytes', v_source.declared_bytes,
                                         'sha256', pg_catalog.encode(v_source.verified_sha256, 'hex'));
  end if;
  select a.* into v_art from public.artifacts a
    join public.render_jobs j on j.project_id = a.project_id and j.id = v_try.job_id
   where a.id = p_input_ref and a.job_id = v_try.job_id;
  if not found or v_art.state <> 'ready' or v_art.deleted_at is not null then
    raise exception using errcode = 'P0410', message = 'gone';
  end if;
  return pg_catalog.jsonb_build_object('inputRef', v_art.id, 'kind', v_art.kind, 'bucketClass', v_art.bucket_class,
                                       'r2Key', v_art.r2_key, 'bytes', v_art.bytes,
                                       'sha256', pg_catalog.encode(v_art.sha256, 'hex'));
end
$$;

-- 8. authorize_artifact_read_for_attempt (security-model §4.1): the render-attempt twin of authorize_artifact_read.
-- Only the verify_output stage reads artifacts this way, and only an artifact of its own job that is either listed in
-- its input_refs (and still ready) or an output another attempt of the job wrote that waits for verification. Every
-- other stage reads through authorize_attempt_input; another job's or project's artifact, a writing or failed output
-- and a deleted one are P0404.
create function app_gateway.authorize_artifact_read_for_attempt(p_attempt uuid, p_lease_hash bytea, p_artifact uuid,
                                                                p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_try public.render_attempts := app_private.lock_running_attempt(p_attempt, p_lease_hash);
  v_art public.artifacts;
begin
  if v_try.stage <> 'verify_output' then
    raise exception using errcode = 'P0409', message = 'not_verify_stage';
  end if;
  select a.* into v_art from public.artifacts a
    join public.render_jobs j on j.project_id = a.project_id and j.id = v_try.job_id
   where a.id = p_artifact and a.job_id = v_try.job_id and a.deleted_at is null;
  if not found
     or not ((v_art.state = 'ready'
              and v_try.input_refs @> pg_catalog.jsonb_build_array(
                    pg_catalog.jsonb_build_object('kind', 'artifact', 'id', v_art.id::text)))
             or (v_art.state = 'verifying' and v_art.attempt_id is distinct from v_try.id)) then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  return pg_catalog.jsonb_build_object('artifactId', v_art.id, 'kind', v_art.kind, 'state', v_art.state,
                                       'bucketClass', v_art.bucket_class, 'r2Key', v_art.r2_key,
                                       'bytes', v_art.bytes, 'sha256', pg_catalog.encode(v_art.sha256, 'hex'));
end
$$;

-- 9. Function privileges: the orchestrator's alone (T-DB-04, T-DB-57) ------------------------------------------------
revoke all on function
  app_private.lock_running_attempt(uuid, bytea),
  app_private.lock_attempt_session(uuid, uuid),
  app_private.check_upload_parts(app_ops.upload_sessions, jsonb),
  app_private.output_session_json(app_ops.upload_sessions, text, boolean),
  app_gateway.authorize_output_upload_for_attempt(uuid, bytea, text, bigint, bytea, uuid),
  app_gateway.attach_upload_id_for_attempt(uuid, bytea, uuid, text, uuid),
  app_gateway.record_part_for_attempt(uuid, bytea, uuid, int, int, text, bytea, bytea, uuid),
  app_gateway.complete_upload_check_for_attempt(uuid, bytea, uuid, jsonb, uuid),
  app_gateway.mark_output_written_for_attempt(uuid, bytea, uuid, bigint, uuid),
  app_gateway.authorize_attempt_input(uuid, bytea, uuid, uuid),
  app_gateway.authorize_artifact_read_for_attempt(uuid, bytea, uuid, uuid)
  from public, anon, authenticated, service_role;

grant execute on function
  app_gateway.authorize_output_upload_for_attempt(uuid, bytea, text, bigint, bytea, uuid),
  app_gateway.attach_upload_id_for_attempt(uuid, bytea, uuid, text, uuid),
  app_gateway.record_part_for_attempt(uuid, bytea, uuid, int, int, text, bytea, bytea, uuid),
  app_gateway.complete_upload_check_for_attempt(uuid, bytea, uuid, jsonb, uuid),
  app_gateway.mark_output_written_for_attempt(uuid, bytea, uuid, bigint, uuid),
  app_gateway.authorize_attempt_input(uuid, bytea, uuid, uuid),
  app_gateway.authorize_artifact_read_for_attempt(uuid, bytea, uuid, uuid)
  to jovra_orchestrator;

-- 10. One owner (T-DB-66) --------------------------------------------------------------------------------------------
alter function app_private.lock_running_attempt(uuid, bytea) owner to jovra_owner;
alter function app_private.lock_attempt_session(uuid, uuid) owner to jovra_owner;
alter function app_private.check_upload_parts(app_ops.upload_sessions, jsonb) owner to jovra_owner;
alter function app_private.output_session_json(app_ops.upload_sessions, text, boolean) owner to jovra_owner;
alter function app_gateway.authorize_output_upload_for_attempt(uuid, bytea, text, bigint, bytea, uuid)
  owner to jovra_owner;
alter function app_gateway.attach_upload_id_for_attempt(uuid, bytea, uuid, text, uuid) owner to jovra_owner;
alter function app_gateway.record_part_for_attempt(uuid, bytea, uuid, int, int, text, bytea, bytea, uuid)
  owner to jovra_owner;
alter function app_gateway.complete_upload_check_for_attempt(uuid, bytea, uuid, jsonb, uuid) owner to jovra_owner;
alter function app_gateway.mark_output_written_for_attempt(uuid, bytea, uuid, bigint, uuid) owner to jovra_owner;
alter function app_gateway.authorize_attempt_input(uuid, bytea, uuid, uuid) owner to jovra_owner;
alter function app_gateway.authorize_artifact_read_for_attempt(uuid, bytea, uuid, uuid) owner to jovra_owner;
