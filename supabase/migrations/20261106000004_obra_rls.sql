-- =====================================================================
-- ObraCerta · 004 · Segurança: grants, RLS e Storage
-- Modelo: acesso por obra (obra_membro), não por usuário.
--   admin       -> tudo
--   colaborador -> lê tudo; registra gastos, pagamentos, propostas, fornecedores,
--                  anexos, medições, diário, reserva e simulações
-- DELETE físico não é concedido a ninguém: exclusão é lógica (obra.excluir_registro).
-- =====================================================================

revoke all on all tables in schema obra from anon, authenticated;
grant select, insert, update on all tables in schema obra to authenticated;
grant select on obra.auditoria to authenticated;
revoke insert, update on obra.auditoria from authenticated;
grant usage on all sequences in schema obra to authenticated;
grant execute on all functions in schema obra to authenticated;
revoke execute on all functions in schema obra from anon, public;

-- ---------------------------------------------------------------------
-- Helpers de policy por tipo de tabela
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  -- tabelas com obra_id + exclusão lógica, escrita restrita ao admin
  foreach t in array array['premissa','etapa','ambiente','categoria','orcamento_item','orcamento_versao',
                           'contrato','reserva_conta','reserva_balde','financiamento_liberacao',
                           'importacao','importacao_mapa'] loop
    execute format('alter table obra.%I enable row level security', t);
    execute format($p$create policy %1$s_sel on obra.%1$I for select to authenticated
                    using (obra.eh_membro(obra_id) %2$s)$p$, t,
                   case when t in ('orcamento_versao','reserva_balde','importacao','importacao_mapa')
                        then '' else 'and excluido_em is null' end);
    execute format('create policy %1$s_ins on obra.%1$I for insert to authenticated
                    with check (obra.eh_admin(obra_id))', t);
    execute format('create policy %1$s_upd on obra.%1$I for update to authenticated
                    using (obra.eh_admin(obra_id)) with check (obra.eh_admin(obra_id))', t);
  end loop;

  -- tabelas com obra_id + exclusão lógica, escrita por qualquer membro
  foreach t in array array['fornecedor','proposta','despesa','rateio','parcela','pagamento',
                           'reserva_movimento','reserva_saldo','fgts_evento','financiamento_simulacao',
                           'amortizacao_extra','etapa_medicao','etapa_checklist','registro','anexo'] loop
    execute format('alter table obra.%I enable row level security', t);
    execute format('create policy %1$s_sel on obra.%1$I for select to authenticated
                    using (obra.eh_membro(obra_id) and excluido_em is null)', t);
    execute format('create policy %1$s_ins on obra.%1$I for insert to authenticated
                    with check (obra.eh_membro(obra_id))', t);
    execute format('create policy %1$s_upd on obra.%1$I for update to authenticated
                    using (obra.eh_membro(obra_id)) with check (obra.eh_membro(obra_id))', t);
  end loop;
end $$;

-- obra
alter table obra.obra enable row level security;
create policy obra_sel on obra.obra for select to authenticated using (obra.eh_membro(id) and excluido_em is null);
create policy obra_upd on obra.obra for update to authenticated using (obra.eh_admin(id)) with check (obra.eh_admin(id));
-- criação de obra só via obra.criar_obra() (security definer), que já cadastra o admin

-- membros e convites
alter table obra.obra_membro enable row level security;
create policy obra_membro_sel on obra.obra_membro for select to authenticated using (obra.eh_membro(obra_id));
create policy obra_membro_ins on obra.obra_membro for insert to authenticated with check (obra.eh_admin(obra_id));
create policy obra_membro_upd on obra.obra_membro for update to authenticated
  using (obra.eh_admin(obra_id)) with check (obra.eh_admin(obra_id));

alter table obra.obra_convite enable row level security;
create policy obra_convite_sel on obra.obra_convite for select to authenticated using (obra.eh_admin(obra_id));
create policy obra_convite_ins on obra.obra_convite for insert to authenticated with check (obra.eh_admin(obra_id));
create policy obra_convite_upd on obra.obra_convite for update to authenticated
  using (obra.eh_admin(obra_id)) with check (obra.eh_admin(obra_id));

-- filhas sem obra_id: herdam do pai
alter table obra.orcamento_item_preco enable row level security;
create policy preco_sel on obra.orcamento_item_preco for select to authenticated
  using (exists (select 1 from obra.orcamento_item i where i.id = item_id and obra.eh_membro(i.obra_id)));
create policy preco_ins on obra.orcamento_item_preco for insert to authenticated
  with check (exists (select 1 from obra.orcamento_item i where i.id = item_id and obra.eh_admin(i.obra_id)));
create policy preco_upd on obra.orcamento_item_preco for update to authenticated
  using (exists (select 1 from obra.orcamento_item i where i.id = item_id and obra.eh_admin(i.obra_id)));

alter table obra.etapa_dependencia enable row level security;
create policy dep_sel on obra.etapa_dependencia for select to authenticated
  using (exists (select 1 from obra.etapa e where e.id = etapa_id and obra.eh_membro(e.obra_id)));
create policy dep_ins on obra.etapa_dependencia for insert to authenticated
  with check (exists (select 1 from obra.etapa e where e.id = etapa_id and obra.eh_admin(e.obra_id)));
create policy dep_upd on obra.etapa_dependencia for update to authenticated
  using (exists (select 1 from obra.etapa e where e.id = etapa_id and obra.eh_admin(e.obra_id)));
grant delete on obra.etapa_dependencia to authenticated;   -- dependência é configuração, pode ser removida
create policy dep_del on obra.etapa_dependencia for delete to authenticated
  using (exists (select 1 from obra.etapa e where e.id = etapa_id and obra.eh_admin(e.obra_id)));

alter table obra.proposta_item enable row level security;
create policy pitem_sel on obra.proposta_item for select to authenticated
  using (excluido_em is null and exists (select 1 from obra.proposta p where p.id = proposta_id and obra.eh_membro(p.obra_id)));
create policy pitem_ins on obra.proposta_item for insert to authenticated
  with check (exists (select 1 from obra.proposta p where p.id = proposta_id and obra.eh_membro(p.obra_id)));
create policy pitem_upd on obra.proposta_item for update to authenticated
  using (exists (select 1 from obra.proposta p where p.id = proposta_id and obra.eh_membro(p.obra_id)));

alter table obra.anexo_vinculo enable row level security;
create policy avinc_sel on obra.anexo_vinculo for select to authenticated
  using (exists (select 1 from obra.anexo a where a.id = anexo_id and obra.eh_membro(a.obra_id)));
create policy avinc_ins on obra.anexo_vinculo for insert to authenticated
  with check (exists (select 1 from obra.anexo a where a.id = anexo_id and obra.eh_membro(a.obra_id)));

alter table obra.importacao_linha enable row level security;
create policy implin_sel on obra.importacao_linha for select to authenticated
  using (exists (select 1 from obra.importacao i where i.id = importacao_id and obra.eh_membro(i.obra_id)));
create policy implin_upd on obra.importacao_linha for update to authenticated
  using (exists (select 1 from obra.importacao i where i.id = importacao_id and obra.eh_admin(i.obra_id)
                 and i.status = 'em_revisao'));
-- inserção de linhas só via obra.importacao_criar() (security definer)

alter table obra.auditoria enable row level security;
create policy auditoria_sel on obra.auditoria for select to authenticated using (obra.eh_membro(obra_id));

-- views: leitura (a RLS das tabelas se aplica via security_invoker)
grant select on all tables in schema obra to authenticated;

-- ---------------------------------------------------------------------
-- Storage: bucket privado obra-anexos, caminho <obra_id>/<entidade>/<arquivo>
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from information_schema.schemata where schema_name = 'storage') then
    insert into storage.buckets (id, name, public, file_size_limit)
    values ('obra-anexos', 'obra-anexos', false, 52428800)
    on conflict (id) do nothing;

    execute $p$create policy obra_anexos_sel on storage.objects for select to authenticated
      using (case when bucket_id = 'obra-anexos' and (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$' then obra.eh_membro(((storage.foldername(name))[1])::uuid) else false end)$p$;
    execute $p$create policy obra_anexos_ins on storage.objects for insert to authenticated
      with check (case when bucket_id = 'obra-anexos' and (storage.foldername(name))[1] ~ '^[0-9a-f-]{36}$' then obra.eh_membro(((storage.foldername(name))[1])::uuid) else false end)$p$;
  end if;
end $$;
