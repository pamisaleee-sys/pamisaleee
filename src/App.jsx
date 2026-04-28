import { Routes, Route, Navigate, NavLink, useLocation } from 'react-router-dom'
import { useAuth } from './contexts/AuthContext'
import Login from './pages/Login'
import Signup from './pages/Signup'
import Home from './pages/Home'
import Tournament from './pages/Tournament'
import Bets from './pages/Bets'
import Leaderboard from './pages/Leaderboard'
import Admin from './pages/Admin'

function Protected({ children }) {
  const { session, loading } = useAuth()
  if (loading) return <div className="container"><p className="muted">Cargando...</p></div>
  if (!session) return <Navigate to="/login" replace />
  return children
}

function TabBar() {
  const loc = useLocation()
  if (loc.pathname.startsWith('/login') || loc.pathname.startsWith('/signup')) return null
  const tabs = [
    { to: '/', label: 'Torneos' },
    { to: '/leaderboard', label: 'Tabla' },
    { to: '/bets', label: 'Apuestas' }
  ]
  return (
    <nav className="tabbar">
      {tabs.map(t => (
        <NavLink
          key={t.to}
          to={t.to}
          end={t.to === '/'}
          className={({ isActive }) => isActive ? 'active' : ''}
        >{t.label}</NavLink>
      ))}
    </nav>
  )
}

export default function App() {
  return (
    <>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/signup" element={<Signup />} />
        <Route path="/" element={<Protected><Home /></Protected>} />
        <Route path="/t/:id" element={<Protected><Tournament /></Protected>} />
        <Route path="/t/:id/bets" element={<Protected><Bets /></Protected>} />
        <Route path="/t/:id/admin" element={<Protected><Admin /></Protected>} />
        <Route path="/leaderboard" element={<Protected><Leaderboard /></Protected>} />
        <Route path="/bets" element={<Protected><Bets /></Protected>} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
      <TabBar />
    </>
  )
}
