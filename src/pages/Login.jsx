import { useState } from 'react'
import { Link, Navigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useAuth } from '../contexts/AuthContext'

export default function Login() {
  const { session } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [err, setErr] = useState('')
  const [loading, setLoading] = useState(false)

  if (session) return <Navigate to="/" replace />

  const submit = async (e) => {
    e.preventDefault()
    setErr(''); setLoading(true)
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    setLoading(false)
    if (error) setErr(error.message)
  }

  return (
    <div className="container">
      <h1>pamisaleee</h1>
      <p className="muted">Penca + apuestas con amigos</p>
      <form className="stack" onSubmit={submit} style={{ marginTop: 24 }}>
        <div className="stack" style={{ gap: 4 }}>
          <span className="label">Email</span>
          <input type="email" required value={email} onChange={e => setEmail(e.target.value)} />
        </div>
        <div className="stack" style={{ gap: 4 }}>
          <span className="label">Contraseña</span>
          <input type="password" required value={password} onChange={e => setPassword(e.target.value)} />
        </div>
        {err && <div className="error">{err}</div>}
        <button className="primary" type="submit" disabled={loading}>
          {loading ? 'Entrando...' : 'Entrar'}
        </button>
      </form>
      <p className="muted" style={{ marginTop: 16, textAlign: 'center' }}>
        ¿No tenés cuenta? <Link to="/signup">Crear una</Link>
      </p>
    </div>
  )
}
