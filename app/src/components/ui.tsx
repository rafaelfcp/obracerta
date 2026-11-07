import type { ReactNode } from 'react'
import { clamp01, pct } from '../lib/format'
import type { Semaforo } from '../lib/tipos'

export function Card({ titulo, extra, children, className = '' }: { titulo?: ReactNode; extra?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <section className={`card ${className}`}>
      {(titulo || extra) && (
        <header className="card-h">
          {titulo && <h2>{titulo}</h2>}
          {extra}
        </header>
      )}
      {children}
    </section>
  )
}

export function Linha({ rotulo, valor, forte, tom }: { rotulo: ReactNode; valor: ReactNode; forte?: boolean; tom?: 'neg' | 'pos' | 'muted' }) {
  return (
    <div className={`linha ${forte ? 'forte' : ''}`}>
      <span>{rotulo}</span>
      <span className={`num ${tom ?? ''}`}>{valor}</span>
    </div>
  )
}

export function Barra({ valor, rotulo, tom = 'pri' }: { valor: number; rotulo?: string; tom?: 'pri' | 'ok' | 'warn' | 'bad' }) {
  return (
    <div className="barra-wrap">
      <div className="barra" role="progressbar" aria-valuenow={Math.round(clamp01(valor) * 100)} aria-valuemin={0} aria-valuemax={100}>
        <div className={`barra-fill ${tom}`} style={{ width: `${clamp01(valor) * 100}%` }} />
      </div>
      {rotulo !== undefined && <span className="barra-rot num">{rotulo || pct(valor)}</span>}
    </div>
  )
}

const SEMAFORO: Record<string, [string, string]> = {
  verde: ['ok', 'No orçamento'],
  amarelo: ['warn', 'Atenção'],
  vermelho: ['bad', 'Estourado'],
  sem_orcamento: ['muted', 'Sem orçamento'],
}
export function Sinal({ s, curto }: { s: Semaforo; curto?: boolean }) {
  const [cls, txt] = SEMAFORO[s] ?? ['muted', s]
  return (
    <span className={`sinal ${cls}`} title={txt}>
      <i />
      {!curto && txt}
    </span>
  )
}

export function Chip({ children, tom = 'muted' }: { children: ReactNode; tom?: 'muted' | 'warn' | 'bad' | 'ok' | 'pri' }) {
  return <span className={`chip ${tom}`}>{children}</span>
}

export function Estado({ carregando, erro, onTentar }: { carregando: boolean; erro: string | null; onTentar?: () => void }) {
  if (erro)
    return (
      <div className="estado erro">
        <p>{erro}</p>
        {onTentar && (
          <button className="btn sec" onClick={onTentar}>
            Tentar de novo
          </button>
        )}
      </div>
    )
  if (carregando)
    return (
      <div className="estado">
        <div className="skeleton" />
        <div className="skeleton" />
        <div className="skeleton curto" />
      </div>
    )
  return null
}

export function Vazio({ children }: { children: ReactNode }) {
  return <p className="vazio">{children}</p>
}
