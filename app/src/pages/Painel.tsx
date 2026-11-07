import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useDados } from '../lib/useDados'
import { useAuth } from '../lib/auth'
import { brl, brlK, data, pct } from '../lib/format'
import type { Etapa, Painel as TPainel } from '../lib/tipos'
import { Barra, Card, Estado, Linha, Sinal } from '../components/ui'

const STATUS: Record<string, string> = {
  planejamento: 'Planejamento',
  em_andamento: 'Em andamento',
  pausada: 'Pausada',
  concluida: 'Concluída',
}

export default function Painel() {
  const { membro } = useAuth()
  const painel = useDados(
    () => supabase.from('v_obra_painel').select('*').eq('obra_id', membro!.obra_id).maybeSingle<TPainel>(),
    [membro?.obra_id],
  )
  const etapas = useDados(
    () =>
      supabase
        .from('v_etapa_painel')
        .select('id, ordem, nome, orcado, pago, pct_financeiro, semaforo')
        .eq('obra_id', membro!.obra_id)
        .order('orcado', { ascending: false })
        .limit(5)
        .returns<Etapa[]>(),
    [membro?.obra_id],
  )

  const p = painel.dados
  if (!p) return <div className="pagina"><Estado carregando={painel.carregando} erro={painel.erro} onTentar={painel.recarregar} /></div>

  const disponivelNeg = (p.saldo_disponivel ?? 0) < 0
  const nomeCurto = membro?.nome_exibicao ? `Olá, ${membro.nome_exibicao}` : 'Olá'

  return (
    <div className="pagina">
      <header className="hero">
        <p className="hero-ola">{nomeCurto}</p>
        <h1>{p.nome}</h1>
        <div className="hero-meta">
          <span className="chip claro">{STATUS[p.status_geral] ?? p.status_geral}</span>
          <Sinal s={p.semaforo} />
        </div>
        <div className="hero-total">
          <span>Orçado total</span>
          <strong className="num">{brl(p.orcado_total)}</strong>
        </div>
        <Barra valor={p.pct_financeiro_pago} rotulo={`${pct(p.pct_financeiro_pago)} pago`} tom="ok" />
        <div className="hero-mini">
          <div><span>Pago</span><b className="num">{brlK(p.pago)}</b></div>
          <div><span>A pagar</span><b className="num">{brlK(p.a_pagar)}</b></div>
          <div><span>Restante</span><b className="num">{brlK(p.valor_restante)}</b></div>
        </div>
      </header>

      {(p.estouros > 0 || p.parcelas_atrasadas > 0 || p.etapas_atrasadas > 0) && (
        <Link to="/alertas" className="faixa bad">
          {p.estouros > 0 && <span>{p.estouros} estouro(s)</span>}
          {p.parcelas_atrasadas > 0 && <span>{p.parcelas_atrasadas} parcela(s) atrasada(s)</span>}
          {p.etapas_atrasadas > 0 && <span>{p.etapas_atrasadas} etapa(s) atrasada(s)</span>}
          <span className="seta">›</span>
        </Link>
      )}

      <Card titulo="Composição do orçamento">
        <Linha rotulo="Lote e custas" valor={brl(p.orcado_lote)} />
        <Linha rotulo="Obra (itens incluídos)" valor={brl(p.orcado_obra)} />
        <Linha rotulo={`Contingência`} valor={brl(p.contingencia)} />
        <Linha rotulo="Total" valor={brl(p.orcado_total)} forte />
        <Linha rotulo="Custo projetado" valor={brl(p.custo_projetado)} tom={p.custo_projetado > p.orcado_total ? 'neg' : undefined} />
      </Card>

      <Card titulo="Reserva">
        <Linha rotulo="Saldo no CDB" valor={brl(p.saldo_reserva)} />
        <Linha rotulo="Reserva de segurança (não usar)" valor={`− ${brl(p.reserva_seguranca)}`} tom="muted" />
        <Linha rotulo="Disponível para a obra" valor={brl(p.saldo_disponivel)} forte tom={disponivelNeg ? 'neg' : 'pos'} />
        {disponivelNeg && (
          <p className="nota">A segurança está dentro do CDB, então hoje falta {brl(-(p.saldo_disponivel ?? 0))} para preservá-la inteira.</p>
        )}
        <Linha rotulo="FGTS previsto" valor={brl(p.fgts_previsto)} />
      </Card>

      <Card titulo="Financiamento Caixa" extra={p.simulacao_ativa ? <span className="sub">{p.simulacao_ativa}</span> : null}>
        <Linha rotulo="Valor financiado" valor={brl(p.financiamento_ativo)} />
        <Linha rotulo="Liberado até agora" valor={brl(p.caixa_liberado)} />
        <Linha rotulo="Juros de obra previstos" valor={brl(p.juros_obra_previstos)} />
        <Linha rotulo="Dinheiro próprio ainda necessário" valor={brl(p.necessidade_complementar)} forte tom="neg" />
      </Card>

      <Card titulo="Maiores etapas" extra={<Link to="/etapas" className="mini-link">ver todas ›</Link>}>
        {etapas.dados ? (
          <ul className="lista-simples">
            {etapas.dados.map((e) => (
              <li key={e.id}>
                <Link to={`/etapas/${e.id}`}>
                  <div className="ls-top">
                    <span>{e.ordem}. {e.nome}</span>
                    <span className="num">{brlK(e.orcado)}</span>
                  </div>
                  <Barra valor={e.pct_financeiro} tom={e.semaforo === 'vermelho' ? 'bad' : e.semaforo === 'amarelo' ? 'warn' : 'pri'} />
                </Link>
              </li>
            ))}
          </ul>
        ) : (
          <Estado carregando={etapas.carregando} erro={etapas.erro} onTentar={etapas.recarregar} />
        )}
      </Card>

      <Card titulo="Prazos">
        <Linha rotulo="Início previsto" valor={data(p.inicio_previsto)} />
        <Linha rotulo="Conclusão prevista" valor={data(p.conclusao_prevista)} />
        <Linha rotulo="Avanço físico" valor={pct(p.pct_fisico)} />
      </Card>
    </div>
  )
}
