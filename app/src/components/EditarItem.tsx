import { useEffect, useState } from 'react'
import { supabase, mensagemErro } from '../lib/supabase'
import { brl } from '../lib/format'
import type { Item } from '../lib/tipos'

type Cenario = 'economico' | 'medio' | 'alto'
const CENARIOS: [Cenario, string][] = [
  ['economico', 'Econômico'],
  ['medio', 'Médio'],
  ['alto', 'Alto'],
]

// aceita "1.234,56", "1234,56" ou "1234.56"
export function lerNumero(txt: string): number | null {
  const t = txt.trim()
  if (!t) return null
  const normal = t.includes(',') ? t.replace(/\./g, '').replace(',', '.') : t
  const v = Number(normal)
  return Number.isFinite(v) ? v : null
}
const paraTexto = (v: number | null | undefined) => (v === null || v === undefined ? '' : String(v).replace('.', ','))

// Liga/desliga o item no total (atalho usado na lista).
export async function alternarIncluido(i: Item) {
  const { error } = await supabase.from('orcamento_item').update({ incluido: !i.incluido }).eq('id', i.id)
  if (error) throw error
}

export default function EditarItem({ item, aoFechar, aoSalvar }: { item: Item; aoFechar: () => void; aoSalvar: () => void }) {
  const [carregando, setCarregando] = useState(true)
  const [incluido, setIncluido] = useState(item.incluido)
  const [cenario, setCenario] = useState<Cenario>((item.cenario_escolhido as Cenario) ?? 'medio')
  const [qtd, setQtd] = useState(paraTexto(item.quantidade))
  const [valorFixo, setValorFixo] = useState<string | null>(null) // null = item calculado por quantidade x preço
  const [precos, setPrecos] = useState<Record<Cenario, string>>({ economico: '', medio: '', alto: '' })
  const [salvando, setSalvando] = useState(false)
  const [erro, setErro] = useState<string | null>(null)

  useEffect(() => {
    ;(async () => {
      const [{ data: it }, { data: pr }] = await Promise.all([
        supabase.from('orcamento_item').select('valor_fixo').eq('id', item.id).maybeSingle(),
        supabase.from('orcamento_item_preco').select('cenario, preco_unitario').eq('item_id', item.id),
      ])
      if (it?.valor_fixo !== null && it?.valor_fixo !== undefined) setValorFixo(paraTexto(Number(it.valor_fixo)))
      const p = { economico: '', medio: '', alto: '' }
      for (const r of pr ?? []) p[r.cenario as Cenario] = paraTexto(Number(r.preco_unitario))
      setPrecos(p)
      setCarregando(false)
    })()
  }, [item.id])

  const previa =
    valorFixo !== null ? lerNumero(valorFixo) : (lerNumero(qtd) ?? 0) * (lerNumero(precos[cenario]) ?? 0)

  async function salvar() {
    setErro(null)
    setSalvando(true)
    try {
      // 1) preços primeiro: o trigger do item recalcula o valor com os preços já gravados
      if (valorFixo === null) {
        for (const [c] of CENARIOS) {
          const v = lerNumero(precos[c])
          if (v === null) continue
          const { data, error } = await supabase
            .from('orcamento_item_preco')
            .update({ preco_unitario: v })
            .eq('item_id', item.id)
            .eq('cenario', c)
            .select('item_id')
          if (error) throw error
          if (!data?.length) {
            const { error: e2 } = await supabase.from('orcamento_item_preco').insert({ item_id: item.id, cenario: c, preco_unitario: v })
            if (e2) throw e2
          }
        }
      }
      // 2) o item (dispara o recálculo de valor_orcado e a auditoria)
      const campos: Record<string, unknown> = { incluido, cenario_escolhido: cenario }
      if (valorFixo !== null) campos.valor_fixo = lerNumero(valorFixo)
      else campos.quantidade = lerNumero(qtd)
      const { error } = await supabase.from('orcamento_item').update(campos).eq('id', item.id)
      if (error) throw error
      aoSalvar()
    } catch (e) {
      setErro(mensagemErro(e))
    } finally {
      setSalvando(false)
    }
  }

  const alternativa = item.revisar_motivos?.includes('alternativa_excludente')

  return (
    <div className="sheet-fundo" onClick={aoFechar}>
      <div className="sheet" role="dialog" aria-modal="true" aria-label="Editar item" onClick={(e) => e.stopPropagation()}>
        <div className="sheet-alca" />
        <header className="sheet-h">
          <span className="item-num">#{item.numero_origem ?? '—'}</span>
          <h2>{item.descricao}</h2>
        </header>

        {carregando ? (
          <div className="skeleton" />
        ) : (
          <div className="form">
            <label className="switch-linha">
              <span>
                <b>Incluído no total</b>
                <small>{incluido ? 'Soma no orçamento' : 'Fica como opcional, fora da soma'}</small>
              </span>
              <input type="checkbox" role="switch" checked={incluido} onChange={(e) => setIncluido(e.target.checked)} />
            </label>
            {alternativa && incluido && (
              <p className="msg aviso">Este item é uma alternativa: confira se a outra opção está fora do total.</p>
            )}

            {valorFixo !== null ? (
              <label>
                Valor (R$)
                <input inputMode="decimal" value={valorFixo} onChange={(e) => setValorFixo(e.target.value)} />
              </label>
            ) : (
              <>
                <div>
                  <span className="rotulo">Cenário usado no orçamento</span>
                  <div className="segmentos tres">
                    {CENARIOS.map(([c, rot]) => (
                      <button type="button" key={c} className={cenario === c ? 'ativo' : ''} onClick={() => setCenario(c)}>
                        {rot}
                      </button>
                    ))}
                  </div>
                </div>
                <label>
                  Quantidade ({item.unidade ?? 'un'})
                  <input inputMode="decimal" value={qtd} onChange={(e) => setQtd(e.target.value)} />
                </label>
                <div className="precos">
                  {CENARIOS.map(([c, rot]) => (
                    <label key={c} className={cenario === c ? 'destaque' : ''}>
                      Preço {rot}
                      <input inputMode="decimal" value={precos[c]} onChange={(e) => setPrecos({ ...precos, [c]: e.target.value })} />
                    </label>
                  ))}
                </div>
              </>
            )}

            <div className="previa">
              <span>Novo valor do item</span>
              <b className="num">{brl(previa)}</b>
            </div>
            {erro && <p className="msg erro">{erro}</p>}
            <div className="sheet-acoes">
              <button type="button" className="btn sec" onClick={aoFechar}>Cancelar</button>
              <button type="button" className="btn" disabled={salvando} onClick={salvar}>{salvando ? 'Salvando…' : 'Salvar'}</button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
