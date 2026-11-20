import { Link } from 'react-router-dom'
import { brlK } from '../lib/format'
import type { Etapa } from '../lib/tipos'

// Painel "Orçado x Realizado" por etapa (visual escuro fixo, nos dois temas).
// Sem datas nas etapas, o eixo X é a ORDEM das etapas (sequência da obra), não o tempo.
// Realizado = comprometido = maior entre contratado e pago (o que já é compromisso firme).
// Projeção = soma de v_etapa_painel.projetado = greatest(orçado + desvio dos itens, contratado, pago).

export type EtapaOR = Pick<Etapa, 'id' | 'ordem' | 'nome' | 'orcado' | 'contratado' | 'pago' | 'projetado' | 'semaforo'>

const N = (v: unknown) => Number(v) || 0
const pctSinal = (v: number | null) =>
  v === null ? '—' : `${v > 0 ? '+' : v < 0 ? '−' : ''}${Math.abs(v * 100).toLocaleString('pt-BR', { minimumFractionDigits: 1, maximumFractionDigits: 1 })}%`
const brlSinal = (v: number) => `${v > 0 ? '+' : v < 0 ? '−' : ''}${brlK(Math.abs(v))}`

const TOM: Record<string, string> = { verde: 'ok', amarelo: 'warn', vermelho: 'bad', sem_orcamento: 'mut' }

function calcularOR(etapas: EtapaOR[]) {
  const lista = [...etapas].sort((a, b) => a.ordem - b.ordem)
  const linhas = lista.map((e) => {
    const orcado = N(e.orcado)
    const real = Math.max(N(e.contratado), N(e.pago))
    const projetado = N(e.projetado)
    const desvio = projetado - orcado
    return { ...e, orcado, real, projetado, desvio, desvioPct: orcado > 0 ? desvio / orcado : null }
  })
  const orcado = linhas.reduce((s, l) => s + l.orcado, 0)
  const projetado = linhas.reduce((s, l) => s + l.projetado, 0)
  const real = linhas.reduce((s, l) => s + l.real, 0)
  const pago = lista.reduce((s, e) => s + N(e.pago), 0)
  // desvio "até hoje": só nas etapas que já têm compromisso (contratado/pago)
  const comMov = linhas.filter((l) => l.real > 0)
  const orcadoComMov = comMov.reduce((s, l) => s + l.orcado, 0)
  const desvioHoje = comMov.reduce((s, l) => s + (l.real - l.orcado), 0)
  return {
    linhas,
    orcado,
    projetado,
    real,
    pago,
    desvioProj: projetado - orcado,
    desvioProjPct: orcado > 0 ? (projetado - orcado) / orcado : null,
    comMov: comMov.length,
    desvioHoje,
    desvioHojePct: orcadoComMov > 0 ? desvioHoje / orcadoComMov : null,
    semOrcamento: linhas.filter((l) => l.semaforo === 'sem_orcamento'),
    estouradas: linhas.filter((l) => l.semaforo === 'vermelho'),
  }
}

function Curva({ c }: { c: ReturnType<typeof calcularOR> }) {
  const W = 320, H = 118, L = 6, R = 12, T = 10, B = 18
  const n = c.linhas.length
  const max = Math.max(c.orcado, c.projetado, c.real, 1)
  const x = (i: number) => L + (i / Math.max(n, 1)) * (W - L - R)
  const y = (v: number) => T + (1 - v / max) * (H - T - B)
  const acum = (f: (l: (typeof c.linhas)[number]) => number) => {
    const pts: [number, number][] = [[x(0), y(0)]]
    let s = 0
    c.linhas.forEach((l, i) => { s += f(l); pts.push([x(i + 1), y(s)]) })
    return pts
  }
  const path = (pts: [number, number][]) => pts.map(([a, b], i) => `${i ? 'L' : 'M'}${a.toFixed(1)},${b.toFixed(1)}`).join(' ')
  const pOrc = acum((l) => l.orcado)
  const pProj = acum((l) => l.projetado)
  // realizado só até a última etapa com movimento
  let ult = -1
  c.linhas.forEach((l, i) => { if (l.real > 0) ult = i })
  const pReal = ult >= 0 ? acum((l) => l.real).slice(0, ult + 2) : []
  const realAcima = c.desvioHoje > 0
  const fimP = pProj[pProj.length - 1], fimO = pOrc[pOrc.length - 1]
  const ticks = [1, 5, 10, 15, n].filter((t, i, a) => t <= n && a.indexOf(t) === i)

  return (
    <svg className="or-curva" viewBox={`0 0 ${W} ${H}`} role="img" aria-label="Curva acumulada por etapa: orçado, projeção e realizado">
      <defs>
        <filter id="or-glow" x="-10%" y="-30%" width="120%" height="160%"><feGaussianBlur stdDeviation="3" /></filter>
        <linearGradient id="or-area" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#6ea8ff" stopOpacity=".18" /><stop offset="1" stopColor="#6ea8ff" stopOpacity="0" /></linearGradient>
      </defs>
      {[0.25, 0.5, 0.75].map((f) => <line key={f} x1={L} x2={W - R} y1={T + f * (H - T - B)} y2={T + f * (H - T - B)} className="or-grade" />)}
      <path d={`${path(pOrc)} L${fimO[0]},${y(0)} Z`} fill="url(#or-area)" />
      <path d={path(pProj)} className="or-l proj glow" filter="url(#or-glow)" />
      <path d={path(pProj)} className="or-l proj" />
      <path d={path(pOrc)} className="or-l orc" />
      {pReal.length > 1 && <path d={path(pReal)} className={`or-l real ${realAcima ? 'acima' : ''}`} />}
      {pReal.length > 1 && <circle cx={pReal[pReal.length - 1][0]} cy={pReal[pReal.length - 1][1]} r="4" className={`or-ponto ${realAcima ? 'acima' : ''}`} />}
      <circle cx={fimO[0]} cy={fimO[1]} r="4" className="or-fim orc" />
      <circle cx={fimP[0]} cy={fimP[1]} r={c.desvioProj > 0 ? 5 : 3} className="or-fim proj" />
      {ticks.map((t) => <text key={t} x={x(t - 0.5)} y={H - 4} className="or-tick">{t}</text>)}
    </svg>
  )
}

