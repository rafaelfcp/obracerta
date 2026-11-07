-- =====================================================================
-- ObraCerta · 003 · Views de cálculo
-- Todas com security_invoker = true: a RLS das tabelas vale para quem consulta.
-- Regra de ouro: valor previsto nunca conta como realizado.
-- =====================================================================

-- Pago por origem (contrato ou despesa avulsa). Despesa dentro de contrato soma no contrato.
create view obra.v_origem_pago with (security_invoker = true) as
select pa.obra_id,
       coalesce(d.contrato_id, pa.contrato_id)                 as contrato_id,
       case when d.contrato_id is null then pa.despesa_id end   as despesa_id,
       sum(pg.valor)                                            as pago
  from obra.pagamento pg
  join obra.parcela pa on pa.id = pg.parcela_id and pa.excluido_em is null
  left join obra.despesa d on d.id = pa.despesa_id
 where pg.excluido_em is null
 group by 1, 2, 3;

-- Cada linha de rateio com o comprometido e o pago proporcional da sua origem
create view obra.v_rateio_valor with (security_invoker = true) as
with tot as (
  select contrato_id, despesa_id, sum(valor) total
    from obra.rateio where excluido_em is null group by 1, 2
)
select r.id, r.obra_id, r.contrato_id, r.despesa_id, r.orcamento_item_id, r.etapa_id, r.ambiente_id,
       coalesce(c.fornecedor_id, d.fornecedor_id)            as fornecedor_id,
       d.categoria_id,
       coalesce(cat.sinal, 1)                                as sinal,
       coalesce(c.data_assinatura, d.data)                   as data_compromisso,
       r.valor * coalesce(cat.sinal, 1)                      as comprometido,
       round(coalesce(op.pago, 0) * r.valor / nullif(tot.total, 0), 2) * coalesce(cat.sinal, 1) as pago
  from obra.rateio r
  join tot on tot.contrato_id is not distinct from r.contrato_id
          and tot.despesa_id  is not distinct from r.despesa_id
  left join obra.contrato c   on c.id = r.contrato_id
  left join obra.despesa  d   on d.id = r.despesa_id
  left join obra.categoria cat on cat.id = d.categoria_id
  left join obra.v_origem_pago op on op.contrato_id is not distinct from r.contrato_id
                                 and op.despesa_id  is not distinct from r.despesa_id
 where r.excluido_em is null
   and (c.id is null or (c.excluido_em is null and c.status in ('ativo','concluido','em_renegociacao')))
   and (d.id is null or (d.excluido_em is null and d.status <> 'cancelada'));

-- ---------------------------------------------------------------------
-- Item
-- ---------------------------------------------------------------------
create view obra.v_item_resumo with (security_invoker = true) as
select i.id, i.obra_id, i.tipo_custo, i.etapa_id, i.ambiente_id, i.categoria_id, i.classe, i.grupo,
       i.descricao, i.unidade, i.quantidade, i.cenario_escolhido, i.prioridade, i.incluido,
       i.estimativa, i.revisar, i.revisar_motivos, i.grupo_alternativa, i.numero_origem,
       case when i.incluido then i.valor_orcado else 0 end           as orcado,
       i.valor_orcado                                                 as valor_orcado_cenario,
       coalesce(rv.comprometido, 0)                                    as contratado,
       coalesce(rv.pago, 0)                                            as pago,
       coalesce(rv.comprometido, 0) - coalesce(rv.pago, 0)             as a_pagar,
       case when i.incluido then i.valor_orcado else 0 end - coalesce(rv.comprometido, 0) as saldo_orcamento,
       greatest(case when i.incluido then i.valor_orcado else 0 end,
                coalesce(rv.comprometido, 0), coalesce(rv.pago, 0))    as projetado,
       case when coalesce(rv.comprometido, 0) > 0 or coalesce(rv.pago, 0) > 0
            then greatest(coalesce(rv.comprometido, 0), coalesce(rv.pago, 0))
                 - case when i.incluido then i.valor_orcado else 0 end
            else 0 end                                                 as desvio
  from obra.orcamento_item i
  left join (select orcamento_item_id, sum(comprometido) comprometido, sum(pago) pago
               from obra.v_rateio_valor group by 1) rv on rv.orcamento_item_id = i.id
 where i.excluido_em is null;

