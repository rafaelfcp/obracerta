import { useEffect, useRef, useState, type ChangeEvent } from 'react'
import * as pdfjs from 'pdfjs-dist'
import workerUrl from 'pdfjs-dist/build/pdf.worker.min.mjs?url'
import { supabase, mensagemErro } from '../lib/supabase'
import { useDados } from '../lib/useDados'
import { useAuth } from '../lib/auth'
import { data } from '../lib/format'
import { Card, Estado, Vazio } from '../components/ui'
import { Topo } from '../components/Layout'

pdfjs.GlobalWorkerOptions.workerSrc = workerUrl

const BUCKET = 'obra-anexos'
const TIPO = 'projeto_arquitetonico'

interface Anexo {
  id: string
  titulo: string
  storage_path: string
  mime: string | null
  tamanho_bytes: number | null
  criado_em: string
}

// Desenha cada página do PDF num canvas, na largura da tela x zoom (o contêiner rola para os lados).
function VisorPdf({ url }: { url: string }) {
  const caixa = useRef<HTMLDivElement>(null)
  const [zoom, setZoom] = useState(1)
  const [paginas, setPaginas] = useState(0)
  const [erro, setErro] = useState<string | null>(null)
  const doc = useRef<pdfjs.PDFDocumentProxy | null>(null)

  useEffect(() => {
    let cancelado = false
    setErro(null)
    pdfjs
      .getDocument(url)
      .promise.then((d) => {
        if (cancelado) return
        doc.current = d
        setPaginas(d.numPages)
      })
      .catch((e) => setErro(mensagemErro(e)))
    return () => {
      cancelado = true
      doc.current?.destroy()
    }
  }, [url])

  useEffect(() => {
    const d = doc.current
    const el = caixa.current
    if (!d || !el || !paginas) return
    let cancelado = false
    ;(async () => {
      const largura = el.clientWidth * zoom
      const dpr = Math.min(window.devicePixelRatio || 1, 3)
      const canvases = [...el.querySelectorAll('canvas')]
      for (let n = 1; n <= paginas && !cancelado; n++) {
        const pg = await d.getPage(n)
        const base = pg.getViewport({ scale: 1 })
        const vp = pg.getViewport({ scale: (largura / base.width) * dpr })
        const cv = canvases[n - 1]
        cv.width = vp.width
        cv.height = vp.height
        cv.style.width = `${largura}px`
        await pg.render({ canvasContext: cv.getContext('2d')!, viewport: vp }).promise
      }
    })()
    return () => {
      cancelado = true
    }
  }, [paginas, zoom])

  if (erro) return <p className="msg erro">Não consegui abrir o PDF: {erro}</p>
  return (
    <div className="visor">
      <div className="visor-zoom">
        <button className="btn sec" onClick={() => setZoom((z) => Math.max(1, z - 0.5))} disabled={zoom <= 1} aria-label="Diminuir zoom">−</button>
        <span className="num">{Math.round(zoom * 100)}%</span>
        <button className="btn sec" onClick={() => setZoom((z) => Math.min(4, z + 0.5))} disabled={zoom >= 4} aria-label="Aumentar zoom">+</button>
        <a className="btn sec" href={url} target="_blank" rel="noreferrer">Abrir PDF</a>
      </div>
      <div className="visor-paginas" ref={caixa}>
        {!paginas && <div className="skeleton alto" />}
        {Array.from({ length: paginas }, (_, k) => (
          <canvas key={k} aria-label={`Página ${k + 1}`} />
        ))}
      </div>
    </div>
  )
}

