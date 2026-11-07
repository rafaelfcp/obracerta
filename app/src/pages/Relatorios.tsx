import { useEffect, useRef, useState, type KeyboardEvent } from 'react'
import { Link, Navigate, useNavigate, useParams } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useDados } from '../lib/useDados'
import { useAuth } from '../lib/auth'
import {
  CATALOGO, EMAIL_RE, MAX_DEST, enviarRelatorio, gerarPrevia, listarEnvios, relatorioPorSlug, tituloDoTipo,
  type Previa,
} from '../lib/relatorios'
import { Card, Chip, Estado, Vazio } from '../components/ui'
import { Topo } from '../components/Layout'

const quando = (iso: string) =>
  new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })

// ---------------------------------------------------------------------------
// /relatorios — catálogo + últimos envios
// ---------------------------------------------------------------------------
export default function Relatorios() {
  const { membro } = useAuth()
  const envios = useDados(() => listarEnvios(membro!.obra_id), [membro?.obra_id])
  const nomes = useDados(
    () =>
      supabase
        .from('obra_membro')
        .select('usuario_id, nome_exibicao')
        .eq('obra_id', membro!.obra_id)
        .returns<{ usuario_id: string; nome_exibicao: string | null }[]>(),
    [membro?.obra_id],
  )
  const nomeDe = (id: string) => nomes.dados?.find((m) => m.usuario_id === id)?.nome_exibicao ?? '—'

  return (
    <div className="pagina">
      <Topo titulo="Relatórios" sub="Gere, confira e envie por e-mail" />

      <ul className="lista-cards">
        {CATALOGO.map((r) => {
          const corpo = (
            <>
              <div className="rel-info">
                <b>{r.titulo}</b>
                <span>{r.descricao}</span>
              </div>
              {r.disponivel ? <span className="seta">›</span> : <Chip>Em breve</Chip>}
            </>
          )
          return (
            <li key={r.tipo}>
              {r.disponivel ? (
                <Link to={`/relatorios/${r.slug}`} className="card rel-item">{corpo}</Link>
              ) : (
                <div className="card rel-item off" aria-disabled="true">{corpo}</div>
              )}
            </li>
          )
        })}
      </ul>

      <Card titulo="Últimos envios" extra={<button className="link" onClick={envios.recarregar}>Atualizar</button>}>
        {!envios.dados ? (
          <Estado carregando={envios.carregando} erro={envios.erro} onTentar={envios.recarregar} />
        ) : envios.dados.length === 0 ? (
          <Vazio>Nenhum relatório enviado ainda.</Vazio>
        ) : (
          <ul className="lista-simples envios">
            {envios.dados.map((e) => (
              <li key={e.id}>
                <div className="ls-top">
                  <b>{tituloDoTipo(e.tipo)}</b>
                  <Chip tom={e.status === 'enviado' ? 'ok' : 'bad'}>{e.status === 'enviado' ? 'Enviado' : 'Falhou'}</Chip>
                </div>
                <span className="sub">
                  {quando(e.criado_em)} · {nomeDe(e.criado_por)} → {e.destinatarios.join(', ')}
                </span>
                {e.erro && <span className="sub neg">{e.erro}</span>}
              </li>
            ))}
          </ul>
        )}
      </Card>
    </div>
  )
}

