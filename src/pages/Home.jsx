import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useAuth } from '../contexts/AuthContext'

export default function Home() {
  const { user, profile, signOut } = useAuth()
  const [tournaments, setTournaments] = useState([])
  const [loading, setLoading] = useState(true)
  const [showCreate, setShowCreate] = useState(false)
  const [showJoin, setShowJoin] = useState(false)
  const [name, setName] = useState('')
  const [inviteCode, setInviteCode] = useState('')
  const [err, setErr] = useState('')

  const load = async () => {
    setLoading(true)
    const { data } = await supabase
      .from('tournament_members')
      .select('points_balance, tournaments(id, name, invite_code, created_by)')
      .eq('user_id', user.id)
    setTournaments(data ?? [])
    setLoading(false)
  }

  useEffect(() => { if (user) load() }, [user])

  const createTournament = async (e) => {
    e.preventDefault(); setErr('')
    const { data, error } = await supabase
      .from('tournaments')
      .insert({ name, created_by: user.id })
      .select()
      .single()
    if (error) return setErr(error.message)
    // el creador se auto-une con el saldo inicial
    await supabase.rpc('join_tournament', { p_invite_code: data.invite_code })
    setName(''); setShowCreate(false); load()
  }

  const joinTournament = async (e) => {
    e.preventDefault(); setErr('')
    const { error } = await supabase.rpc('join_tournament', { p_invite_code: inviteCode.trim().toUpperCase() })
    if (error) return setErr(error.message)
    setInviteCode(''); setShowJoin(false); load()
  }

  return (
    <div className="container">
      <div className="row" style={{ justifyContent: 'space-between', marginBottom: 16 }}>
        <div>
          <h1>Hola, {profile?.username ?? '...'}</h1>
          <p className="muted">Tus torneos</p>
        </div>
        <button onClick={signOut}>Salir</button>
      </div>

      <div className="row" style={{ marginBottom: 16 }}>
        <button className="primary" onClick={() => { setShowCreate(!showCreate); setShowJoin(false) }}>
          + Crear torneo
        </button>
        <button onClick={() => { setShowJoin(!showJoin); setShowCreate(false) }}>
          Unirme con código
        </button>
      </div>

      {showCreate && (
        <form className="card stack" onSubmit={createTournament} style={{ marginBottom: 16 }}>
          <span className="label">Nombre del torneo</span>
          <input required value={name} onChange={e => setName(e.target.value)} placeholder="Ej: Penca del Mundial 2026" />
          {err && <div className="error">{err}</div>}
          <button className="primary" type="submit">Crear</button>
        </form>
      )}

      {showJoin && (
        <form className="card stack" onSubmit={joinTournament} style={{ marginBottom: 16 }}>
          <span className="label">Código de invitación</span>
          <input required value={inviteCode} onChange={e => setInviteCode(e.target.value.toUpperCase())} placeholder="6 caracteres" maxLength={6} />
          {err && <div className="error">{err}</div>}
          <button className="primary" type="submit">Unirme</button>
        </form>
      )}

      {loading ? <p className="muted">Cargando...</p> : (
        <div className="stack">
          {tournaments.length === 0 && (
            <div className="card"><p className="muted">Todavía no participás en ningún torneo.</p></div>
          )}
          {tournaments.map(tm => {
            const t = tm.tournaments
            return (
              <Link key={t.id} to={`/t/${t.id}`} className="card" style={{ color: 'inherit' }}>
                <div className="row" style={{ justifyContent: 'space-between' }}>
                  <div>
                    <h3>{t.name}</h3>
                    <span className="muted">Código: <b>{t.invite_code}</b></span>
                  </div>
                  <span className="badge accent">{tm.points_balance} pts</span>
                </div>
              </Link>
            )
          })}
        </div>
      )}
    </div>
  )
}
