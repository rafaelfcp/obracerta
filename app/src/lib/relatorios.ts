import { supabase } from './supabase'

// Catálogo de relatórios. Para lançar um relatório novo:
//   1) banco: função obra.relatorio_<tipo>(obra) + incluir o tipo no CHECK de obra.relatorio_envio
//   2) Edge Function obra-enviar-relatorio: aceitar o tipo e renderizar
//   3) aqui: trocar `disponivel` para true
export type TipoRelatorio = 'status_etapas' | 'pagamentos_mes' | 'fluxo_caixa' | 'curva_s'

export interface RelatorioDef {
  tipo: TipoRelatorio
  slug: string // rota: /relatorios/<slug>
  titulo: string
  descricao: string
  disponivel: boolean
}

export const CATALOGO: RelatorioDef[] = [
  {
    tipo: 'status_etapas',
    slug: 'status-etapas',
    titulo: 'Resumo de status das etapas',
    descricao: 'Avanço físico, orçado x pago, prazos e pontos de atenção das etapas. Vai com planilha CSV anexa.',
    disponivel: true,
  },
  {
    tipo: 'pagamentos_mes',
    slug: 'pagamentos-mes',
    titulo: 'Pagamentos do mês',
    descricao: 'O que foi pago e o que vence no mês, por etapa e fornecedor.',
    disponivel: false,
  },
  {
    tipo: 'fluxo_caixa',
    slug: 'fluxo-caixa',
    titulo: 'Fluxo de caixa projetado',
    descricao: 'Saídas previstas x reserva, FGTS e liberações da Caixa, mês a mês.',
    disponivel: false,
  },
  {
    tipo: 'curva_s',
    slug: 'curva-s',
    titulo: 'Curva S',
    descricao: 'Avanço físico x financeiro acumulado ao longo da obra.',
    disponivel: false,
  },
]

export const relatorioPorSlug = (slug?: string) => CATALOGO.find((r) => r.slug === slug)
export const tituloDoTipo = (tipo: string) => CATALOGO.find((r) => r.tipo === tipo)?.titulo ?? tipo

export const EMAIL_RE = /^[A-Z0-9._%+-]+@[A-Z0-9-]+(\.[A-Z0-9-]+)*\.[A-Z]{2,}$/i
export const MAX_DEST = 10

export interface Previa {
  assunto: string
  html: string
  dados: { gerado_em: string; totais: { etapas: number } }
}
export interface EnvioOk {
  ok: true
  envio_id: string | null
  destinatarios: string[]
  assunto: string
  aviso_log?: string
}
export interface EnvioLog {
  id: string
  tipo: string
  destinatarios: string[]
  assunto: string
  status: 'enviado' | 'erro'
  erro: string | null
  criado_em: string
  criado_por: string
}

const FN = 'obra-enviar-relatorio'

// Mensagens dos códigos que a Edge Function devolve ({ erro, mensagem }).
const MSG: Record<string, string> = {
  OC_EMAIL_NAO_CONFIGURADO: 'O envio por e-mail não está configurado no servidor.',
  OC_LIMITE: 'Limite de 10 envios por hora atingido. Tente mais tarde.',
  OC_SEM_PERMISSAO: 'Você não tem acesso a esta obra.',
  OC_SEM_TOKEN: 'Sua sessão expirou. Entre de novo.',
}

async function chamar<T>(body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke(FN, { body })
  if (error) {
    let codigo = '', mensagem = error.message
    try {
      const j = await (error as { context?: Response }).context?.json()
      if (j?.erro) {
        codigo = j.erro
        mensagem = j.mensagem
      }
    } catch {
      /* resposta sem JSON (rede, gateway) */
    }
    if (/Failed to fetch|NetworkError/i.test(mensagem)) mensagem = 'Sem conexão com o servidor. Verifique a internet.'
    throw new Error(MSG[codigo] ?? mensagem)
  }
  return data as T
}

export const gerarPrevia = (obraId: string, tipo: TipoRelatorio, mensagem: string) =>
  chamar<Previa>({ acao: 'preview', tipo, obra_id: obraId, mensagem: mensagem.trim() || null })

export const enviarRelatorio = (obraId: string, tipo: TipoRelatorio, destinatarios: string[], assunto: string, mensagem: string) =>
  chamar<EnvioOk>({ acao: 'enviar', tipo, obra_id: obraId, destinatarios, assunto: assunto.trim(), mensagem: mensagem.trim() || null })

export const listarEnvios = (obraId: string) =>
  supabase
    .from('relatorio_envio')
    .select('id, tipo, destinatarios, assunto, status, erro, criado_em, criado_por')
    .eq('obra_id', obraId)
    .order('criado_em', { ascending: false })
    .limit(20)
    .returns<EnvioLog[]>()
