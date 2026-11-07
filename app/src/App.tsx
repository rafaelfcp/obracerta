import { lazy, Suspense } from 'react'
import { HashRouter, Navigate, Route, Routes } from 'react-router-dom'
import { AuthProvider, useAuth } from './lib/auth'
import Layout from './components/Layout'
import Login from './pages/Login'
import SemObra from './pages/SemObra'
import Painel from './pages/Painel'
import Etapas, { EtapaDetalhe } from './pages/Etapas'
import Orcamento from './pages/Orcamento'
import Alertas from './pages/Alertas'
import Conta, { TrocarSenha } from './pages/Conta'
import Relatorios, { RelatorioDetalhe } from './pages/Relatorios'

// pdf.js é pesado: só baixa quando abrir a aba Planta
const Planta = lazy(() => import('./pages/Planta'))

function Portao() {
  const { session, membro, carregando, semObra, recuperando, fimRecuperacao } = useAuth()

  if (carregando)
    return (
      <div className="splash">
        <img src="./icons/icon.svg" alt="" width={64} height={64} />
      </div>
    )
  if (!session) return <Login />
  if (recuperando)
    return (
      <div className="login">
        <div className="card login-form">
          <h2>Crie a senha nova</h2>
          <TrocarSenha aoConcluir={fimRecuperacao} />
        </div>
      </div>
    )
  if (semObra || !membro) return <SemObra />

  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Painel />} />
        <Route path="etapas" element={<Etapas />} />
        <Route path="etapas/:id" element={<EtapaDetalhe />} />
        <Route path="orcamento" element={<Orcamento />} />
        <Route path="planta" element={<Suspense fallback={<div className="pagina"><div className="skeleton alto" /></div>}><Planta /></Suspense>} />
        <Route path="alertas" element={<Alertas />} />
        <Route path="relatorios" element={<Relatorios />} />
        <Route path="relatorios/:slug" element={<RelatorioDetalhe />} />
        <Route path="conta" element={<Conta />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  )
}

export default function App() {
  return (
    <AuthProvider>
      <HashRouter>
        <Portao />
      </HashRouter>
    </AuthProvider>
  )
}