-- ---------------------------------------------------------------------
-- Etapa (com rateio do custo indireto proporcional ao orçado direto)
-- ---------------------------------------------------------------------
create view obra.v_etapa_resumo with (security_invoker = true) as
with direto as (
  select e.id etapa_id, e.obra_id, e.recebe_indireto,
         coalesce(sum(ir.orcado) filter (where ir.tipo_custo = 'direto'), 0) orcado_direto,
         coalesce(sum(ir.desvio) filter (where ir.tipo_custo = 'direto'), 0) desvio_itens
    from obra.etapa e
    left join obra.v_item_resumo ir on ir.etapa_id = e.id
   where e.excluido_em is null
   group by 1, 2, 3
),
base as (
  select obra_id, sum(orcado_direto) filter (where recebe_indireto) base_indireto
    from direto group by 1
),
indireto as (
  select ir.obra_id, sum(ir.orcado) orcado, sum(ir.contratado) contratado, sum(ir.pago) pago
    from obra.v_item_resumo ir where ir.tipo_custo = 'indireto' group by 1
),
exec as (  -- compromissos lançados direto na etapa (rateios de itens diretos ou sem item)
  select rv.etapa_id, sum(rv.comprometido) contratado, sum(rv.pago) pago
    from obra.v_rateio_valor rv
    left join obra.orcamento_item i on i.id = rv.orcamento_item_id
   where coalesce(i.tipo_custo, 'direto') = 'direto' and rv.etapa_id is not null
   group by 1
)
select e.id, e.obra_id, e.ordem, e.nome, e.status, e.situacao_kanban,
       e.inicio_previsto, e.fim_previsto, e.inicio_real, e.fim_real,
       e.pct_fisico, e.recebe_indireto, e.fornecedor_principal_id, e.responsavel,
       d.orcado_direto,
       d.desvio_itens,
       coalesce(case when d.recebe_indireto and b.base_indireto > 0
                     then d.orcado_direto / b.base_indireto end, 0)                         as fator_indireto,
       round(d.orcado_direto + coalesce(case when d.recebe_indireto and b.base_indireto > 0
                     then ind.orcado * d.orcado_direto / b.base_indireto end, 0), 2)        as orcado,
       round(coalesce(x.contratado, 0) + coalesce(case when d.recebe_indireto and b.base_indireto > 0
                     then ind.contratado * d.orcado_direto / b.base_indireto end, 0), 2)    as contratado,
       round(coalesce(x.pago, 0) + coalesce(case when d.recebe_indireto and b.base_indireto > 0
                     then ind.pago * d.orcado_direto / b.base_indireto end, 0), 2)          as pago,
       (e.fim_previsto < current_date and e.status not in ('concluida','cancelada'))
         or (e.inicio_previsto < current_date and e.inicio_real is null and e.status = 'planejada') as atrasada
  from obra.etapa e
  join direto d on d.etapa_id = e.id
  left join base b on b.obra_id = e.obra_id
  left join indireto ind on ind.obra_id = e.obra_id
  left join exec x on x.etapa_id = e.id
 where e.excluido_em is null;

