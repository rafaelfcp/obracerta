// Formato das views do schema obra usadas pelo app (colunas conferidas no banco em 07/11/2026).

export type Semaforo = 'verde' | 'amarelo' | 'vermelho' | 'sem_orcamento' | string

export interface Painel {
  obra_id: string
  nome: string
  status_geral: string
  orcado_total: number
  orcado_lote: number
  orcado_obra: number
  contingencia: number
  contingencia_disponivel: number
  contratado: number
  pago: number
  a_pagar: number
  atrasado: number
  desvio: number
  desvio_pct: number
  custo_projetado: number
  valor_restante: number
  pct_fisico: number
  pct_financeiro_pago: number
  pct_financeiro_comprometido: number
  semaforo: Semaforo
  estouros: number
  etapas_atrasadas: number
  parcelas_atrasadas: number
  saldo_reserva: number | null
  reserva_seguranca: number
  saldo_disponivel: number | null
  fgts_previsto: number
  fgts_liberado: number
  fgts_utilizado: number
  simulacao_ativa: string | null
  financiamento_ativo: number | null
  caixa_liberado: number
  juros_obra_previstos: number | null
  necessidade_complementar: number | null
  inicio_previsto: string | null
  conclusao_prevista: string | null
}

export interface Etapa {
  id: string
  ordem: number
  nome: string
  status: string
  inicio_previsto: string | null
  fim_previsto: string | null
  pct_fisico: number
  recebe_indireto: boolean
  orcado_direto: number
  fator_indireto: number
  orcado: number
  contratado: number
  pago: number
  a_pagar: number
  saldo_orcamento: number
  projetado: number
  desvio: number
  desvio_pct: number
  pct_financeiro: number
  atrasada: boolean
  semaforo: Semaforo
}

export interface Item {
  id: string
  tipo_custo: 'direto' | 'indireto' | 'aquisicao_lote'
  etapa_id: string | null
  ambiente_id: string | null
  classe: string | null
  grupo: string | null
  descricao: string
  unidade: string | null
  quantidade: number | null
  cenario_escolhido: string | null
  prioridade: string | null
  incluido: boolean
  estimativa: boolean
  revisar: boolean
  revisar_motivos: string[]
  grupo_alternativa: string | null
  numero_origem: number | null
  orcado: number
  valor_orcado_cenario: number
  contratado: number
  pago: number
  a_pagar: number
  projetado: number
  desvio: number
}

export interface Alerta {
  nivel: string
  tipo: string
  mensagem: string
  entidade: string | null
  entidade_id: string | null
  data_ref: string | null
  valor: number | null
}

export interface Membro {
  obra_id: string
  usuario_id: string
  perfil: 'admin' | 'colaborador'
  nome_exibicao: string | null
}
