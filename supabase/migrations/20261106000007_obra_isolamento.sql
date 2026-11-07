-- =====================================================================
-- ObraCerta · 007 · Isolamento do DashBoard-Financeiro (schema public)
--
-- Requisito: o ObraCerta não pode ler, alterar nem depender de registros do
-- Controle Financeiro. Garantia em três camadas:
--   1. Nenhum objeto do schema obra referencia o schema public (verificável no catálogo).
--   2. Todo o schema obra passa a pertencer ao role obra_owner, SEM privilégio em public.
--      As funções SECURITY DEFINER rodam como obra_owner: mesmo um bug não consegue
--      gravar no Financeiro (o banco nega com "permission denied").
--   3. O ObraCerta não usa o schema auth: obra.uid()/obra.jwt() leem o token da
--      requisição (mesma fonte de auth.uid()), e a FK para auth.users é removida.
-- obra.verificar_isolamento() reexecuta as checagens a qualquer momento.
-- Migrations futuras do ObraCerta devem começar com: set role obra_owner;
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Identidade do usuário sem depender do schema auth
-- ---------------------------------------------------------------------
create or replace function obra.uid()
returns uuid language sql stable set search_path = '' as $$
  select nullif(coalesce(current_setting('request.jwt.claim.sub', true),
                         (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')), '')::uuid;
$$;

create or replace function obra.jwt()
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb;
$$;

-- reescreve as funções do schema obra trocando auth.uid()/auth.jwt() por obra.uid()/obra.jwt()
do $$
declare r record;
begin
  for r in select p.oid from pg_proc p
            where p.pronamespace = 'obra'::regnamespace
              and p.proname not in ('uid','jwt')
              and (p.prosrc like '%auth.uid()%' or p.prosrc like '%auth.jwt()%') loop
    execute replace(replace(pg_get_functiondef(r.oid), 'auth.uid()', 'obra.uid()'), 'auth.jwt()', 'obra.jwt()');
  end loop;
end $$;

-- defaults de coluna (criado_por, usuario_id da auditoria)
do $$
declare r record;
begin
  for r in select table_name, column_name from information_schema.columns
            where table_schema = 'obra' and column_default like '%auth.uid()%' loop
    execute format('alter table obra.%I alter column %I set default obra.uid()', r.table_name, r.column_name);
  end loop;
end $$;

-- membro deixa de referenciar auth.users (o vínculo é garantido por obra.aceitar_convites/criar_obra)
alter table obra.obra_membro drop constraint if exists obra_membro_usuario_id_fkey;

-- ---------------------------------------------------------------------
-- 2. Dono dedicado do schema, sem privilégios fora dele
-- ---------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'obra_owner') then
    create role obra_owner nologin noinherit;
  end if;
end $$;
grant obra_owner to current_user;          -- necessário para transferir a posse
grant usage, create on schema obra to obra_owner;

do $$
declare r record;
begin
  for r in select c.relname, c.relkind from pg_class c
            where c.relnamespace = 'obra'::regnamespace and c.relkind in ('r','v','m','p') loop
    execute format('alter %s obra.%I owner to obra_owner',
                   case r.relkind when 'v' then 'view' when 'm' then 'materialized view' else 'table' end,
                   r.relname);
  end loop;
  for r in select p.oid from pg_proc p where p.pronamespace = 'obra'::regnamespace loop
    execute format('alter function %s owner to obra_owner', r.oid::regprocedure);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 3. Verificação de isolamento (deve retornar zero em todas as linhas)
-- ---------------------------------------------------------------------
create or replace function obra.verificar_isolamento()
returns table (checagem text, ocorrencias bigint)
language sql stable security definer set search_path = '' as $$
  select 'dependencias de objetos obra em objetos public', count(*)
    from pg_catalog.pg_depend d
    join pg_catalog.pg_class c on c.oid = d.objid and c.relnamespace = 'obra'::regnamespace
    join pg_catalog.pg_class r on r.oid = d.refobjid and r.relnamespace = 'public'::regnamespace
  union all
  select 'triggers em tabelas public chamando funcoes obra', count(*)
    from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid = t.tgrelid
    join pg_catalog.pg_proc p on p.oid = t.tgfoid
   where c.relnamespace = 'public'::regnamespace and p.pronamespace = 'obra'::regnamespace
  union all
  select 'policies em tabelas public citando obra', count(*)
    from pg_catalog.pg_policies
   where schemaname = 'public' and (coalesce(qual, '') ilike '%obra.%' or coalesce(with_check, '') ilike '%obra.%')
  union all
  select 'funcoes obra citando public. ou auth.', count(*)
    from pg_catalog.pg_proc
   where pronamespace = 'obra'::regnamespace and proname <> 'verificar_isolamento'
     and (prosrc ilike '%public.%' or prosrc ilike '%auth.%')
  union all
  select 'views obra citando public.', count(*)
    from pg_catalog.pg_views where schemaname = 'obra' and definition ilike '%public.%'
  union all
  select 'objetos obra com dono diferente de obra_owner', count(*)
    from (select relowner o from pg_catalog.pg_class where relnamespace = 'obra'::regnamespace and relkind in ('r','v','m','p')
          union all
          select proowner from pg_catalog.pg_proc where pronamespace = 'obra'::regnamespace) x
   where pg_catalog.pg_get_userbyid(x.o) <> 'obra_owner'
  union all
  select 'tabelas public que obra_owner consegue ler ou alterar', count(*)
    from pg_catalog.pg_class c
   where c.relnamespace = 'public'::regnamespace and c.relkind in ('r','p','v','m')
     and pg_catalog.has_table_privilege('obra_owner', c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
  union all
  select 'chaves estrangeiras de obra para fora do schema', count(*)
    from pg_catalog.pg_constraint
   where connamespace = 'obra'::regnamespace and contype = 'f'
     and (select relnamespace from pg_catalog.pg_class where oid = confrelid) <> 'obra'::regnamespace;
$$;
alter function obra.verificar_isolamento() owner to obra_owner;
grant execute on function obra.uid(), obra.jwt(), obra.verificar_isolamento() to authenticated;
revoke execute on function obra.verificar_isolamento() from anon, public;
