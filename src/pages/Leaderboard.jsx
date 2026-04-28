import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../contexts/AuthContext'

export default function Leaderboard() {
  const { user } = useAuth()
  const [tournaments, setTournaments] = useState([])
  const [selected, setSelected] = useState('')
  const [rows, setRows] = useState([])

  useEffect(() => {
    if (!user) return
    supabase
      .from('tournament_members')
      .select('tournaments(id,name)')
      .eq('user_id', user.id)
      .then(({ data }) => {
        const ts = (data ?? []).map(d => d.tournaments).filter(Boolean)
        setTournaments(ts)
        if (ts[0]) setSelected(ts[0].id)
      })
  }, [user])

  useEffect(() => {
    if (!selected) return
    supabase
      .from('tournament_members')
      .select('points_balance, profiles(username)')
      .eq('tournament_id', selected)
      .order('points_balance', { ascending: false })
      .then(({ data }) => setRows(data ?? []))
  }, [selected])

  return (
    <div className="container">
      <h1>Tabla de posiciones</h1>
      {tournaments.length === 0 ? (
        <p className="muted">Unite a un torneo primero.</p>
      ) : (
        <>
          <select value={selected} onChange={e => setSelected(e.target.value)} style={{ marginBottom: 16 }}>
            {tournaments.map(t => <option key={t.id} value={t.id}>{t.name}</option>)}
          </select>
          <div className="stack">
            {rows.map((r, i) => (
              <div key={i} className="card row" style={{ justifyContent: 'space-between' }}>
                <span><b>#{i + 1}</b> &nbsp; {r.profiles?.username ?? '—'}</span>
                <span className="badge accent">{r.points_balance} pts</span>
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  )
}
