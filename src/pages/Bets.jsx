import { useEffect, useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { supabase } from '../lib/supabase'
import { useAuth } from '../contexts/AuthContext'

export default function Bets() {
  const { id: tournamentId } = useParams()
  const { user } = useAuth()
  const [markets, setMarkets] = useState([])
  const [balance, setBalance] = useState(0)
  const [stake, setStake] = useState({})  // option_id -> amount
  const [loading, setLoading] = useState(true)
  const [err, setErr] = useState('')

  const load = async () => {
    if (!tournamentId) return setLoading(false)
    setLoading(true)
    const [{ data: m }, { data: bal }] = await Promise.all([
      supabase
        .from('betting_markets')
        .select('id, type, title, description, status, closes_at, winning_option_id, market_options(id,label,odds)')
        .eq('tournament_id', tournamentId)
        .order('created_at', { ascending: false }),
      supabase.from('tournament_members').select('points_balance').eq('tournament_id', tournamentId).eq('user_id', user.id).single()
    ])
    setMarkets(m ?? [])
    setBalance(bal?.points_balance ?? 0)
    setLoading(false)
  }

  useEffect(() => { if (user && tournamentId) load() }, [tournamentId, user])

  const placeBet = async (marketId, optionId) => {
    const amount = Number(stake[optionId])
    if (!amount || amount <= 0) { setErr('Monto inválido'); return }
    setErr('')
    const { error } = await supabase.rpc('place_bet', {
      p_market_id: marketId,
      p_option_id: optionId,
      p_points: amount
    })
    if (error) return setErr(error.message)
    setStake(s => ({ ...s, [optionId]: '' }))
    load()
  }

  if (!tournamentId) {
    return (
      <div className="container">
        <h1>Apuestas</h1>
        <p className="muted">Elegí un torneo desde "Torneos" para ver sus mercados.</p>
      </div>
    )
  }

  return (
    <div className="container">
      <Link to={`/t/${tournamentId}`} className="muted">← Torneo</Link>
      <div className="row" style={{ justifyContent: 'space-between', marginTop: 8 }}>
        <h1>Mercados</h1>
        <span className="badge accent">{balance} pts</span>
      </div>

      {loading ? <p className="muted">Cargando...</p> : (
        <div className="stack">
          {markets.length === 0 && <div className="card"><p className="muted">Todavía no hay mercados abiertos.</p></div>}
          {err && <div className="error">{err}</div>}
          {markets.map(m => (
            <div key={m.id} className="card stack">
              <div className="row" style={{ justifyContent: 'space-between' }}>
                <h3>{m.title}</h3>
                <span className="badge">{m.status}</span>
              </div>
              {m.description && <p className="muted">{m.description}</p>}
              <div className="stack">
                {m.market_options?.map(o => {
                  const isWinner = m.winning_option_id === o.id
                  return (
                    <div key={o.id} className="row" style={{ justifyContent: 'space-between', gap: 8 }}>
                      <span>{o.label} {isWinner && <span className="badge accent">✓</span>}</span>
                      <div className="row" style={{ gap: 6 }}>
                        <span className="badge">x{o.odds}</span>
                        {m.status === 'open' && (
                          <>
                            <input
                              type="number" min="1" inputMode="numeric"
                              style={{ width: 72 }}
                              placeholder="pts"
                              value={stake[o.id] ?? ''}
                              onChange={e => setStake(s => ({ ...s, [o.id]: e.target.value }))}
                            />
                            <button className="primary" onClick={() => placeBet(m.id, o.id)}>Apostar</button>
                          </>
                        )}
                      </div>
                    </div>
                  )
                })}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
