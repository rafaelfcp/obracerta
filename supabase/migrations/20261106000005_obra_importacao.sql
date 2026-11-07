-- =====================================================================
-- ObraCerta · 005 · Importação da planilha (staging -> revisão -> merge)
-- Fluxo:
--   1. app lê o .xlsx (SheetJS), normaliza e chama obra.importacao_criar(obra, arquivo, sha, linhas)
--   2. obra.importacao_classificar() marca cada linha: novo / atualizar / sem_mudanca /
--      a_revisar / conflito / removido, com problemas e diff campo a campo
--   3. tela de revisão ajusta decisao, etapa e ambiente por linha
--   4. obra.importacao_confirmar() aplica tudo numa transação (MERGE por chave natural)
-- =====================================================================

-- Chave natural estável: slug(classe)|slug(grupo)|slug(descrição)
create or replace function obra.slug(p text)
returns text language sql immutable as $$
  select trim(both '-' from regexp_replace(
           translate(lower(coalesce(p, '')),
                     'áàâãäéèêëíìîïóòôõöúùûüçñ²³º°',
                     'aaaaaeeeeiiiiooooouuuucn23oo'),
           '[^a-z0-9]+', '-', 'g'));
$$;

create or replace function obra.chave_item(p_classe text, p_grupo text, p_descricao text)
returns text language sql immutable as $$
  select obra.slug(p_classe) || '|' || obra.slug(p_grupo) || '|' || obra.slug(p_descricao);
$$;

-- Campos comparáveis de uma linha normalizada da planilha
create or replace function obra.import_campos(d jsonb)
returns jsonb language sql immutable as $$
  select jsonb_build_object(
    'classe',          d ->> 'classe',
    'grupo',           d ->> 'grupo',
    'descricao',       d ->> 'descricao',
    'unidade',         d ->> 'unidade',
    'quantidade',      (d ->> 'quantidade')::numeric,
    'prioridade',      d ->> 'prioridade',
    'fase',            d ->> 'fase',
    'pct_financiavel', coalesce((d ->> 'pct_financiavel')::numeric, 0),
    'incluido',        coalesce((d ->> 'incluido')::boolean, true),
    'cenario',         d ->> 'cenario',
    'valor_fixo',      (d ->> 'valor_fixo')::numeric,
    'precos',          coalesce(d -> 'precos', '{}'::jsonb),
    'observacao',      d ->> 'observacao');
$$;

-- Os mesmos campos, lidos do item como está hoje no app
create or replace function obra.item_campos(p_item uuid)
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'classe', i.classe, 'grupo', i.grupo, 'descricao', i.descricao, 'unidade', i.unidade,
    'quantidade', i.quantidade, 'prioridade', i.prioridade, 'fase', i.fase,
    'pct_financiavel', i.pct_financiavel, 'incluido', i.incluido, 'cenario', i.cenario_escolhido,
    'valor_fixo', i.valor_fixo,
    'precos', coalesce((select jsonb_object_agg(p.cenario, p.preco_unitario)
                          from obra.orcamento_item_preco p where p.item_id = i.id), '{}'::jsonb),
    'observacao', i.observacao)
  from obra.orcamento_item i where i.id = p_item;
$$;

-- Diferença campo a campo entre dois jsonb (só chaves com valor diferente)
create or replace function obra.jsonb_diff(p_a jsonb, p_b jsonb, p_rotulo_a text default 'app',
                                           p_rotulo_b text default 'planilha')
returns jsonb language sql immutable as $$
  select coalesce(jsonb_object_agg(k, jsonb_build_object(p_rotulo_a, p_a -> k, p_rotulo_b, p_b -> k)), '{}'::jsonb)
    from (select jsonb_object_keys(p_a) k union select jsonb_object_keys(p_b)) ks
   where (p_a -> k) is distinct from (p_b -> k);
$$;