export default function Planta() {
  const { membro } = useAuth()
  const [url, setUrl] = useState<string | null>(null)
  const [selecionado, setSelecionado] = useState<string | null>(null)
  const [enviando, setEnviando] = useState(false)
  const [erroEnvio, setErroEnvio] = useState<string | null>(null)

  const lista = useDados(
    () =>
      supabase
        .from('anexo')
        .select('id, titulo, storage_path, mime, tamanho_bytes, criado_em')
        .eq('obra_id', membro!.obra_id)
        .eq('tipo_documento', TIPO)
        .order('criado_em', { ascending: false })
        .returns<Anexo[]>(),
    [membro?.obra_id],
  )
  const atual = lista.dados?.find((a) => a.id === selecionado) ?? lista.dados?.[0] ?? null

  // link temporário (1 h) para o arquivo no bucket privado
  useEffect(() => {
    setUrl(null)
    if (!atual) return
    supabase.storage
      .from(BUCKET)
      .createSignedUrl(atual.storage_path, 3600)
      .then(({ data: d }) => setUrl(d?.signedUrl ?? null))
  }, [atual?.storage_path])

  async function enviar(ev: ChangeEvent<HTMLInputElement>) {
    const arq = ev.target.files?.[0]
    ev.target.value = ''
    if (!arq) return
    setErroEnvio(null)
    if (arq.type !== 'application/pdf' && !arq.type.startsWith('image/')) return setErroEnvio('Envie um PDF ou uma imagem.')
    setEnviando(true)
    try {
      const nome = arq.name.normalize('NFD').replace(/[^\w.-]+/g, '_')
      const caminho = `${membro!.obra_id}/planta/${Date.now()}-${nome}`
      const up = await supabase.storage.from(BUCKET).upload(caminho, arq, { contentType: arq.type })
      if (up.error) throw up.error
      const { error } = await supabase.from('anexo').insert({
        obra_id: membro!.obra_id,
        tipo_documento: TIPO,
        titulo: arq.name.replace(/\.[^.]+$/, ''),
        storage_path: caminho,
        mime: arq.type,
        tamanho_bytes: arq.size,
        data_documento: new Date().toISOString().slice(0, 10),
      })
      if (error) throw error
      setSelecionado(null)
      await lista.recarregar()
    } catch (e) {
      setErroEnvio(mensagemErro(e))
    } finally {
      setEnviando(false)
    }
  }

  const ehPdf = atual?.mime === 'application/pdf' || atual?.storage_path.toLowerCase().endsWith('.pdf')

  return (
    <div className="pagina">
      <Topo titulo="Planta" sub={atual ? `${atual.titulo} · enviada em ${data(atual.criado_em)}` : undefined} />
      {!lista.dados ? (
        <Estado carregando={lista.carregando} erro={lista.erro} onTentar={lista.recarregar} />
      ) : !atual ? (
        <Card>
          <Vazio>Nenhuma planta enviada ainda.</Vazio>
        </Card>
      ) : !url ? (
        <div className="skeleton alto" />
      ) : ehPdf ? (
        <VisorPdf url={url} />
      ) : (
        <div className="visor-paginas"><img src={url} alt={atual.titulo} className="planta-img" /></div>
      )}

      <Card titulo="Versões">
        {lista.dados && lista.dados.length > 1 && (
          <ul className="versoes">
            {lista.dados.map((a, k) => (
              <li key={a.id}>
                <button className={a.id === atual?.id ? 'ativo' : ''} onClick={() => setSelecionado(a.id)}>
                  <span>{a.titulo}{k === 0 ? ' (vigente)' : ''}</span>
                  <small>{data(a.criado_em)}</small>
                </button>
              </li>
            ))}
          </ul>
        )}
        <label className="btn largo enviar">
          {enviando ? 'Enviando…' : atual ? 'Enviar nova versão (PDF ou imagem)' : 'Enviar a planta (PDF ou imagem)'}
          <input type="file" accept="application/pdf,image/*" onChange={enviar} disabled={enviando} hidden />
        </label>
        {erroEnvio && <p className="msg erro">{erroEnvio}</p>}
        <p className="nota">O arquivo fica no armazenamento privado da obra: só vocês dois acessam. A versão mais recente é a vigente.</p>
      </Card>
    </div>
  )
}
