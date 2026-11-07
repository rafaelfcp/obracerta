-- ObraCerta 013 — Geração de Relatórios (aplicada em produção como obra_011_relatorios em 07/11/2026)
-- 1) obra.relatorio_status_etapas(obra): JSON com o resumo de status das etapas
-- 2) obra.relatorio_envio: log imutável de envios por e-mail (quem, para quem, o quê, resultado)
-- Isolamento: tudo pertence a obra_owner; nada toca o schema public.
set role obra_owner;

-- ---------------------------------------------------------------------------
-- Validação de e-mails (CHECK não aceita subquery, então vai numa função imutável)
-- ---------------------------------------------------------------------------
create or replace function obra.emails_validos(p text[])
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p is not null
     and not exists (select 1 from unnest(p) d
                      where d is null
                         or length(d) > 254
                         or d !~* '^[A-Z0-9._%+\-]+@[A-Z0-9\-]+(\.[A-Z0-9\-]+)*\.[A-Z]{2,}$');
$$;

-- ---------------------------------------------------------------------------
-- Log de envios
-- ---------------------------------------------------------------------------
create table obra.relatorio_envio (
  id             uuid primary key default gen_random_uuid(),
  obra_id        uuid not null references obra.obra(id),
  tipo           text not null check (tipo in ('status_etapas')),
  destinatarios  text[] not null,
  assunto        text not null check (length(assunto) between 1 and 200),
  mensagem       text check (length(mensagem) <= 2000),
  parametros     jsonb not null default '{}'::jsonb,
  resumo         jsonb not null default '{}'::jsonb,   -- totais do relatório no momento do envio
  status         text not null check (status in ('enviado','erro')),
  provedor_id    text,
  erro           text,
  criado_em      timestamptz not null default now(),
  criado_por     uuid not null default obra.uid(),
  constraint relatorio_envio_qtd_dest check (cardinality(destinatarios) between 1 and 10),
  constraint relatorio_envio_dest_validos check (obra.emails_validos(destinatarios))
);

create index relatorio_envio_obra_idx on obra.relatorio_envio (obra_id, criado_em desc);
create index relatorio_envio_user_idx on obra.relatorio_envio (criado_por, criado_em desc);

alter table obra.relatorio_envio enable row level security;

create policy relatorio_envio_select on obra.relatorio_envio
  for select to authenticated
  using (obra.eh_membro(obra_id));

create policy relatorio_envio_insert on obra.relatorio_envio
  for insert to authenticated
  with check (obra.eh_membro(obra_id) and criado_por = obra.uid());

-- Log é imutável: sem UPDATE/DELETE para authenticated
revoke update, delete, truncate on obra.relatorio_envio from authenticated;

-- ---------------------------------------------------------------------------
-- Relatório: Resumo de Status das Etapas
-- security invoker: lê via views security_invoker, então a RLS do usuário vale.
-- ---------------------------------------------------------------------------
create or replace function obra.relatorio_status_etapas(p_obra uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_obra   jsonb;
  v_etapas jsonb;
  v_totais jsonb;
begin
  perform obra.exigir_membro(p_obra);

  select jsonb_build_object(
           'id', p.obra_id, 'nome', p.nome, 'status_geral', p.status_geral,
           'inicio_previsto', p.inicio_previsto, 'conclusao_prevista', p.conclusao_prevista,
           'orcado_total', round(p.orcado_total, 2), 'orcado_obra', round(p.orcado_obra, 2),
           'pago', round(p.pago, 2), 'contratado', round(p.contratado, 2),
           'pct_fisico', round(p.pct_fisico, 4),
           'pct_financeiro_pago', round(p.pct_financeiro_pago, 4),
           'etapas_atrasadas', p.etapas_atrasadas, 'semaforo', p.semaforo)
    into v_obra
    from obra.v_obra_painel p
   where p.obra_id = p_obra;

  if v_obra is null then
    raise exception 'OC_NAO_ENCONTRADO: obra não encontrada' using errcode = 'P0002';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'ordem', e.ordem, 'nome', e.nome,
           'status', e.status, 'situacao', e.situacao_kanban,
           'responsavel', e.responsavel,
           'inicio_previsto', e.inicio_previsto, 'fim_previsto', e.fim_previsto,
           'inicio_real', e.inicio_real, 'fim_real', e.fim_real,
           'pct_fisico', round(coalesce(e.pct_fisico, 0), 4),
           'pct_financeiro', round(e.pct_financeiro, 4),
           'orcado', round(e.orcado, 2), 'contratado', round(e.contratado, 2),
           'pago', round(e.pago, 2), 'a_pagar', round(e.a_pagar, 2),
           'desvio', round(e.desvio, 2), 'desvio_pct', round(e.desvio_pct, 4),
           'atrasada', coalesce(e.atrasada, false), 'semaforo', e.semaforo
         ) order by e.ordem), '[]'::jsonb)
    into v_etapas
    from obra.v_etapa_painel e
   where e.obra_id = p_obra;

  select jsonb_build_object(
           'etapas', count(*),
           'planejada',    count(*) filter (where e.status = 'planejada'),
           'em_andamento', count(*) filter (where e.status = 'em_andamento'),
           'pausada',      count(*) filter (where e.status = 'pausada'),
           'concluida',    count(*) filter (where e.status = 'concluida'),
           'cancelada',    count(*) filter (where e.status = 'cancelada'),
           'atrasadas',    count(*) filter (where e.atrasada),
           'sem_orcamento',count(*) filter (where e.semaforo = 'sem_orcamento'),
           'sem_datas',    count(*) filter (where e.inicio_previsto is null or e.fim_previsto is null),
           'orcado',       round(coalesce(sum(e.orcado), 0), 2),
           'contratado',   round(coalesce(sum(e.contratado), 0), 2),
           'pago',         round(coalesce(sum(e.pago), 0), 2))
    into v_totais
    from obra.v_etapa_painel e
   where e.obra_id = p_obra;

  return jsonb_build_object(
    'tipo', 'status_etapas',
    'gerado_em', now(),
    'obra', v_obra,
    'totais', v_totais,
    'etapas', v_etapas);
end $$;

revoke all on function obra.relatorio_status_etapas(uuid) from public;
grant execute on function obra.relatorio_status_etapas(uuid) to authenticated;

-- Quantos envios o usuário fez na última hora (usado no rate limit da Edge Function)
create or replace function obra.relatorio_envios_ultima_hora()
returns integer
language sql
stable
security invoker
set search_path = ''
as $$
  select count(*)::int from obra.relatorio_envio
   where criado_por = obra.uid() and criado_em > now() - interval '1 hour';
$$;

revoke all on function obra.relatorio_envios_ultima_hora() from public;
grant execute on function obra.relatorio_envios_ultima_hora() to authenticated;

reset role;
