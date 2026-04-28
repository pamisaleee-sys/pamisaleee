import { useEffect, useState } from 'react'
import { useParams, Link, Navigate } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useAuth } from '../contexts/AuthContext'

export default function Admin() {
  const { id: tournamentId } = useParams()
  const { user } = useAuth()
  const [tournament, setTournament] = useState(null)
  const [matches, setMatches] = useState([])
  const [markets, setMarkets] = useState([])
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState('')

  // Form estado
  const [scores, setScores] = useState({}) // match_id -> {home, away}
  const [newMarket, setNewMarket] = useState({ type: 'top_scorer', title: '', description: '' })
  const [newOptions, setNewOptions] = useState({}) // marketId -> [{label, odds}]

  const load = async () => {
    setLoading(true)
    const [{ data: t }, { data: m }, { data: mk }] = await Promise.all([
      supabase.from('tournaments').select('*').eq('id', tournamentId).single(),
      supabase.from('matches')
        .select('id, match_date, status, home_score, away_score, home:home_team_id(code), away:away_team_id(code)')
        .order('match_date'),
      supabase.from('betting_markets')
        .select('id, type, title, description, status, winning_option_id, market_options(id,label,odds)')
        .eq('tournament_id', tournamentId)
        .order('created_at', { ascending: false })
    ])
    setTournament(t)
    setMatches(m ?? [])
    setMarkets(mk ?? [])
    setLoading(false)
  }

  useEffect(() => { if (user && tournamentId) load() }, [tournamentId, user])

  if (loading) return <div className="container"><p className="muted">Cargando...</p></div>
  if (!tournament) return <Navigate to="/" replace />
  if (tournament.created_by !== user.id) {
    return <div className="container"><p className="error">Solo el creador del torneo puede acceder acá.</p><Link to={`/t/${tournamentId}`}>Volver</Link></div>
  }

  const finishMatch = async (matchId) => {
    setErr('')
    const s = scores[matchId]
    if (s?.home == null || s?.away == null) return setErr('Cargá los goles antes de finalizar')
    const { error } = await supabase
      .from('matches')
      .update({ status: 'finished', home_score: Number(s.home), away_score: Number(s.away) })
      .eq('id', matchId)
    if (error) return setErr(error.message)
    load()
  }

  const createMarket = async (e) => {
    e.preventDefault(); setErr('')
    if (!newMarket.title) return setErr('Falta título')
    const { error } = await supabase.from('betting_markets').insert({
      tournament_id: tournamentId,
      type: newMarket.type,
      title: newMarket.title,
      description: newMarket.description || null,
      status: 'open'
    })
    if (error) return setErr(error.message)
    setNewMarket({ type: 'top_scorer', title: '', description: '' })
    load()
  }

  const addOption = async (marketId) => {
    setErr('')
    const o = newOptions[marketId]
    if (!o?.label || !o?.odds) return setErr('Label y cuota requeridos')
    const { error } = await supabase.from('market_options').insert({
      market_id: marketId,
      label: o.label,
      odds: Number(o.odds)
    })
    if (error) return setErr(error.message)
    setNewOptions(s => ({ ...s, [marketId]: { label: '', odds: '' } }))
    load()
  }

  const settleMarket = async (marketId, optionId) => {
    setErr('')
    if (!confirm('¿Liquidar con esta opción ganadora? No se puede deshacer.')) return
    const { error } = await supabase.rpc('settle_market', {
      p_market_id: marketId,
      p_winning_option: optionId
    })
    if (error) return setErr(error.message)
    load()
  }

  return (
    <div className="container">
      <Link to={`/t/${tournamentId}`} className="muted">← Torneo</Link>
      <h1>Admin — {tournament.name}</h1>

      {err && <div className="error" style={{ marginTop: 12 }}>{err}</div>}

      <h2>Partidos</h2>
      <div className="stack">
        {matches.map(m => {
          const s = scores[m.id] ?? { home: m.home_score ?? '', away: m.away_score ?? '' }
          return (
            <div key={m.id} className="card stack">
              <div className="row" style={{ justifyContent: 'space-between' }}>
                <span>{m.home?.code} vs {m.away?.code}</span>
                <span className="badge">{m.status}</span>
              </div>
              <span className="muted">{new Date(m.match_date).toLocaleString()}</span>
              {m.status !== 'finished' && (
                <div className="row" style={{ gap: 6 }}>
                  <input type="number" min="0" style={{ width: 60 }} placeholder="H" value={s.home}
                    onChange={e => setScores(st => ({ ...st, [m.id]: { ...s, home: e.target.value } }))} />
                  <span>-</span>
                  <input type="number" min="0" style={{ width: 60 }} placeholder="A" value={s.away}
                    onChange={e => setScores(st => ({ ...st, [m.id]: { ...s, away: e.target.value } }))} />
                  <button className="primary" onClick={() => finishMatch(m.id)}>Finalizar</button>
                </div>
              )}
              {m.status === 'finished' && <span><b>{m.home_score} - {m.away_score}</b></span>}
            </div>
          )
        })}
      </div>

      <h2>Nuevo mercado</h2>
      <form className="card stack" onSubmit={createMarket}>
        <select value={newMarket.type} onChange={e => setNewMarket(s => ({ ...s, type: e.target.value }))}>
          <option value="top_scorer">Goleador</option>
          <option value="first_goal">Primer gol</option>
          <option value="total_cards">Tarjetas</option>
          <option value="exact_score">Resultado exacto</option>
          <option value="match_winner">Ganador del partido</option>
        </select>
        <input placeholder="Título (ej: Goleador del Mundial)" value={newMarket.title}
          onChange={e => setNewMarket(s => ({ ...s, title: e.target.value }))} />
        <input placeholder="Descripción (opcional)" value={newMarket.description}
          onChange={e => setNewMarket(s => ({ ...s, description: e.target.value }))} />
        <button className="primary" type="submit">Crear mercado</button>
      </form>

      <h2>Mercados existentes</h2>
      <div className="stack">
        {markets.map(mk => {
          const no = newOptions[mk.id] ?? { label: '', odds: '' }
          return (
            <div key={mk.id} className="card stack">
              <div className="row" style={{ justifyContent: 'space-between' }}>
                <h3>{mk.title}</h3>
                <span className="badge">{mk.status}</span>
              </div>
              <div className="stack">
                {mk.market_options?.map(o => (
                  <div key={o.id} className="row" style={{ justifyContent: 'space-between' }}>
                    <span>{o.label} <span className="badge">x{o.odds}</span>
                      {mk.winning_option_id === o.id && <span className="badge accent"> ✓ ganadora</span>}
                    </span>
                    {mk.status === 'open' && (
                      <button className="danger" onClick={() => settleMarket(mk.id, o.id)}>Liquidar con esta</button>
                    )}
                  </div>
                ))}
                {mk.status === 'open' && (
                  <div className="row" style={{ gap: 6 }}>
                    <input placeholder="Nueva opción" value={no.label}
                      onChange={e => setNewOptions(s => ({ ...s, [mk.id]: { ...no, label: e.target.value } }))} />
                    <input type="number" min="1.01" step="0.01" placeholder="cuota" style={{ width: 80 }} value={no.odds}
                      onChange={e => setNewOptions(s => ({ ...s, [mk.id]: { ...no, odds: e.target.value } }))} />
                    <button onClick={() => addOption(mk.id)}>+</button>
                  </div>
                )}
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
