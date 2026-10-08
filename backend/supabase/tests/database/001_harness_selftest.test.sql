-- The harness checks itself, so later RLS tests can trust "acting as X" (S75 / B-02).
begin;
select plan(12);

select tests.create_supabase_user('harness_alice');
select tests.create_supabase_user('harness_bob', 'harness.bob@example.test');

select isnt(tests.get_supabase_uid('harness_alice'), tests.get_supabase_uid('harness_bob'),
  'two test users get distinct ids');
select is((select email from auth.users where id = tests.get_supabase_uid('harness_bob')), 'harness.bob@example.test',
  'create_supabase_user keeps an explicit email');
select ok((select email_confirmed_at is not null from auth.users where id = tests.get_supabase_uid('harness_alice')),
  'test users have a confirmed email');
select throws_ok($$ select tests.get_supabase_uid('nobody') $$, 'P0001', 'tests: no test user with identifier nobody',
  'an unknown identifier raises instead of returning null');

select tests.authenticate_as('harness_alice');
select is(auth.uid(), tests.get_supabase_uid('harness_alice'), 'authenticate_as sets auth.uid()');
select is(current_user::text, 'authenticated', 'authenticate_as switches to the authenticated role');
select is(auth.jwt() ->> 'email', 'harness_alice@example.test', 'the claims carry the user''s email');
select is((auth.jwt() ->> 'is_anonymous')::boolean, false, 'the claims say the user is not anonymous');

select tests.authenticate_as('harness_bob');
select is(auth.uid(), tests.get_supabase_uid('harness_bob'), 'authenticate_as can switch to another user');

select tests.clear_authentication();
select is(auth.uid(), null, 'clear_authentication leaves no user');
select is(current_user::text, 'anon', 'clear_authentication switches to the anon role');

select tests.authenticate_as_service_role();
select is(current_user::text, 'service_role', 'authenticate_as_service_role switches to service_role');
select tests.clear_authentication();

select * from finish();
rollback;