-- Indicadores derivados por etapa (semáforo)
create view obra.v_etapa_painel with (security_invoker = true) as
-- desvio = soma dos desvios dos itens já contratados/pagos (itens sem compromisso não contam);
-- projetado = orçado + desvio (o que a etapa deve custar, olhando os compromissos de hoje)
select er.*,
       er.contratado - er.pago                                  as a_pagar,
       er.orcado - er.contratado                                as saldo_orcamento,
       greatest(er.orcado + er.desvio_itens, er.contratado, er.pago) as projetado,
       er.desvio_itens                                          as desvio,
       case when er.orcado > 0 then round(er.desvio_itens / er.orcado, 4) end as desvio_pct,
       case when er.orcado > 0 then round(er.pago / er.orcado, 4) end     as pct_financeiro,
       case
         when er.orcado = 0 and er.contratado = 0 then 'sem_orcamento'
         when er.orcado = 0 then 'vermelho'
         when greatest(er.orcado + er.desvio_itens, er.contratado) > er.orcado * o.limite_estouro_pct then 'vermelho'
         when greatest(er.orcado + er.desvio_itens, er.contratado) > er.orcado * o.limite_atencao_pct then 'amarelo'
         else 'verde'
       end as semaforo
  from obra.v_etapa_resumo er
  join obra.obra o on o.id = er.obra_id;

-- ---------------------------------------------------------------------
-- Ambiente
-- ---------------------------------------------------------------------
create view obra.v_ambiente_painel with (security_invoker = true) as
with it as (
  select ambiente_id, obra_id, sum(orcado) orcado from obra.v_item_resumo
   where tipo_custo <> 'aquisicao_lote' group by 1, 2
),
rv as (
  select ambiente_id, obra_id, sum(comprometido) contratado, sum(pago) pago,
         count(*) lancamentos
    from obra.v_rateio_valor group by 1, 2
)
select a.id, a.obra_id, a.ordem, a.nome, a.pavimento, a.area_m2,
       coalesce(it.orcado, 0)      as orcado,
       coalesce(rv.contratado, 0)  as contratado,
       coalesce(rv.pago, 0)        as pago,
       coalesce(rv.contratado, 0) - coalesce(rv.pago, 0) as a_pagar,
       coalesce(rv.lancamentos, 0) = 0 as sem_gasto,
       case
         when coalesce(it.orcado, 0) = 0 and coalesce(rv.contratado, 0) = 0 then 'sem_orcamento'
         when coalesce(it.orcado, 0) = 0 then 'vermelho'
         when greatest(coalesce(rv.contratado,0), coalesce(rv.pago,0)) > it.orcado * o.limite_estouro_pct then 'vermelho'
         when greatest(coalesce(rv.contratado,0), coalesce(rv.pago,0)) > it.orcado * o.limite_atencao_pct then 'amarelo'
         else 'verde'
       end as semaforo
  from obra.ambiente a
  join obra.obra o on o.id = a.obra_id
  left join it on it.ambiente_id = a.id
  left join rv on rv.ambiente_id = a.id
 where a.excluido_em is null;

-- ---------------------------------------------------------------------
-- Parcelas (agenda de pagamentos)
-- ---------------------------------------------------------------------
create view obra.v_parcela_agenda with (security_invoker = true) as
select pa.id, pa.obra_id, pa.numero, pa.vencimento, pa.valor, pa.status,
       pa.contrato_id, pa.despesa_id,
       coalesce(c.objeto, d.descricao)                       as descricao,
       coalesce(c.fornecedor_id, d.fornecedor_id)            as fornecedor_id,
       f.nome                                                as fornecedor,
       coalesce(pg.pago, 0)                                  as pago,
       pa.valor - coalesce(pg.pago, 0)                       as saldo,
       pa.vencimento - current_date                          as dias_para_vencer,
       pa.status in ('prevista','parcial') and pa.vencimento < current_date as atrasada,
       (select count(*) from obra.parcela p2
         where coalesce(p2.contrato_id, p2.despesa_id) = coalesce(pa.contrato_id, pa.despesa_id)
           and p2.excluido_em is null) as total_parcelas
  from obra.parcela pa
  left join obra.contrato c on c.id = pa.contrato_id
  left join obra.despesa  d on d.id = pa.despesa_id
  left join obra.fornecedor f on f.id = coalesce(c.fornecedor_id, d.fornecedor_id)
  left join (select parcela_id, sum(valor) pago from obra.pagamento where excluido_em is null group by 1) pg
         on pg.parcela_id = pa.id
 where pa.excluido_em is null and pa.status <> 'cancelada'
   and (c.id is null or (c.excluido_em is null and c.status <> 'cancelada'))
   and (d.id is null or (d.excluido_em is null and d.status <> 'cancelada'));

