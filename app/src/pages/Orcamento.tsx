import { useMemo, useState } from 'react'
import { supabase, mensagemErro } from '../lib/supabase'
import { useDados } from '../lib/useDados'
import { useAuth } from '../lib/auth'
import { brl, brlK, num } from '../lib/format'
import type { Item } from '../lib/tipos'
import { Chip, Estado, Vazio } from '../components/ui'
import { Topo } from '../components/Layout'
import EditarItem, { alternarIncluido } from '../components/EditarItem'

type Filtro = 'incluidos' | 'opcionais' | 'revisar' | 'todos'

const MOTIVO: Record<string, string> = {
  alternativa_excludente: 'alternativa: escolher uma',
  estimativa_a_confirmar: 'estimativa',
  mapeamento_a_revisar: 'mapeamento',
  quantidade_zero: 'quantidade zero',
}

const CENARIO: Record<string, string> = { economico: 'Econômico', medio: 'Médio', alto: 'Alto' }

// valor exibido: o orçado (itens incluídos) ou, para opcionais fora do total, o valor do cenário escolhido
const valorItem = (i: Item) => (i.incluido ? Number(i.orcado) : Number(i.valor_orcado_cenario))

export function ItemLinha({ i, onAlterado }: { i: Item; onAlterado?: () => void }) {
  const { membro } = useAuth()
  const podeEditar = !!membro && !!onAlterado
  const [aberto, setAberto] = useState(false)
  const [editando, setEditando] = useState(false)
  const [ocupado, setOcupado] = useState(false)
  const [erro, setErro] = useState<string | null>(null)

  async function alternar() {
    setOcupado(true)
    setErro(null)
    try {
      await alternarIncluido(i)
      onAlterado?.()
    } catch (e) {
      setErro(mensagemErro(e))
    } finally {
      setOcupado(false)
    }
  }

  return (
    <li className={`item ${i.incluido ? '' : 'fora'}`}>
      <button className="item-top" onClick={() => setAberto(!aberto)} aria-expanded={aberto}>
        <div className="item-desc">
          <span className="item-num">#{i.numero_origem ?? '—'}</span>
          <span>{i.descricao}</span>
        </div>
        <span className="num item-valor">{brl(valorItem(i))}</span>
      </button>
      <div className="item-chips">
        {!i.incluido && <Chip>fora do total</Chip>}
        {i.tipo_custo === 'indireto' && <Chip tom="pri">indireto rateado</Chip>}
        {i.tipo_custo === 'aquisicao_lote' && <Chip tom="pri">lote</Chip>}
        {Number(i.pago) > 0 && <Chip tom="ok">pago {brlK(i.pago)}</Chip>}
        {i.estimativa && <Chip tom="warn">estimativa</Chip>}
        {i.revisar && <Chip tom="bad">revisar</Chip>}
      </div>
      {aberto && (
        <>
          <dl className="item-det">
            <div><dt>Grupo</dt><dd>{i.grupo ?? '—'}</dd></div>
            <div><dt>Quantidade</dt><dd>{num(i.quantidade)} {i.unidade ?? ''}</dd></div>
            <div><dt>Cenário</dt><dd>{CENARIO[i.cenario_escolhido ?? ''] ?? '—'}</dd></div>
            <div><dt>Prioridade</dt><dd>{i.prioridade ?? '—'}</dd></div>
            <div><dt>Contratado</dt><dd className="num">{brl(i.contratado)}</dd></div>
            <div><dt>Pago</dt><dd className="num">{brl(i.pago)}</dd></div>
            {i.revisar_motivos?.length > 0 && (
              <div className="full"><dt>Revisar</dt><dd>{i.revisar_motivos.map((m) => MOTIVO[m] ?? m).join(', ')}</dd></div>
            )}
          </dl>
          {podeEditar && (
            <div className="item-acoes">
              <button className="btn sec" disabled={ocupado} onClick={alternar}>
                {ocupado ? '…' : i.incluido ? 'Tirar do total' : 'Incluir no total'}
              </button>
              <button className="btn" onClick={() => setEditando(true)}>Editar valores</button>
            </div>
          )}
          {erro && <p className="msg erro item-msg">{erro}</p>}
        </>
      )}
      {editando && (
        <EditarItem
          item={i}
          aoFechar={() => setEditando(false)}
          aoSalvar={() => {
            setEditando(false)
            onAlterado?.()
          }}
        />
      )}
    </li>
  )
}

