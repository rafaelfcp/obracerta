-- =====================================================================
-- ObraCerta · 001 · Schema base
-- Schema dedicado "obra" no mesmo projeto do DashBoard-Financeiro.
-- Convenções:
--   * id uuid, obra_id em toda tabela de negócio
--   * valores numeric(14,2); quantidades numeric(14,3); percentuais numeric(7,4)
--   * auditoria de autoria: criado_em/por, atualizado_em/por
--   * exclusão lógica: excluido_em/por/motivo (DELETE físico é revogado)
-- =====================================================================

create schema if not exists obra;
comment on schema obra is 'ObraCerta — controle da construção da Casa Villagio Tunis';

grant usage on schema obra to authenticated, service_role;

-- ---------------------------------------------------------------------
-- Obra e acesso
-- ---------------------------------------------------------------------
create table obra.obra (
  id                  uuid primary key default gen_random_uuid(),
  nome                text not null,
  referencia_lote     text,
  endereco            text,
  lote_frente_m       numeric(6,2),
  lote_fundo_m        numeric(6,2),
  inicio_previsto     date,
  conclusao_prevista  date,
  status_geral        text not null default 'planejamento'
    check (status_geral in ('planejamento','projeto','licenciamento','fundacao','estrutura',
                            'alvenaria','instalacoes','acabamento','paisagismo','concluida')),
  contingencia_pct    numeric(7,4) not null default 0.10,
  limite_atencao_pct  numeric(7,4) not null default 1.00,  -- amarelo a partir de 100% do orçado
  limite_estouro_pct  numeric(7,4) not null default 1.05,  -- vermelho acima de 105%
  observacao          text,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text
);

create table obra.obra_membro (
  obra_id     uuid not null references obra.obra(id),
  usuario_id  uuid not null references auth.users(id),
  perfil      text not null check (perfil in ('admin','colaborador')),
  nome_exibicao text,
  criado_em   timestamptz not null default now(),
  primary key (obra_id, usuario_id)
);

create table obra.obra_convite (
  id          uuid primary key default gen_random_uuid(),
  obra_id     uuid not null references obra.obra(id),
  email       text not null,
  perfil      text not null default 'colaborador' check (perfil in ('admin','colaborador')),
  nome_exibicao text,
  aceito_em   timestamptz,
  aceito_por  uuid,
  criado_em   timestamptz not null default now(),
  criado_por  uuid default auth.uid(),
  unique (obra_id, email)
);

-- Premissas da obra (áreas da planta, BDI, perda etc.) — chave/valor versionável
create table obra.premissa (
  id          uuid primary key default gen_random_uuid(),
  obra_id     uuid not null references obra.obra(id),
  chave       text not null,
  valor       numeric(14,4),
  unidade     text,
  fonte       text,
  observacao  text,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text,
  unique (obra_id, chave)
);

-- ---------------------------------------------------------------------
-- Dimensões
-- ---------------------------------------------------------------------
create table obra.etapa (
  id                  uuid primary key default gen_random_uuid(),
  obra_id             uuid not null references obra.obra(id),
  ordem               int  not null,
  nome                text not null,
  status              text not null default 'planejada'
    check (status in ('planejada','em_andamento','pausada','concluida','cancelada')),
  situacao_kanban     text not null default 'a_fazer'
    check (situacao_kanban in ('a_fazer','em_andamento','aguardando_aprovacao','aguardando_material',
                               'aguardando_pagamento','pausada','concluida')),
  inicio_previsto     date,
  fim_previsto        date,
  inicio_real         date,
  fim_real            date,
  pct_fisico          numeric(7,4) not null default 0 check (pct_fisico between 0 and 1),
  metodo_pct_fisico   text not null default 'manual' check (metodo_pct_fisico in ('manual','checklist')),
  recebe_indireto     boolean not null default true,  -- recebe rateio de custos indiretos
  fornecedor_principal_id uuid,
  responsavel         text,
  observacao          text,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text,
  check (fim_previsto is null or inicio_previsto is null or fim_previsto >= inicio_previsto)
);
create unique index etapa_ordem_uk on obra.etapa(obra_id, ordem) where excluido_em is null;

