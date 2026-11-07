-- Simula o mínimo do Supabase para testes locais (roles, auth.users, auth.uid(), auth.jwt())
do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin create role service_role nologin bypassrls; exception when duplicate_object then null; end $$;
create schema auth;
create table auth.users (id uuid primary key, email text);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(coalesce(current_setting('request.jwt.claim.sub', true),
                         (current_setting('request.jwt.claims', true)::jsonb ->> 'sub')), '')::uuid $$;
create function auth.jwt() returns jsonb language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on all functions in schema auth to anon, authenticated, service_role;

insert into auth.users values ('05c1d5f2-b450-4828-87f4-71a9cb638580', 'raf.fcp@gmail.com'),
                              ('11111111-1111-1111-1111-111111111111', 'esposa@exemplo.com'),
                              ('22222222-2222-2222-2222-222222222222', 'intruso@exemplo.com');

-- Simula uma tabela do DashBoard-Financeiro no schema public, com os grants típicos do Supabase
create table public.lancamentos (id bigint generated always as identity primary key, descricao text, valor numeric(14,2));
grant all on public.lancamentos to anon, authenticated, service_role;
insert into public.lancamentos(descricao, valor) values ('registro do financeiro', 100);
