"""Gera o SQL de configuração da obra Casa Villagio Tunis (obra, áreas, reserva, FGTS,
simulações e o mapa planilha -> etapa/ambiente aprovado em 06/11/2026).

Uso: python3 -I gerar_seed.py <itens.json> <premissas.json> <saida.sql>
"""
import json
import sys

RAFAEL = "05c1d5f2-b450-4828-87f4-71a9cb638580"

# grupo da planilha -> (etapa ordem, ambiente, categoria, tipo_custo, revisar, observacao)
GRUPO = {
    "Terreno": (None, None, None, "aquisicao_lote", False, None),
    "Impostos e custas do terreno": (None, None, "Impostos", "aquisicao_lote", False, "Custas de cartório"),
    "Serviços preliminares, canteiro e ligações provisórias": (3, "Casa toda", None, "direto", False, None),
    "Fundação, estrutura de concreto e lajes": (4, "Fundações e estrutura", None, "direto", False, None),
    "Alvenaria e vedações": (5, "Casa toda", None, "direto", False, None),
    "Cobertura (telhado, calhas, forro)": (6, "Casa toda", None, "direto", False, None),
    "Impermeabilização (lajes, sacada, banheiros)": (11, "Casa toda", None, "direto", False, None),
    "Instalações hidráulicas e sanitárias": (7, "Casa toda", None, "direto", False, None),
    "Instalações elétricas e de dados": (8, "Casa toda", None, "direto", False, None),
    "Esquadrias (portas e janelas)": (13, "Casa toda", None, "direto", False, None),
    "Revestimentos de piso e parede": (11, "Casa toda", None, "direto", False, None),
    "Pintura e gesso": (17, "Casa toda", None, "direto", False, None),
    "Louças, metais e bancadas": (14, "Casa toda", None, "direto", False, None),
    "Bancadas de pedra (granito, quartzo)": (15, "Cozinha", None, "direto", False, None),
    "Guarda-corpos e serralheria (sacada e escada)": (13, "Casa toda", None, "direto", False, None),
    "Gourmet: churrasqueira e bancada": (18, "Área gourmet", None, "direto", False, None),
    "Administração da obra, empreiteiro e limpeza final": (19, "Casa toda", None, "direto", False, None),
    "Projeto arquitetônico (legal + executivo)": (1, "Casa toda", "Projetos", "direto", False, None),
    "Projetos complementares (estrutural, hidráulico, elétrico)": (1, "Casa toda", "Projetos", "direto", False, None),
    "Sondagem (SPT) e topografia": (1, "Casa toda", "Projetos", "direto", False, None),
    "Prefeitura: aprovação, alvará e habite-se": (2, "Casa toda", "Taxas e aprovações", "direto", False, None),
    "Condomínio: análise de projeto, taxa de obra e caução (devolvível)": (2, "Casa toda", "Taxas e aprovações", "direto", False, None),
    "INSS da obra (CNO/SERO)": (2, "Casa toda", "Impostos", "direto", False, None),
    "Cartório: averbação da construção": (2, "Casa toda", "Taxas e aprovações", "direto", False, None),
    "Avaliação de engenharia e tarifas": (2, "Casa toda", "Taxas e aprovações", "direto", False, "Custo do financiamento Caixa"),
    "Registro do contrato de financiamento em cartório": (2, "Casa toda", "Taxas e aprovações", "direto", False, "Custo do financiamento Caixa"),
    "Ligações definitivas de água, esgoto e energia": (7, "Casa toda", None, "direto", False, None),
    "Deck e paisagismo": (18, "Área externa", None, "direto", False, None),
    "Piscina 2 x 4 m (depois do habite-se)": (18, "Área externa", None, "direto", False, None),
    "Ar-condicionado (pré-instalação ou splits)": (10, "Casa toda", None, "direto", False, None),
    "Aquecimento solar e/ou energia solar": (None, "Casa toda", None, "direto", False, None),
    "Marcenaria (armários planejados)": (None, None, None, "direto", False, None),
    "Mobília e eletrodomésticos": (None, "Casa toda", None, "direto", False, None),
    "Moradia durante a obra (aluguel e mudança)": (None, "Outros", None, "direto", False, None),
    "Closet em drywall (alternativa à marcenaria)": (None, "Suíte master", None, "direto", False, "alternativa:closet"),
}