create table obra.etapa_dependencia (
  etapa_id      uuid not null references obra.etapa(id),
  depende_de_id uuid not null references obra.etapa(id),
  tipo          text not null default 'FS' check (tipo in ('FS','SS','FF')),
  primary key (etapa_id, depende_de_id),
  check (etapa_id <> depende_de_id)
);

create table obra.ambiente (
  id          uuid primary key default gen_random_uuid(),
  obra_id     uuid not null references obra.obra(id),
  ordem       int not null,
  nome        text not null,
  pavimento   text check (pavimento in ('terreo','superior','externo','toda')),
  area_m2     numeric(10,2),
  observacao  text,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text
);
create unique index ambiente_nome_uk on obra.ambiente(obra_id, lower(nome)) where excluido_em is null;

create table obra.categoria (
  id          uuid primary key default gen_random_uuid(),
  obra_id     uuid not null references obra.obra(id),
  nome        text not null,
  natureza    text not null check (natureza in ('material','mao_de_obra','projeto','taxa','ferramenta',
                     'locacao','frete','imposto','imprevisto','reembolso','estorno','outros')),
  sinal       smallint not null default 1 check (sinal in (-1,1)), -- reembolso/estorno reduzem o gasto
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text
);
create unique index categoria_nome_uk on obra.categoria(obra_id, lower(nome)) where excluido_em is null;

create table obra.fornecedor (
  id          uuid primary key default gen_random_uuid(),
  obra_id     uuid not null references obra.obra(id),
  nome        text not null,
  tipo        text check (tipo in ('pessoa_fisica','pessoa_juridica')),
  documento   text,               -- CPF/CNPJ
  especialidade text,
  telefone    text,
  email       text,
  pix         text,
  observacao  text,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text
);
create unique index fornecedor_nome_uk on obra.fornecedor(obra_id, lower(nome)) where excluido_em is null;

alter table obra.etapa
  add constraint etapa_fornecedor_fk foreign key (fornecedor_principal_id) references obra.fornecedor(id);

-- ---------------------------------------------------------------------
-- Planejado: orçamento
-- ---------------------------------------------------------------------
create table obra.orcamento_item (
  id                uuid primary key default gen_random_uuid(),
  obra_id           uuid not null references obra.obra(id),
  tipo_custo        text not null default 'direto'
    check (tipo_custo in ('direto','indireto','aquisicao_lote')),
  etapa_id          uuid references obra.etapa(id),     -- null = A revisar (exceto lote/indireto)
  ambiente_id       uuid references obra.ambiente(id),  -- null = A revisar (exceto lote)
  categoria_id      uuid references obra.categoria(id),
  classe            text,          -- "Categoria" da planilha (Obra principal, Projetos...)
  grupo             text,          -- "Grupo" da planilha
  descricao         text not null,
  unidade           text,
  quantidade        numeric(14,3),
  prioridade        text check (prioridade in ('essencial','importante','opcional')),
  fase              text,          -- fase da planilha (1-Projeto, 4-Obra...)
  pct_financiavel   numeric(7,4) not null default 0 check (pct_financiavel between 0 and 1),
  base_contingencia boolean not null default false, -- entra na base de cálculo da contingência
  incluido          boolean not null default true,
  cenario_escolhido text check (cenario_escolhido in ('economico','medio','alto')),
  valor_fixo        numeric(14,2), -- itens sem quantidade x preço (ex.: lote)
  valor_orcado      numeric(14,2) not null default 0, -- mantido por trigger
  grupo_alternativa text,          -- itens mutuamente exclusivos
  estimativa        boolean not null default false,
  revisar           boolean not null default false,
  revisar_motivos   text[] not null default '{}',
  observacao        text,          -- espelha a observação da planilha (comparada na reimportação)
  nota              text,          -- anotações do app / do mapeamento (não comparada)
  chave_natural     text not null,
  numero_origem     int,           -- "#" da planilha (pode repetir)
  origem            text not null default 'manual' check (origem in ('manual','importacao')),
  import_snapshot   jsonb,         -- dados normalizados da última importação aplicada
  importacao_id     uuid,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text
);
create unique index orcamento_item_chave_uk on obra.orcamento_item(obra_id, chave_natural) where excluido_em is null;
create index orcamento_item_etapa_ix on obra.orcamento_item(etapa_id);
create index orcamento_item_amb_ix on obra.orcamento_item(ambiente_id);

