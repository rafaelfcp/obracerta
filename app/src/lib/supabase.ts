import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL ?? 'https://lfagemsbgtzlqjjagrmn.supabase.co'
const key = import.meta.env.VITE_SUPABASE_KEY ?? 'sb_publishable_oiahYUSr3GlnBQaOdmpKSw_d3fp05aR'

// Cliente preso ao schema `obra`: toda .from() e .rpc() vai para obra.*, nunca para public.*
// (public é o DashBoard-Financeiro e não deve ser tocado pelo app).
export const supabase = createClient(url, key, {
  db: { schema: 'obra' },
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
})

// Mensagens de erro de negócio lançadas pelas funções do banco (OC_*) e do Auth, em português.
export function mensagemErro(e: unknown): string {
  const msg = (e as { message?: string })?.message ?? String(e)
  const mapa: [RegExp, string][] = [
    [/Invalid login credentials/i, 'E-mail ou senha incorretos.'],
    [/Email not confirmed/i, 'Confirme o e-mail pelo link que o Supabase enviou antes de entrar.'],
    [/User already registered/i, 'Este e-mail já tem conta. Use "Entrar" ou "Esqueci a senha".'],
    [/Password should be at least/i, 'A senha precisa ter pelo menos 6 caracteres.'],
    [/rate limit/i, 'Muitas tentativas seguidas. Espere alguns minutos e tente de novo.'],
    [/OC_SEM_PERMISSAO/, 'Seu perfil não permite essa ação.'],
    [/OC_ESTOURO_ORCAMENTO/, 'Esse lançamento estoura o orçamento do item.'],
    [/OC_PAGO_ACIMA_CONTRATADO/, 'O pagamento passa do valor contratado.'],
    [/Failed to fetch|NetworkError/i, 'Sem conexão com o servidor. Verifique a internet.'],
  ]
  for (const [re, txt] of mapa) if (re.test(msg)) return txt
  return msg
}
