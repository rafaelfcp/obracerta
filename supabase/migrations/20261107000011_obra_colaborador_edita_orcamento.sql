-- Colaborador(a) também edita o orçamento: incluir/tirar do total, cenário, quantidade e preços.
-- Continua só do admin: criar itens, importar planilha, convites, exclusões e configurações da obra.
set role obra_owner;

alter policy orcamento_item_upd on obra.orcamento_item
  using (obra.eh_membro(obra_id))
  with check (obra.eh_membro(obra_id));

alter policy preco_upd on obra.orcamento_item_preco
  using (exists (select 1 from obra.orcamento_item i where i.id = orcamento_item_preco.item_id and obra.eh_membro(i.obra_id)));

alter policy preco_ins on obra.orcamento_item_preco
  with check (exists (select 1 from obra.orcamento_item i where i.id = orcamento_item_preco.item_id and obra.eh_membro(i.obra_id)));

reset role;
