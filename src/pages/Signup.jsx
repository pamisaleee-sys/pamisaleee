import { useState } from 'react'
import { Link, Navigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useAuth } from '../contexts/AuthContext'

export default function Signup() {
  const { session } = useAuth()
  const [email, setEmail] = useState('')
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [err, setErr] = useState('')
  const [msg, setMsg] = useState('')
  const [loading, setLoading] = useState(false)

  if (session) return <Navigate to="/" replace />

  const submit = async (e) => {
    e.preventDefault()
    setErr(''); setMsg(''); setLoading(true)
    const { error } = await supabase.auth.signUp({
      email, password,
      options: { data: { username } }
    })
    setLoading(false)
    if (error) setErr(error.message)
    else setMsg('Cuenta creada. Revisá tu email para confirmar.')
  }

  return (
    <div className="container">
      <h1>Crear cuenta</h1>
      <p className="muted">Elegí un nombre de usuario único</p>
      <form className="stack" onSubmit={submit} style={{ marginTop: 24 }}>
        <div className="stack" style={{ gap: 4 }}>
          <span className="label">Usuario</span>
          <input required minLength={3} maxLength={20} value={username} onChange={e => setUsername(e.target.value)} />
        </div>
        <div className="stack" style={{ gap: 4 }}>
          <span className="label">Email</span>
          <input type="email" required value={email} onChange={e => setEmail(e.target.value)} />
        </div>
        <div className="stack" style={{ gap: 4 }}>
          <span className="label">Contraseña</span>
          <input type="password" required minLength={6} value={password} onChange={e => setPassword(e.target.value)} />
        </div>
        {err && <div className="error">{err}</div>}
        {msg && <div className="card" style={{ color: 'var(--accent)' }}>{msg}</div>}
        <button className="primary" type="submit" disabled={loading}>
          {loading ? 'Creando...' : 'Crear cuenta'}
        </button>
      </form>
      <p className="muted" style={{ marginTop: 16, textAlign: 'center' }}>
        ¿Ya tenés cuenta? <Link to="/login">Entrar</Link>
      </p>
    </div>
  )
}