-- ---------------------------------------------------------------------
-- Fornecedor
-- ---------------------------------------------------------------------
create view obra.v_fornecedor_painel with (security_invoker = true) as
select f.id, f.obra_id, f.nome, f.especialidade,
       coalesce(rv.contratado, 0) as contratado,
       coalesce(rv.pago, 0)       as pago,
       coalesce(ag.a_pagar, 0)    as a_pagar,
       ag.proximo_vencimento,
       coalesce(ag.atrasadas, 0)  as parcelas_atrasadas
  from obra.fornecedor f
  left join (select fornecedor_id, sum(comprometido) contratado, sum(pago) pago
               from obra.v_rateio_valor group by 1) rv on rv.fornecedor_id = f.id
  left join (select fornecedor_id, sum(saldo) filter (where status <> 'paga') a_pagar,
                    min(vencimento) filter (where status in ('prevista','parcial')) proximo_vencimento,
                    count(*) filter (where atrasada) atrasadas
               from obra.v_parcela_agenda group by 1) ag on ag.fornecedor_id = f.id
 where f.excluido_em is null;

-- ---------------------------------------------------------------------
-- Gastos por mês e categoria (realizado = pagamentos)
-- ---------------------------------------------------------------------
create view obra.v_gasto_mensal with (security_invoker = true) as
select pg.obra_id,
       date_trunc('month', pg.data)::date                      as mes,
       coalesce(cat.nome, case when pa.contrato_id is not null then 'Contratos' else 'Sem categoria' end) as categoria,
       coalesce(cat.natureza, 'outros')                         as natureza,
       sum(pg.valor * coalesce(cat.sinal, 1))                   as pago
  from obra.pagamento pg
  join obra.parcela pa on pa.id = pg.parcela_id
  left join obra.despesa d on d.id = pa.despesa_id
  left join obra.categoria cat on cat.id = d.categoria_id
 where pg.excluido_em is null and pa.excluido_em is null
 group by 1, 2, 3, 4;

-- ---------------------------------------------------------------------
-- Reserva
-- ---------------------------------------------------------------------
create view obra.v_reserva_resumo with (security_invoker = true) as
with ancora as (
  select distinct on (obra_id) obra_id, data, saldo_bruto
    from (select obra_id, data, sum(saldo_bruto) saldo_bruto
            from obra.reserva_saldo where excluido_em is null group by 1, 2) s
   order by obra_id, data desc
),
mov as (
  select m.obra_id,
         sum(m.valor) filter (where not m.previsto)                                   as mov_total,
         sum(m.valor) filter (where not m.previsto and m.data > a.data)               as mov_pos_ancora,
         sum(m.valor) filter (where not m.previsto and m.tipo in ('aporte_mensal','aporte_eventual')) as aportes,
         sum(m.valor) filter (where not m.previsto and m.tipo = 'rendimento')         as rendimentos
    from obra.reserva_movimento m
    left join ancora a on a.obra_id = m.obra_id
   where m.excluido_em is null
   group by 1
),
pag as (
  select pg.obra_id, sum(pg.valor) total,
         sum(pg.valor) filter (where pg.data > a.data) pos_ancora
    from obra.pagamento pg
    left join ancora a on a.obra_id = pg.obra_id
   where pg.excluido_em is null and pg.fonte = 'reserva'
   group by 1
),
fgts as (
  select obra_id,
         sum(valor) filter (where status in ('previsto','solicitado')) previsto,
         sum(valor) filter (where status = 'liberado')                 liberado,
         sum(valor) filter (where status = 'utilizado')                utilizado
    from obra.fgts_evento where excluido_em is null group by 1
)
select o.id as obra_id,
       a.data                                as data_ultimo_saldo,
       case when a.obra_id is not null
            then a.saldo_bruto + coalesce(mv.mov_pos_ancora, 0) - coalesce(pg.pos_ancora, 0)
            -- sem leitura de saldo: só há saldo se houver movimentos registrados
            when mv.mov_total is not null
            then mv.mov_total - coalesce(pg.total, 0) end               as saldo_reserva,
       coalesce(mv.aportes, 0)               as aportes,
       coalesce(mv.rendimentos, 0)           as rendimentos,
       coalesce(seg.valor_alvo, 0)           as reserva_seguranca,
       coalesce(f.previsto, 0)               as fgts_previsto,
       coalesce(f.liberado, 0)               as fgts_liberado,
       coalesce(f.utilizado, 0)              as fgts_utilizado
  from obra.obra o
  left join ancora a on a.obra_id = o.id
  left join mov mv on mv.obra_id = o.id
  left join pag pg on pg.obra_id = o.id
  left join fgts f on f.obra_id = o.id
  left join obra.reserva_balde seg on seg.obra_id = o.id and seg.balde = 'seguranca'
 where o.excluido_em is null;