// ---------------------------------------------------------------------------
// /relatorios/:slug — pré-visualização + envio por e-mail
// ---------------------------------------------------------------------------
export function RelatorioDetalhe() {
  const { slug } = useParams()
  const nav = useNavigate()
  const { membro, session } = useAuth()
  const def = relatorioPorSlug(slug)

  const [previa, setPrevia] = useState<Previa | null>(null)
  const [gerando, setGerando] = useState(false)
  const [erroPrevia, setErroPrevia] = useState<string | null>(null)

  const [dest, setDest] = useState<string[]>([])
  const [rascunho, setRascunho] = useState('')
  const [assunto, setAssunto] = useState('')
  const [mensagem, setMensagem] = useState('')
  const [msg, setMsg] = useState<{ ok: boolean; txt: string } | null>(null)
  const [confirmando, setConfirmando] = useState(false)
  const [enviando, setEnviando] = useState(false)
  const iframe = useRef<HTMLIFrameElement>(null)

  async function gerar() {
    if (!def?.disponivel || !membro) return
    setGerando(true)
    setErroPrevia(null)
    try {
      const p = await gerarPrevia(membro.obra_id, def.tipo, mensagem)
      setPrevia(p)
      setAssunto((a) => a || p.assunto)
    } catch (e) {
      setErroPrevia((e as Error).message)
    } finally {
      setGerando(false)
    }
  }

  useEffect(() => {
    gerar()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [slug, membro?.obra_id])

  if (!def || !def.disponivel) return <Navigate to="/relatorios" replace />

  const meuEmail = session?.user.email?.toLowerCase() ?? null

  function adicionar(texto: string) {
    const novos = texto.split(/[,;\s]+/).map((s) => s.trim().toLowerCase()).filter(Boolean)
    if (!novos.length) return
    const ruins = novos.filter((n) => !EMAIL_RE.test(n))
    if (ruins.length) return setMsg({ ok: false, txt: `E-mail inválido: ${ruins.join(', ')}` })
    setMsg(null)
    setDest((d) => [...new Set([...d, ...novos])].slice(0, MAX_DEST))
    setRascunho('')
  }
  function teclas(e: KeyboardEvent<HTMLInputElement>) {
    if (['Enter', ',', ';'].includes(e.key) && rascunho.trim()) {
      e.preventDefault()
      adicionar(rascunho)
    }
    if (e.key === 'Backspace' && !rascunho) setDest((d) => d.slice(0, -1))
  }

  async function enviar() {
    setEnviando(true)
    try {
      const r = await enviarRelatorio(membro!.obra_id, def!.tipo, dest, assunto, mensagem)
      setMsg({ ok: true, txt: `Enviado para ${r.destinatarios.join(', ')}.${r.aviso_log ? ` (${r.aviso_log})` : ''}` })
      setDest([])
    } catch (e) {
      setMsg({ ok: false, txt: (e as Error).message })
    } finally {
      setEnviando(false)
      setConfirmando(false)
    }
  }

  const pendente = rascunho.trim() && EMAIL_RE.test(rascunho.trim())
  const podeEnviar = !!previa && (dest.length > 0 || !!pendente) && !!assunto.trim() && !enviando

  return (
    <div className="pagina">
      <Topo titulo={def.titulo} sub="Pré-visualize e envie por e-mail" voltar={() => nav('/relatorios')} />

      <Card titulo="Enviar por e-mail">
        <div className="form">
          <div>
            <span className="rotulo">Destinatários ({dest.length}/{MAX_DEST})</span>
            <div className="dest" onClick={() => document.getElementById('rel-dest')?.focus()}>
              {dest.map((d) => (
                <span key={d} className="chip pri dest-chip">
                  {d}
                  <button type="button" aria-label={`Remover ${d}`} onClick={() => setDest((x) => x.filter((y) => y !== d))}>×</button>
                </span>
              ))}
              <input
                id="rel-dest" type="email" inputMode="email" autoComplete="email" enterKeyHint="done"
                placeholder={dest.length ? '' : 'nome@exemplo.com'}
                value={rascunho}
                onChange={(e) => setRascunho(e.target.value)}
                onKeyDown={teclas}
                onBlur={() => rascunho.trim() && adicionar(rascunho)}
                disabled={dest.length >= MAX_DEST}
              />
            </div>
            {meuEmail && !dest.includes(meuEmail) && (
              <button type="button" className="link" onClick={() => adicionar(meuEmail)}>+ Enviar para mim</button>
            )}
          </div>
          <label>
            Assunto
            <input id="rel-assunto" value={assunto} maxLength={200} onChange={(e) => setAssunto(e.target.value)} />
          </label>
          <label>
            Mensagem (opcional, aparece no topo do e-mail)
            <textarea id="rel-msg" rows={3} maxLength={2000} value={mensagem} onChange={(e) => setMensagem(e.target.value)}
              onBlur={() => previa && gerar()} />
          </label>
          {msg && <p className={`msg ${msg.ok ? 'ok' : 'erro'}`}>{msg.txt}</p>}
          <button className="btn largo" disabled={!podeEnviar}
            onClick={() => { if (pendente) adicionar(rascunho); setConfirmando(true) }}>
            Revisar e enviar
          </button>
        </div>
      </Card>

      <Card
        titulo="Pré-visualização"
        extra={
          <div className="rel-acoes">
            <button className="link" onClick={gerar} disabled={gerando}>{gerando ? 'Gerando…' : 'Atualizar'}</button>
            {previa && <button className="link" onClick={() => iframe.current?.contentWindow?.print()}>Imprimir / PDF</button>}
          </div>
        }
      >
        {previa && (
          <p className="nota">
            {previa.dados.totais.etapas} etapas · gerado em {quando(previa.dados.gerado_em)} · o e-mail vai igual a este, com o CSV anexo
          </p>
        )}
        {previa ? (
          // sem allow-scripts: o HTML do e-mail não executa nada; allow-same-origin só para imprimir
          <iframe ref={iframe} className="rel-previa" title="Pré-visualização do e-mail" srcDoc={previa.html} sandbox="allow-same-origin allow-modals" />
        ) : (
          <Estado carregando={gerando} erro={erroPrevia} onTentar={gerar} />
        )}
      </Card>

      {confirmando && (
        <div className="sheet-fundo" onClick={() => !enviando && setConfirmando(false)}>
          <div className="sheet" role="dialog" aria-modal="true" aria-labelledby="rel-conf" onClick={(e) => e.stopPropagation()}>
            <div className="sheet-alca" />
            <div className="sheet-h"><h2 id="rel-conf">Enviar relatório?</h2></div>
            <div className="form">
              <p className="nota">{def.titulo} vai para:</p>
              <ul className="rel-conf-lista">{dest.map((d) => <li key={d}>{d}</li>)}</ul>
              <p className="sub">Assunto: {assunto}</p>
              <div className="sheet-acoes">
                <button className="btn sec" onClick={() => setConfirmando(false)} disabled={enviando}>Cancelar</button>
                <button className="btn" onClick={enviar} disabled={enviando}>{enviando ? 'Enviando…' : 'Enviar agora'}</button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