export default function OrcadoRealizado({ etapas, obra }: { etapas: EtapaOR[]; obra: string }) {
  const c = calcularOR(etapas)
  const tomProj = c.desvioProj > 0 ? 'bad' : c.desvioProj < 0 ? 'ok' : 'neu'

  return (
    <section className="or" aria-label="Orçado x realizado por etapa">
      <header className="or-h">
        <div>
          <h2>ORÇADO X REALIZADO <span>· {obra}</span></h2>
          <p className={`or-alerta ${tomProj}`}>
            <i />
            {c.comMov === 0
              ? 'Nenhuma etapa contratada ainda: os desvios aparecem com os contratos e pagamentos'
              : c.desvioProj > 0
                ? `Projeção: a obra fecha ${brlSinal(c.desvioProj)} acima do orçado`
                : 'Projeção dentro do orçado das etapas'}
          </p>
        </div>
        <ul className="or-leg">
          <li className="orc">Orçado</li>
          <li className="real">Realizado</li>
          <li className="proj">Projeção</li>
        </ul>
      </header>

      <div className="or-kpis">
        <div className="or-kpi">
          <span>Desvio até hoje</span>
          <strong className={`num ${c.desvioHoje > 0 ? 'bad' : c.desvioHoje < 0 ? 'ok' : 'neu'}`}>{brlSinal(c.desvioHoje)}</strong>
          <small>{c.comMov ? `${pctSinal(c.desvioHojePct)} nas ${c.comMov} etapa(s) contratadas` : 'sem etapas contratadas'}</small>
          <dl>
            <dt>Contratado</dt><dd className="num">{brlK(c.real)}</dd>
            <dt>Pago</dt><dd className="num">{brlK(c.pago)}</dd>
          </dl>
        </div>
        <div className={`or-kpi proj ${tomProj}`}>
          <span>Projeção · fim</span>
          <strong className={`num ${tomProj}`}>{brlSinal(c.desvioProj)}</strong>
          <small>{pctSinal(c.desvioProjPct)} sobre o orçado das etapas</small>
          <dl>
            <dt>Orçado</dt><dd className="num">{brlK(c.orcado)}</dd>
            <dt>Projetado</dt><dd className="num">{brlK(c.projetado)}</dd>
          </dl>
        </div>
      </div>

      <Curva c={c} />
      <p className="or-eixo">Acumulado por etapa, na ordem da obra (1 a {c.linhas.length}) · sem lote e contingência</p>

      <div className="or-cards" role="list">
        {c.linhas.map((l) => {
          const tom = TOM[l.semaforo] ?? 'mut'
          const base = Math.max(l.orcado, l.projetado, l.real, 1)
          return (
            <Link key={l.id} to={`/etapas/${l.id}`} className={`or-card ${tom}`} role="listitem">
              <div className="or-card-h">
                <b>{l.ordem}. {l.nome}</b>
                <em className="num">{l.semaforo === 'sem_orcamento' ? 'sem orç.' : pctSinal(l.desvioPct)}</em>
              </div>
              <div className="or-barra">
                <div className="or-barra-fill" style={{ width: `${(l.real / base) * 100}%` }} />
                {l.orcado > 0 && l.real > 0 && <i style={{ left: `${(l.orcado / base) * 100}%` }} />}
              </div>
              <dl>
                <dt>orç</dt><dd className="num">{brlK(l.orcado)}</dd>
                <dt>real</dt><dd className={`num real ${l.real > 0 ? 'tem' : ''}`}>{brlK(l.real)}</dd>
              </dl>
            </Link>
          )
        })}
      </div>

      {(c.semOrcamento.length > 0 || c.estouradas.length > 0) && (
        <ul className="or-atencao">
          {c.estouradas.length > 0 && <li className="bad">Estouradas: {c.estouradas.map((e) => e.nome).join(', ')}</li>}
          {c.semOrcamento.length > 0 && <li className="warn">Sem orçamento: {c.semOrcamento.map((e) => e.nome).join(', ')}</li>}
        </ul>
      )}
    </section>
  )
}