-- ---------------------------------------------------------------------
-- Obra: o painel principal
-- ---------------------------------------------------------------------
create view obra.v_obra_resumo with (security_invoker = true) as
with it as (
  select obra_id,
         sum(orcado) filter (where tipo_custo = 'aquisicao_lote')  as orcado_lote,
         sum(orcado) filter (where tipo_custo <> 'aquisicao_lote') as orcado_obra,
         sum(projetado) filter (where tipo_custo <> 'aquisicao_lote') as projetado_obra,
         sum(projetado) filter (where tipo_custo = 'aquisicao_lote') as projetado_lote,
         sum(greatest(desvio, 0))                                  as estouros
    from obra.v_item_resumo group by 1
),
base_cont as (
  select i.obra_id, sum(i.valor_orcado) base
    from obra.orcamento_item i
   where i.excluido_em is null and i.incluido and i.base_contingencia group by 1
),
sem_item as (  -- compromissos lançados sem item de orçamento
  select obra_id, sum(comprometido) comprometido from obra.v_rateio_valor
   where orcamento_item_id is null group by 1
),
rv as (
  select obra_id, sum(comprometido) contratado from obra.v_rateio_valor group by 1
),
pg as (
  select obra_id, sum(valor) pago,
         sum(valor) filter (where fonte = 'caixa') pago_caixa,
         sum(valor) filter (where fonte = 'fgts')  pago_fgts
    from obra.pagamento where excluido_em is null group by 1
),
ap as (
  select obra_id, sum(saldo) a_pagar,
         sum(saldo) filter (where atrasada) atrasado,
         count(*) filter (where atrasada) parcelas_atrasadas
    from obra.v_parcela_agenda where status <> 'paga' group by 1
),
fis as (
  select obra_id, sum(pct_fisico * orcado) / nullif(sum(orcado), 0) pct_fisico,
         count(*) filter (where atrasada) etapas_atrasadas
    from obra.v_etapa_resumo group by 1
),
lib as (
  select obra_id, sum(valor_liberado) filter (where not previsto) liberado
    from obra.financiamento_liberacao where excluido_em is null group by 1
),
sim as (
  select obra_id, (resultado ->> 'valor_financiado')::numeric valor_financiado,
         (resultado ->> 'juros_obra')::numeric juros_obra, nome
    from obra.financiamento_simulacao where ativa and excluido_em is null
)
select o.id as obra_id, o.nome, o.status_geral, o.inicio_previsto, o.conclusao_prevista,
       coalesce(it.orcado_lote, 0)                                         as orcado_lote,
       coalesce(it.orcado_obra, 0)                                         as orcado_obra,
       round(o.contingencia_pct * coalesce(bc.base, 0), 2)                 as contingencia,
       coalesce(it.orcado_lote, 0) + coalesce(it.orcado_obra, 0)
         + round(o.contingencia_pct * coalesce(bc.base, 0), 2)             as orcado_total,
       coalesce(rv.contratado, 0)                                          as contratado,
       coalesce(pg.pago, 0)                                                as pago,
       coalesce(ap.a_pagar, 0)                                             as a_pagar,
       coalesce(ap.atrasado, 0)                                            as atrasado,
       coalesce(ap.parcelas_atrasadas, 0)                                  as parcelas_atrasadas,
       coalesce(it.estouros, 0)                                            as estouros,
       greatest(round(o.contingencia_pct * coalesce(bc.base, 0), 2) - coalesce(it.estouros, 0), 0) as contingencia_disponivel,
       -- custo projetado na conclusão
       coalesce(it.projetado_lote, 0) + coalesce(it.projetado_obra, 0) + coalesce(si.comprometido, 0)
         + greatest(round(o.contingencia_pct * coalesce(bc.base, 0), 2) - coalesce(it.estouros, 0), 0) as custo_projetado,
       round(coalesce(fis.pct_fisico, 0), 4)                               as pct_fisico,
       coalesce(fis.etapas_atrasadas, 0)                                   as etapas_atrasadas,
       r.saldo_reserva, r.reserva_seguranca, r.fgts_previsto, r.fgts_liberado, r.fgts_utilizado,
       coalesce(lib.liberado, 0)                                           as caixa_liberado,
       sim.valor_financiado                                                as financiamento_ativo,
       coalesce(sim.juros_obra, 0)                                         as juros_obra_previstos,
       sim.nome                                                            as simulacao_ativa
  from obra.obra o
  left join it on it.obra_id = o.id
  left join base_cont bc on bc.obra_id = o.id
  left join sem_item si on si.obra_id = o.id
  left join rv on rv.obra_id = o.id
  left join pg on pg.obra_id = o.id
  left join ap on ap.obra_id = o.id
  left join fis on fis.obra_id = o.id
  left join obra.v_reserva_resumo r on r.obra_id = o.id
  left join lib on lib.obra_id = o.id
  left join sim on sim.obra_id = o.id
 where o.excluido_em is null;

