import { Link, useNavigate, useParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useDados } from '../lib/useDados'
import { useAuth } from '../lib/auth'
import { brl, brlK, data, pct } from '../lib/format'
import type { Etapa, Item } from '../lib/tipos'
import { Barra, Card, Chip, Estado, Linha, Sinal, Vazio } from '../components/ui'
import { Topo } from '../components/Layout'
import { ItemLinha } from './Orcamento'

const STATUS: Record<string, string> = {
  planejada: 'Planejada',
  em_andamento: 'Em andamento',
  pausada: 'Pausada',
  concluida: 'Concluída',
}

const tomSemaforo = (s: string) => (s === 'vermelho' ? 'bad' : s === 'amarelo' ? 'warn' : 'pri') as 'bad' | 'warn' | 'pri'

export default function Etapas() {
  const { membro } = useAuth()
  const { dados, erro, carregando, recarregar } = useDados(
    () => supabase.from('v_etapa_painel').select('*').eq('obra_id', membro!.obra_id).order('ordem').returns<Etapa[]>(),
    [membro?.obra_id],
  )
  const total = dados?.reduce((s, e) => s + Number(e.orcado), 0) ?? 0

  return (
    <div className="pagina">
      <Topo titulo="Etapas" sub={dados ? `${dados.length} etapas · ${brl(total)} com o indireto rateado` : undefined} />
      {!dados ? (
        <Estado carregando={carregando} erro={erro} onTentar={recarregar} />
      ) : (
        <ul className="lista-cards">
          {dados.map((e) => (
            <li key={e.id}>
              <Link to={`/etapas/${e.id}`} className="card etapa-card">
                <div className="ec-top">
                  <span className="ec-ordem">{e.ordem}</span>
                  <div className="ec-nome">
                    <b>{e.nome}</b>
                    <span>{STATUS[e.status] ?? e.status}{e.atrasada ? ' · atrasada' : ''}</span>
                  </div>
                  <Sinal s={e.semaforo} curto />
                </div>
                <div className="ec-valores">
                  <div><span>Orçado</span><b className="num">{brlK(e.orcado)}</b></div>
                  <div><span>Pago</span><b className="num">{brlK(e.pago)}</b></div>
                  <div><span>Físico</span><b className="num">{pct(e.pct_fisico)}</b></div>
                </div>
                <Barra valor={e.pct_financeiro} tom={tomSemaforo(e.semaforo)} />
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

export function EtapaDetalhe() {
  const { id } = useParams()
  const nav = useNavigate()
  const etapa = useDados(() => supabase.from('v_etapa_painel').select('*').eq('id', id!).maybeSingle<Etapa>(), [id])
  const itens = useDados(
    () => supabase.from('v_item_resumo').select('*').eq('etapa_id', id!).order('numero_origem').returns<Item[]>(),
    [id],
  )
  const e = etapa.dados

  return (
    <div className="pagina">
      <Topo titulo={e ? `${e.ordem}. ${e.nome}` : 'Etapa'} sub={e ? STATUS[e.status] ?? e.status : undefined} voltar={() => nav(-1)} />
      {!e ? (
        <Estado carregando={etapa.carregando} erro={etapa.erro} onTentar={etapa.recarregar} />
      ) : (
        <>
          <Card titulo="Valores" extra={<Sinal s={e.semaforo} />}>
            <Linha rotulo="Orçado direto (itens)" valor={brl(e.orcado_direto)} />
            {e.recebe_indireto && (
              <Linha rotulo={`Indireto rateado (${pct(e.fator_indireto)} da base)`} valor={brl(Number(e.orcado) - Number(e.orcado_direto))} tom="muted" />
            )}
            <Linha rotulo="Orçado da etapa" valor={brl(e.orcado)} forte />
            <Linha rotulo="Contratado" valor={brl(e.contratado)} />
            <Linha rotulo="Pago" valor={brl(e.pago)} />
            <Linha rotulo="A pagar" valor={brl(e.a_pagar)} />
            <Linha rotulo="Projetado" valor={brl(e.projetado)} tom={Number(e.desvio) > 0 ? 'neg' : undefined} />
            <Linha rotulo="Desvio" valor={`${brl(e.desvio)} (${pct(e.desvio_pct)})`} tom={Number(e.desvio) > 0 ? 'neg' : 'muted'} />
          </Card>
          <Card titulo="Prazo">
            <Linha rotulo="Início previsto" valor={data(e.inicio_previsto)} />
            <Linha rotulo="Fim previsto" valor={data(e.fim_previsto)} />
            <div className="dupla-barra">
              <span>Físico</span>
              <Barra valor={e.pct_fisico} rotulo="" />
              <span>Financeiro</span>
              <Barra valor={e.pct_financeiro} rotulo="" tom={tomSemaforo(e.semaforo)} />
            </div>
          </Card>
          <Card titulo="Itens do orçamento" extra={itens.dados ? <Chip>{itens.dados.length}</Chip> : null}>
            {itens.dados ? (
              itens.dados.length ? (
                <ul className="lista-itens">
                  {itens.dados.map((i) => (
                    <ItemLinha key={i.id} i={i} />
                  ))}
                </ul>
              ) : (
                <Vazio>Nenhum item direto nesta etapa.</Vazio>
              )
            ) : (
              <Estado carregando={itens.carregando} erro={itens.erro} onTentar={itens.recarregar} />
            )}
          </Card>
        </>
      )}
    </div>
  )
}
