-- Testes de regras de negócio e segurança. Cada bloco falha com exception se a regra não se comportar.
-- Rodar após run_local.sh (planilha em revisão).
\set ON_ERROR_STOP 1
\set rafael '{"sub":"05c1d5f2-b450-4828-87f4-71a9cb638580","role":"authenticated","email":"raf.fcp@gmail.com"}'
\set esposa '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated","email":"esposa@exemplo.com"}'
\set intruso '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated","email":"intruso@exemplo.com"}'

-- 1. Rafael (admin) confirma a importação e roda as simulações -----------------------------
begin;
set local role authenticated;
select set_config('request.jwt.claims', :'rafael', true);
select obra.importacao_confirmar((select id from obra.importacao where status = 'em_revisao')) as confirmacao;
select obra.simular_financiamento(id) ->> 'valor_financiado' as financiado from obra.financiamento_simulacao;
insert into obra.obra_convite(obra_id, email, perfil, nome_exibicao)
select id, 'esposa@exemplo.com', 'colaborador', 'Esposa' from obra.obra;
commit;

-- 2. Esposa aceita o convite e vira colaboradora ---------------------------------------------
begin;
set local role authenticated;
select set_config('request.jwt.claims', :'esposa', true);
select obra.aceitar_convites() as obra_aceita;
commit;

begin;
set local role authenticated;
select set_config('request.jwt.claims', :'esposa', true);
do $$
declare v_obra uuid; v_n int; v_desp uuid;
begin
  select id into v_obra from obra.obra;
  if v_obra is null then raise exception 'FALHA: esposa não enxerga a obra'; end if;
  select count(*) into v_n from obra.v_item_resumo;
  if v_n <> 97 then raise exception 'FALHA: esposa deveria ver 97 itens, viu %', v_n; end if;

  -- colaboradora registra gasto
  v_desp := obra.registrar_gasto(p_obra => v_obra, p_valor => 350, p_descricao => 'Cópias do projeto',
              p_fornecedor_nome => 'Gráfica Teste', p_etapa_id => (select id from obra.etapa where ordem = 1),
              p_ambiente_id => (select id from obra.ambiente where nome = 'Casa toda'),
              p_categoria_id => (select id from obra.categoria where nome = 'Projetos'), p_pago => true, p_forma => 'pix');
  if (select status from obra.despesa where id = v_desp) <> 'paga' then raise exception 'FALHA: despesa deveria estar paga'; end if;

  -- colaboradora NÃO altera orçamento (RLS: 0 linhas)
  update obra.orcamento_item set quantidade = 999 where numero_origem = 1;
  get diagnostics v_n = row_count;
  if v_n <> 0 then raise exception 'FALHA: colaboradora alterou orçamento'; end if;

  -- colaboradora NÃO exclui item de orçamento
  begin
    perform obra.excluir_registro('orcamento_item', (select id from obra.orcamento_item where numero_origem = 1), 'teste');
    raise exception 'FALHA: colaboradora excluiu item';
  exception when others then
    if sqlerrm not like 'OC_SEM_PERMISSAO%' then raise; end if;
  end;
  raise notice 'OK esposa: vê a obra, registra gasto, não altera nem exclui orçamento';
end $$;
commit;

-- DELETE físico negado para qualquer usuário
begin;
set local role authenticated;
select set_config('request.jwt.claims', :'rafael', true);
do $$
begin
  begin
    delete from obra.despesa;
    raise exception 'FALHA: delete físico permitido';
  exception when insufficient_privilege then
    raise notice 'OK delete físico negado';
  end;
end $$;
commit;

-- 3. Intruso não vê nada e não grava -------------------------------------------------------
begin;
set local role authenticated;
select set_config('request.jwt.claims', :'intruso', true);
do $$
declare v_n int;
begin
  select count(*) into v_n from obra.obra;
  if v_n <> 0 then raise exception 'FALHA: intruso vê obra'; end if;
  select count(*) into v_n from obra.v_obra_painel;
  if v_n <> 0 then raise exception 'FALHA: intruso vê painel'; end if;
  begin
    perform obra.registrar_gasto(p_obra => (select '00000000-0000-0000-0000-000000000000'::uuid), p_valor => 1, p_descricao => 'x');
    raise exception 'FALHA: intruso gravou';
  exception when others then
    if sqlerrm not like 'OC_SEM_PERMISSAO%' then raise; end if;
  end;
  raise notice 'OK intruso: sem acesso';
end $$;
commit;

