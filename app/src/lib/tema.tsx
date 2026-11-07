import { useEffect, useState } from 'react'

export type Tema = 'auto' | 'claro' | 'escuro'
const CHAVE = 'obracerta.tema'
const escuroDoSistema = () => window.matchMedia('(prefers-color-scheme: dark)').matches

export function lerTema(): Tema {
  try {
    const t = localStorage.getItem(CHAVE)
    if (t === 'claro' || t === 'escuro') return t
  } catch {
    /* navegador sem localStorage: segue o sistema */
  }
  return 'auto'
}

// Aplica no <html>: data-theme força claro/escuro; sem atributo, o CSS segue o sistema.
export function aplicarTema(t: Tema) {
  const html = document.documentElement
  if (t === 'auto') html.removeAttribute('data-theme')
  else html.setAttribute('data-theme', t === 'escuro' ? 'dark' : 'light')
  const escuro = t === 'escuro' || (t === 'auto' && escuroDoSistema())
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', escuro ? '#121614' : '#1f3a2e')
}

export function useTema() {
  const [tema, setTemaState] = useState<Tema>(lerTema)
  const [escuro, setEscuro] = useState(() => tema === 'escuro' || (tema === 'auto' && escuroDoSistema()))

  useEffect(() => {
    aplicarTema(tema)
    const mq = window.matchMedia('(prefers-color-scheme: dark)')
    const atualizar = () => setEscuro(tema === 'escuro' || (tema === 'auto' && mq.matches))
    atualizar()
    mq.addEventListener('change', atualizar)
    // outras telas abertas (ex.: Conta e Painel) ficam sincronizadas
    const sync = () => setTemaState(lerTema())
    window.addEventListener('obracerta-tema', sync)
    return () => {
      mq.removeEventListener('change', atualizar)
      window.removeEventListener('obracerta-tema', sync)
    }
  }, [tema])

  function setTema(t: Tema) {
    try {
      if (t === 'auto') localStorage.removeItem(CHAVE)
      else localStorage.setItem(CHAVE, t)
    } catch {
      /* sem persistência: vale só nesta sessão */
    }
    setTemaState(t)
    aplicarTema(t)
    window.dispatchEvent(new Event('obracerta-tema'))
  }

  return { tema, escuro, setTema }
}

export function BotaoTema() {
  const { escuro, setTema } = useTema()
  return (
    <button className="tema-btn" onClick={() => setTema(escuro ? 'claro' : 'escuro')} aria-label={escuro ? 'Mudar para modo claro' : 'Mudar para modo escuro'} title={escuro ? 'Modo claro' : 'Modo escuro'}>
      <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
        {escuro ? (
          <>
            <circle cx="12" cy="12" r="4" />
            <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
          </>
        ) : (
          <path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z" />
        )}
      </svg>
    </button>
  )
}
