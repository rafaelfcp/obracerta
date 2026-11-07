-- =====================================================================
-- ObraCerta · 002 · Regras de negócio (funções e triggers)
-- Códigos de erro de negócio (SQLSTATE classe P0 com mensagem prefixada):
--   OC_SEM_PERMISSAO, OC_ESTOURO_ORCAMENTO, OC_PAGO_ACIMA_CONTRATADO,
--   OC_RATEIO_ACIMA_TOTAL, OC_DELETE_PROIBIDO
-- O app captura o prefixo e mostra o alerta com o botão "confirmar mesmo assim".
-- =====================================================================

-- ---------------------------------------------------------------------
-- Acesso
-- ---------------------------------------------------------------------
create or replace function obra.eh_membro(p_obra uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from obra.obra_membro m
                 where m.obra_id = p_obra and m.usuario_id = auth.uid());
$$;

create or replace function obra.eh_admin(p_obra uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from obra.obra_membro m
                 where m.obra_id = p_obra and m.usuario_id = auth.uid() and m.perfil = 'admin');
$$;

create or replace function obra.exigir_membro(p_obra uuid)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if not obra.eh_membro(p_obra) then
    raise exception 'OC_SEM_PERMISSAO: usuário não é membro desta obra' using errcode = 'P0001';
  end if;
end $$;

create or replace function obra.exigir_admin(p_obra uuid)
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if not obra.eh_admin(p_obra) then
    raise exception 'OC_SEM_PERMISSAO: ação restrita ao administrador da obra' using errcode = 'P0001';
  end if;
end $$;

-- Convite: a esposa cria a conta (magic link) e, no primeiro acesso, o app chama esta função
create or replace function obra.aceitar_convites()
returns setof uuid language plpgsql security definer set search_path = '' as $$
declare v_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
        r record;
begin
  for r in select * from obra.obra_convite c
           where lower(c.email) = v_email and c.aceito_em is null loop
    insert into obra.obra_membro(obra_id, usuario_id, perfil, nome_exibicao)
    values (r.obra_id, auth.uid(), r.perfil, r.nome_exibicao)
    on conflict (obra_id, usuario_id) do nothing;
    update obra.obra_convite set aceito_em = now(), aceito_por = auth.uid() where id = r.id;
    return next r.obra_id;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Carimbo de atualização