create table obra.orcamento_item_preco (
  item_id         uuid not null references obra.orcamento_item(id),
  cenario         text not null check (cenario in ('economico','medio','alto')),
  preco_unitario  numeric(14,4) not null check (preco_unitario >= 0),
  atualizado_em   timestamptz not null default now(),
  atualizado_por  uuid,
  primary key (item_id, cenario)
);

create table obra.orcamento_versao (
  id          uuid primary key default gen_random_uuid(),
  obra_id     uuid not null references obra.obra(id),
  nome        text not null,
  data_base   date not null default current_date,
  total       numeric(14,2) not null,
  snapshot    jsonb not null,
  vigente     boolean not null default false,
  observacao  text,
  criado_em   timestamptz not null default now(),
  criado_por  uuid default auth.uid()
);
create unique index orcamento_versao_vigente_uk on obra.orcamento_versao(obra_id) where vigente;

-- ---------------------------------------------------------------------
-- Proposto: propostas de fornecedores
-- ---------------------------------------------------------------------
create table obra.proposta (
  id              uuid primary key default gen_random_uuid(),
  obra_id         uuid not null references obra.obra(id),
  fornecedor_id   uuid references obra.fornecedor(id),
  titulo          text not null,          -- serviço/item cotado (agrupa a comparação)
  etapa_id        uuid references obra.etapa(id),
  ambiente_id     uuid references obra.ambiente(id),
  categoria_id    uuid references obra.categoria(id),
  versao          int not null default 1,
  substitui_id    uuid references obra.proposta(id),
  status          text not null default 'rascunho'
    check (status in ('rascunho','solicitado','recebido','aprovado','recusado','substituido')),
  data_recebida   date,
  validade        date,
  prazo_execucao_dias int,
  condicao_pagamento text,
  parcelas_qtd    int,
  entrada_pct     numeric(7,4),
  desconto        numeric(14,2) not null default 0,
  impostos        numeric(14,2) not null default 0,
  valor_total     numeric(14,2) not null default 0, -- mantido por trigger (itens - desconto + impostos)
  observacao      text,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text
);

create table obra.proposta_item (
  id              uuid primary key default gen_random_uuid(),
  proposta_id     uuid not null references obra.proposta(id),
  orcamento_item_id uuid references obra.orcamento_item(id),
  descricao       text not null,
  unidade         text,
  quantidade      numeric(14,3) not null default 1,
  valor_unitario  numeric(14,4) not null default 0,
  valor_total     numeric(14,2) generated always as (round(quantidade * valor_unitario, 2)) stored,
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text
);

-- ---------------------------------------------------------------------
-- Comprometido: contratos, despesas, rateio, parcelas
-- ---------------------------------------------------------------------
create table obra.contrato (
  id              uuid primary key default gen_random_uuid(),
  obra_id         uuid not null references obra.obra(id),
  fornecedor_id   uuid references obra.fornecedor(id),
  proposta_id     uuid references obra.proposta(id),
  tipo            text not null default 'contrato' check (tipo in ('contrato','ordem_servico','pedido_compra')),
  numero          text,
  objeto          text not null,
  valor_total     numeric(14,2) not null check (valor_total >= 0),
  forma_pagamento text,
  data_assinatura date,
  status          text not null default 'ativo'
    check (status in ('rascunho','ativo','concluido','cancelado','em_renegociacao')),
  aprovado_por    uuid,
  aprovado_em     timestamptz,
  confirmado_estouro boolean not null default false, -- contratar acima do orçado exige confirmação
  observacao      text,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text
);

-- Gasto avulso (ou vinculado a um contrato existente)
create table obra.despesa (
  id              uuid primary key default gen_random_uuid(),
  obra_id         uuid not null references obra.obra(id),
  data            date not null default current_date,
  descricao       text not null,
  valor_total     numeric(14,2) not null check (valor_total > 0),
  fornecedor_id   uuid references obra.fornecedor(id),
  categoria_id    uuid references obra.categoria(id),
  contrato_id     uuid references obra.contrato(id), -- despesa dentro de um contrato (ex.: medição)
  proposta_id     uuid references obra.proposta(id),
  tipo_documento  text check (tipo_documento in ('nota_fiscal','recibo','cupom','boleto','outro')),
  numero_documento text,
  status          text not null default 'prevista'
    check (status in ('prevista','paga','parcial','cancelada')),  -- derivado das parcelas
  confirmado_estouro boolean not null default false,
  observacao      text,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text
);

