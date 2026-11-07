import { createContext, useContext, useEffect, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from './supabase'
import type { Membro } from './tipos'

interface AuthCtx {
  session: Session | null
  membro: Membro | null
  carregando: boolean
  // true quando o login deu certo mas o usuário ainda não é membro de nenhuma obra
  semObra: boolean
  recuperando: boolean
  fimRecuperacao: () => void
  sair: () => Promise<void>
  recarregarMembro: () => Promise<void>
}

const Ctx = createContext<AuthCtx>(null as unknown as AuthCtx)
export const useAuth = () => useContext(Ctx)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [membro, setMembro] = useState<Membro | null>(null)
  const [carregando, setCarregando] = useState(true)
  const [semObra, setSemObra] = useState(false)
  const [recuperando, setRecuperando] = useState(false)

  async function carregarMembro(s: Session | null) {
    if (!s) {
      setMembro(null)
      setSemObra(false)
      return
    }
    // 1º acesso da colaboradora: transforma o convite (por e-mail) em membro da obra.
    // Para quem já é membro, a função não faz nada.
    await supabase.rpc('aceitar_convites')
    const { data } = await supabase
      .from('obra_membro')
      .select('obra_id, usuario_id, perfil, nome_exibicao')
      .eq('usuario_id', s.user.id)
      .limit(1)
    const m = (data?.[0] as Membro | undefined) ?? null
    setMembro(m)
    setSemObra(!m)
  }

  useEffect(() => {
    supabase.auth.getSession().then(async ({ data }) => {
      setSession(data.session)
      await carregarMembro(data.session)
      setCarregando(false)
    })
    const { data: sub } = supabase.auth.onAuthStateChange((evento, s) => {
      setSession(s)
      // link de "esqueci a senha": o usuário volta logado e precisa definir a senha nova
      if (evento === 'PASSWORD_RECOVERY') setRecuperando(true)
      // o callback do Supabase não pode aguardar outra chamada ao Supabase: agenda para depois
      if (evento === 'SIGNED_IN' || evento === 'SIGNED_OUT') {
        setTimeout(() => {
          setCarregando(true)
          carregarMembro(s).finally(() => setCarregando(false))
        }, 0)
      }
    })
    return () => sub.subscription.unsubscribe()
  }, [])

  const valor: AuthCtx = {
    session,
    membro,
    carregando,
    semObra,
    recuperando,
    fimRecuperacao: () => setRecuperando(false),
    sair: async () => {
      await supabase.auth.signOut()
    },
    recarregarMembro: () => carregarMembro(session),
  }
  return <Ctx.Provider value={valor}>{children}</Ctx.Provider>
}
