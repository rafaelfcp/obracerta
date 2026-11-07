import { NavLink, Outlet } from 'react-router-dom'

const Ic = {
  painel: <path d="M4 13h6V4H4zm0 7h6v-5H4zm10 0h6v-9h-6zm0-16v5h6V4z" />,
  etapas: <path d="M4 6h16M4 12h10M4 18h6" strokeWidth="2.2" fill="none" strokeLinecap="round" />,
  orcamento: <path d="M6 3h9l4 4v14H6zM14 3v5h5M9 13h7M9 17h5" fill="none" strokeWidth="1.9" strokeLinejoin="round" strokeLinecap="round" />,
  alertas: <path d="M12 3a6 6 0 0 0-6 6v4l-2 3h16l-2-3V9a6 6 0 0 0-6-6zm-2 16a2 2 0 0 0 4 0" fill="none" strokeWidth="1.9" strokeLinejoin="round" />,
  conta: <path d="M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zm-7 9a7 7 0 0 1 14 0" fill="none" strokeWidth="1.9" strokeLinecap="round" />,
}

const itens: [string, string, keyof typeof Ic][] = [
  ['/', 'Painel', 'painel'],
  ['/etapas', 'Etapas', 'etapas'],
  ['/orcamento', 'Orçamento', 'orcamento'],
  ['/alertas', 'Alertas', 'alertas'],
  ['/conta', 'Conta', 'conta'],
]

export default function Layout() {
  return (
    <div className="app">
      <main className="conteudo">
        <Outlet />
      </main>
      <nav className="tabbar" aria-label="Navegação principal">
        {itens.map(([to, rot, ic]) => (
          <NavLink key={to} to={to} end={to === '/'} className={({ isActive }) => (isActive ? 'ativo' : '')}>
            <svg viewBox="0 0 24 24" aria-hidden="true" stroke="currentColor" fill="currentColor">
              {Ic[ic]}
            </svg>
            <span>{rot}</span>
          </NavLink>
        ))}
      </nav>
    </div>
  )
}

export function Topo({ titulo, sub, voltar }: { titulo: string; sub?: string; voltar?: () => void }) {
  return (
    <header className="topo">
      {voltar && (
        <button className="voltar" onClick={voltar} aria-label="Voltar">
          <svg viewBox="0 0 24 24" width="22" height="22" stroke="currentColor" fill="none" strokeWidth="2.2" strokeLinecap="round">
            <path d="M15 5l-7 7 7 7" />
          </svg>
        </button>
      )}
      <div>
        <h1>{titulo}</h1>
        {sub && <p>{sub}</p>}
      </div>
    </header>
  )
}