-- Sugestão de etapa/ambiente/categoria a partir do mapa persistente (item > grupo > classe)
create or replace function obra.import_sugestao(p_obra uuid, p_chave text, p_grupo text, p_classe text)
returns jsonb language sql stable as $$
  with cand as (
    select m.*, case m.escopo when 'item' then 1 when 'grupo' then 2 else 3 end prio
      from obra.importacao_mapa m
     where m.obra_id = p_obra
       and ((m.escopo = 'item' and m.valor = p_chave)
         or (m.escopo = 'grupo' and m.valor = obra.slug(p_grupo))
         or (m.escopo = 'classe' and m.valor = obra.slug(p_classe)))
  )
  select jsonb_build_object(
    -- custo indireto e aquisição do lote não pertencem a uma etapa
    'etapa_id',     case when coalesce((select tipo_custo from cand where tipo_custo is not null order by prio limit 1),
                                       'direto') = 'direto'
                         then (select etapa_id from cand where etapa_id is not null order by prio limit 1) end,
    'ambiente_id',  (select ambiente_id  from cand where ambiente_id  is not null order by prio limit 1),
    'categoria_id', (select categoria_id from cand where categoria_id is not null order by prio limit 1),
    'tipo_custo',   coalesce((select tipo_custo from cand where tipo_custo is not null order by prio limit 1), 'direto'),
    'revisar',      coalesce((select bool_or(revisar) from cand), false),
    'grupo_alternativa', (select substring(observacao from 'alternativa:([a-z0-9_-]+)') from cand
                           where observacao like '%alternativa:%' order by prio limit 1),
    'observacao',   (select string_agg(observacao, ' / ' order by prio) from cand
                      where observacao is not null and observacao not like 'alternativa:%'));
$$;

