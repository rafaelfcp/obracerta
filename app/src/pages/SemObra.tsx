import { useState } from 'react'
import { useAuth } from '../lib/auth'

// Usuário autenticado mas sem convite aceito: não vê nenhum dado (o RLS também bloqueia).
export default function SemObra() {
  const { session, sair, recarregarMembro } = useAuth()
  const [verificando, setVerificando] = useState(false)
  return (
    <div className="login">
      <div className="card login-form">
        <h2>Sem acesso a uma obra</h2>
        <p>
          A conta <b>{session?.user.email}</b> ainda não foi convidada para nenhuma obra. Peça ao administrador para enviar o
          convite para este e-mail exato e toque em "Verificar de novo".
        </p>
        <button
          className="btn"
          disabled={verificando}
          onClick={async () => {
            setVerificando(true)
            await recarregarMembro()
            setVerificando(false)
          }}
        >
          {verificando ? 'Verificando…' : 'Verificar de novo'}
        </button>
        <button className="btn sec" onClick={sair}>
          Sair
        </button>
      </div>
    </div>
  )
}