-- Distribuição do valor de um contrato ou despesa por item/etapa/ambiente
create table obra.rateio (
  id              uuid primary key default gen_random_uuid(),
  obra_id         uuid not null references obra.obra(id),
  contrato_id     uuid references obra.contrato(id),
  despesa_id      uuid references obra.despesa(id),
  orcamento_item_id uuid references obra.orcamento_item(id),
  etapa_id        uuid references obra.etapa(id),
  ambiente_id     uuid references obra.ambiente(id),
  valor           numeric(14,2) not null check (valor > 0),
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text,
  check ((contrato_id is null) <> (despesa_id is null))
);
create index rateio_contrato_ix on obra.rateio(contrato_id);
create index rateio_despesa_ix on obra.rateio(despesa_id);
create index rateio_item_ix on obra.rateio(orcamento_item_id);

create table obra.parcela (
  id              uuid primary key default gen_random_uuid(),
  obra_id         uuid not null references obra.obra(id),
  contrato_id     uuid references obra.contrato(id),
  despesa_id      uuid references obra.despesa(id),
  numero          int not null default 1,
  vencimento      date not null,
  valor           numeric(14,2) not null check (valor > 0),
  status          text not null default 'prevista'
    check (status in ('prevista','paga','parcial','cancelada')),  -- derivado dos pagamentos
  observacao      text,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text,
  check ((contrato_id is null) <> (despesa_id is null))
);
create index parcela_venc_ix on obra.parcela(obra_id, vencimento) where excluido_em is null;

-- ---------------------------------------------------------------------
-- Realizado: pagamentos
-- ---------------------------------------------------------------------
create table obra.pagamento (
  id              uuid primary key default gen_random_uuid(),
  obra_id         uuid not null references obra.obra(id),
  parcela_id      uuid not null references obra.parcela(id),
  data            date not null default current_date,
  valor           numeric(14,2) not null check (valor > 0),
  forma           text check (forma in ('pix','boleto','ted','cartao_credito','cartao_debito',
                                        'dinheiro','cheque','financiamento_caixa','fgts')),
  fonte           text not null default 'reserva'
    check (fonte in ('reserva','conta_corrente','fgts','caixa')),
  confirmado_excesso boolean not null default false, -- pagar acima do contratado exige confirmação
  observacao      text,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text
);
create index pagamento_parcela_ix on obra.pagamento(parcela_id);
create index pagamento_data_ix on obra.pagamento(obra_id, data) where excluido_em is null;

-- ---------------------------------------------------------------------
-- Reserva, FGTS e financiamento
-- ---------------------------------------------------------------------
create table obra.reserva_conta (
  id          uuid primary key default gen_random_uuid(),
  obra_id     uuid not null references obra.obra(id),
  nome        text not null,                  -- ex.: CDB 101,5% CDI
  instituicao text,
  pct_cdi     numeric(7,4),
  ativa       boolean not null default true,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text
);

create table obra.reserva_movimento (
  id          uuid primary key default gen_random_uuid(),
  obra_id     uuid not null references obra.obra(id),
  conta_id    uuid references obra.reserva_conta(id),
  data        date not null,
  tipo        text not null check (tipo in ('saldo_inicial','aporte_mensal','aporte_eventual','rendimento',
                                            'resgate','destinacao_obra','destinacao_entrada')),
  valor       numeric(14,2) not null,   -- positivo entra, negativo sai (resgate/destinações)
  previsto    boolean not null default false,
  recorrente_ate date,                  -- aporte mensal recorrente (planejado) até esta data
  observacao  text,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text
);

-- Leitura de saldo real (âncora), como casa_propria_saldos do Financeiro
create table obra.reserva_saldo (
  id          uuid primary key default gen_random_uuid(),
  obra_id     uuid not null references obra.obra(id),
  conta_id    uuid references obra.reserva_conta(id),
  data        date not null,
  saldo_bruto numeric(14,2) not null,
  observacao  text,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text
);