-- Indicadores derivados do painel (separado para manter as fórmulas legíveis)
create view obra.v_obra_painel with (security_invoker = true) as
select v.*,
       v.custo_projetado - v.orcado_total                                   as desvio,
       case when v.orcado_total > 0 then round((v.custo_projetado - v.orcado_total) / v.orcado_total, 4) end as desvio_pct,
       case when v.custo_projetado > 0 then round(v.pago / v.custo_projetado, 4) end as pct_financeiro_pago,
       case when v.custo_projetado > 0 then round(v.contratado / v.custo_projetado, 4) end as pct_financeiro_comprometido,
       v.custo_projetado - v.pago                                           as valor_restante,
       -- disponível para novos gastos: reserva sem a segurança + FGTS liberado + Caixa liberado não usado - a pagar
       -- (null enquanto não houver leitura de saldo da reserva)
       v.saldo_reserva - coalesce(v.reserva_seguranca, 0)
         + coalesce(v.fgts_liberado, 0) + greatest(v.caixa_liberado - coalesce((select sum(valor) from obra.pagamento
                 where obra_id = v.obra_id and fonte = 'caixa' and excluido_em is null), 0), 0)
         - v.a_pagar                                                        as saldo_disponivel,
       -- necessidade de recurso complementar: o que falta pagar (+ juros de obra da simulação ativa)
       -- menos as fontes ainda não usadas (reserva livre + FGTS não utilizado + financiamento não gasto)
       greatest(v.custo_projetado - v.pago + v.juros_obra_previstos
                - greatest(coalesce(v.saldo_reserva, 0) - coalesce(v.reserva_seguranca, 0), 0)
                - coalesce(v.fgts_previsto, 0) - coalesce(v.fgts_liberado, 0)
                - greatest(coalesce(v.financiamento_ativo, 0) - coalesce((select sum(valor) from obra.pagamento
                      where obra_id = v.obra_id and fonte = 'caixa' and excluido_em is null), 0), 0), 0)
                                                                            as necessidade_complementar,
       case
         when v.custo_projetado > v.orcado_total * o.limite_estouro_pct then 'vermelho'
         when v.custo_projetado > v.orcado_total * o.limite_atencao_pct then 'amarelo'
         else 'verde'
       end as semaforo
  from obra.v_obra_resumo v
  join obra.obra o on o.id = v.obra_id;

