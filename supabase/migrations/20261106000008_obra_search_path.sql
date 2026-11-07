-- =====================================================================
-- ObraCerta · 008 · search_path fixo em todas as funções do schema obra
-- (alerta 0011 do linter do Supabase). Todo o código já usa nomes qualificados (obra.*).
-- Convenção a partir daqui: migrations do ObraCerta rodam como obra_owner.
-- =====================================================================
set role obra_owner;
do $$
declare r record;
begin
  for r in select p.oid from pg_proc p
            where p.pronamespace = 'obra'::regnamespace
              and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%') loop
    execute format('alter function %s set search_path = %L', r.oid::regprocedure, '');
  end loop;
end $$;
reset role;
