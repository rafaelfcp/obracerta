import { useState, type FormEvent } from 'react'
import { supabase, mensagemErro } from '../lib/supabase'

type Modo = 'entrar' | 'criar' | 'esqueci'

export default function Login() {
  const [modo, setModo] = useState<Modo>('entrar')
  const [email, setEmail] = useState('')
  const [senha, setSenha] = useState('')
  const [nome, setNome] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  const [aviso, setAviso] = useState<string | null>(null)

  const voltarAoApp = window.location.origin + window.location.pathname

  async function enviar(ev: FormEvent) {
    ev.preventDefault()
    setErro(null)
    setAviso(null)
    setEnviando(true)
    try {
      if (modo === 'entrar') {
        const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password: senha })
        if (error) throw error
      } else if (modo === 'criar') {
        const { data, error } = await supabase.auth.signUp({
          email: email.trim(),
          password: senha,
          options: { emailRedirectTo: voltarAoApp, data: { nome: nome.trim() || undefined } },
        })
        if (error) throw error
        // sem sessão = o projeto exige confirmação por e-mail
        if (!data.session) setAviso('Conta criada. Abra o link que chegou no seu e-mail e depois entre com a senha.')
      } else {
        const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), { redirectTo: voltarAoApp })
        if (error) throw error
        setAviso('Se o e-mail tiver conta, chega um link para criar uma senha nova.')
      }
    } catch (e) {
      setErro(mensagemErro(e))
    } finally {
      setEnviando(false)
    }
  }

  const titulo = { entrar: 'Entrar', criar: 'Criar conta', esqueci: 'Recuperar senha' }[modo]

  return (
    <div className="login">
      <div className="login-marca">
        <img src="./icons/icon.svg" alt="" width={56} height={56} />
        <h1>ObraCerta</h1>
        <p>Casa Villagio Tunis</p>
      </div>

      <form className="card login-form" onSubmit={enviar}>
        <h2>{titulo}</h2>
        {modo === 'criar' && (
          <label>
            Como quer ser chamada(o)
            <input value={nome} onChange={(e) => setNome(e.target.value)} autoComplete="given-name" placeholder="Seu nome" />
          </label>
        )}
        <label>
          E-mail
          <input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="email" inputMode="email" />
        </label>
        {modo !== 'esqueci' && (
          <label>
            Senha
            <input
              type="password"
              required
              minLength={6}
              value={senha}
              onChange={(e) => setSenha(e.target.value)}
              autoComplete={modo === 'criar' ? 'new-password' : 'current-password'}
            />
          </label>
        )}

        {erro && <p className="msg erro" role="alert">{erro}</p>}
        {aviso && <p className="msg ok" role="status">{aviso}</p>}

        <button className="btn" disabled={enviando}>
          {enviando ? 'Aguarde…' : titulo}
        </button>

        <div className="login-links">
          {modo !== 'entrar' && <button type="button" className="link" onClick={() => setModo('entrar')}>Já tenho conta</button>}
          {modo !== 'criar' && <button type="button" className="link" onClick={() => setModo('criar')}>Primeiro acesso (criar conta)</button>}
          {modo !== 'esqueci' && <button type="button" className="link" onClick={() => setModo('esqueci')}>Esqueci a senha</button>}
        </div>
      </form>
      <p className="login-rodape">Só entra quem foi convidado para a obra.</p>
    </div>
  )
}