-- ---------------------------------------------------------------------
-- Curva S simplificada (planejado linear por etapa x realizado)
-- ---------------------------------------------------------------------
create view obra.v_curva_s with (security_invoker = true) as
with lim as (
  select obra_id,
         date_trunc('month', least(min(inicio_previsto), coalesce((select min(data) from obra.pagamento p
                    where p.obra_id = e.obra_id and p.excluido_em is null), min(inicio_previsto))))::date ini,
         date_trunc('month', greatest(max(fim_previsto), current_date))::date fim
    from obra.v_etapa_resumo e
   where inicio_previsto is not null and fim_previsto is not null
   group by obra_id
),
meses as (
  select l.obra_id, generate_series(l.ini, l.fim, interval '1 month')::date mes from lim l
),
plan as (
  select m.obra_id, m.mes,
         sum(e.orcado * greatest(0, least(1,
             ((least((m.mes + interval '1 month')::date, e.fim_previsto + 1) - e.inicio_previsto)::numeric)
             / nullif((e.fim_previsto + 1 - e.inicio_previsto), 0)))) acum
    from meses m
    join obra.v_etapa_resumo e on e.obra_id = m.obra_id
   where e.inicio_previsto is not null and e.fim_previsto is not null
   group by 1, 2
),
real as (
  select m.obra_id, m.mes,
         (select coalesce(sum(p.valor), 0) from obra.pagamento p
           where p.obra_id = m.obra_id and p.excluido_em is null
             and p.data < (m.mes + interval '1 month')::date) acum
    from meses m
)
select p.obra_id, p.mes,
       round(p.acum, 2)                                   as planejado_acumulado,
       case when p.mes <= current_date then r.acum end    as realizado_acumulado
  from plan p join real r using (obra_id, mes);

-- ---------------------------------------------------------------------
-- Alertas consolidados
-- ---------------------------------------------------------------------
create view obra.v_alerta with (security_invoker = true) as
select obra_id, 'vermelho' nivel, 'parcela_atrasada' tipo,
       'Parcela vencida: ' || coalesce(fornecedor || ' — ', '') || descricao as mensagem,
       'parcela' entidade, id entidade_id, vencimento as data_ref, saldo as valor
  from obra.v_parcela_agenda where atrasada
union all
select obra_id, 'amarelo', 'parcela_vencendo',
       'Vence em ' || dias_para_vencer || ' dia(s): ' || coalesce(fornecedor || ' — ', '') || descricao,
       'parcela', id, vencimento, saldo
  from obra.v_parcela_agenda where status in ('prevista','parcial') and dias_para_vencer between 0 and 3
union all
select obra_id, 'vermelho', 'item_estouro',
       'Acima do orçado: ' || descricao, 'orcamento_item', id, null::date, desvio
  from obra.v_item_resumo where desvio > 0.005
union all
select obra_id, 'vermelho', 'etapa_atrasada', 'Etapa atrasada: ' || nome, 'etapa', id, fim_previsto, null
  from obra.v_etapa_resumo where atrasada
