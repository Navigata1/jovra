-- S79 / B-06 (gateway half), part 1: the user-route commands the gateway calls as jovra_gateway for projects,
-- sources, camera invites, uploads, grants, share links and deletion requests, plus audit_denial
-- (docs/backend/architecture.md §5.1, §6.2, §6.3, §10; security-model.md §4.1, §13.1, §13.2, §13.4, §13.8).
--
-- Every command follows the security-model §4.1 template:
--   1. re-check the actor against current rows (ownership, membership, invite, session) with FOR UPDATE where state
--      changes; an unrelated or unknown actor is P0404, identical to a missing object (T-DB-33);
--   2. validate every input against server-held expectations; never accept keys, prices or roles from the caller;
--   3. perform the transition and write app_ops.audit_events ('allowed') in the same transaction;
--   4. raise coded errors: P0401 unauthorized, P0404 not_found, P0409 conflict, P0410 expired, P0422 invalid,
--      P0429 quota. A raised command rolls its own audit row back, so the gateway records denials with a second call
--      to app_gateway.audit_denial (append only).
-- Every command is volatile (T-DB-03, the Hyperdrive caching backstop), security definer, search_path '', owned by
-- jovra_owner, and executable by jovra_gateway only, never by jovra_orchestrator or a client role (T-DB-04, T-DB-57).
-- The orchestrator commands (set_job_state, reserve_stage, claim/finish_attempt, the *_for_attempt upload variants)
-- are S80. Part 2 (20261008041000_gateway_commands_money.sql) holds create_quote, accept_quote and review_job.

-- 1. Environment setting and new columns --------------------------------------------------------------------------
-- The environment name is a row written per environment (the local seed writes 'local'; the operator writes 'test'
-- or 'live' at G1), never a request or session value (security-model §13.3). No row reads as 'test', so a missing
-- row fails closed: accept_quote then requires the tester flag.
create table app_ops.settings (
  id         boolean primary key default true check (id),   -- exactly one row
  env        text not null check (env in ('local', 'test', 'live')),
  updated_at timestamptz not null default now()
);
alter table app_ops.settings enable row level security;
revoke all on app_ops.settings from public, anon, authenticated, service_role;
create trigger a05_refuse_secrets before insert or update on app_ops.settings
  for each row execute function app_private.refuse_secrets();

-- The guest capability (jvg_ token) is minted by the gateway and stored only as its SHA-256; it is replaced (so the
-- earlier one stops working) by every issue_guest_capability. Never granted to a client (camera_invites grants are
-- column-scoped, migration 1).
alter table public.camera_invites
  add column capability_hash bytea unique check (octet_length(capability_hash) = 32);

-- 2. Helpers -----------------------------------------------------------------------------------------------------------

