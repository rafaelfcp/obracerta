-- =====================================================================
-- ObraCerta · 009 · Privilégios padrão para objetos futuros do obra_owner
-- Só o role authenticated (usuário logado) recebe acesso; anon não recebe nada.
-- Diferente do exemplo da documentação do Supabase (GRANT ALL a anon): aqui o
-- acesso mínimo é deliberado, e DELETE continua negado (exclusão é lógica).
-- =====================================================================
alter default privileges for role obra_owner in schema obra grant select, insert, update on tables to authenticated;
alter default privileges for role obra_owner in schema obra grant usage on sequences to authenticated;
alter default privileges for role obra_owner in schema obra grant execute on functions to authenticated;
alter default privileges for role obra_owner in schema obra revoke execute on functions from public;
grant usage on schema obra to service_role;
