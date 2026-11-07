import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useDados } from '../lib/useDados'
import { useAuth } from '../lib/auth'
import { brl, data } from '../lib/format'
import type { Alerta } from '../lib/tipos'
import { Estado, Vazio } from '../components/ui'
import { Topo } from '../components/Layout'

const ORDEM: Record<string, number> = { vermelho: 0, amarelo: 1, cinza: 2 }
const NIVEL: Record<string, string> = { vermelho: 'bad', amarelo: 'warn', cinza: 'muted' }

function destino(a: Alerta) {
  if (a.entidade === 'etapa' && a.entidade_id) return `/etapas/${a.entidade_id}`
  if (a.entidade === 'orcamento_item') return '/orcamento'
  return null
}

export default function Alertas() {
  const { membro } = useAuth()
  const { dados, erro, carregando, recarregar } = useDados(
    () => supabase.from('v_alerta').select('*').eq('obra_id', membro!.obra_id).returns<Alerta[]>(),
    [membro?.obra_id],
  )
  const lista = [...(dados ?? [])].sort((a, b) => (ORDEM[a.nivel] ?? 9) - (ORDEM[b.nivel] ?? 9))

  return (
    <div className="pagina">
      <Topo titulo="Alertas" sub={dados ? `${lista.length} aviso(s)` : undefined} />
      {!dados ? (
        <Estado carregando={carregando} erro={erro} onTentar={recarregar} />
      ) : lista.length === 0 ? (
        <Vazio>Nenhum alerta. Tudo dentro do previsto.</Vazio>
      ) : (
        <ul className="lista-cards">
          {lista.map((a, k) => {
            const to = destino(a)
            const corpo = (
              <>
                <i className={`ponto ${NIVEL[a.nivel] ?? 'muted'}`} />
                <div>
                  <p>{a.mensagem}</p>
                  {(a.data_ref || (a.valor !== null && Number(a.valor) !== 0)) && (
                    <span className="sub">
                      {a.data_ref && data(a.data_ref)}
                      {a.data_ref && a.valor ? ' · ' : ''}
                      {a.valor ? brl(a.valor) : ''}
                    </span>
                  )}
                </div>
                {to && <span className="seta">›</span>}
              </>
            )
            return (
              <li key={k}>
                {to ? (
                  <Link to={to} className="card alerta">
                    {corpo}
                  </Link>
                ) : (
                  <div className="card alerta">{corpo}</div>
                )}
              </li>
            )
          })}
        </ul>
      )}
    </div>
  )
}
