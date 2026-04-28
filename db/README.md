# Base de datos — pamisaleee

## Cómo aplicar el schema en Supabase

1. Entrar al proyecto en https://mavxruagxofoffcpxyak.supabase.co
2. Ir a **SQL Editor** → **New query**
3. Ejecutar los archivos **en orden**:
   1. `01_schema.sql` — tablas, tipos y trigger de auto-creación de perfil
   2. `02_rls_policies.sql` — Row Level Security (cada user ve solo lo suyo)
   3. `03_functions.sql` — lógica de negocio: `join_tournament`, `place_bet`, `settle_market`, cálculo de puntos
   4. `04_seed_teams.sql` — equipos iniciales (editable)

Cada archivo es idempotente en lo posible; si algo falla podés borrar la tabla y correr de nuevo.

## Chequeo rápido post-deploy

```sql
-- Verificar que RLS está activo en todas las tablas
select tablename, rowsecurity
from pg_tables
where schemaname = 'public'
order by tablename;
```

Todas deberían tener `rowsecurity = true`.

## Flujo de la app contra la DB

| Acción del usuario          | Lo que hace la app                                        |
|----------------------------|-----------------------------------------------------------|
| Registrarse                | `supabase.auth.signUp` → trigger crea fila en `profiles`  |
| Crear torneo               | `insert into tournaments` (RLS exige `created_by=uid`)    |
| Unirse con código          | `rpc('join_tournament', { p_invite_code })`               |
| Cargar predicción          | `upsert into predictions`                                 |
| Apostar                    | `rpc('place_bet', { p_market_id, p_option_id, p_points })`|
| Admin cierra partido       | update `matches.status='finished'` + `home_score/away_score` → trigger liquida predicciones |
| Admin liquida mercado      | `rpc('settle_market', { p_market_id, p_winning_option })` |

## Tabla de posiciones

```sql
-- Leaderboard de un torneo (query desde el cliente)
select p.username, tm.points_balance
from tournament_members tm
join profiles p on p.id = tm.user_id
where tm.tournament_id = '<TOURNAMENT_ID>'
order by tm.points_balance desc;
```