union all
select obra_id, 'cinza', 'etapa_sem_orcamento', 'Etapa sem orçamento: ' || nome, 'etapa', id, null, null
  from obra.v_etapa_painel where semaforo = 'sem_orcamento' and status <> 'cancelada'
union all
select r.obra_id, 'cinza', 'gasto_sem_classificacao',
       'Gasto sem ' || case when r.etapa_id is null and r.ambiente_id is null then 'etapa e ambiente'
                            when r.etapa_id is null then 'etapa' else 'ambiente' end
         || ': ' || coalesce(d.descricao, c.objeto), 'rateio', r.id, coalesce(d.data, c.data_assinatura), r.valor
  from obra.rateio r
  left join obra.despesa d on d.id = r.despesa_id
  left join obra.contrato c on c.id = r.contrato_id
  left join obra.orcamento_item i on i.id = r.orcamento_item_id
 where r.excluido_em is null and coalesce(i.tipo_custo, 'direto') = 'direto'
   and (r.etapa_id is null or r.ambiente_id is null)
union all
select obra_id, 'amarelo', 'proposta_vencendo', 'Proposta vence em breve: ' || titulo,
       'proposta', id, validade, valor_total
  from obra.proposta
 where excluido_em is null and status in ('recebido','solicitado')
   and validade between current_date and current_date + 7
union all
select obra_id, 'amarelo', 'contingencia',
       'Contingência mais de 50% consumida com menos de 50% de avanço físico', 'obra', obra_id, null, estouros
  from obra.v_obra_resumo
 where contingencia > 0 and estouros > contingencia * 0.5 and pct_fisico < 0.5
union all
select obra_id, 'cinza', 'itens_a_revisar', count(*) || ' item(ns) do orçamento marcados "A revisar"',
       'orcamento_item', null, null, sum(orcado)
  from obra.v_item_resumo where revisar group by obra_id;

-- ---------------------------------------------------------------------
-- Projeção de caixa (próximos 12 meses): parcelas em aberto + orçado não contratado
-- distribuído pelo restante do prazo previsto de cada etapa
-- ---------------------------------------------------------------------
create view obra.v_fluxo_projetado with (security_invoker = true) as
with meses as (
  select o.id obra_id, generate_series(date_trunc('month', current_date)::date,
         (date_trunc('month', current_date) + interval '11 months')::date, interval '1 month')::date mes
    from obra.obra o where o.excluido_em is null
),
parc as (
  select obra_id, greatest(date_trunc('month', vencimento)::date, date_trunc('month', current_date)::date) mes,
         sum(saldo) valor
    from obra.v_parcela_agenda where status in ('prevista','parcial') group by 1, 2
),
nao_contratado as (
  select e.obra_id, e.id, greatest(e.orcado - e.contratado, 0) saldo,
         date_trunc('month', greatest(coalesce(e.inicio_previsto, current_date), current_date))::date ini,
         date_trunc('month', greatest(coalesce(e.fim_previsto, current_date), current_date))::date fim
    from obra.v_etapa_resumo e
   where e.status not in ('concluida','cancelada') and e.inicio_previsto is not null
),
dist as (
  select n.obra_id, m.mes,
         sum(n.saldo / ((extract(year from age(n.fim, n.ini)) * 12 + extract(month from age(n.fim, n.ini))) + 1)) valor
    from nao_contratado n
    join meses m on m.obra_id = n.obra_id and m.mes between n.ini and n.fim
   group by 1, 2
)
select m.obra_id, m.mes,
       coalesce(p.valor, 0)  as parcelas_em_aberto,
       round(coalesce(d.valor, 0), 2) as orcado_a_contratar,
       round(coalesce(p.valor, 0) + coalesce(d.valor, 0), 2) as saida_prevista
  from meses m
  left join parc p on p.obra_id = m.obra_id and p.mes = m.mes
  left join dist d on d.obra_id = m.obra_id and d.mes = m.mes;
