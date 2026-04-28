import { useEffect, useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useAuth } from '../contexts/AuthContext'

export default function Tournament() {
  const { id } = useParams()
  const { user } = useAuth()
  const [tournament, setTournament] = useState(null)
  const [matches, setMatches] = useState([])
  const [preds, setPreds] = useState({})   // match_id -> {home, away, id?}
  const [balance, setBalance] = useState(0)
  const [saving, setSaving] = useState(null)

  const load = async () => {
    const [{ data: t }, { data: m }, { data: p }, { data: bal }] = await Promise.all([
      supabase.from('tournaments').select('*').eq('id', id).single(),
      supabase
        .from('matches')
        .select('id, match_date, status, home_score, away_score, home:home_team_id(name,code,flag_emoji), away:away_team_id(name,code,flag_emoji)')
        .order('match_date', { ascending: true }),
      supabase.from('predictions').select('*').eq('tournament_id', id).eq('user_id', user.id),
      supabase.from('tournament_members').select('points_balance').eq('tournament_id', id).eq('user_id', user.id).single()
    ])
    setTournament(t)
    setMatches(m ?? [])
    const map = {}
    for (const pr of (p ?? [])) map[pr.match_id] = { id: pr.id, home: pr.predicted_home, away: pr.predicted_away, points: pr.points_awarded }
    setPreds(map)
    setBalance(bal?.points_balance ?? 0)
  }

  useEffect(() => { if (user && id) load() }, [id, user])

  const savePrediction = async (matchId) => {
    const p = preds[matchId]
    if (p?.home == null || p?.away == null) return
    setSaving(matchId)
    const { error } = await supabase.from('predictions').upsert({
      user_id: user.id,
      tournament_id: id,
      match_id: matchId,
      predicted_home: Number(p.home),
      predicted_away: Number(p.away)
    }, { onConflict: 'user_id,tournament_id,match_id' })
    setSaving(null)
    if (error) alert(error.message)
  }

  if (!tournament) return <div className="container"><p className="muted">Cargando...</p></div>

  return (
    <div className="container">
      <Link to="/" className="muted">← Torneos</Link>
      <div className="row" style={{ justifyContent: 'space-between', marginTop: 8 }}>
        <div>
          <h1>{tournament.name}</h1>
          <span className="muted">Código: <b>{tournament.invite_code}</b></span>
        </div>
        <span className="badge accent">{balance} pts</span>
      </div>

      <div className="row" style={{ marginTop: 16, marginBottom: 16 }}>
        <Link to={`/t/${id}/bets`}><button className="primary">Apuestas</button></Link>
        {tournament.created_by === user.id && (
          <Link to={`/t/${id}/admin`}><button>Admin</button></Link>
        )}
      </div>

      <h2>Partidos</h2>
      {matches.length === 0 && <p className="muted">Todavía no hay partidos cargados. El admin del torneo debe cargarlos en Supabase.</p>}
      <div className="stack">
        {matches.map(m => {
          const p = preds[m.id] ?? { home: '', away: '' }
          const finished = m.status === 'finished'
          const locked = m.status !== 'scheduled'
          return (
            <div key={m.id} className="card stack">
              <div className="row" style={{ justifyContent: 'space-between' }}>
                <span className="muted">{new Date(m.match_date).toLocaleString()}</span>
                <span className="badge">{m.status}</span>
              </div>
              <div className="row" style={{ justifyContent: 'space-between', gap: 12 }}>
                <span>{m.home?.flag_emoji} {m.home?.code}</span>
                <div className="row" style={{ gap: 4 }}>
                  <input
                    type="number" min="0" inputMode="numeric"
                    style={{ width: 56, textAlign: 'center' }}
                    value={p.home ?? ''}
                    disabled={locked}
                    onChange={e => setPreds(s => ({ ...s, [m.id]: { ...p, home: e.target.value } }))}
                  />
                  <span>-</span>
                  <input
                    type="number" min="0" inputMode="numeric"
                    style={{ width: 56, textAlign: 'center' }}
                    value={p.away ?? ''}
                    disabled={locked}
                    onChange={e => setPreds(s => ({ ...s, [m.id]: { ...p, away: e.target.value } }))}
                  />
                </div>
                <span>{m.away?.code} {m.away?.flag_emoji}</span>
              </div>
              {finished && (
                <div className="muted row" style={{ justifyContent: 'space-between' }}>
                  <span>Resultado: <b>{m.home_score}-{m.away_score}</b></span>
                  <span>Ganaste: <b>{p.points ?? 0}</b> pts</span>
                </div>
              )}
              {!locked && (
                <button onClick={() => savePrediction(m.id)} disabled={saving === m.id}>
                  {saving === m.id ? 'Guardando...' : 'Guardar predicción'}
                </button>
              )}
            </div>
          )
        })}
      </div>
    </div>
  )
}