-- Separação lógica do dinheiro: segurança e imprevistos não são "disponível para a obra"
create table obra.reserva_balde (
  id          uuid primary key default gen_random_uuid(),
  obra_id     uuid not null references obra.obra(id),
  balde       text not null check (balde in ('seguranca','imprevistos','obra','entrada')),
  valor_alvo  numeric(14,2),           -- null = calculado (imprevistos = contingência)
  observacao  text,
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  unique (obra_id, balde)
);

create table obra.fgts_evento (
  id            uuid primary key default gen_random_uuid(),
  obra_id       uuid not null references obra.obra(id),
  titular       text,
  descricao     text,
  valor         numeric(14,2) not null,
  status        text not null default 'previsto' check (status in ('previsto','solicitado','liberado','utilizado')),
  data_prevista date,
  data_real     date,
  observacao    text,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text
);

create table obra.financiamento_simulacao (
  id              uuid primary key default gen_random_uuid(),
  obra_id         uuid not null references obra.obra(id),
  nome            text not null,
  data_simulacao  date not null default current_date,
  linha           text not null default 'SBPE',
  sistema         text not null default 'SAC' check (sistema in ('SAC','PRICE')),
  taxa_aa         numeric(9,6) not null,       -- nominal a.a. (+TR)
  prazo_meses     int not null,
  renda_familiar  numeric(14,2) not null,
  comprometimento_max numeric(7,4) not null default 0.30,
  cota_max        numeric(7,4) not null default 0.80,
  avaliacao_pct_custo numeric(7,4) not null default 1.00,
  seguro_pct_mes  numeric(9,6) not null default 0.0007,
  tarifa_mes      numeric(10,2) not null default 25,
  meses_obra      int not null default 15,
  valor_terreno   numeric(14,2),
  entrada         numeric(14,2),               -- opcional: aporte além do terreno
  fgts_abatimento numeric(14,2) not null default 0,
  ativa           boolean not null default false,
  resultado       jsonb,                       -- retrato do cálculo na data
  observacao      text,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text
);
create unique index fin_sim_ativa_uk on obra.financiamento_simulacao(obra_id) where ativa and excluido_em is null;

create table obra.financiamento_liberacao (
  id            uuid primary key default gen_random_uuid(),
  obra_id       uuid not null references obra.obra(id),
  data          date not null,
  pct_obra_medido numeric(7,4),
  valor_liberado numeric(14,2) not null,
  previsto      boolean not null default false,
  observacao    text,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text
);

create table obra.amortizacao_extra (
  id            uuid primary key default gen_random_uuid(),
  obra_id       uuid not null references obra.obra(id),
  data          date not null,
  valor         numeric(14,2) not null check (valor > 0),
  efeito        text not null check (efeito in ('reduzir_prazo','reduzir_parcela')),
  fonte         text check (fonte in ('reserva','fgts','conta_corrente')),
  simulado      boolean not null default true,
  observacao    text,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text
);

-- ---------------------------------------------------------------------
-- Execução física, diário e anexos
-- ---------------------------------------------------------------------
create table obra.etapa_medicao (
  id          uuid primary key default gen_random_uuid(),
  obra_id     uuid not null references obra.obra(id),
  etapa_id    uuid not null references obra.etapa(id),
  data        date not null default current_date,
  pct_fisico  numeric(7,4) not null check (pct_fisico between 0 and 1),
  metodo      text not null default 'manual' check (metodo in ('manual','checklist')),
  comentario  text,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text
);

create table obra.etapa_checklist (
  id          uuid primary key default gen_random_uuid(),
  obra_id     uuid not null references obra.obra(id),
  etapa_id    uuid not null references obra.etapa(id),
  ordem       int not null default 0,
  descricao   text not null,
  peso        numeric(7,4) not null default 1 check (peso > 0),
  concluido   boolean not null default false,
  concluido_em timestamptz,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text
);

-- Diário: decisões, pendências, comentários
create table obra.registro (
  id          uuid primary key default gen_random_uuid(),
  obra_id     uuid not null references obra.obra(id),
  tipo        text not null check (tipo in ('decisao','pendencia','comentario')),
  texto       text not null,
  etapa_id    uuid references obra.etapa(id),
  ambiente_id uuid references obra.ambiente(id),
  fornecedor_id uuid references obra.fornecedor(id),
  resolvido_em timestamptz,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  atualizado_em timestamptz not null default now(),
  atualizado_por uuid,
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text
);