-- 4. Estouro de orçamento e pagamento acima do contratado (Rafael) --------------------------
begin;
set local role authenticated;
select set_config('request.jwt.claims', :'rafael', true);
do $$
declare v_obra uuid; v_item uuid; v_orc numeric; v_c uuid; v_parc uuid;
begin
  select id into v_obra from obra.obra;
  select id, valor_orcado into v_item, v_orc from obra.orcamento_item where numero_origem = 4; -- fundação

  insert into obra.fornecedor(obra_id, nome, especialidade) values (v_obra, 'Fundações Teste Ltda', 'Fundação');
  insert into obra.contrato(obra_id, fornecedor_id, objeto, valor_total, forma_pagamento)
  values (v_obra, (select id from obra.fornecedor where nome = 'Fundações Teste Ltda'), 'Fundação completa', 50000, '2x')
  returning id into v_c;

  -- rateio acima do orçado sem confirmação -> bloqueia
  begin
    insert into obra.rateio(obra_id, contrato_id, orcamento_item_id, valor) values (v_obra, v_c, v_item, 50000);
    raise exception 'FALHA: estouro sem confirmação aceito';
  exception when others then
    if sqlerrm not like 'OC_ESTOURO_ORCAMENTO%' then raise; end if;
  end;

  -- com confirmação explícita -> aceita
  update obra.contrato set confirmado_estouro = true where id = v_c;
  insert into obra.rateio(obra_id, contrato_id, orcamento_item_id, valor) values (v_obra, v_c, v_item, 50000);
  if (select etapa_id from obra.rateio where contrato_id = v_c) <> (select id from obra.etapa where ordem = 3) then
    raise exception 'FALHA: rateio não herdou a etapa do item';
  end if;

  perform obra.gerar_parcelas(v_c, null, 2, current_date - 10);
  select id into v_parc from obra.parcela where contrato_id = v_c and numero = 1;
  perform obra.registrar_pagamento(v_parc, p_forma => 'pix');
  if (select status from obra.parcela where id = v_parc) <> 'paga' then raise exception 'FALHA: parcela 1 não ficou paga'; end if;

  -- pagar mais que o contratado sem confirmação -> bloqueia
  begin
    perform obra.registrar_pagamento((select id from obra.parcela where contrato_id = v_c and numero = 2), 30000);
    raise exception 'FALHA: pagamento acima do contratado aceito';
  exception when others then
    if sqlerrm not like 'OC_PAGO_ACIMA_CONTRATADO%' then raise; end if;
  end;

  if not exists (select 1 from obra.v_alerta where tipo = 'item_estouro') then raise exception 'FALHA: sem alerta de estouro'; end if;
  if not exists (select 1 from obra.v_alerta where tipo = 'parcela_atrasada') then
    -- parcela 2 vence em current_date - 10 + 1 mês: futura; parcela 1 paga. Sem atraso esperado.
    null;
  end if;
  raise notice 'OK estouro: bloqueia sem confirmação, aceita confirmado; pago acima bloqueado';
end $$;
commit;

-- 5. Medição física, exclusão lógica e auditoria --------------------------------------------
begin;
set local role authenticated;
select set_config('request.jwt.claims', :'rafael', true);
do $$
declare v_obra uuid; v_desp uuid; v_n int;
begin
  select id into v_obra from obra.obra;
  insert into obra.etapa_medicao(obra_id, etapa_id, pct_fisico, comentario)
  values (v_obra, (select id from obra.etapa where ordem = 1), 0.4, 'Anteprojeto entregue');
  if (select pct_fisico from obra.etapa where ordem = 1) <> 0.4 then raise exception 'FALHA: medição não atualizou etapa'; end if;
  if (select status from obra.etapa where ordem = 1) <> 'em_andamento' then raise exception 'FALHA: status da etapa'; end if;

  select id into v_desp from obra.despesa where descricao = 'Cópias do projeto';
  perform obra.excluir_registro('despesa', v_desp, 'Lançado em duplicidade (teste)');
  if exists (select 1 from obra.despesa where id = v_desp) then raise exception 'FALHA: excluída ainda visível'; end if;
  if exists (select 1 from obra.v_parcela_agenda where despesa_id = v_desp) then raise exception 'FALHA: parcela da excluída visível'; end if;

  select count(*) into v_n from obra.auditoria where operacao = 'EXCLUSAO_LOGICA';
  if v_n < 3 then raise exception 'FALHA: auditoria da exclusão (% registros)', v_n; end if;
  raise notice 'OK medição, exclusão lógica em cascata e auditoria (% eventos de exclusão)', v_n;
end $$;
commit;

-- 6. Painel após os testes -------------------------------------------------------------------
begin;
set local role authenticated;
select set_config('request.jwt.claims', :'rafael', true);
select orcado_total, contratado, pago, a_pagar, custo_projetado, desvio, pct_fisico, pct_financeiro_pago,
       saldo_reserva, necessidade_complementar, semaforo
  from obra.v_obra_painel;
select ordem, nome, orcado, contratado, pago, desvio, semaforo from obra.v_etapa_painel where ordem in (1,3);
select nivel, tipo, left(mensagem, 70) mensagem, valor from obra.v_alerta order by nivel;
commit;
