# pamisaleee

App web para jugar la penca del Mundial 2026 con amigos, con capa extra de apuestas usando los puntos ganados.

## Stack
- React 18 + Vite
- Supabase (Postgres + Auth + RLS)
- Deploy en Vercel

## Desarrollo local

```bash
npm install
cp .env.example .env   # ya viene con las credenciales del proyecto
npm run dev
```

Abrir http://localhost:5173

## Estructura

```
db/                    SQL para Supabase (correr en orden)
src/
  lib/supabase.js      cliente singleton
  contexts/AuthContext función global de sesión
  pages/               Login, Signup, Home, Tournament, Bets, Leaderboard
  App.jsx              router + tabbar
```

## Reglas de puntos (penca)
- Resultado exacto: **5** pts
- Ganador correcto: **2** pts
- +**1** si además acierta la diferencia de goles

## Flujo de torneo
1. Usuario se registra (crea fila auto en `profiles` vía trigger).
2. Crea un torneo → se genera un `invite_code` de 6 chars.
3. Comparte el código; otros usan "Unirme con código" y reciben `starting_points` (default 100).
4. El admin (creador) carga partidos y mercados de apuestas en Supabase.
5. Los jugadores predicen y apuestan.
6. Cuando el admin marca un partido como `finished` + carga el score, el trigger liquida predicciones y suma puntos.
7. Para liquidar un mercado de apuestas: `rpc('settle_market', { p_market_id, p_winning_option })`.

## Deploy
- Push a GitHub (repo privado).
- Import en Vercel, setear env vars `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY`.
- Agregar la URL de Vercel en **Supabase → Authentication → URL Configuration → Redirect URLs**.
