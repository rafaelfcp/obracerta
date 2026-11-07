import { supabase } from './supabase'
import { useDados } from './useDados'
import type { Item } from './tipos'

export type Cenario = 'economico' | 'medio' | 'alto'
export const CENARIOS: [Cenario, string][] = [
  ['economico', 'Econômico'],
  ['medio', 'Médio'],
  ['alto', 'Alto'],
]
export type Precos = Partial<Record<Cenario, number>>
export type MapaPrecos = Map<string, Precos>

// Preços unitários dos 3 padrões de todos os itens visíveis (o RLS limita às obras do usuário).
export function usePrecos() {
  const r = useDados(
    () =>
      supabase
        .from('orcamento_item_preco')
        .select('item_id, cenario, preco_unitario')
        .returns<{ item_id: string; cenario: Cenario; preco_unitario: number }[]>(),
    [],
  )
  const mapa: MapaPrecos = new Map()
  for (const p of r.dados ?? []) {
    const m = mapa.get(p.item_id) ?? {}
    m[p.cenario] = Number(p.preco_unitario)
    mapa.set(p.item_id, m)
  }
  return { mapa, recarregar: r.recarregar, carregando: r.carregando }
}

// Mesma regra de obra.calcular_valor_item: round(quantidade x preço do padrão, 2).
// null = item sem preço por padrão (valor fechado, ex.: lote e ITBI).
export function valorNoCenario(i: Item, precos: Precos | undefined, c: Cenario): number | null {
  if (!precos || precos[c] === undefined) return null
  if (i.quantidade === null) return 0
  return Math.round(Number(i.quantidade) * precos[c]! * 100) / 100
}

export function temPadroes(_i: Item, precos: Precos | undefined) {
  return !!precos && CENARIOS.some(([c]) => precos[c] !== undefined)
}

export async function escolherCenario(itemId: string, c: Cenario) {
  const { error } = await supabase.from('orcamento_item').update({ cenario_escolhido: c }).eq('id', itemId)
  if (error) throw error
}
