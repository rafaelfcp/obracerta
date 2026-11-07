-- =====================================================================
-- ObraCerta · 010 · Importação em partes (planilhas grandes / envio em lotes)
-- obra.importacao_anexar(imp, linhas): acrescenta linhas a uma importação em revisão
-- e reclassifica tudo. Usada pelo app quando o payload for grande.
-- =====================================================================
set role obra_owner;
create or replace function obra.importacao_anexar(p_imp uuid, p_linhas jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_obra uuid;
begin
  select obra_id into v_obra from obra.importacao where id = p_imp and status = 'em_revisao';
  if v_obra is null then raise exception 'Importação inexistente ou já encerrada'; end if;
  perform obra.exigir_admin(v_obra);
  insert into obra.importacao_linha(importacao_id, aba, linha_planilha, chave_natural, dados_brutos, dados)
  select p_imp, coalesce(l ->> 'aba', 'Itens'), (l ->> 'linha')::int,
         obra.chave_item(l ->> 'classe', l ->> 'grupo', l ->> 'descricao'),
         l -> 'bruto', l - 'bruto'
    from jsonb_array_elements(p_linhas) l;
  -- linhas "removido" calculadas com a carga parcial deixam de valer: recalcula sobre o total
  update obra.importacao_linha set acao = null, decisao = null
   where importacao_id = p_imp and acao = 'removido'
     and chave_natural in (select obra.chave_item(l ->> 'classe', l ->> 'grupo', l ->> 'descricao')
                             from jsonb_array_elements(p_linhas) l);
  return obra.importacao_classificar(p_imp);
end $$;
revoke execute on function obra.importacao_anexar(uuid, jsonb) from public, anon;
grant execute on function obra.importacao_anexar(uuid, jsonb) to authenticated;
reset role;