create table obra.anexo (
  id            uuid primary key default gen_random_uuid(),
  obra_id       uuid not null references obra.obra(id),
  tipo_documento text not null check (tipo_documento in ('contrato','orcamento','nota_fiscal','recibo',
                   'comprovante','art_rrt','projeto_arquitetonico','projeto_executivo','alvara','habite_se',
                   'foto','video','decisao','planilha','outro')),
  titulo        text,
  storage_path  text not null,         -- bucket obra-anexos
  mime          text,
  tamanho_bytes bigint,
  sha256        text,
  data_documento date,
  observacao    text,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid(),
  excluido_em  timestamptz, excluido_por uuid, excluido_motivo text
);

create table obra.anexo_vinculo (
  anexo_id    uuid not null references obra.anexo(id),
  entidade    text not null check (entidade in ('etapa','ambiente','fornecedor','proposta','contrato',
                   'despesa','parcela','pagamento','orcamento_item','registro','importacao')),
  entidade_id uuid not null,
  primary key (anexo_id, entidade, entidade_id)
);
create index anexo_vinculo_ent_ix on obra.anexo_vinculo(entidade, entidade_id);

-- ---------------------------------------------------------------------
-- Importação da planilha (staging)
-- ---------------------------------------------------------------------
create table obra.importacao (
  id            uuid primary key default gen_random_uuid(),
  obra_id       uuid not null references obra.obra(id),
  arquivo_nome  text not null,
  arquivo_sha256 text,
  storage_path  text,
  status        text not null default 'em_revisao' check (status in ('em_revisao','confirmada','cancelada')),
  resumo        jsonb,
  confirmada_em timestamptz,
  confirmada_por uuid,
  criado_em    timestamptz not null default now(),
  criado_por   uuid default auth.uid()
);

create table obra.importacao_linha (
  id            uuid primary key default gen_random_uuid(),
  importacao_id uuid not null references obra.importacao(id),
  aba           text not null default 'Itens',
  linha_planilha int,
  chave_natural text not null,
  dados_brutos  jsonb,          -- a linha original, intocada
  dados         jsonb not null, -- normalizada
  sugestao      jsonb,          -- etapa/ambiente/categoria sugeridos
  acao          text check (acao in ('novo','atualizar','sem_mudanca','a_revisar','conflito','removido')),
  problemas     text[] not null default '{}',
  diff          jsonb,          -- {campo: {app, planilha}}
  decisao       text check (decisao in ('aplicar','ignorar','manter_app','usar_planilha','excluir')),
  etapa_id      uuid references obra.etapa(id),     -- escolha na tela de revisão
  ambiente_id   uuid references obra.ambiente(id),
  destino_id    uuid references obra.orcamento_item(id)
);
create index importacao_linha_imp_ix on obra.importacao_linha(importacao_id);

-- Mapeamento persistente grupo/item da planilha -> etapa/ambiente (reaproveitado em reimportações)
create table obra.importacao_mapa (
  id          uuid primary key default gen_random_uuid(),
  obra_id     uuid not null references obra.obra(id),
  escopo      text not null check (escopo in ('item','grupo','classe')),
  valor       text not null,       -- chave_natural (item), slug do grupo ou da classe
  etapa_id    uuid references obra.etapa(id),
  ambiente_id uuid references obra.ambiente(id),
  categoria_id uuid references obra.categoria(id),
  tipo_custo  text check (tipo_custo in ('direto','indireto','aquisicao_lote')),
  revisar     boolean not null default false,
  observacao  text,
  unique (obra_id, escopo, valor)
);

-- ---------------------------------------------------------------------
-- Auditoria
-- ---------------------------------------------------------------------
create table obra.auditoria (
  id          bigint generated always as identity primary key,
  obra_id     uuid,
  tabela      text not null,
  registro_id uuid,
  operacao    text not null,          -- INSERT / UPDATE / DELETE / EXCLUSAO_LOGICA
  antes       jsonb,
  depois      jsonb,
  campos      text[],                 -- campos alterados
  origem      text,                   -- app / importacao / sistema
  usuario_id  uuid default auth.uid(),
  em          timestamptz not null default now()
);
create index auditoria_reg_ix on obra.auditoria(tabela, registro_id);
create index auditoria_obra_ix on obra.auditoria(obra_id, em desc);
