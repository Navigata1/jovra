-- DELIBERATELY FAILING (S75 acceptance: a failing pgTAP test must turn backend-db red). Removed in the next commit.
begin;
select plan(1);
select is(app_private.before_user_created('{"user": {"email": "stranger@example.test"}}'::jsonb), '{}'::jsonb,
  'deliberately wrong: claims an unknown address may sign up');
select * from finish();
rollback;