# número do item na planilha -> sobrescritas (etapa, ambiente, categoria, tipo, revisar, observacao)
ITEM = {
    4:  (3, "Fundações e estrutura", None, None, False, None),
    14: (3, "Fundações e estrutura", None, None, False, None),
    29: (12, "Garagem", None, None, False, None),
    32: (17, "Fachada", None, None, False, None),
    37: (18, "Área gourmet", None, None, False, None),
    38: (14, "Lavanderia", None, None, False, None),
    39: (14, "Banheiros", None, None, False, None),
    40: (15, "Casa toda", None, None, True, "Frontão, furos e frete servem a todas as bancadas"),
    41: (15, "Casa toda", None, None, True, "Frontão, furos e frete servem a todas as bancadas"),
    42: (15, "Casa toda", None, None, True, "Frontão, furos e frete servem a todas as bancadas"),
    45: (18, "Churrasqueira", None, None, False, None),
    46: (12, "Área gourmet", None, None, False, None),
    47: (None, "Casa toda", None, "indireto", True, "Custo indireto rateado entre as etapas 3 a 19 (proposta a confirmar)"),
    59: (2, "Casa toda", "Taxas e aprovações", None, True, "Caução devolvível: depósito a recuperar"),
    65: (8, "Casa toda", None, None, False, None),
    67: (18, "Jardim", None, None, False, None),
    71: (15, "Cozinha", None, None, False, None),
    72: (15, "Cozinha", None, None, False, None),
    73: (15, "Cozinha", None, None, False, None),
    74: (None, "Área gourmet", None, None, False, None),
    75: (None, "Área gourmet", None, None, False, None),
    76: (None, "Lavanderia", None, None, False, None),
    77: (None, "Lavanderia", None, None, False, None),
    78: (None, "Cozinha", None, None, False, "Despensa"),
    79: (None, "Suíte master", None, None, False, "alternativa:closet"),
    80: (None, "Quartos", None, None, False, None),
    81: (None, "Quartos", None, None, False, None),
    82: (None, "Banheiros", None, None, False, None),
    83: (None, "Banheiros", None, None, False, None),
    84: (None, "Banheiros", None, None, False, None),
    89: (13, "Banheiros", None, None, False, None),
}

AREAS = {"Sala": 33.6, "Cozinha": 16.0, "Área de serviço": 6.2, "Suíte master": 26.6, "Quartos": 29.4,
         "Banheiros": 11.2, "Garagem": 28.0, "Área gourmet": 16.25}


def q(v):
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    return "'" + str(v).replace("'", "''") + "'"


def ref(ordem, amb, cat):
    e = f"(select id from obra.etapa where obra_id = v_obra and ordem = {ordem})" if ordem else "null"
    a = f"(select id from obra.ambiente where obra_id = v_obra and nome = {q(amb)})" if amb else "null"
    c = f"(select id from obra.categoria where obra_id = v_obra and nome = {q(cat)})" if cat else "null"
    return e, a, c