-- ---------------------------------------------------------------------
create or replace function obra.importacao_classificar(p_imp uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_obra uuid;
  r record;
  v_item obra.orcamento_item;
  v_plan jsonb; v_atual jsonb; v_snap jsonb;
  v_sug jsonb;
  v_prob text[];
  v_acao text;
  v_calc numeric;
  v_resumo jsonb;
begin
  select obra_id into v_obra from obra.importacao where id = p_imp and status = 'em_revisao';
  if v_obra is null then raise exception 'Importação inexistente ou já encerrada'; end if;
  perform obra.exigir_admin(v_obra);

  -- linhas "removido" (itens que sumiram da planilha) não são reclassificadas
  for r in select l.* from obra.importacao_linha l
            where l.importacao_id = p_imp and l.acao is distinct from 'removido' loop
    v_plan := obra.import_campos(r.dados);
    v_sug  := obra.import_sugestao(v_obra, r.chave_natural, r.dados ->> 'grupo', r.dados ->> 'classe');
    v_prob := '{}';

    select * into v_item from obra.orcamento_item i
     where i.obra_id = v_obra and i.chave_natural = r.chave_natural and i.excluido_em is null;

    -- problemas de qualidade da linha
    if (select count(*) from obra.importacao_linha x
         where x.importacao_id = p_imp and x.chave_natural = r.chave_natural) > 1 then
      v_prob := array_append(v_prob, 'chave_duplicada');
    end if;
    if (r.dados ->> 'numero') is not null and (select count(*) from obra.importacao_linha x
         where x.importacao_id = p_imp and x.dados ->> 'numero' = r.dados ->> 'numero') > 1 then
      v_prob := array_append(v_prob, 'numero_duplicado');
    end if;
    if (v_plan ->> 'quantidade')::numeric = 0 then v_prob := array_append(v_prob, 'quantidade_zero'); end if;
    if (v_plan ->> 'quantidade') is null and (v_plan ->> 'valor_fixo') is null then
      v_prob := array_append(v_prob, 'sem_quantidade_nem_valor');
    end if;
    if v_sug ->> 'tipo_custo' = 'direto' and (v_plan ->> 'incluido')::boolean then
      if coalesce(r.etapa_id, v_item.etapa_id, (v_sug ->> 'etapa_id')::uuid) is null then
        v_prob := array_append(v_prob, 'sem_etapa'); end if;
      if coalesce(r.ambiente_id, v_item.ambiente_id, (v_sug ->> 'ambiente_id')::uuid) is null then
        v_prob := array_append(v_prob, 'sem_ambiente'); end if;
    end if;
    if (v_sug ->> 'grupo_alternativa') is not null then v_prob := array_append(v_prob, 'alternativa_excludente'); end if;
    if coalesce(v_plan ->> 'observacao', '') ~* '(estimativa minha|confirmar|conferir)' then
      v_prob := array_append(v_prob, 'estimativa_a_confirmar');
    end if;
    if (v_sug ->> 'revisar')::boolean then v_prob := array_append(v_prob, 'mapeamento_a_revisar'); end if;
    -- valor informado na planilha x quantidade x preço do cenário escolhido
    v_calc := coalesce((v_plan ->> 'valor_fixo')::numeric,
                       round((v_plan ->> 'quantidade')::numeric
                             * (v_plan -> 'precos' ->> (v_plan ->> 'cenario'))::numeric, 2));
    if (r.dados ->> 'valor_planilha') is not null and v_calc is not null
       and abs(v_calc - (r.dados ->> 'valor_planilha')::numeric) > 0.05 then
      v_prob := array_append(v_prob, 'valor_divergente');
    end if;

    -- ação
    if v_item.id is null then
      v_acao := case when v_prob && array['chave_duplicada','sem_etapa','sem_ambiente','quantidade_zero',
                        'sem_quantidade_nem_valor','alternativa_excludente','mapeamento_a_revisar','valor_divergente']
                     then 'a_revisar' else 'novo' end;
    else
      v_atual := obra.item_campos(v_item.id);
      v_snap  := coalesce(v_item.import_snapshot, v_atual);
      if v_plan = v_snap or v_plan = v_atual then v_acao := 'sem_mudanca';
      elsif v_atual = v_snap then v_acao := 'atualizar';
      else v_acao := 'conflito';
      end if;
    end if;

    update obra.importacao_linha l set
      sugestao = v_sug,
      problemas = v_prob,
      acao = v_acao,
      diff = case when v_item.id is not null then obra.jsonb_diff(v_atual, v_plan) end,
      destino_id = v_item.id,
      etapa_id = coalesce(l.etapa_id, v_item.etapa_id, (v_sug ->> 'etapa_id')::uuid),
      ambiente_id = coalesce(l.ambiente_id, v_item.ambiente_id, (v_sug ->> 'ambiente_id')::uuid),
      decisao = coalesce(l.decisao, case v_acao when 'novo' then 'aplicar' when 'a_revisar' then 'aplicar'
                                                when 'atualizar' then 'aplicar' when 'conflito' then 'manter_app'
                                                else 'ignorar' end)
     where l.id = r.id;
  end loop;

  -- itens importados antes que sumiram da planilha
  insert into obra.importacao_linha(importacao_id, chave_natural, dados, acao, decisao, destino_id, diff)
  select p_imp, i.chave_natural, obra.item_campos(i.id), 'removido', 'ignorar', i.id, null
    from obra.orcamento_item i
   where i.obra_id = v_obra and i.origem = 'importacao' and i.excluido_em is null
     and not exists (select 1 from obra.importacao_linha l
                      where l.importacao_id = p_imp and l.chave_natural = i.chave_natural);

  select jsonb_build_object(
           'linhas', count(*) filter (where acao <> 'removido'),
           'por_acao', (select jsonb_object_agg(acao, n) from (select acao, count(*) n from obra.importacao_linha
                         where importacao_id = p_imp group by acao) a),
           'por_problema', (select jsonb_object_agg(p, n) from (select unnest(problemas) p, count(*) n
                         from obra.importacao_linha where importacao_id = p_imp group by 1) b),
           'total_planilha_incluido', (select sum(coalesce((dados ->> 'valor_fixo')::numeric,
                         round((dados ->> 'quantidade')::numeric * (dados -> 'precos' ->> (dados ->> 'cenario'))::numeric, 2)))
                         from obra.importacao_linha where importacao_id = p_imp and acao <> 'removido'
                          and coalesce((dados ->> 'incluido')::boolean, true)))
    into v_resumo
    from obra.importacao_linha where importacao_id = p_imp;

  update obra.importacao set resumo = v_resumo where id = p_imp;
  return v_resumo;
end $$;

-- ---------------------------------------------------------------------
create or replace function obra.importacao_criar(p_obra uuid, p_arquivo text, p_sha256 text,
                                                 p_linhas jsonb, p_storage_path text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_imp uuid; v_ja boolean;
begin
  perform obra.exigir_admin(p_obra);
  -- importações anteriores ainda em revisão são canceladas (uma revisão aberta por vez)
  update obra.importacao set status = 'cancelada' where obra_id = p_obra and status = 'em_revisao';

  select exists (select 1 from obra.importacao where obra_id = p_obra and arquivo_sha256 = p_sha256
                  and status = 'confirmada') into v_ja;

  insert into obra.importacao(obra_id, arquivo_nome, arquivo_sha256, storage_path)
  values (p_obra, p_arquivo, p_sha256, p_storage_path) returning id into v_imp;

  insert into obra.importacao_linha(importacao_id, aba, linha_planilha, chave_natural, dados_brutos, dados)
  select v_imp, coalesce(l ->> 'aba', 'Itens'), (l ->> 'linha')::int,
         obra.chave_item(l ->> 'classe', l ->> 'grupo', l ->> 'descricao'),
         l -> 'bruto', l - 'bruto'
    from jsonb_array_elements(p_linhas) l;

  perform obra.importacao_classificar(v_imp);
  if v_ja then
    update obra.importacao set resumo = resumo || '{"arquivo_ja_importado": true}' where id = v_imp;
  end if;
  return v_imp;
end $$;

-- ---------------------------------------------------------------------
create or replace function obra.importacao_confirmar(p_imp uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_obra uuid;
  r record;
  v_plan jsonb;
  v_sug jsonb;
  v_id uuid;
  v_forma text;
  n_ins int := 0; n_upd int := 0; n_exc int := 0; n_snap int := 0; n_pag int := 0;
begin
  select obra_id into v_obra from obra.importacao where id = p_imp and status = 'em_revisao' for update;
  if v_obra is null then raise exception 'Importação inexistente ou já encerrada'; end if;
  perform obra.exigir_admin(v_obra);
  perform set_config('obra.origem', 'importacao', true);

  for r in select * from obra.importacao_linha where importacao_id = p_imp order by linha_planilha nulls last loop
    v_plan := obra.import_campos(r.dados);
    v_sug  := coalesce(r.sugestao, '{}');

    if r.acao in ('novo','a_revisar') and r.decisao = 'aplicar' then
      insert into obra.orcamento_item(obra_id, tipo_custo, etapa_id, ambiente_id, categoria_id, classe, grupo,
             descricao, unidade, quantidade, prioridade, fase, pct_financiavel, base_contingencia, incluido,
             cenario_escolhido, valor_fixo, grupo_alternativa, estimativa, revisar, revisar_motivos, observacao, nota,
             chave_natural, numero_origem, origem, import_snapshot, importacao_id)
      values (v_obra, coalesce(v_sug ->> 'tipo_custo', 'direto'), r.etapa_id, r.ambiente_id,
             (v_sug ->> 'categoria_id')::uuid, v_plan ->> 'classe', v_plan ->> 'grupo',
             v_plan ->> 'descricao', v_plan ->> 'unidade', (v_plan ->> 'quantidade')::numeric,
             v_plan ->> 'prioridade', v_plan ->> 'fase', (v_plan ->> 'pct_financiavel')::numeric,
             coalesce((r.dados ->> 'base_contingencia')::boolean, false),
             (v_plan ->> 'incluido')::boolean, v_plan ->> 'cenario', (v_plan ->> 'valor_fixo')::numeric,
             v_sug ->> 'grupo_alternativa',
             'estimativa_a_confirmar' = any(r.problemas),
             cardinality(array_remove(array_remove(r.problemas, 'estimativa_a_confirmar'), 'numero_duplicado')) > 0,
             array_remove(r.problemas, 'numero_duplicado'),
             v_plan ->> 'observacao', v_sug ->> 'observacao',
             r.chave_natural, (r.dados ->> 'numero')::int, 'importacao', v_plan, p_imp)
      returning id into v_id;

      insert into obra.orcamento_item_preco(item_id, cenario, preco_unitario)
      select v_id, e.key, e.value::numeric from jsonb_each_text(v_plan -> 'precos') e;
      n_ins := n_ins + 1;

      -- pagamento já realizado na planilha (ex.: lote quitado)
      if lower(coalesce(r.dados -> 'pago' ->> 'status', '')) = 'sim' then
        v_forma := case lower(coalesce(r.dados -> 'pago' ->> 'forma', ''))
                     when 'pix' then 'pix' when 'boleto' then 'boleto' when 'transferência (ted)' then 'ted'
                     when 'cartão de crédito' then 'cartao_credito' when 'cartão de débito' then 'cartao_debito'
                     when 'dinheiro' then 'dinheiro' when 'cheque' then 'cheque'
                     when 'financiamento caixa' then 'financiamento_caixa' when 'fgts' then 'fgts' end;
        perform obra.registrar_gasto(
          p_obra => v_obra,
          p_valor => coalesce((r.dados -> 'pago' ->> 'valor')::numeric, obra.calcular_valor_item(
                       (select i from obra.orcamento_item i where i.id = v_id))),
          p_descricao => v_plan ->> 'descricao',
          p_data => coalesce((r.dados -> 'pago' ->> 'data')::date, current_date),
          p_categoria_id => (v_sug ->> 'categoria_id')::uuid,
          p_orcamento_item_id => v_id,
          p_pago => true,
          p_forma => v_forma,
          p_fonte => 'reserva',
          p_observacao => 'Pagamento importado da planilha');
        n_pag := n_pag + 1;
      end if;
      update obra.importacao_linha set destino_id = v_id where id = r.id;

    elsif (r.acao = 'atualizar' and r.decisao = 'aplicar') or (r.acao = 'conflito' and r.decisao = 'usar_planilha') then
      update obra.orcamento_item set
        classe = v_plan ->> 'classe', grupo = v_plan ->> 'grupo', descricao = v_plan ->> 'descricao',
        unidade = v_plan ->> 'unidade', quantidade = (v_plan ->> 'quantidade')::numeric,
        prioridade = v_plan ->> 'prioridade', fase = v_plan ->> 'fase',
        pct_financiavel = (v_plan ->> 'pct_financiavel')::numeric, incluido = (v_plan ->> 'incluido')::boolean,
        cenario_escolhido = v_plan ->> 'cenario', valor_fixo = (v_plan ->> 'valor_fixo')::numeric,
        observacao = v_plan ->> 'observacao',
        etapa_id = coalesce(r.etapa_id, etapa_id), ambiente_id = coalesce(r.ambiente_id, ambiente_id),
        import_snapshot = v_plan, importacao_id = p_imp
       where id = r.destino_id;
      insert into obra.orcamento_item_preco(item_id, cenario, preco_unitario)
      select r.destino_id, e.key, e.value::numeric from jsonb_each_text(v_plan -> 'precos') e
      on conflict (item_id, cenario) do update set preco_unitario = excluded.preco_unitario
       where obra.orcamento_item_preco.preco_unitario is distinct from excluded.preco_unitario;
      n_upd := n_upd + 1;

    elsif r.acao = 'conflito' and r.decisao = 'manter_app' then
      -- mantém o valor do app; registra a planilha como referência para não reabrir o conflito
      update obra.orcamento_item set import_snapshot = v_plan, importacao_id = p_imp where id = r.destino_id;
      n_snap := n_snap + 1;

    elsif r.acao = 'removido' and r.decisao = 'excluir' then
      update obra.orcamento_item set excluido_em = now(), excluido_por = auth.uid(),
             excluido_motivo = 'Removido da planilha (importação ' || p_imp || ')'
       where id = r.destino_id and excluido_em is null;
      n_exc := n_exc + 1;
    end if;
  end loop;

  update obra.importacao set status = 'confirmada', confirmada_em = now(), confirmada_por = auth.uid(),
         resumo = coalesce(resumo, '{}') || jsonb_build_object('aplicado', jsonb_build_object(
           'inseridos', n_ins, 'atualizados', n_upd, 'conflitos_mantidos', n_snap,
           'excluidos', n_exc, 'pagamentos_criados', n_pag))
   where id = p_imp;

  return jsonb_build_object('inseridos', n_ins, 'atualizados', n_upd, 'conflitos_mantidos', n_snap,
                            'excluidos', n_exc, 'pagamentos_criados', n_pag);
end $$;

grant execute on function obra.slug(text), obra.chave_item(text,text,text), obra.import_campos(jsonb),
  obra.item_campos(uuid), obra.jsonb_diff(jsonb,jsonb,text,text), obra.import_sugestao(uuid,text,text,text),
  obra.importacao_classificar(uuid), obra.importacao_criar(uuid,text,text,jsonb,text),
  obra.importacao_confirmar(uuid) to authenticated;
revoke execute on function obra.importacao_classificar(uuid), obra.importacao_criar(uuid,text,text,jsonb,text),
  obra.importacao_confirmar(uuid) from anon, public;
