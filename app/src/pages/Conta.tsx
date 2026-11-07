import { useState, type FormEvent } from 'react'
import { supabase, mensagemErro } from '../lib/supabase'
import { useAuth } from '../lib/auth'
import { Card, Linha } from '../components/ui'
import { Topo } from '../components/Layout'

export function TrocarSenha({ aoConcluir }: { aoConcluir?: () => void }) {
  const [senha, setSenha] = useState('')
  const [conf, setConf] = useState('')
  const [msg, setMsg] = useState<{ ok: boolean; txt: string } | null>(null)
  const [enviando, setEnviando] = useState(false)

  async function enviar(ev: FormEvent) {
    ev.preventDefault()
    if (senha !== conf) return setMsg({ ok: false, txt: 'As senhas não conferem.' })
    setEnviando(true)
    const { error } = await supabase.auth.updateUser({ password: senha })
    setEnviando(false)
    if (error) return setMsg({ ok: false, txt: mensagemErro(error) })
    setMsg({ ok: true, txt: 'Senha alterada.' })
    setSenha('')
    setConf('')
    aoConcluir?.()
  }

  return (
    <form className="form" onSubmit={enviar}>
      <label>
        Nova senha
        <input type="password" minLength={6} required value={senha} onChange={(e) => setSenha(e.target.value)} autoComplete="new-password" />
      </label>
      <label>
        Repita a senha
        <input type="password" minLength={6} required value={conf} onChange={(e) => setConf(e.target.value)} autoComplete="new-password" />
      </label>
      {msg && <p className={`msg ${msg.ok ? 'ok' : 'erro'}`}>{msg.txt}</p>}
      <button className="btn" disabled={enviando}>{enviando ? 'Salvando…' : 'Salvar senha'}</button>
    </form>
  )
}

export default function Conta() {
  const { session, membro, sair } = useAuth()
  return (
    <div className="pagina">
      <Topo titulo="Conta" />
      <Card titulo="Você">
        <Linha rotulo="Nome" valor={membro?.nome_exibicao ?? '—'} />
        <Linha rotulo="E-mail" valor={session?.user.email} />
        <Linha rotulo="Perfil" valor={membro?.perfil === 'admin' ? 'Administrador' : 'Colaboradora(or)'} />
      </Card>
      <Card titulo="Trocar senha">
        <TrocarSenha />
      </Card>
      <Card titulo="Instalar no celular">
        <p className="nota">
          iPhone: no Safari, toque em Compartilhar → "Adicionar à Tela de Início". Android: no Chrome, menu ⋮ → "Instalar app".
        </p>
      </Card>
      <button className="btn sec largo" onClick={sair}>Sair</button>
      <p className="versao">ObraCerta v0.1 · dados no schema obra (isolado do Financeiro)</p>
    </div>
  )
}
