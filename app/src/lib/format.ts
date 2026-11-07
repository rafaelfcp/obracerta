const brlFmt = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' })
const brlCurto = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 })
const pctFmt = new Intl.NumberFormat('pt-BR', { style: 'percent', maximumFractionDigits: 1 })
const numFmt = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 2 })

const n = (v: unknown) => (v === null || v === undefined || v === '' ? null : Number(v))

export const brl = (v: unknown) => (n(v) === null ? '—' : brlFmt.format(n(v)!))
export const brlK = (v: unknown) => (n(v) === null ? '—' : brlCurto.format(n(v)!))
export const pct = (v: unknown) => (n(v) === null ? '—' : pctFmt.format(n(v)!))
export const num = (v: unknown) => (n(v) === null ? '—' : numFmt.format(n(v)!))

export function data(v: string | null | undefined) {
  if (!v) return '—'
  const [y, m, d] = v.slice(0, 10).split('-')
  return `${d}/${m}/${y}`
}

export function mesAno(v: string | null | undefined) {
  if (!v) return '—'
  const [y, m] = v.slice(0, 7).split('-')
  const meses = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez']
  return `${meses[Number(m) - 1]}/${y.slice(2)}`
}

export const clamp01 = (v: unknown) => Math.max(0, Math.min(1, Number(v) || 0))