-- ---------------------------------------------------------------------
create or replace function obra.tg_carimbo()
returns trigger language plpgsql as $$
begin
  new.atualizado_em := now();
  new.atualizado_por := auth.uid();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['obra','premissa','etapa','ambiente','categoria','fornecedor','orcamento_item',
    'proposta','contrato','despesa','rateio','parcela','pagamento','reserva_conta','reserva_movimento',
    'fgts_evento','financiamento_simulacao','etapa_checklist','registro'] loop
    execute format('create trigger tg_%1$s_carimbo before update on obra.%1$I
                    for each row execute function obra.tg_carimbo()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Auditoria genérica (old/new em JSONB + campos alterados)
-- ---------------------------------------------------------------------
create or replace function obra.tg_auditoria()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_old jsonb := case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end;
  v_new jsonb := case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end;
  v_campos text[];
  v_op text := tg_op;
  v_ref jsonb := coalesce(v_new, v_old);
  v_obra uuid;
begin
  if tg_op = 'UPDATE' then
    select array_agg(k order by k) into v_campos
      from jsonb_object_keys(v_new) k
     where k not in ('atualizado_em','atualizado_por')
       and (v_new -> k) is distinct from (v_old -> k);
    if v_campos is null then return new; end if;  -- nada relevante mudou
    if (v_old ->> 'excluido_em') is null and (v_new ->> 'excluido_em') is not null then
      v_op := 'EXCLUSAO_LOGICA';
    end if;
  end if;

  v_obra := (v_ref ->> 'obra_id')::uuid;
  if v_obra is null and tg_table_name = 'orcamento_item_preco' then
    select i.obra_id into v_obra from obra.orcamento_item i where i.id = (v_ref ->> 'item_id')::uuid;
  end if;

  insert into obra.auditoria(obra_id, tabela, registro_id, operacao, antes, depois, campos, origem)
  values (v_obra, tg_table_name,
          coalesce((v_ref ->> 'id')::uuid, (v_ref ->> 'item_id')::uuid),
          v_op, v_old, v_new, v_campos,
          coalesce(nullif(current_setting('obra.origem', true), ''), 'app'));
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array['obra','etapa','orcamento_item','orcamento_item_preco','proposta','contrato',
    'despesa','rateio','parcela','pagamento','reserva_movimento','reserva_balde','fgts_evento',
    'financiamento_simulacao','financiamento_liberacao','obra_membro','premissa'] loop
    execute format('create trigger tg_%1$s_auditoria after insert or update or delete on obra.%1$I
                    for each row execute function obra.tg_auditoria()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- DELETE físico proibido (exclusão é lógica, via obra.excluir_registro)
-- ---------------------------------------------------------------------
create or replace function obra.tg_bloqueia_delete()
returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('obra.permite_delete', true), '') = 'on' then
    return old;
  end if;
  raise exception 'OC_DELETE_PROIBIDO: use obra.excluir_registro() (exclusão lógica) em %', tg_table_name
    using errcode = 'P0001';
end $$;

do $$
declare t text;
begin
  foreach t in array array['obra','etapa','ambiente','categoria','fornecedor','orcamento_item','proposta',
    'proposta_item','contrato','despesa','rateio','parcela','pagamento','reserva_conta','reserva_movimento',
    'reserva_saldo','fgts_evento','financiamento_simulacao','financiamento_liberacao','amortizacao_extra',
    'etapa_medicao','etapa_checklist','registro','anexo','premissa','auditoria'] loop
    execute format('create trigger tg_%1$s_sem_delete before delete on obra.%1$I
                    for each row execute function obra.tg_bloqueia_delete()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Orçamento: valor_orcado = quantidade x preço do cenário escolhido (ou valor_fixo)
-- ---------------------------------------------------------------------
create or replace function obra.calcular_valor_item(p_item obra.orcamento_item)
returns numeric language sql stable as $$
  select case
           when p_item.valor_fixo is not null then p_item.valor_fixo
           when p_item.quantidade is null or p_item.cenario_escolhido is null then 0
           else coalesce(round(p_item.quantidade * (
                  select p.preco_unitario from obra.orcamento_item_preco p
                   where p.item_id = p_item.id and p.cenario = p_item.cenario_escolhido), 2), 0)
         end;
$$;

create or replace function obra.tg_item_valor()
returns trigger language plpgsql as $$
begin
  new.valor_orcado := obra.calcular_valor_item(new);
  return new;
end $$;

create trigger tg_orcamento_item_valor before insert or update on obra.orcamento_item
  for each row execute function obra.tg_item_valor();

create or replace function obra.tg_preco_recalcula_item()
returns trigger language plpgsql as $$
begin
  -- força o BEFORE UPDATE do item a recalcular valor_orcado
  update obra.orcamento_item i set valor_orcado = i.valor_orcado
   where i.id = coalesce(new.item_id, old.item_id);
  return null;
end $$;

create trigger tg_preco_recalcula after insert or update or delete on obra.orcamento_item_preco
  for each row execute function obra.tg_preco_recalcula_item();

create or replace function obra.tg_preco_carimbo()
returns trigger language plpgsql as $$
begin new.atualizado_em := now(); new.atualizado_por := auth.uid(); return new; end $$;
create trigger tg_preco_carimbo before insert or update on obra.orcamento_item_preco
  for each row execute function obra.tg_preco_carimbo();

-- ---------------------------------------------------------------------
-- Proposta: total = itens - desconto + impostos; só admin aprova
-- ---------------------------------------------------------------------
create or replace function obra.tg_proposta_total()
returns trigger language plpgsql as $$
begin
  new.valor_total := coalesce((select sum(pi.valor_total) from obra.proposta_item pi
                                where pi.proposta_id = new.id and pi.excluido_em is null), 0)
                     - coalesce(new.desconto, 0) + coalesce(new.impostos, 0);
  if new.status = 'aprovado' and (tg_op = 'INSERT' or old.status is distinct from 'aprovado') then
    perform obra.exigir_admin(new.obra_id);
  end if;
  return new;
end $$;
create trigger tg_proposta_total before insert or update on obra.proposta
  for each row execute function obra.tg_proposta_total();

create or replace function obra.tg_proposta_item_total()
returns trigger language plpgsql as $$
begin
  update obra.proposta p set desconto = p.desconto where p.id = coalesce(new.proposta_id, old.proposta_id);
  return null;
end $$;
create trigger tg_proposta_item_total after insert or update or delete on obra.proposta_item
  for each row execute function obra.tg_proposta_item_total();

-- Ao aprovar uma proposta, as concorrentes do mesmo título viram "recusado"
create or replace function obra.tg_proposta_aprovada()
returns trigger language plpgsql as $$
begin
  if new.status = 'aprovado' and old.status is distinct from 'aprovado' then
    update obra.proposta p set status = 'recusado'
     where p.obra_id = new.obra_id and p.id <> new.id and p.excluido_em is null
       and lower(p.titulo) = lower(new.titulo) and p.status in ('solicitado','recebido','rascunho');
  end if;
  return null;
end $$;
create trigger tg_proposta_aprovada after update on obra.proposta
  for each row execute function obra.tg_proposta_aprovada();

-- ---------------------------------------------------------------------
-- Contrato: aprovação registrada
-- ---------------------------------------------------------------------
create or replace function obra.tg_contrato_aprovacao()
returns trigger language plpgsql as $$
begin
  if new.status = 'ativo' and (tg_op = 'INSERT' or old.status is distinct from 'ativo') and new.aprovado_em is null then
    new.aprovado_em := now();
    new.aprovado_por := auth.uid();
  end if;
  return new;
end $$;
create trigger tg_contrato_aprovacao before insert or update on obra.contrato
  for each row execute function obra.tg_contrato_aprovacao();

-- ---------------------------------------------------------------------
-- Rateio: herda etapa/ambiente do item; não passa do total da origem;
-- comprometer acima do orçado do item exige confirmação explícita
-- ---------------------------------------------------------------------
create or replace function obra.tg_rateio_regras()
returns trigger language plpgsql as $$
declare
  v_total_origem numeric;
  v_soma numeric;
  v_orcado numeric;
  v_comprometido numeric;
  v_confirmado boolean;
begin
  if new.excluido_em is not null then return new; end if;

  if new.orcamento_item_id is not null then
    select coalesce(new.etapa_id, i.etapa_id), coalesce(new.ambiente_id, i.ambiente_id), i.valor_orcado
      into new.etapa_id, new.ambiente_id, v_orcado
      from obra.orcamento_item i where i.id = new.orcamento_item_id;
  end if;

  if new.contrato_id is not null then
    select c.valor_total, c.confirmado_estouro into v_total_origem, v_confirmado
      from obra.contrato c where c.id = new.contrato_id;
    select coalesce(sum(r.valor), 0) into v_soma from obra.rateio r
     where r.contrato_id = new.contrato_id and r.excluido_em is null and r.id <> new.id;
  else
    select d.valor_total, d.confirmado_estouro into v_total_origem, v_confirmado
      from obra.despesa d where d.id = new.despesa_id;
    select coalesce(sum(r.valor), 0) into v_soma from obra.rateio r
     where r.despesa_id = new.despesa_id and r.excluido_em is null and r.id <> new.id;
  end if;

  if v_soma + new.valor > v_total_origem + 0.005 then
    raise exception 'OC_RATEIO_ACIMA_TOTAL: rateio (%) passa do valor total da origem (%)',
      v_soma + new.valor, v_total_origem using errcode = 'P0001';
  end if;

  -- estouro do orçado do item (contratos ativos/concluídos + despesas não canceladas)
  if new.orcamento_item_id is not null and not coalesce(v_confirmado, false) then
    select coalesce(sum(r.valor), 0) into v_comprometido
      from obra.rateio r
      left join obra.contrato c on c.id = r.contrato_id
      left join obra.despesa  d on d.id = r.despesa_id
     where r.orcamento_item_id = new.orcamento_item_id and r.excluido_em is null and r.id <> new.id
       and (c.id is null or (c.status in ('ativo','concluido','em_renegociacao') and c.excluido_em is null))
       and (d.id is null or (d.status <> 'cancelada' and d.excluido_em is null and d.contrato_id is null));
    if v_comprometido + new.valor > v_orcado + 0.005 then
      raise exception 'OC_ESTOURO_ORCAMENTO: comprometido (%) passa do orçado do item (%). Confirme o estouro para prosseguir.',
        v_comprometido + new.valor, v_orcado using errcode = 'P0001';
    end if;
  end if;
  return new;
end $$;
create trigger tg_rateio_regras before insert or update on obra.rateio
  for each row execute function obra.tg_rateio_regras();

-- ---------------------------------------------------------------------
-- Pagamento: não passa do contratado sem confirmação; status derivado
-- ---------------------------------------------------------------------
create or replace function obra.tg_pagamento_regras()
returns trigger language plpgsql as $$
declare
  v_contrato uuid; v_despesa uuid; v_total numeric; v_pago numeric;
begin
  if new.excluido_em is not null or new.confirmado_excesso then return new; end if;
  select p.contrato_id, p.despesa_id into v_contrato, v_despesa from obra.parcela p where p.id = new.parcela_id;
  -- despesa dentro de contrato: o teto é o contrato
  if v_despesa is not null then
    select d.contrato_id into v_contrato from obra.despesa d where d.id = v_despesa and d.contrato_id is not null;
  end if;

  if v_contrato is not null then
    select c.valor_total into v_total from obra.contrato c where c.id = v_contrato;
    select coalesce(sum(pg.valor), 0) into v_pago
      from obra.pagamento pg join obra.parcela pa on pa.id = pg.parcela_id
      left join obra.despesa d on d.id = pa.despesa_id
     where (pa.contrato_id = v_contrato or d.contrato_id = v_contrato)
       and pg.excluido_em is null and pg.id <> new.id;
  else
    select d.valor_total into v_total from obra.despesa d where d.id = v_despesa;
    select coalesce(sum(pg.valor), 0) into v_pago
      from obra.pagamento pg join obra.parcela pa on pa.id = pg.parcela_id
     where pa.despesa_id = v_despesa and pg.excluido_em is null and pg.id <> new.id;
  end if;

  if v_pago + new.valor > v_total + 0.005 then
    raise exception 'OC_PAGO_ACIMA_CONTRATADO: pago (%) passaria do contratado (%). Confirme o excesso para prosseguir.',
      v_pago + new.valor, v_total using errcode = 'P0001';
  end if;
  return new;
end $$;
create trigger tg_pagamento_regras before insert or update on obra.pagamento
  for each row execute function obra.tg_pagamento_regras();

create or replace function obra.atualizar_status_parcela(p_parcela uuid)
returns void language plpgsql as $$
declare v_valor numeric; v_pago numeric; v_status text; v_despesa uuid;
begin
  select pa.valor, pa.despesa_id, pa.status into v_valor, v_despesa, v_status from obra.parcela pa where pa.id = p_parcela;
  if v_status = 'cancelada' then return; end if;
  select coalesce(sum(valor), 0) into v_pago from obra.pagamento where parcela_id = p_parcela and excluido_em is null;
  update obra.parcela set status = case when v_pago <= 0.005 then 'prevista'
                                        when v_pago + 0.005 >= v_valor then 'paga'
                                        else 'parcial' end
   where id = p_parcela;

  if v_despesa is not null then
    update obra.despesa d set status = s.st
      from (select case when bool_and(pa.status = 'paga') then 'paga'
                        when bool_or(pa.status in ('paga','parcial')) then 'parcial'
                        else 'prevista' end st
              from obra.parcela pa
             where pa.despesa_id = v_despesa and pa.excluido_em is null and pa.status <> 'cancelada') s
     where d.id = v_despesa and d.status <> 'cancelada' and s.st is not null;
  end if;
end $$;

create or replace function obra.tg_pagamento_status()
returns trigger language plpgsql as $$
begin
  perform obra.atualizar_status_parcela(coalesce(new.parcela_id, old.parcela_id));
  if tg_op = 'UPDATE' and new.parcela_id <> old.parcela_id then
    perform obra.atualizar_status_parcela(old.parcela_id);
  end if;
  return null;
end $$;
create trigger tg_pagamento_status after insert or update on obra.pagamento
  for each row execute function obra.tg_pagamento_status();

-- ---------------------------------------------------------------------
-- % físico: medição manual ou checklist atualiza a etapa
-- ---------------------------------------------------------------------
create or replace function obra.tg_medicao_etapa()
returns trigger language plpgsql as $$
begin
  if new.excluido_em is null then
    update obra.etapa e set pct_fisico = new.pct_fisico,
           status = case when new.pct_fisico >= 1 then 'concluida'
                         when new.pct_fisico > 0 and e.status = 'planejada' then 'em_andamento'
                         else e.status end,
           inicio_real = case when new.pct_fisico > 0 then coalesce(e.inicio_real, new.data) else e.inicio_real end,
           fim_real = case when new.pct_fisico >= 1 then coalesce(e.fim_real, new.data) else e.fim_real end
     where e.id = new.etapa_id;
  end if;
  return null;
end $$;
create trigger tg_medicao_etapa after insert on obra.etapa_medicao
  for each row execute function obra.tg_medicao_etapa();

create or replace function obra.tg_checklist_pct()
returns trigger language plpgsql as $$
declare v_etapa uuid := coalesce(new.etapa_id, old.etapa_id); v_pct numeric; v_obra uuid;
begin
  if (select metodo_pct_fisico from obra.etapa where id = v_etapa) <> 'checklist' then return null; end if;
  select coalesce(sum(peso) filter (where concluido), 0) / nullif(sum(peso), 0), min(obra_id::text)::uuid
    into v_pct, v_obra
    from obra.etapa_checklist where etapa_id = v_etapa and excluido_em is null;
  insert into obra.etapa_medicao(obra_id, etapa_id, pct_fisico, metodo, comentario)
  values (v_obra, v_etapa, round(coalesce(v_pct, 0), 4), 'checklist', 'Atualização automática do checklist');
  return null;
end $$;
create trigger tg_checklist_pct after insert or update on obra.etapa_checklist
  for each row execute function obra.tg_checklist_pct();

-- ---------------------------------------------------------------------
-- Operações de negócio (RPC chamadas pelo app)
-- ---------------------------------------------------------------------

-- Gera N parcelas iguais (diferença de centavos na última)
create or replace function obra.gerar_parcelas(
  p_contrato uuid, p_despesa uuid, p_qtd int, p_primeiro_vencimento date,
  p_intervalo_meses int default 1, p_valor_total numeric default null)
returns setof obra.parcela language plpgsql security invoker set search_path = '' as $$
declare v_obra uuid; v_total numeric; v_base numeric; i int;
begin
  if p_qtd < 1 then raise exception 'Quantidade de parcelas inválida'; end if;
  if p_contrato is not null then
    select obra_id, coalesce(p_valor_total, valor_total) into v_obra, v_total from obra.contrato where id = p_contrato;
  else
    select obra_id, coalesce(p_valor_total, valor_total) into v_obra, v_total from obra.despesa where id = p_despesa;
  end if;
  v_base := trunc(v_total / p_qtd, 2);
  for i in 1..p_qtd loop
    return query insert into obra.parcela(obra_id, contrato_id, despesa_id, numero, vencimento, valor)
      values (v_obra, p_contrato, p_despesa, i,
              (p_primeiro_vencimento + make_interval(months => (i - 1) * p_intervalo_meses))::date,
              case when i = p_qtd then v_total - v_base * (p_qtd - 1) else v_base end)
      returning *;
  end loop;
end $$;

-- Lançamento rápido de gasto: despesa + rateio + parcelas (+ pagamento se já pago) numa transação
create or replace function obra.registrar_gasto(
  p_obra uuid,
  p_valor numeric,
  p_descricao text,
  p_data date default current_date,
  p_fornecedor_id uuid default null,
  p_fornecedor_nome text default null,
  p_categoria_id uuid default null,
  p_etapa_id uuid default null,
  p_ambiente_id uuid default null,
  p_orcamento_item_id uuid default null,
  p_contrato_id uuid default null,
  p_parcelas int default 1,
  p_primeiro_vencimento date default null,
  p_pago boolean default false,
  p_forma text default null,
  p_fonte text default 'reserva',
  p_tipo_documento text default null,
  p_numero_documento text default null,
  p_observacao text default null,
  p_confirmado_estouro boolean default false,
  p_confirmado_excesso boolean default false)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare v_desp uuid; v_forn uuid := p_fornecedor_id; v_parc record;
begin
  perform obra.exigir_membro(p_obra);
  if v_forn is null and nullif(trim(p_fornecedor_nome), '') is not null then
    select id into v_forn from obra.fornecedor
     where obra_id = p_obra and lower(nome) = lower(trim(p_fornecedor_nome)) and excluido_em is null;
    if v_forn is null then
      insert into obra.fornecedor(obra_id, nome) values (p_obra, trim(p_fornecedor_nome)) returning id into v_forn;
    end if;
  end if;

  insert into obra.despesa(obra_id, data, descricao, valor_total, fornecedor_id, categoria_id, contrato_id,
                           tipo_documento, numero_documento, observacao, confirmado_estouro)
  values (p_obra, p_data, p_descricao, p_valor, v_forn, p_categoria_id, p_contrato_id,
          p_tipo_documento, p_numero_documento, p_observacao, p_confirmado_estouro)
  returning id into v_desp;

  -- gasto dentro de um contrato já está comprometido pelo contrato: não gera novo rateio
  if p_contrato_id is null then
    insert into obra.rateio(obra_id, despesa_id, orcamento_item_id, etapa_id, ambiente_id, valor)
    values (p_obra, v_desp, p_orcamento_item_id, p_etapa_id, p_ambiente_id, p_valor);
  end if;

  perform obra.gerar_parcelas(null, v_desp, greatest(coalesce(p_parcelas, 1), 1),
                              coalesce(p_primeiro_vencimento, p_data));

  if p_pago then
    for v_parc in select id, valor from obra.parcela where despesa_id = v_desp order by numero limit 1 loop
      insert into obra.pagamento(obra_id, parcela_id, data, valor, forma, fonte, confirmado_excesso)
      values (p_obra, v_parc.id, p_data, v_parc.valor, p_forma, coalesce(p_fonte, 'reserva'), p_confirmado_excesso);
    end loop;
  end if;
  return v_desp;
end $$;

create or replace function obra.registrar_pagamento(
  p_parcela uuid, p_valor numeric default null, p_data date default current_date,
  p_forma text default null, p_fonte text default 'reserva',
  p_confirmado_excesso boolean default false, p_observacao text default null)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare v_obra uuid; v_saldo numeric; v_id uuid;
begin
  select pa.obra_id, pa.valor - coalesce((select sum(valor) from obra.pagamento
                                           where parcela_id = pa.id and excluido_em is null), 0)
    into v_obra, v_saldo from obra.parcela pa where pa.id = p_parcela;
  perform obra.exigir_membro(v_obra);
  insert into obra.pagamento(obra_id, parcela_id, data, valor, forma, fonte, confirmado_excesso, observacao)
  values (v_obra, p_parcela, p_data, coalesce(p_valor, v_saldo), p_forma, coalesce(p_fonte, 'reserva'),
          p_confirmado_excesso, p_observacao)
  returning id into v_id;
  return v_id;
end $$;

-- Exclusão lógica com permissão por tabela e "cascata" lógica nos dependentes
create or replace function obra.excluir_registro(p_tabela text, p_id uuid, p_motivo text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_obra uuid;
  v_admin_only text[] := array['etapa','ambiente','categoria','orcamento_item','contrato','premissa',
                               'reserva_conta','financiamento_liberacao'];
  v_membro text[] := array['fornecedor','proposta','proposta_item','despesa','rateio','parcela','pagamento',
                           'reserva_movimento','reserva_saldo','fgts_evento','financiamento_simulacao',
                           'amortizacao_extra','etapa_medicao','etapa_checklist','registro','anexo'];
begin
  if not (p_tabela = any(v_admin_only) or p_tabela = any(v_membro)) then
    raise exception 'Tabela % não admite exclusão', p_tabela;
  end if;

  if p_tabela = 'proposta_item' then
    execute 'select p.obra_id from obra.proposta_item pi join obra.proposta p on p.id = pi.proposta_id where pi.id = $1'
      into v_obra using p_id;
  else
    execute format('select obra_id from obra.%I where id = $1', p_tabela) into v_obra using p_id;
  end if;
  if v_obra is null then raise exception 'Registro não encontrado'; end if;

  if p_tabela = any(v_admin_only) then perform obra.exigir_admin(v_obra);
  else perform obra.exigir_membro(v_obra); end if;

  execute format('update obra.%I set excluido_em = now(), excluido_por = auth.uid(), excluido_motivo = $2
                   where id = $1 and excluido_em is null', p_tabela) using p_id, p_motivo;

  -- dependentes
  if p_tabela in ('despesa','contrato') then
    execute format('update obra.pagamento set excluido_em = now(), excluido_por = auth.uid(), excluido_motivo = $2
                     where excluido_em is null and parcela_id in (select id from obra.parcela where %I = $1)',
                   p_tabela || '_id') using p_id, 'Origem excluída: ' || coalesce(p_motivo, '');
    execute format('update obra.parcela set excluido_em = now(), excluido_por = auth.uid(), excluido_motivo = $2
                     where excluido_em is null and %I = $1', p_tabela || '_id')
      using p_id, 'Origem excluída: ' || coalesce(p_motivo, '');
    execute format('update obra.rateio set excluido_em = now(), excluido_por = auth.uid(), excluido_motivo = $2
                     where excluido_em is null and %I = $1', p_tabela || '_id')
      using p_id, 'Origem excluída: ' || coalesce(p_motivo, '');
  elsif p_tabela = 'parcela' then
    update obra.pagamento set excluido_em = now(), excluido_por = auth.uid(), excluido_motivo = 'Parcela excluída'
     where parcela_id = p_id and excluido_em is null;
  elsif p_tabela = 'pagamento' then
    perform obra.atualizar_status_parcela((select parcela_id from obra.pagamento where id = p_id));
  elsif p_tabela = 'proposta' then
    update obra.proposta_item set excluido_em = now(), excluido_por = auth.uid(), excluido_motivo = 'Proposta excluída'
     where proposta_id = p_id and excluido_em is null;
  end if;
end $$;