def main(itens_path, premissas_path, saida):
    itens = json.load(open(itens_path, encoding="utf-8"))
    premissas = json.load(open(premissas_path, encoding="utf-8"))
    grupos_planilha = {l["grupo"] for l in itens}
    faltando = grupos_planilha - set(GRUPO)
    if faltando:
        raise SystemExit(f"Grupos sem mapeamento: {faltando}")

    out = []
    w = out.append
    w("-- Gerado por tools/gerar_seed.py — configuração da obra Casa Villagio Tunis")
    w("do $seed$")
    w("declare v_obra uuid; v_sim1 uuid; v_sim2 uuid;")
    w("begin")
    w(f"  perform set_config('request.jwt.claims', '{{\"sub\":\"{RAFAEL}\",\"role\":\"authenticated\",\"email\":\"raf.fcp@gmail.com\"}}', true);")
    w("  if exists (select 1 from obra.obra where nome = 'Casa Villagio Tunis' and excluido_em is null) then")
    w("    raise exception 'Obra Casa Villagio Tunis já existe';")
    w("  end if;")
    w("  v_obra := obra.criar_obra('Casa Villagio Tunis', 'Lote no condomínio Villagio Tunis, Jundiaí/SP', 8, 28);")
    w("  update obra.obra set endereco = 'Condomínio Villagio Tunis, Jundiaí/SP',")
    w("         observacao = 'Sobrado com garagem coberta e área gourmet. Planta vigente: planta PDF (06/11/2026).' where id = v_obra;")
    w("  update obra.obra_membro set nome_exibicao = 'Rafael' where obra_id = v_obra;")
    for nome, area in AREAS.items():
        w(f"  update obra.ambiente set area_m2 = {area} where obra_id = v_obra and nome = {q(nome)};")
    w("  update obra.ambiente set observacao = 'Banheiro social + 2 lavabos (banho da suíte está em Suíte master)'"
      " where obra_id = v_obra and nome = 'Banheiros';")
    w("  update obra.ambiente set observacao = 'Estrutura, telhado, instalações e administração' "
      "where obra_id = v_obra and nome = 'Casa toda';")

    # premissas (áreas da planta PDF e parâmetros da planilha)
    for p in premissas:
        w("  insert into obra.premissa(obra_id, chave, valor, unidade, fonte, observacao) values "
          f"(v_obra, {q(p['chave'])}, {q(p['valor'])}, {q(p['unidade'])}, {q(p['fonte'])}, {q(p.get('observacao'))});")

    # reserva
    w("  update obra.reserva_balde set valor_alvo = 150000, observacao = 'Decisão de 06/11/2026: fora do saldo disponível para a obra'"
      " where obra_id = v_obra and balde = 'seguranca';")
    w("  update obra.reserva_balde set observacao = 'Calculado: contingência de 10% sobre obra principal + extras'"
      " where obra_id = v_obra and balde = 'imprevistos';")
    w("  insert into obra.fgts_evento(obra_id, titular, descricao, valor, status, data_prevista, observacao) values "
      "(v_obra, 'Rafael e esposa', 'FGTS do casal para a obra', 80000, 'previsto', '2028-09-01', "
      "'Copiado do DashBoard-Financeiro (premissa do plano). Saldo FGTS Rafael em 04/11/2026: R$ 11.316,17');")

    # simulações Caixa (premissas da aba Financiamento da planilha)
    for var, nome, taxa, ativa in (("v_sim1", "SBPE SAC 11,19% a.a. + TR (planilha)", 0.1119, True),
                                    ("v_sim2", "SBPE SAC 11,00% a.a. + TR", 0.11, False)):
        w("  insert into obra.financiamento_simulacao(obra_id, nome, linha, sistema, taxa_aa, prazo_meses, renda_familiar,"
          " comprometimento_max, cota_max, avaliacao_pct_custo, seguro_pct_mes, tarifa_mes, meses_obra, valor_terreno,"
          " ativa, observacao) values "
          f"(v_obra, {q(nome)}, 'SBPE', 'SAC', {taxa}, 420, 25900, 0.30, 0.80, 1.00, 0.0007, 25, 15, 278350, {q(ativa)},"
          " 'Premissas da aba Financiamento da planilha v2. Renda de R$ 25.900 (o Financeiro usa R$ 32.000: confirmar).')"
          f" returning id into {var};")

    # mapa planilha -> etapa/ambiente
    for grupo, (ordem, amb, cat, tipo, rev, obs) in GRUPO.items():
        e, a, c = ref(ordem, amb, cat)
        w("  insert into obra.importacao_mapa(obra_id, escopo, valor, etapa_id, ambiente_id, categoria_id, tipo_custo, revisar, observacao)"
          f" values (v_obra, 'grupo', obra.slug({q(grupo)}), {e}, {a}, {c}, {q(tipo)}, {q(rev)}, {q(obs)});")
    por_numero = {}
    for l in itens:
        if l["numero"] in ITEM:
            por_numero.setdefault(l["numero"], l)
    for numero, (ordem, amb, cat, tipo, rev, obs) in ITEM.items():
        l = por_numero[numero]
        e, a, c = ref(ordem, amb, cat)
        w("  insert into obra.importacao_mapa(obra_id, escopo, valor, etapa_id, ambiente_id, categoria_id, tipo_custo, revisar, observacao)"
          f" values (v_obra, 'item', obra.chave_item({q(l['classe'])}, {q(l['grupo'])}, {q(l['descricao'])}), {e}, {a}, {c},"
          f" {q(tipo)}, {q(rev)}, {q(obs)});")
    w("  raise notice 'obra=%', v_obra;")
    w("end $seed$;")
    open(saida, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print(f"seed -> {saida} ({len(out)} linhas)")


if __name__ == "__main__":
    main(*sys.argv[1:4])
