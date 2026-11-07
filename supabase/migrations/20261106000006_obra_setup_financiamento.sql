-- =====================================================================
-- ObraCerta · 006 · Criação de obra (estrutura padrão) e simulação Caixa
-- =====================================================================

-- Cria a obra com o usuário atual como admin e a estrutura padrão:
-- 19 etapas, ambientes da casa (+ "Casa toda"), naturezas de gasto e baldes da reserva.
create or replace function obra.criar_obra(p_nome text, p_referencia_lote text default null,
                                           p_frente numeric default null, p_fundo numeric default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_obra uuid;
begin
  if auth.uid() is null then raise exception 'Usuário não autenticado'; end if;

  insert into obra.obra(nome, referencia_lote, lote_frente_m, lote_fundo_m, criado_por)
  values (p_nome, p_referencia_lote, p_frente, p_fundo, auth.uid()) returning id into v_obra;

  insert into obra.obra_membro(obra_id, usuario_id, perfil) values (v_obra, auth.uid(), 'admin');

  insert into obra.etapa(obra_id, ordem, nome, recebe_indireto)
  select v_obra, e.ordem, e.nome, e.ordem >= 3
    from (values (1,'Projeto arquitetônico e complementares'), (2,'Aprovações, alvarás e regularizações'),
                 (3,'Fundação'), (4,'Estrutura'), (5,'Alvenaria e vedação'), (6,'Cobertura'),
                 (7,'Instalações hidráulicas'), (8,'Instalações elétricas'), (9,'Instalações de gás'),
                 (10,'Climatização'), (11,'Revestimentos internos'), (12,'Revestimentos externos'),
                 (13,'Esquadrias'), (14,'Louças e metais'), (15,'Cozinha'), (16,'Iluminação'),
                 (17,'Pintura'), (18,'Paisagismo e área externa'), (19,'Limpeza final e entrega')) e(ordem, nome);

  insert into obra.ambiente(obra_id, ordem, nome, pavimento)
  select v_obra, a.ordem, a.nome, a.pav
    from (values (1,'Casa toda','toda'), (2,'Fundações e estrutura','toda'), (3,'Fachada','externo'),
                 (4,'Sala','terreo'), (5,'Cozinha','terreo'), (6,'Suíte master','superior'),
                 (7,'Quartos','superior'), (8,'Banheiros',null), (9,'Lavanderia','terreo'),
                 (10,'Área de serviço','terreo'), (11,'Área gourmet','externo'), (12,'Churrasqueira','externo'),
                 (13,'Garagem','terreo'), (14,'Área externa','externo'), (15,'Jardim','externo'),
                 (16,'Outros',null)) a(ordem, nome, pav);

  insert into obra.categoria(obra_id, nome, natureza, sinal)
  values (v_obra,'Materiais','material',1), (v_obra,'Mão de obra','mao_de_obra',1),
         (v_obra,'Projetos','projeto',1), (v_obra,'Taxas e aprovações','taxa',1),
         (v_obra,'Ferramentas','ferramenta',1), (v_obra,'Locação de equipamentos','locacao',1),
         (v_obra,'Frete','frete',1), (v_obra,'Impostos','imposto',1), (v_obra,'Imprevistos','imprevisto',1),
         (v_obra,'Reembolsos','reembolso',-1), (v_obra,'Estornos','estorno',-1);

  insert into obra.reserva_balde(obra_id, balde, valor_alvo)
  values (v_obra,'seguranca',0), (v_obra,'imprevistos',null), (v_obra,'obra',null), (v_obra,'entrada',null);

  return v_obra;
end $$;

-- ---------------------------------------------------------------------
-- Simulação SBPE/SFH (SAC ou PRICE), mesma lógica da planilha v2
-- ---------------------------------------------------------------------
create or replace function obra.simular_financiamento(p_sim uuid)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  s obra.financiamento_simulacao;
  o record;
  i numeric; n int; seg numeric;
  v_financiavel numeric; v_base_aval numeric; v_custo_sem_terreno numeric;
  v_aval numeric; v_lim_cota numeric; v_lim_renda numeric; v_fin numeric;
  v_p1 numeric; v_pn numeric; v_juros_obra numeric; v_juros_total numeric; v_seguros numeric;
  v_tarifas numeric; v_pmt numeric; v_fator numeric; v_res jsonb; v_limite text;
begin
  select * into s from obra.financiamento_simulacao where id = p_sim and excluido_em is null;
  if s.id is null then raise exception 'Simulação não encontrada'; end if;
  perform obra.exigir_membro(s.obra_id);

  select coalesce(sum(i2.valor_orcado * i2.pct_financiavel) filter (where i2.tipo_custo <> 'aquisicao_lote'), 0) fin,
         coalesce(sum(i2.valor_orcado) filter (where i2.base_contingencia), 0) base_aval,
         coalesce(sum(i2.valor_orcado) filter (where i2.tipo_custo <> 'aquisicao_lote'), 0) obra_sem_terreno
    into o
    from obra.orcamento_item i2 where i2.obra_id = s.obra_id and i2.excluido_em is null and i2.incluido;

  v_financiavel := o.fin;
  v_base_aval := o.base_aval;
  v_custo_sem_terreno := o.obra_sem_terreno
    + round((select contingencia_pct from obra.obra where id = s.obra_id) * o.base_aval, 2);

  i := s.taxa_aa / 12; n := s.prazo_meses; seg := s.seguro_pct_mes;
  v_aval := coalesce(s.valor_terreno, 0) + v_base_aval * s.avaliacao_pct_custo;
  v_lim_cota := s.cota_max * v_aval;

  if s.sistema = 'SAC' then
    v_lim_renda := greatest(0, (s.renda_familiar * s.comprometimento_max - s.tarifa_mes) / (1.0 / n + i + seg));
  else
    v_fator := i / (1 - power(1 + i, -n));
    v_lim_renda := greatest(0, (s.renda_familiar * s.comprometimento_max - s.tarifa_mes) / (v_fator + seg));
  end if;

  v_fin := least(v_financiavel, v_lim_cota, v_lim_renda, coalesce(v_financiavel - s.entrada, v_financiavel));
  v_limite := case v_fin when v_lim_renda then 'renda' when v_lim_cota then 'cota' else 'custo_financiavel' end;

  if s.sistema = 'SAC' then
    v_p1 := v_fin * (1.0 / n + i + seg) + s.tarifa_mes;
    v_pn := v_fin / n * (1 + i + seg) + s.tarifa_mes;
    v_juros_total := v_fin * i * (n + 1) / 2;
    v_seguros := seg * v_fin * (n + 1) / 2;
  else
    v_pmt := v_fin * v_fator;
    v_p1 := v_pmt + v_fin * seg + s.tarifa_mes;
    v_pn := v_pmt + s.tarifa_mes;
    v_juros_total := v_pmt * n - v_fin;
    v_seguros := seg * v_fin * (n + 1) / 2;
  end if;
  v_tarifas := s.tarifa_mes * n;
  v_juros_obra := v_fin * i * (s.meses_obra + 1) / 2;

  v_res := jsonb_build_object(
    'calculado_em', now(),
    'custo_sem_terreno', round(v_custo_sem_terreno, 2),
    'custo_financiavel', round(v_financiavel, 2),
    'valor_avaliacao', round(v_aval, 2),
    'limite_cota', round(v_lim_cota, 2),
    'limite_renda', round(v_lim_renda, 2),
    'limitado_por', v_limite,
    'valor_financiado', round(v_fin, 2),
    'primeira_parcela', round(v_p1, 2),
    'ultima_parcela', round(v_pn, 2),
    'renda_minima', round(v_p1 / s.comprometimento_max, 2),
    'juros_obra', round(v_juros_obra, 2),
    'dinheiro_proprio', round(v_custo_sem_terreno - v_fin + v_juros_obra, 2),
    'total_juros', round(v_juros_total, 2),
    'total_seguros', round(v_seguros, 2),
    'total_tarifas', round(v_tarifas, 2),
    'total_pago', round(v_fin + v_juros_total + v_seguros + v_tarifas, 2),
    'parcela_media', round((v_fin + v_juros_total + v_seguros + v_tarifas) / n, 2),
    'primeira_parcela_pos_fgts', round(greatest(v_fin - s.fgts_abatimento, 0)
        * (case when s.sistema = 'SAC' then 1.0 / n + i + seg else v_fator + seg end) + s.tarifa_mes, 2));

  update obra.financiamento_simulacao set resultado = v_res where id = p_sim;
  return v_res;
end $$;

-- Tabela de evolução (SAC/PRICE), com amortizações extraordinárias simuladas
create or replace function obra.tabela_financiamento(p_sim uuid, p_meses int default null)
returns table (n int, amortizacao numeric, juros numeric, seguro numeric, tarifa numeric,
               amortizacao_extra numeric, parcela numeric, saldo numeric)
language plpgsql stable security invoker set search_path = '' as $$
declare
  s obra.financiamento_simulacao; v_saldo numeric; v_i numeric; v_n int; v_k int := 0;
  v_am numeric; v_j numeric; v_sg numeric; v_extra numeric; v_pmt numeric; v_rest int;
begin
  select * into s from obra.financiamento_simulacao where id = p_sim;
  v_saldo := (s.resultado ->> 'valor_financiado')::numeric;
  v_i := s.taxa_aa / 12; v_n := s.prazo_meses;
  while v_saldo > 0.005 and v_k < coalesce(p_meses, v_n) loop
    v_k := v_k + 1;
    v_rest := v_n - v_k + 1;
    v_j := v_saldo * v_i;
    v_sg := v_saldo * s.seguro_pct_mes;
    if s.sistema = 'SAC' then
      v_am := least(v_saldo, (s.resultado ->> 'valor_financiado')::numeric / v_n);
    else
      v_pmt := v_saldo * v_i / (1 - power(1 + v_i, -v_rest));
      v_am := least(v_saldo, v_pmt - v_j);
    end if;
    -- amortização extra simulada no mês k (contado da 1ª parcela)
    select coalesce(sum(a.valor), 0) into v_extra from obra.amortizacao_extra a
     where a.obra_id = s.obra_id and a.excluido_em is null and a.simulado
       and (extract(year from age(a.data, s.data_simulacao)) * 12 + extract(month from age(a.data, s.data_simulacao)))::int + 1 = v_k;
    n := v_k; amortizacao := round(v_am, 2); juros := round(v_j, 2); seguro := round(v_sg, 2);
    tarifa := s.tarifa_mes; amortizacao_extra := round(least(v_extra, v_saldo - v_am), 2);
    parcela := round(v_am + v_j + v_sg + s.tarifa_mes, 2);
    v_saldo := v_saldo - v_am - least(v_extra, v_saldo - v_am);
    saldo := round(v_saldo, 2);
    return next;
  end loop;
end $$;

grant execute on function obra.criar_obra(text,text,numeric,numeric), obra.simular_financiamento(uuid),
  obra.tabela_financiamento(uuid,int) to authenticated;
revoke execute on function obra.criar_obra(text,text,numeric,numeric) from anon, public;
