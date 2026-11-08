-- Local seed (S79 / B-06): this stack is the 'local' environment. accept_quote requires profiles.is_tester everywhere
-- else, and a database without this row reads as 'test' (fail closed). The hosted test and live projects get their
-- row from the operator at G1, never from this file.
insert into app_ops.settings (env) values ('local') on conflict (id) do update set env = excluded.env;