// Ações em lote para uma classe inteira (ex.: "Opcionais"), com confirmação em 2 toques.
function AcoesGrupo({ itens, onAlterado }: { itens: Item[]; onAlterado: () => void }) {
  const [confirmar, setConfirmar] = useState<boolean | null>(null) // valor de incluido a aplicar
  const [ocupado, setOcupado] = useState(false)
  const [erro, setErro] = useState<string | null>(null)
  const dentro = itens.filter((i) => i.incluido).length
  const fora = itens.length - dentro

  async function aplicar(incluido: boolean) {
    setOcupado(true)
    setErro(null)
    const ids = itens.filter((i) => i.incluido !== incluido && i.tipo_custo !== 'aquisicao_lote').map((i) => i.id)
    const { error } = await supabase.from('orcamento_item').update({ incluido }).in('id', ids)
    setOcupado(false)
    setConfirmar(null)
    if (error) return setErro(mensagemErro(error))
    onAlterado()
  }

  if (confirmar !== null)
    return (
      <div className="grupo-acoes confirma">
        <span>{confirmar ? `Incluir ${fora} item(ns) no total?` : `Tirar ${dentro} item(ns) do total?`}</span>
        <button className="btn sec" onClick={() => setConfirmar(null)}>Não</button>
        <button className="btn" disabled={ocupado} onClick={() => aplicar(confirmar)}>{ocupado ? '…' : 'Sim'}</button>
      </div>
    )
  return (
    <div className="grupo-acoes">
      {fora > 0 && <button className="link" onClick={() => setConfirmar(true)}>Incluir todos ({fora})</button>}
      {dentro > 0 && <button className="link" onClick={() => setConfirmar(false)}>Tirar todos do total ({dentro})</button>}
      {erro && <p className="msg erro">{erro}</p>}
    </div>
  )
}

export default function Orcamento() {
  const { membro } = useAuth()
  // admin e colaborador(a) editam o orçamento (migration 011); o banco confere via RLS
  const podeEditar = !!membro
  const [filtro, setFiltro] = useState<Filtro>('incluidos')
  const [busca, setBusca] = useState('')
  const { dados, erro, carregando, recarregar } = useDados(
    () => supabase.from('v_item_resumo').select('*').eq('obra_id', membro!.obra_id).order('numero_origem').returns<Item[]>(),
    [membro?.obra_id],
  )

  const contagem = useMemo(() => {
    const d = dados ?? []
    return {
      incluidos: d.filter((i) => i.incluido).length,
      opcionais: d.filter((i) => !i.incluido).length,
      revisar: d.filter((i) => i.revisar).length,
      todos: d.length,
    }
  }, [dados])

  const grupos = useMemo(() => {
    const termo = busca.trim().toLowerCase()
    const filtrados = (dados ?? []).filter((i) => {
      if (filtro === 'incluidos' && !i.incluido) return false
      if (filtro === 'opcionais' && i.incluido) return false
      if (filtro === 'revisar' && !i.revisar) return false
      if (termo && !`${i.descricao} ${i.grupo ?? ''} ${i.numero_origem ?? ''}`.toLowerCase().includes(termo)) return false
      return true
    })
    const mapa = new Map<string, Item[]>()
    for (const i of filtrados) {
      const k = i.classe ?? 'Sem classe'
      mapa.set(k, [...(mapa.get(k) ?? []), i])
    }
    return [...mapa.entries()].map(([classe, itens]) => ({ classe, itens, total: itens.reduce((s, i) => s + valorItem(i), 0) }))
  }, [dados, filtro, busca])

  const totalFiltro = grupos.reduce((s, g) => s + g.total, 0)

  return (
    <div className="pagina">
      <Topo titulo="Orçamento" sub={dados ? `${contagem.todos} itens · soma do filtro ${brl(totalFiltro)}` : undefined} />
      <div className="filtros">
        <input type="search" placeholder="Buscar item, grupo ou #" value={busca} onChange={(e) => setBusca(e.target.value)} />
        <div className="segmentos" role="tablist">
          {(
            [
              ['incluidos', 'No total'],
              ['opcionais', 'Opcionais'],
              ['revisar', 'Revisar'],
              ['todos', 'Todos'],
            ] as [Filtro, string][]
          ).map(([f, rot]) => (
            <button key={f} role="tab" aria-selected={filtro === f} className={filtro === f ? 'ativo' : ''} onClick={() => setFiltro(f)}>
              {rot} <small>{contagem[f]}</small>
            </button>
          ))}
        </div>
      </div>
      {podeEditar && dados && <p className="nota pad">Toque num item para tirar do total, incluir ou editar valores.</p>}
      {!dados ? (
        <Estado carregando={carregando} erro={erro} onTentar={recarregar} />
      ) : grupos.length === 0 ? (
        <Vazio>Nenhum item com esse filtro.</Vazio>
      ) : (
        grupos.map((g) => (
          <section key={g.classe} className="card grupo">
            <header className="card-h">
              <h2>{g.classe}</h2>
              <span className="num sub">{brl(g.total)}</span>
            </header>
            {podeEditar && g.classe !== 'Terreno e impostos' && <AcoesGrupo itens={g.itens} onAlterado={recarregar} />}
            <ul className="lista-itens">
              {g.itens.map((i) => (
                <ItemLinha key={i.id} i={i} onAlterado={recarregar} />
              ))}
            </ul>
          </section>
        ))
      )}
      {filtro === 'incluidos' && dados && <p className="nota pad">A contingência de 10% não aparece aqui: ela está no Painel.</p>}
    </div>
  )
}