-- Facts about an Auth user that only the auth schema holds: the email when (and only when) it is confirmed, whether
-- the user is anonymous, and when the named Auth session was created (re-authentication, §13.4). jovra_owner cannot
-- read the auth schema, so this one helper keeps the migration owner, like the S75 hook functions (T-DB-66 names
-- it), and only jovra_owner may execute it. It never stores or logs anything.
create function app_private.auth_user_facts(p_user uuid, p_session uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select pg_catalog.jsonb_build_object(
           'confirmedEmail', case when u.email_confirmed_at is not null then u.email end,
           'anonymous', coalesce(u.is_anonymous, false),
           'sessionCreatedAt', (select s.created_at from auth.sessions s
                                 where s.id = p_session and s.user_id = u.id))
    from auth.users u
   where u.id = p_user
$$;
revoke all on function app_private.auth_user_facts(uuid, uuid) from public, anon, authenticated, service_role;
grant execute on function app_private.auth_user_facts(uuid, uuid) to jovra_owner;
-- create_grant and redeem_grant (owned by jovra_owner) bind invitations to an email HMAC (§13.2).
grant execute on function app_private.email_hmac(text) to jovra_owner;

-- 'local' | 'test' | 'live'; no row is 'test' (fail closed).
create function app_private.jovra_env() returns text
language sql stable security definer set search_path = '' as $$
  select coalesce((select s.env from app_ops.settings s where s.id), 'test')
$$;

-- Six decimal digits derived from a seed: the device code both phones show (from the device key thumbprint) and the
-- code a pending coach reads to the owner. Big-endian first four bytes of SHA-256, modulo 10^6, zero-padded.
create function app_private.six_digits(p_seed bytea) returns text
language sql immutable set search_path = '' as $$
  select pg_catalog.lpad(((pg_catalog.get_byte(h, 0)::bigint * 16777216 + pg_catalog.get_byte(h, 1) * 65536
                           + pg_catalog.get_byte(h, 2) * 256 + pg_catalog.get_byte(h, 3)) % 1000000)::text, 6, '0')
    from (select pg_catalog.sha256(p_seed) as h) x
$$;

-- What a project owner sees of a pending coach: the verified email masked (j•••@e•••.com), never display_name.
create function app_private.mask_email(p_email text) returns text
language sql immutable set search_path = '' as $$
  select case when p_email is null or pg_catalog.strpos(p_email, '@') = 0 then null else
    pg_catalog.left(pg_catalog.split_part(p_email, '@', 1), 1) || '•••@'
    || pg_catalog.left(pg_catalog.split_part(p_email, '@', 2), 1) || '•••'
    || case when pg_catalog.strpos(pg_catalog.split_part(p_email, '@', 2), '.') > 0
            then '.' || pg_catalog.reverse(pg_catalog.split_part(pg_catalog.reverse(p_email), '.', 1))
            else '' end
  end
$$;

-- The approval code of a project_coach redemption: bound to the grant, the redeemer and the redemption time.
create function app_private.member_approval_code(p_grant uuid, p_user uuid, p_redeemed_at timestamptz) returns text
language sql immutable set search_path = '' as $$
  select app_private.six_digits(pg_catalog.convert_to(
           p_grant::text || ':' || p_user::text || ':'
           || (extract(epoch from p_redeemed_at) * 1000000)::bigint::text, 'UTF8'))
$$;

-- A real (non-anonymous) user with a profile, else P0401.
create function app_private.require_real_user(p_actor uuid) returns void
language plpgsql stable security definer set search_path = '' as $$
declare
  v_facts jsonb := app_private.auth_user_facts(p_actor, null);
begin
  if p_actor is null or v_facts is null or (v_facts ->> 'anonymous')::boolean
     or not exists (select 1 from public.profiles p where p.id = p_actor) then
    raise exception using errcode = 'P0401', message = 'unauthorized';
  end if;
end
$$;

-- The project, locked, when p_actor owns it and its deletion has not started; else P0404.
create function app_private.lock_owned_project(p_actor uuid, p_project uuid) returns public.projects
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_project public.projects;
begin
  select p.* into v_project from public.projects p
   where p.id = p_project and p.owner_id = p_actor and p.deleted_at is null
   for update;
  if not found or p_actor is null then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  return v_project;
end
$$;

-- An upload actor is still authorized right now (architecture §6.3 step 1): the owner still owns the live project,
-- or the guest's invite is approved, unrevoked, its capability unexpired, and the source is the invite's own.
create function app_private.upload_actor_ok(p_kind text, p_actor uuid, p_project uuid, p_source uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(case p_kind
    when 'owner' then exists (select 1 from public.projects p
                               where p.id = p_project and p.owner_id = p_actor and p.deleted_at is null)
    when 'camera_guest' then exists (
      select 1 from public.camera_invites i
        join public.projects p on p.id = i.project_id and p.deleted_at is null
        join public.camera_sources s on s.invite_id = i.id and s.project_id = i.project_id
       where i.id = p_actor and i.project_id = p_project and s.id = p_source
         and i.approved_at is not null and i.revoked_at is null and i.capability_hash is not null
         and i.capability_expires_at > now())
    else false
  end, false)
$$;

-- Coded validation for command arguments (security-model §9: the column is named, never the value).
create function app_private.check_sha256(p_value bytea, p_column text) returns void
language plpgsql immutable set search_path = '' as $$
begin
  if p_value is null or pg_catalog.octet_length(p_value) <> 32 then
    raise exception using errcode = 'P0422', message = 'invalid_value:' || p_column;
  end if;
end
$$;

-- 3. audit_denial (security-model §4.1): the gateway's second call after a command raised. Append only: it writes one
-- denied row and reads or changes nothing else, so it cannot be used to probe rows. The target's project is not
-- resolved for the same reason.
create function app_gateway.audit_denial(p_actor_kind text, p_actor uuid, p_action text, p_target_kind text,
                                         p_target uuid, p_reason text, p_request_id uuid)
returns void language plpgsql volatile security definer set search_path = '' as $$
begin
  if p_actor_kind is null or p_actor_kind not in ('user', 'camera_guest', 'gateway') then
    raise exception using errcode = 'P0422', message = 'invalid_value:actor_kind';
  end if;
  if p_action is null or pg_catalog.char_length(p_action) > 64 or p_action !~ '^[a-z_]+(\.[a-z_]+)+$' then
    raise exception using errcode = 'P0422', message = 'invalid_value:action';
  end if;
  if p_target_kind is not null and p_target_kind !~ '^[a-z_]{1,40}$' then
    raise exception using errcode = 'P0422', message = 'invalid_value:target_kind';
  end if;
  if p_reason is null or p_reason !~ '^[a-z0-9_]{1,64}$' then
    raise exception using errcode = 'P0422', message = 'invalid_value:reason';
  end if;
  perform app_private.write_audit(p_actor_kind, p_actor, null, p_action, p_target_kind, p_target, 'denied', p_reason,
                                  p_request_id);
end
$$;

-- 4. Projects and sources ------------------------------------------------------------------------------------------
-- create_project: a real user creates a project; a retry with the same local id returns the same project (story
-- 199). Server-path inserts skip the PostgREST quota trigger, so the daily projects quota is applied here.
create function app_gateway.create_project(p_actor uuid, p_local_project uuid, p_title text, p_kind text,
                                           p_sample boolean, p_request_id uuid)
returns uuid language plpgsql volatile security definer set search_path = '' as $$
declare
  v_project public.projects;
  v_limit   int;
begin
  perform app_private.require_real_user(p_actor);
  if p_local_project is null then
    raise exception using errcode = 'P0422', message = 'required:local_project_id';
  end if;
  select p.* into v_project from public.projects p
   where p.owner_id = p_actor and p.local_project_id = p_local_project
   for update;
  if found then
    if v_project.deleted_at is not null then
      raise exception using errcode = 'P0409', message = 'project_deleted';
    end if;
    return v_project.id;
  end if;
  select q.max_rows_per_day into v_limit from app_ops.quota_limits q where q.table_name = 'projects';
  if v_limit is null or (select pg_catalog.count(*) from public.projects p
                          where p.owner_id = p_actor
                            and p.created_at >= pg_catalog.date_trunc('day', now(), 'UTC')) >= v_limit then
    raise exception using errcode = 'P0429', message = 'quota_exceeded';
  end if;
  insert into public.projects (owner_id, local_project_id, title, kind, sample)
  values (p_actor, p_local_project, coalesce(p_title, ''), coalesce(p_kind, 'match'), coalesce(p_sample, false))
  returning * into v_project;
  perform app_private.write_audit('user', p_actor, v_project.id, 'project.create', 'project', v_project.id, 'allowed',
                                  null, p_request_id);
  return v_project.id;
end
$$;

-- declare_source: the owner declares one of their own sources from the local manifest. The client probe is stored
-- as client_probe (allowlisted by the table's validation), never as probe. Idempotent per local source id.
create function app_gateway.declare_source(p_actor uuid, p_project uuid, p_slot public.camera_slot,
                                           p_local_source uuid, p_bytes bigint, p_sha256 bytea, p_client_probe jsonb,
                                           p_request_id uuid)
returns uuid language plpgsql volatile security definer set search_path = '' as $$
declare
  v_project public.projects := app_private.lock_owned_project(p_actor, p_project);
  v_source  public.camera_sources;
begin
  if p_slot is null or p_local_source is null then
    raise exception using errcode = 'P0422', message = 'required:source';
  end if;
  if p_bytes is null or p_bytes <= 0 or p_bytes > 8589934592 then   -- 8 GiB per original (INFERRED cap)
    raise exception using errcode = 'P0422', message = 'invalid_value:declared_bytes';
  end if;
  perform app_private.check_sha256(p_sha256, 'declared_sha256');
  select s.* into v_source from public.camera_sources s
   where s.project_id = v_project.id and s.local_source_id = p_local_source and s.state <> 'deleted';
  if found then
    if v_source.slot = p_slot and v_source.declared_bytes = p_bytes and v_source.declared_sha256 = p_sha256
       and v_source.invite_id is null then
      return v_source.id;   -- a retry of the same declaration
    end if;
    raise exception using errcode = 'P0409', message = 'source_conflict';
  end if;
  if exists (select 1 from public.camera_sources s
              where s.project_id = v_project.id and s.slot = p_slot and s.state <> 'deleted')
     or exists (select 1 from public.camera_invites i
                 where i.project_id = v_project.id and i.slot = p_slot and i.revoked_at is null
                   and ((i.redeemed_at is null and i.redeem_by > now())
                        or (i.redeemed_at is not null
                            and (i.capability_expires_at is null or i.capability_expires_at > now())))) then
    raise exception using errcode = 'P0409', message = 'slot_taken';
  end if;
  insert into public.camera_sources (project_id, slot, local_source_id, uploader_user_id, state, declared_bytes,
                                     declared_sha256, client_probe)
  values (v_project.id, p_slot, p_local_source, p_actor, 'declared', p_bytes, p_sha256,
          coalesce(p_client_probe, '{}'::jsonb))
  returning * into v_source;
  perform app_private.write_audit('user', p_actor, v_project.id, 'source.declare', 'camera_source', v_source.id,
                                  'allowed', null, p_request_id);
  return v_source.id;
end
$$;

-- 5. Camera invites (architecture §5.1, security-model §8.2) ---------------------------------------------------------
create function app_gateway.create_camera_invite(p_actor uuid, p_project uuid, p_slot public.camera_slot,
                                                 p_label text, p_code_hash bytea, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_project public.projects := app_private.lock_owned_project(p_actor, p_project);
  v_invite  public.camera_invites;
begin
  if p_slot is null then
    raise exception using errcode = 'P0422', message = 'required:slot';
  end if;
  perform app_private.check_len(p_label, 60, 'display_label');
  perform app_private.check_sha256(p_code_hash, 'code_hash');
  -- an expired, unredeemed invite gives its slot back (the open-invite index cannot hold now())
  update public.camera_invites i set revoked_at = now()
   where i.project_id = v_project.id and i.slot = p_slot and i.revoked_at is null and i.redeemed_at is null
     and i.redeem_by <= now();
  if exists (select 1 from public.camera_sources s
              where s.project_id = v_project.id and s.slot = p_slot and s.state <> 'deleted')
     or exists (select 1 from public.camera_invites i
                 where i.project_id = v_project.id and i.slot = p_slot and i.revoked_at is null
                   and (i.redeemed_at is null
                        or i.capability_expires_at is null or i.capability_expires_at > now())) then
    raise exception using errcode = 'P0409', message = 'slot_taken';
  end if;
  if (select pg_catalog.count(*) from public.camera_invites i
       where i.project_id = v_project.id and i.revoked_at is null
         and ((i.redeemed_at is null and i.redeem_by > now())
              or (i.redeemed_at is not null
                  and (i.capability_expires_at is null or i.capability_expires_at > now())))) >= 5 then
    raise exception using errcode = 'P0409', message = 'too_many_invites';
  end if;
  if exists (select 1 from public.camera_invites i where i.code_hash = p_code_hash) then
    raise exception using errcode = 'P0409', message = 'code_conflict';
  end if;
  insert into public.camera_invites (project_id, slot, display_label, code_hash, created_by, redeem_by)
  values (v_project.id, p_slot, coalesce(p_label, ''), p_code_hash, p_actor, now() + interval '10 minutes')
  returning * into v_invite;
  perform app_private.write_audit('user', p_actor, v_project.id, 'camera_invite.create', 'camera_invite', v_invite.id,
                                  'allowed', null, p_request_id);
  return pg_catalog.jsonb_build_object('inviteId', v_invite.id, 'redeemBy', v_invite.redeem_by);
end
$$;

create function app_gateway.revoke_camera_invite(p_actor uuid, p_invite uuid, p_request_id uuid)
returns timestamptz language plpgsql volatile security definer set search_path = '' as $$
declare
  v_invite public.camera_invites;
begin
  select i.* into v_invite from public.camera_invites i
    join public.projects p on p.id = i.project_id and p.owner_id = p_actor and p.deleted_at is null
   where i.id = p_invite
   for update of i;
  if not found then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  update public.camera_invites set revoked_at = coalesce(revoked_at, now()) where id = v_invite.id
  returning * into v_invite;
  perform app_private.write_audit('user', p_actor, v_invite.project_id, 'camera_invite.revoke', 'camera_invite',
                                  v_invite.id, 'allowed', null, p_request_id);
  return v_invite.revoked_at;
end
$$;

-- redeem_camera_invite: single use, within redeem_by, unrevoked. p_user comes only from a verified JWT `sub`. The
-- response names no project text before approval; the device code is derived from the device key thumbprint so the
-- host compares the same six digits on both phones. Unknown, expired, used and revoked codes are one P0404.
create function app_gateway.redeem_camera_invite(p_code_hash bytea, p_device_key_thumbprint bytea,
                                                 p_device_label text, p_user uuid, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_invite public.camera_invites;
begin
  perform app_private.check_sha256(p_code_hash, 'code_hash');
  perform app_private.check_sha256(p_device_key_thumbprint, 'device_key_thumbprint');
  perform app_private.check_len(p_device_label, 60, 'device_label');   -- shown to nobody before approval; not stored
  select i.* into v_invite from public.camera_invites i
    join public.projects p on p.id = i.project_id and p.deleted_at is null
   where i.code_hash = p_code_hash and i.revoked_at is null and i.redeemed_at is null and i.redeem_by > now()
   for update of i;
  if not found then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  update public.camera_invites
     set redeemed_at = now(), device_key_thumbprint = p_device_key_thumbprint,
         redeemed_by_user_id = (select pr.id from public.profiles pr where pr.id = p_user)
   where id = v_invite.id;
  perform app_private.write_audit('camera_guest', v_invite.id, v_invite.project_id, 'camera_invite.redeem',
                                  'camera_invite', v_invite.id, 'allowed', null, p_request_id);
  return pg_catalog.jsonb_build_object('redemptionId', v_invite.id,
                                       'deviceCode', app_private.six_digits(p_device_key_thumbprint),
                                       'status', 'awaiting_host');
end
$$;

-- approve_camera_invite: the owner approves after comparing the device code shown on both phones; the guest-supplied
-- label is never the basis. The guest capability may then live at most 24 h.
create function app_gateway.approve_camera_invite(p_actor uuid, p_invite uuid, p_device_code text, p_request_id uuid)
returns timestamptz language plpgsql volatile security definer set search_path = '' as $$
declare
  v_invite public.camera_invites;
  v_at     timestamptz := now();
begin
  select i.* into v_invite from public.camera_invites i
    join public.projects p on p.id = i.project_id and p.owner_id = p_actor and p.deleted_at is null
   where i.id = p_invite and i.revoked_at is null
   for update of i;
  if not found then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  if v_invite.redeemed_at is null then
    raise exception using errcode = 'P0409', message = 'not_redeemed';
  end if;
  if v_invite.approved_at is not null then
    raise exception using errcode = 'P0409', message = 'already_approved';
  end if;
  if p_device_code is null or p_device_code is distinct from app_private.six_digits(v_invite.device_key_thumbprint) then
    raise exception using errcode = 'P0409', message = 'device_code_mismatch';
  end if;
  update public.camera_invites
     set approved_at = v_at, capability_expires_at = v_at + interval '24 hours'
   where id = v_invite.id;
  perform app_private.write_audit('user', p_actor, v_invite.project_id, 'camera_invite.approve', 'camera_invite',
                                  v_invite.id, 'allowed', null, p_request_id);
  return v_at;
end
$$;

-- issue_guest_capability: only after approval, only to the device key that redeemed (the gateway has already
-- checked the signed challenge and its nonce). A new capability replaces the earlier one.
create function app_gateway.issue_guest_capability(p_invite uuid, p_device_key_thumbprint bytea,
                                                   p_capability_hash bytea, p_request_id uuid)
returns timestamptz language plpgsql volatile security definer set search_path = '' as $$
declare
  v_invite public.camera_invites;
begin
  perform app_private.check_sha256(p_device_key_thumbprint, 'device_key_thumbprint');
  perform app_private.check_sha256(p_capability_hash, 'capability_hash');
  select i.* into v_invite from public.camera_invites i
    join public.projects p on p.id = i.project_id and p.deleted_at is null
   where i.id = p_invite and i.approved_at is not null and i.revoked_at is null
     and i.capability_expires_at > now() and i.device_key_thumbprint = p_device_key_thumbprint
   for update of i;
  if not found then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  if exists (select 1 from public.camera_invites i where i.capability_hash = p_capability_hash) then
    raise exception using errcode = 'P0409', message = 'capability_conflict';
  end if;
  update public.camera_invites set capability_hash = p_capability_hash where id = v_invite.id;
  perform app_private.write_audit('camera_guest', v_invite.id, v_invite.project_id, 'guest_capability.issue',
                                  'camera_invite', v_invite.id, 'allowed', null, p_request_id);
  return v_invite.capability_expires_at;
end
$$;

-- The invite behind a live guest capability, locked; else P0404.
create function app_private.lock_guest_invite(p_invite uuid, p_capability_hash bytea) returns public.camera_invites
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_invite public.camera_invites;
begin
  select i.* into v_invite from public.camera_invites i
    join public.projects p on p.id = i.project_id and p.deleted_at is null
   where i.id = p_invite and i.capability_hash = p_capability_hash and i.approved_at is not null
     and i.revoked_at is null and i.capability_expires_at > now()
   for update of i;
  if not found or p_capability_hash is null then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  return v_invite;
end
$$;

-- guest_declare_source: one source per invite, for the invite's slot, with the participant's acknowledgement.
create function app_gateway.guest_declare_source(p_invite uuid, p_capability_hash bytea, p_local_source uuid,
                                                 p_bytes bigint, p_sha256 bytea, p_client_probe jsonb,
                                                 p_request_id uuid)
returns uuid language plpgsql volatile security definer set search_path = '' as $$
declare
  v_invite public.camera_invites := app_private.lock_guest_invite(p_invite, p_capability_hash);
  v_source public.camera_sources;
begin
  if p_local_source is null then
    raise exception using errcode = 'P0422', message = 'required:local_source_id';
  end if;
  if p_bytes is null or p_bytes <= 0 or p_bytes > v_invite.max_bytes then
    raise exception using errcode = 'P0422', message = 'invalid_value:declared_bytes';
  end if;
  perform app_private.check_sha256(p_sha256, 'declared_sha256');
  select s.* into v_source from public.camera_sources s where s.invite_id = v_invite.id and s.state <> 'deleted';
  if found then
    if v_source.local_source_id = p_local_source and v_source.declared_bytes = p_bytes
       and v_source.declared_sha256 = p_sha256 then
      return v_source.id;
    end if;
    raise exception using errcode = 'P0409', message = 'source_exists';
  end if;
  if exists (select 1 from public.camera_sources s
              where s.project_id = v_invite.project_id and s.slot = v_invite.slot and s.state <> 'deleted') then
    raise exception using errcode = 'P0409', message = 'slot_taken';
  end if;
  insert into public.camera_sources (project_id, slot, local_source_id, invite_id, uploader_user_id, label, state,
                                     declared_bytes, declared_sha256, client_probe, participant_ack_at)
  values (v_invite.project_id, v_invite.slot, p_local_source, v_invite.id, v_invite.redeemed_by_user_id,
          v_invite.display_label, 'declared', p_bytes, p_sha256, coalesce(p_client_probe, '{}'::jsonb), now())
  returning * into v_source;
  perform app_private.write_audit('camera_guest', v_invite.id, v_invite.project_id, 'guest_source.declare',
                                  'camera_source', v_source.id, 'allowed', null, p_request_id);
  return v_source.id;
end
$$;

-- 6. Uploads (architecture §6.2, §6.3) ---------------------------------------------------------------------------------
-- authorize_upload: the owner or the slot's guest opens a session for a source whose declaration matches. Any open
-- session of the source is aborted in the same transaction and the new one becomes current_session_id; each session
-- writes its own key. Render hosts use the orchestrator's *_for_attempt variants (S80), never this (T-DB-57).
create function app_gateway.authorize_upload(p_actor_kind text, p_actor uuid, p_source uuid, p_bytes bigint,
                                             p_sha256 bytea, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_source  public.camera_sources;
  v_kind    text;
  v_session app_ops.upload_sessions;
  v_id      uuid := gen_random_uuid();
begin
  if p_actor_kind is null or p_actor_kind not in ('user', 'camera_guest') then
    raise exception using errcode = 'P0422', message = 'actor_kind_not_accepted';
  end if;
  v_kind := case p_actor_kind when 'user' then 'owner' else 'camera_guest' end;
  select s.* into v_source from public.camera_sources s where s.id = p_source for update;
  if not found or not app_private.upload_actor_ok(v_kind, p_actor, v_source.project_id, v_source.id)
     or (v_kind = 'owner' and v_source.invite_id is not null) then   -- a guest's angle is uploaded by its guest
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  if v_source.state not in ('declared', 'uploading') then
    raise exception using errcode = 'P0409', message = 'source_state';
  end if;
  if p_bytes is distinct from v_source.declared_bytes or p_sha256 is distinct from v_source.declared_sha256 then
    raise exception using errcode = 'P0409', message = 'declaration_mismatch';
  end if;
  update app_ops.upload_sessions u set state = 'aborted'
   where u.source_id = v_source.id and u.state in ('opening', 'open', 'completing');
  insert into app_ops.upload_sessions (id, project_id, source_id, actor_kind, actor_id, r2_key, expected_bytes,
                                       expected_sha256, part_count, state, expires_at, hard_expires_at)
  values (v_id, v_source.project_id, v_source.id, v_kind, p_actor,
          'staging/p/' || v_source.project_id || '/s/' || v_source.id || '/original/' || v_id,
          v_source.declared_bytes, v_source.declared_sha256, (v_source.declared_bytes + 33554431) / 33554432,
          'opening', now() + interval '24 hours', now() + interval '48 hours')
  returning * into v_session;
  update public.camera_sources set state = 'uploading', current_session_id = v_session.id where id = v_source.id;
  perform app_private.write_audit(p_actor_kind, p_actor, v_source.project_id, 'upload.authorize', 'upload_session',
                                  v_session.id, 'allowed', null, p_request_id);
  return pg_catalog.jsonb_build_object('sessionId', v_session.id, 'r2Key', v_session.r2_key,
                                       'partSize', v_session.part_size, 'partCount', v_session.part_count,
                                       'expiresAt', v_session.expires_at, 'hardExpiresAt', v_session.hard_expires_at);
end
$$;

-- attach_upload_id: after createMultipartUpload, the gateway records the upload id and the session capability's hash
-- (the jvs_ token itself is returned to the client once and never stored).
create function app_gateway.attach_upload_id(p_actor_kind text, p_actor uuid, p_session uuid, p_r2_upload_id text,
                                             p_capability_hash bytea, p_request_id uuid)
returns timestamptz language plpgsql volatile security definer set search_path = '' as $$
declare
  v_session app_ops.upload_sessions;
begin
  if p_actor_kind is null or p_actor_kind not in ('user', 'camera_guest') then
    raise exception using errcode = 'P0422', message = 'actor_kind_not_accepted';
  end if;
  select u.* into v_session from app_ops.upload_sessions u
   where u.id = p_session and u.source_id is not null and u.actor_id = p_actor
     and u.actor_kind = case p_actor_kind when 'user' then 'owner' else 'camera_guest' end
   for update;
  if not found or not app_private.upload_actor_ok(v_session.actor_kind, v_session.actor_id, v_session.project_id,
                                                  v_session.source_id) then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  if v_session.state <> 'opening' then
    raise exception using errcode = 'P0409', message = 'session_not_opening';
  end if;
  if p_r2_upload_id is null or pg_catalog.char_length(p_r2_upload_id) not between 1 and 1024 then
    raise exception using errcode = 'P0422', message = 'invalid_value:r2_upload_id';
  end if;
  perform app_private.check_sha256(p_capability_hash, 'capability_hash');
  update app_ops.upload_sessions
     set r2_upload_id = p_r2_upload_id, capability_hash = p_capability_hash, state = 'open'
   where id = v_session.id;
  return v_session.expires_at;
end
$$;

-- The session behind a session capability, locked, with the actor re-checked right now; else P0404.
create function app_private.lock_upload_session(p_session uuid, p_capability_hash bytea) returns app_ops.upload_sessions
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_session app_ops.upload_sessions;
begin
  select u.* into v_session from app_ops.upload_sessions u
   where u.id = p_session and u.capability_hash = p_capability_hash and u.source_id is not null
   for update;
  if not found or p_capability_hash is null
     or not app_private.upload_actor_ok(v_session.actor_kind, v_session.actor_id, v_session.project_id,
                                        v_session.source_id) then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  return v_session;
end
$$;

-- record_part: the gateway streamed part n to R2 through a hashing tee; the part must have its exact length and the
-- streamed digest must equal the client's X-Jovra-Part-Sha256 (architecture §6.3 step 5). A re-sent part replaces
-- the earlier one. Parts keep an idle session alive (≤ 24 h after the last part, never past hard_expires_at).
create function app_gateway.record_part(p_session uuid, p_capability_hash bytea, p_part_number int, p_bytes int,
                                        p_etag text, p_sha256 bytea, p_client_sha256 bytea, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_session app_ops.upload_sessions := app_private.lock_upload_session(p_session, p_capability_hash);
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

-- complete_upload_check (architecture §6.3 steps 1-6): the parts R2 will be asked to assemble come from upload_parts,
-- never from the request; the request's list must equal them.
create function app_gateway.complete_upload_check(p_session uuid, p_capability_hash bytea, p_parts jsonb,
                                                  p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_session app_ops.upload_sessions := app_private.lock_upload_session(p_session, p_capability_hash);
  v_source  public.camera_sources;
  v_parts   jsonb;
  v_last    bigint;
begin
  -- 1. open and unexpired (the actor was re-checked by lock_upload_session)
  if v_session.state <> 'open' then
    raise exception using errcode = 'P0409', message = 'session_not_open';
  end if;
  if v_session.expires_at <= now() or v_session.hard_expires_at <= now() then
    raise exception using errcode = 'P0410', message = 'session_expired';
  end if;
  -- 2. the source is of the session's own project, not deleted, and the project is live (wrong-project completion)
  select s.* into v_source from public.camera_sources s
    join public.projects p on p.id = s.project_id and p.deleted_at is null
   where s.id = v_session.source_id and s.project_id = v_session.project_id and s.state <> 'deleted'
   for update of s;
  if not found then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  -- 6. only the current session of an uploading source can complete
  if v_source.current_session_id is distinct from v_session.id or v_source.state <> 'uploading' then
    raise exception using errcode = 'P0409', message = 'stale_session';
  end if;
  -- 3. parts are exactly 1..part_count, full-size except the last, summing to the declared bytes
  v_last := v_session.expected_bytes - (v_session.part_count - 1)::bigint * v_session.part_size;
  if (select pg_catalog.count(*) from app_ops.upload_parts up where up.session_id = v_session.id)
       <> v_session.part_count
     or exists (select 1 from pg_catalog.generate_series(1, v_session.part_count) n
                 where not exists (select 1 from app_ops.upload_parts up
                                    where up.session_id = v_session.id and up.part_number = n)) then
    raise exception using errcode = 'P0409', message = 'parts_incomplete';
  end if;
  if exists (select 1 from app_ops.upload_parts up
              where up.session_id = v_session.id
                and up.bytes <> case when up.part_number < v_session.part_count then v_session.part_size
                                     else v_last end)
     or (select pg_catalog.sum(up.bytes) from app_ops.upload_parts up where up.session_id = v_session.id)
        <> v_session.expected_bytes then
    raise exception using errcode = 'P0409', message = 'part_size_mismatch';
  end if;
  -- 4. the request's list equals the stored parts
  select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('n', up.part_number, 'etag', up.etag)
                              order by up.part_number)
    into v_parts from app_ops.upload_parts up where up.session_id = v_session.id;
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
  update app_ops.upload_sessions set state = 'completing' where id = v_session.id;
  perform app_private.write_audit(case v_session.actor_kind when 'owner' then 'user' else 'camera_guest' end,
                                  v_session.actor_id, v_session.project_id, 'upload.complete_check', 'upload_session',
                                  v_session.id, 'allowed', null, p_request_id);
  return pg_catalog.jsonb_build_object('r2Key', v_session.r2_key, 'uploadId', v_session.r2_upload_id,
                                       'parts', v_parts);
end
$$;

-- mark_uploaded_unverified (step 7-8): R2's head size equals the declaration; the source waits for verify_sources.
create function app_gateway.mark_uploaded_unverified(p_session uuid, p_capability_hash bytea, p_object_bytes bigint,
                                                     p_request_id uuid)
returns public.source_state language plpgsql volatile security definer set search_path = '' as $$
declare
  v_session app_ops.upload_sessions := app_private.lock_upload_session(p_session, p_capability_hash);
begin
  if v_session.state <> 'completing' then
    raise exception using errcode = 'P0409', message = 'session_not_completing';
  end if;
  if p_object_bytes is distinct from v_session.expected_bytes then
    raise exception using errcode = 'P0409', message = 'size_mismatch';
  end if;
  if not exists (select 1 from public.camera_sources s
                  where s.id = v_session.source_id and s.current_session_id = v_session.id
                    and s.state = 'uploading') then
    raise exception using errcode = 'P0409', message = 'stale_session';
  end if;
  update app_ops.upload_sessions set state = 'completed', completed_at = now() where id = v_session.id;
  update public.camera_sources set state = 'uploaded_unverified', r2_key = v_session.r2_key
   where id = v_session.source_id;
  perform app_private.write_audit(case v_session.actor_kind when 'owner' then 'user' else 'camera_guest' end,
                                  v_session.actor_id, v_session.project_id, 'upload.complete', 'camera_source',
                                  v_session.source_id, 'allowed', null, p_request_id);
  return 'uploaded_unverified'::public.source_state;
end
$$;

-- abort_upload: the session holder (capability) or the project owner (p_actor).
create function app_gateway.abort_upload(p_session uuid, p_capability_hash bytea, p_actor uuid, p_request_id uuid)
returns text language plpgsql volatile security definer set search_path = '' as $$
declare
  v_session app_ops.upload_sessions;
begin
  select u.* into v_session from app_ops.upload_sessions u
   where u.id = p_session and u.source_id is not null
     and ((p_capability_hash is not null and u.capability_hash = p_capability_hash
           and app_private.upload_actor_ok(u.actor_kind, u.actor_id, u.project_id, u.source_id))
          or exists (select 1 from public.projects p
                      where p.id = u.project_id and p.owner_id = p_actor and p.deleted_at is null))
   for update;
  if not found then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  if v_session.state in ('opening', 'open', 'completing') then
    update app_ops.upload_sessions set state = 'aborted' where id = v_session.id;
  end if;
  perform app_private.write_audit(case when p_actor is not null then 'user'
                                       when v_session.actor_kind = 'owner' then 'user' else 'camera_guest' end,
                                  coalesce(p_actor, v_session.actor_id), v_session.project_id, 'upload.abort',
                                  'upload_session', v_session.id, 'allowed', null, p_request_id);
  return 'aborted';
end
$$;

-- 7. Grants and memberships (security-model §13.2, §13.8) ------------------------------------------------------------
-- create_grant: every invitation is bound to its recipient's email (HMAC only; the email is never stored, returned
-- or logged). The creator owns the target; clip-bearing grants also need each clip shareable (b20_check_grant_clips).
create function app_gateway.create_grant(p_actor uuid, p_kind public.grant_kind, p_invitee_email text,
                                         p_project uuid, p_lesson uuid, p_artifact uuid, p_clip uuid,
                                         p_expires_in_sec int, p_token_hash bytea, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_project uuid;
  v_hmac    bytea;
  v_grant   public.access_grants;
begin
  if p_kind is null or p_kind = 'share_link' then
    raise exception using errcode = 'P0422', message = 'invalid_value:kind';
  end if;
  if case p_kind
       when 'project_coach' then p_project is null or num_nonnulls(p_lesson, p_artifact, p_clip) > 0
       when 'lesson_coach' then p_lesson is null or num_nonnulls(p_project, p_artifact, p_clip) > 0
       when 'lesson_view' then p_lesson is null or num_nonnulls(p_project, p_artifact, p_clip) > 0
       when 'film_view' then p_artifact is null or num_nonnulls(p_lesson, p_clip) > 0
       when 'lesson_clip_view' then p_clip is null or num_nonnulls(p_project, p_lesson, p_artifact) > 0
     end then
    raise exception using errcode = 'P0422', message = 'invalid_value:target';
  end if;
  -- the creator owns the target, now
  case p_kind
    when 'project_coach' then
      v_project := (app_private.lock_owned_project(p_actor, p_project)).id;
    when 'lesson_coach', 'lesson_view' then
      if not exists (select 1 from public.lessons l where l.id = p_lesson and l.owner_id = p_actor) then
        raise exception using errcode = 'P0404', message = 'not_found';
      end if;
    when 'film_view' then
      select a.project_id into v_project from public.artifacts a
        join public.projects p on p.id = a.project_id and p.owner_id = p_actor and p.deleted_at is null
       where a.id = p_artifact and a.kind = 'film' and a.state = 'ready' and a.deleted_at is null
         and (p_project is null or a.project_id = p_project);
      if v_project is null then
        raise exception using errcode = 'P0404', message = 'not_found';
      end if;
    when 'lesson_clip_view' then
      if not exists (select 1 from public.lesson_clips c
                       join public.lessons l on l.id = c.lesson_id and l.owner_id = p_actor
                       join public.projects p on p.id = c.project_id and p.deleted_at is null
                      where c.id = p_clip) then
        raise exception using errcode = 'P0404', message = 'not_found';
      end if;
  end case;
  if p_invitee_email is null or pg_catalog.char_length(pg_catalog.btrim(p_invitee_email)) not between 3 and 254
     or pg_catalog.btrim(p_invitee_email) !~ '^[^[:space:]@]+@[^[:space:]@]+$' then
    raise exception using errcode = 'P0422', message = 'invalid_value:invitee_email';
  end if;
  v_hmac := app_private.email_hmac(p_invitee_email);
  if v_hmac is null then   -- no HMAC key: an invitation could not be bound to anyone, so none is made
    raise exception using errcode = 'P0409', message = 'invitee_unbindable';
  end if;
  perform app_private.check_sha256(p_token_hash, 'token_hash');
  if p_expires_in_sec is not null and p_expires_in_sec not between 3600 and 31536000 then
    raise exception using errcode = 'P0422', message = 'invalid_value:expires_in_sec';
  end if;
  if exists (select 1 from public.access_grants g where g.token_hash = p_token_hash) then
    raise exception using errcode = 'P0409', message = 'code_conflict';
  end if;
  insert into public.access_grants (kind, project_id, lesson_id, artifact_id, lesson_clip_id, token_hash,
                                    invitee_email_hmac, created_by, redeem_by, expires_at)
  values (p_kind, v_project, p_lesson, p_artifact, p_clip, p_token_hash, v_hmac, p_actor, now() + interval '7 days',
          case when p_expires_in_sec is not null then now() + pg_catalog.make_interval(secs => p_expires_in_sec) end)
  returning * into v_grant;
  perform app_private.write_audit('user', p_actor, v_project, 'grant.create', 'access_grant', v_grant.id, 'allowed',
                                  null, p_request_id, pg_catalog.jsonb_build_object('kind', p_kind));
  return pg_catalog.jsonb_build_object('grantId', v_grant.id, 'redeemBy', v_grant.redeem_by,
                                       'expiresAt', v_grant.expires_at);
end
$$;

-- redeem_grant: only an account whose confirmed email matches the invitation's HMAC; anything else is the same
-- P0404 as an unknown code (T-DB-58). A project_coach redemption creates a pending membership that confers nothing
-- until approve_member (T-DB-51).
create function app_gateway.redeem_grant(p_actor uuid, p_token_hash bytea, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_grant  public.access_grants;
  v_facts  jsonb;
  v_now    timestamptz := now();
  v_member public.project_members;
begin
  select g.* into v_grant from public.access_grants g
   where g.token_hash = p_token_hash and g.kind <> 'share_link'
     and g.revoked_at is null and g.redeemed_at is null and g.redeem_by > now()
     and (g.expires_at is null or g.expires_at > now())
     and app_private.grant_target_live(g.project_id, g.lesson_clip_id)
   for update;
  v_facts := app_private.auth_user_facts(p_actor, null);
  if v_grant.id is null or p_actor is null or v_facts is null or (v_facts ->> 'anonymous')::boolean
     or v_facts ->> 'confirmedEmail' is null
     or app_private.email_hmac(v_facts ->> 'confirmedEmail') is distinct from v_grant.invitee_email_hmac
     or v_grant.created_by = p_actor
     or not exists (select 1 from public.profiles pr where pr.id = p_actor) then
    raise exception using errcode = 'P0404', message = 'not_found';   -- same code and text as an unknown code
  end if;
  update public.access_grants set grantee_user_id = p_actor, redeemed_at = v_now where id = v_grant.id;
  if v_grant.kind = 'project_coach' then
    select m.* into v_member from public.project_members m
     where m.project_id = v_grant.project_id and m.user_id = p_actor
     for update;
    if found then
      if v_member.role = 'owner'
         or (v_member.revoked_at is null and v_member.approved_at is not null
             and (v_member.expires_at is null or v_member.expires_at > now())) then
        raise exception using errcode = 'P0409', message = 'already_member';
      end if;
      update public.project_members
         set granted_by = v_grant.created_by, grant_id = v_grant.id, approved_at = null, revoked_at = null,
             expires_at = v_grant.expires_at, created_at = v_now
       where project_id = v_grant.project_id and user_id = p_actor;
    else
      insert into public.project_members (project_id, user_id, role, granted_by, grant_id, expires_at)
      values (v_grant.project_id, p_actor, 'coach', v_grant.created_by, v_grant.id, v_grant.expires_at);
    end if;
  end if;
  perform app_private.write_audit('user', p_actor, v_grant.project_id, 'grant.redeem', 'access_grant', v_grant.id,
                                  'allowed', null, p_request_id, pg_catalog.jsonb_build_object('kind', v_grant.kind));
  return pg_catalog.jsonb_build_object(
    'grantId', v_grant.id, 'kind', v_grant.kind,
    'status', case when v_grant.kind = 'project_coach' then 'awaiting_owner' else 'active' end,
    'approvalCode', case when v_grant.kind = 'project_coach'
                         then app_private.member_approval_code(v_grant.id, p_actor, v_now) end);
end
$$;

-- list_pending_members: the owner's approval view. The redeemer's verified email, masked; never display_name, which
-- the redeemer controls (§13.2, T-DB-58).
create function app_gateway.list_pending_members(p_actor uuid, p_project uuid, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_project public.projects := app_private.lock_owned_project(p_actor, p_project);
begin
  return coalesce((
    select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
             'userId', m.user_id,
             'maskedEmail', app_private.mask_email(app_private.auth_user_facts(m.user_id, null) ->> 'confirmedEmail'),
             'redeemedAt', g.redeemed_at) order by g.redeemed_at)
      from public.project_members m
      join public.access_grants g on g.id = m.grant_id and g.revoked_at is null
     where m.project_id = v_project.id and m.role = 'coach' and m.approved_at is null and m.revoked_at is null),
    '[]'::jsonb);
end
$$;

-- approve_member: the owner activates a pending coach after the redeemer read them the approval code.
create function app_gateway.approve_member(p_actor uuid, p_project uuid, p_user uuid, p_code text, p_request_id uuid)
returns timestamptz language plpgsql volatile security definer set search_path = '' as $$
declare
  v_project public.projects := app_private.lock_owned_project(p_actor, p_project);
  v_grant   public.access_grants;
  v_at      timestamptz := now();
begin
  select g.* into v_grant from public.project_members m
    join public.access_grants g on g.id = m.grant_id
   where m.project_id = v_project.id and m.user_id = p_user and m.role = 'coach' and m.approved_at is null
     and m.revoked_at is null and g.revoked_at is null and (g.expires_at is null or g.expires_at > now())
   for update of m;
  if not found then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  if p_code is null or p_code is distinct from app_private.member_approval_code(v_grant.id, p_user,
                                                                                 v_grant.redeemed_at) then
    raise exception using errcode = 'P0409', message = 'code_mismatch';
  end if;
  update public.project_members set approved_at = v_at where project_id = v_project.id and user_id = p_user;
  perform app_private.write_audit('user', p_actor, v_project.id, 'member.approve', 'profile', p_user, 'allowed', null,
                                  p_request_id);
  return v_at;
end
$$;

-- revoke_grant: the creator, or the owner of the project whose footage the grant reaches. Revoking a project_coach
-- grant revokes the membership it created in the same transaction. Repeating it returns the first revocation time.
create function app_gateway.revoke_grant(p_actor uuid, p_grant uuid, p_request_id uuid)
returns timestamptz language plpgsql volatile security definer set search_path = '' as $$
declare
  v_grant public.access_grants;
  v_at    timestamptz;
begin
  select g.* into v_grant from public.access_grants g where g.id = p_grant for update;
  if not found or p_actor is null or not (
       v_grant.created_by = p_actor
       or exists (select 1 from public.projects p where p.id = v_grant.project_id and p.owner_id = p_actor)
       or exists (select 1 from public.lesson_clips c join public.projects p on p.id = c.project_id
                   where p.owner_id = p_actor
                     and (c.id = v_grant.lesson_clip_id or c.lesson_id = v_grant.lesson_id))) then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  v_at := coalesce(v_grant.revoked_at, now());
  update public.access_grants set revoked_at = v_at where id = v_grant.id;
  if v_grant.kind = 'project_coach' then
    update public.project_members set revoked_at = v_at where grant_id = v_grant.id and revoked_at is null;
  end if;
  perform app_private.write_audit('user', p_actor, v_grant.project_id, 'grant.revoke', 'access_grant', v_grant.id,
                                  'allowed', null, p_request_id, pg_catalog.jsonb_build_object('kind', v_grant.kind));
  return v_at;
end
$$;

-- revoke_member: the owner ends a coach's membership (pending or active) and the grant that created it.
create function app_gateway.revoke_member(p_actor uuid, p_project uuid, p_user uuid, p_request_id uuid)
returns timestamptz language plpgsql volatile security definer set search_path = '' as $$
declare
  v_project public.projects := app_private.lock_owned_project(p_actor, p_project);
  v_member  public.project_members;
  v_at      timestamptz := now();
begin
  select m.* into v_member from public.project_members m
   where m.project_id = v_project.id and m.user_id = p_user and m.role = 'coach' and m.revoked_at is null
   for update;
  if not found then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  update public.project_members set revoked_at = v_at where project_id = v_project.id and user_id = p_user;
  update public.access_grants set revoked_at = v_at where id = v_member.grant_id and revoked_at is null;
  perform app_private.write_audit('user', p_actor, v_project.id, 'member.revoke', 'profile', p_user, 'allowed', null,
                                  p_request_id);
  return v_at;
end
$$;

-- 8. Share links (architecture §9.2, security-model §8.3) -----------------------------------------------------------
-- create_share_link: the owner shares one ready film, preview or clip excerpt for at most 24 h. A film shared without
-- audio is served from its verified no-audio child (a ready film whose parent is this film, made by remux_no_audio
-- and verify_output, S80); until that child exists the link is refused with audio_variant_pending, so a link never
-- serves sound the owner chose to leave out.
create function app_gateway.create_share_link(p_actor uuid, p_artifact uuid, p_expires_in_sec int,
                                              p_include_audio boolean, p_token_hash bytea, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_artifact public.artifacts;
  v_target   uuid;
  v_grant    public.access_grants;
begin
  select a.* into v_artifact from public.artifacts a
    join public.projects p on p.id = a.project_id and p.owner_id = p_actor and p.deleted_at is null
   where a.id = p_artifact and a.deleted_at is null;
  if not found then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  if v_artifact.kind not in ('film', 'preview', 'clip_excerpt') or v_artifact.state <> 'ready' then
    raise exception using errcode = 'P0409', message = 'not_shareable';
  end if;
  if p_expires_in_sec is null or p_expires_in_sec not between 60 and 86400 then
    raise exception using errcode = 'P0422', message = 'invalid_value:expires_in_sec';
  end if;
  perform app_private.check_sha256(p_token_hash, 'token_hash');
  v_target := v_artifact.id;
  if v_artifact.kind = 'film' then
    if p_include_audio is null then
      raise exception using errcode = 'P0422', message = 'required:include_audio';
    end if;
    if not p_include_audio then
      select c.id into v_target from public.artifacts c
       where c.project_id = v_artifact.project_id and c.parent_artifact_id = v_artifact.id and c.kind = 'film'
         and c.state = 'ready' and c.verified_at is not null and c.deleted_at is null
       order by c.created_at desc limit 1;
      if v_target is null then
        raise exception using errcode = 'P0409', message = 'audio_variant_pending';
      end if;
    end if;
  end if;
  if exists (select 1 from public.access_grants g where g.token_hash = p_token_hash) then
    raise exception using errcode = 'P0409', message = 'code_conflict';
  end if;
  insert into public.access_grants (kind, project_id, artifact_id, token_hash, created_by, expires_at)
  values ('share_link', v_artifact.project_id, v_target, p_token_hash, p_actor,
          now() + pg_catalog.make_interval(secs => p_expires_in_sec))
  returning * into v_grant;
  perform app_private.write_audit('user', p_actor, v_artifact.project_id, 'share_link.create', 'artifact', v_target,
                                  'allowed', null, p_request_id);
  return pg_catalog.jsonb_build_object('shareLinkId', v_grant.id, 'artifactId', v_target,
                                       'expiresAt', v_grant.expires_at);
end
$$;

-- redeem_share_link: authorizes one /s/<token> request; it never writes a grant, a grantee or an audit row.
create function app_gateway.redeem_share_link(p_token_hash bytea, p_request_id uuid)
returns uuid language plpgsql volatile security definer set search_path = '' as $$
declare
  v_artifact uuid;
begin
  select g.artifact_id into v_artifact from public.access_grants g
    join public.projects p on p.id = g.project_id and p.deleted_at is null
    join public.artifacts a on a.id = g.artifact_id and a.project_id = g.project_id
   where g.token_hash = p_token_hash and g.kind = 'share_link' and g.revoked_at is null and g.expires_at > now()
     and a.state = 'ready' and a.deleted_at is null;
  if v_artifact is null then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  return v_artifact;
end
$$;

-- 9. Deletion requests (architecture §10, security-model §13.4) -------------------------------------------------------
-- request_deletion: the owner of the target; account scope only within 10 minutes of a fresh Auth session (the JWT's
-- session_id must name a session of this user created less than 10 minutes ago; a refreshed token is not enough). A
-- source used in films lists them first (state 'dependents') until the owner confirms. A repeat returns the open
-- request (story 199). Project deletion hides the project at once; the deletion Workflow (S94) does the rest.
create function app_gateway.request_deletion(p_actor uuid, p_scope public.deletion_scope, p_target uuid,
                                             p_session_id uuid, p_confirm_dependents boolean, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_project    uuid;
  v_request    public.deletion_requests;
  v_dependents jsonb;
  v_created    timestamptz;
begin
  if p_actor is null or p_scope is null or p_target is null then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  case p_scope
    when 'account' then
      if p_target <> p_actor or not exists (select 1 from public.profiles pr where pr.id = p_actor) then
        raise exception using errcode = 'P0404', message = 'not_found';
      end if;
      v_created := (app_private.auth_user_facts(p_actor, p_session_id) ->> 'sessionCreatedAt')::timestamptz;
      if v_created is null or v_created <= now() - interval '10 minutes' then
        raise exception using errcode = 'P0401', message = 'reauth_required';
      end if;
    when 'project' then
      select p.id into v_project from public.projects p where p.id = p_target and p.owner_id = p_actor for update;
    when 'source' then
      select s.project_id into v_project from public.camera_sources s
        join public.projects p on p.id = s.project_id and p.owner_id = p_actor and p.deleted_at is null
       where s.id = p_target and s.state <> 'deleted';
    when 'artifact' then
      select a.project_id into v_project from public.artifacts a
        join public.projects p on p.id = a.project_id and p.owner_id = p_actor and p.deleted_at is null
       where a.id = p_target and a.deleted_at is null;
    when 'lesson' then
      if not exists (select 1 from public.lessons l where l.id = p_target and l.owner_id = p_actor) then
        raise exception using errcode = 'P0404', message = 'not_found';
      end if;
    when 'lesson_clip' then
      select c.project_id into v_project from public.lesson_clips c
        join public.lessons l on l.id = c.lesson_id and l.owner_id = p_actor
       where c.id = p_target;
      if v_project is null then
        raise exception using errcode = 'P0404', message = 'not_found';
      end if;
  end case;
  if p_scope in ('project', 'source', 'artifact') and v_project is null then
    raise exception using errcode = 'P0404', message = 'not_found';
  end if;
  select d.* into v_request from public.deletion_requests d
   where d.scope = p_scope and d.target_id = p_target and d.state <> 'done';
  if found then
    return pg_catalog.jsonb_build_object('deletionRequestId', v_request.id, 'state', v_request.state);
  end if;
  if p_scope = 'source' and not coalesce(p_confirm_dependents, false) then
    select pg_catalog.jsonb_agg(a.id order by a.created_at) into v_dependents
      from public.artifact_sources x
      join public.artifacts a on a.id = x.artifact_id and a.project_id = x.project_id
     where x.source_id = p_target and x.project_id = v_project and a.deleted_at is null
       and a.kind in ('film', 'preview', 'clip_excerpt');
    if v_dependents is not null then
      return pg_catalog.jsonb_build_object('deletionRequestId', null, 'state', 'dependents',
                                           'dependents', v_dependents);
    end if;
  end if;
  insert into public.deletion_requests (requested_by, scope, target_id) values (p_actor, p_scope, p_target)
  returning * into v_request;
  if p_scope = 'project' then
    update public.projects set deleted_at = coalesce(deleted_at, now()) where id = v_project;
  end if;
  perform app_private.write_audit('user', p_actor, v_project, 'deletion.request', p_scope::text, p_target, 'allowed',
                                  null, p_request_id);
  return pg_catalog.jsonb_build_object('deletionRequestId', v_request.id, 'state', v_request.state);
end
$$;

-- 10. Function privileges ----------------------------------------------------------------------------------------------
revoke all on function
  app_private.jovra_env(), app_private.six_digits(bytea), app_private.mask_email(text),
  app_private.member_approval_code(uuid, uuid, timestamptz), app_private.require_real_user(uuid),
  app_private.lock_owned_project(uuid, uuid), app_private.upload_actor_ok(text, uuid, uuid, uuid),
  app_private.check_sha256(bytea, text), app_private.lock_guest_invite(uuid, bytea),
  app_private.lock_upload_session(uuid, bytea),
  app_gateway.audit_denial(text, uuid, text, text, uuid, text, uuid),
  app_gateway.create_project(uuid, uuid, text, text, boolean, uuid),
  app_gateway.declare_source(uuid, uuid, public.camera_slot, uuid, bigint, bytea, jsonb, uuid),
  app_gateway.create_camera_invite(uuid, uuid, public.camera_slot, text, bytea, uuid),
  app_gateway.revoke_camera_invite(uuid, uuid, uuid),
  app_gateway.redeem_camera_invite(bytea, bytea, text, uuid, uuid),
  app_gateway.approve_camera_invite(uuid, uuid, text, uuid),
  app_gateway.issue_guest_capability(uuid, bytea, bytea, uuid),
  app_gateway.guest_declare_source(uuid, bytea, uuid, bigint, bytea, jsonb, uuid),
  app_gateway.authorize_upload(text, uuid, uuid, bigint, bytea, uuid),
  app_gateway.attach_upload_id(text, uuid, uuid, text, bytea, uuid),
  app_gateway.record_part(uuid, bytea, int, int, text, bytea, bytea, uuid),
  app_gateway.complete_upload_check(uuid, bytea, jsonb, uuid),
  app_gateway.mark_uploaded_unverified(uuid, bytea, bigint, uuid),
  app_gateway.abort_upload(uuid, bytea, uuid, uuid),
  app_gateway.create_grant(uuid, public.grant_kind, text, uuid, uuid, uuid, uuid, int, bytea, uuid),
  app_gateway.redeem_grant(uuid, bytea, uuid),
  app_gateway.list_pending_members(uuid, uuid, uuid),
  app_gateway.approve_member(uuid, uuid, uuid, text, uuid),
  app_gateway.revoke_grant(uuid, uuid, uuid),
  app_gateway.revoke_member(uuid, uuid, uuid, uuid),
  app_gateway.create_share_link(uuid, uuid, int, boolean, bytea, uuid),
  app_gateway.redeem_share_link(bytea, uuid),
  app_gateway.request_deletion(uuid, public.deletion_scope, uuid, uuid, boolean, uuid)
  from public, anon, authenticated, service_role;

-- User-route commands: the gateway's alone, never the orchestrator's (T-DB-57).
grant execute on function
  app_gateway.audit_denial(text, uuid, text, text, uuid, text, uuid),
  app_gateway.create_project(uuid, uuid, text, text, boolean, uuid),
  app_gateway.declare_source(uuid, uuid, public.camera_slot, uuid, bigint, bytea, jsonb, uuid),
  app_gateway.create_camera_invite(uuid, uuid, public.camera_slot, text, bytea, uuid),
  app_gateway.revoke_camera_invite(uuid, uuid, uuid),
  app_gateway.redeem_camera_invite(bytea, bytea, text, uuid, uuid),
  app_gateway.approve_camera_invite(uuid, uuid, text, uuid),
  app_gateway.issue_guest_capability(uuid, bytea, bytea, uuid),
  app_gateway.guest_declare_source(uuid, bytea, uuid, bigint, bytea, jsonb, uuid),
  app_gateway.authorize_upload(text, uuid, uuid, bigint, bytea, uuid),
  app_gateway.attach_upload_id(text, uuid, uuid, text, bytea, uuid),
  app_gateway.record_part(uuid, bytea, int, int, text, bytea, bytea, uuid),
  app_gateway.complete_upload_check(uuid, bytea, jsonb, uuid),
  app_gateway.mark_uploaded_unverified(uuid, bytea, bigint, uuid),
  app_gateway.abort_upload(uuid, bytea, uuid, uuid),
  app_gateway.create_grant(uuid, public.grant_kind, text, uuid, uuid, uuid, uuid, int, bytea, uuid),
  app_gateway.redeem_grant(uuid, bytea, uuid),
  app_gateway.list_pending_members(uuid, uuid, uuid),
  app_gateway.approve_member(uuid, uuid, uuid, text, uuid),
  app_gateway.revoke_grant(uuid, uuid, uuid),
  app_gateway.revoke_member(uuid, uuid, uuid, uuid),
  app_gateway.create_share_link(uuid, uuid, int, boolean, bytea, uuid),
  app_gateway.redeem_share_link(bytea, uuid),
  app_gateway.request_deletion(uuid, public.deletion_scope, uuid, uuid, boolean, uuid)
  to jovra_gateway;

-- 11. One owner (T-DB-66). auth_user_facts keeps the migration owner (it reads auth; see above). -------------------
alter table app_ops.settings owner to jovra_owner;

alter function app_private.jovra_env() owner to jovra_owner;
alter function app_private.six_digits(bytea) owner to jovra_owner;
alter function app_private.mask_email(text) owner to jovra_owner;
alter function app_private.member_approval_code(uuid, uuid, timestamptz) owner to jovra_owner;
alter function app_private.require_real_user(uuid) owner to jovra_owner;
alter function app_private.lock_owned_project(uuid, uuid) owner to jovra_owner;
alter function app_private.upload_actor_ok(text, uuid, uuid, uuid) owner to jovra_owner;
alter function app_private.check_sha256(bytea, text) owner to jovra_owner;
alter function app_private.lock_guest_invite(uuid, bytea) owner to jovra_owner;
alter function app_private.lock_upload_session(uuid, bytea) owner to jovra_owner;
alter function app_gateway.audit_denial(text, uuid, text, text, uuid, text, uuid) owner to jovra_owner;
alter function app_gateway.create_project(uuid, uuid, text, text, boolean, uuid) owner to jovra_owner;
alter function app_gateway.declare_source(uuid, uuid, public.camera_slot, uuid, bigint, bytea, jsonb, uuid)
  owner to jovra_owner;
alter function app_gateway.create_camera_invite(uuid, uuid, public.camera_slot, text, bytea, uuid)
  owner to jovra_owner;
alter function app_gateway.revoke_camera_invite(uuid, uuid, uuid) owner to jovra_owner;
alter function app_gateway.redeem_camera_invite(bytea, bytea, text, uuid, uuid) owner to jovra_owner;
alter function app_gateway.approve_camera_invite(uuid, uuid, text, uuid) owner to jovra_owner;
alter function app_gateway.issue_guest_capability(uuid, bytea, bytea, uuid) owner to jovra_owner;
alter function app_gateway.guest_declare_source(uuid, bytea, uuid, bigint, bytea, jsonb, uuid) owner to jovra_owner;
alter function app_gateway.authorize_upload(text, uuid, uuid, bigint, bytea, uuid) owner to jovra_owner;
alter function app_gateway.attach_upload_id(text, uuid, uuid, text, bytea, uuid) owner to jovra_owner;
alter function app_gateway.record_part(uuid, bytea, int, int, text, bytea, bytea, uuid) owner to jovra_owner;
alter function app_gateway.complete_upload_check(uuid, bytea, jsonb, uuid) owner to jovra_owner;
alter function app_gateway.mark_uploaded_unverified(uuid, bytea, bigint, uuid) owner to jovra_owner;
alter function app_gateway.abort_upload(uuid, bytea, uuid, uuid) owner to jovra_owner;
alter function app_gateway.create_grant(uuid, public.grant_kind, text, uuid, uuid, uuid, uuid, int, bytea, uuid)
  owner to jovra_owner;
alter function app_gateway.redeem_grant(uuid, bytea, uuid) owner to jovra_owner;
alter function app_gateway.list_pending_members(uuid, uuid, uuid) owner to jovra_owner;
alter function app_gateway.approve_member(uuid, uuid, uuid, text, uuid) owner to jovra_owner;
alter function app_gateway.revoke_grant(uuid, uuid, uuid) owner to jovra_owner;
alter function app_gateway.revoke_member(uuid, uuid, uuid, uuid) owner to jovra_owner;
alter function app_gateway.create_share_link(uuid, uuid, int, boolean, bytea, uuid) owner to jovra_owner;
alter function app_gateway.redeem_share_link(bytea, uuid) owner to jovra_owner;
alter function app_gateway.request_deletion(uuid, public.deletion_scope, uuid, uuid, boolean, uuid)
  owner to jovra_owner;
