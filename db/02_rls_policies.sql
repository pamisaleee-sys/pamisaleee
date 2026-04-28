-- =====================================================
-- pamisaleee — Row Level Security
-- Ejecutar DESPUÉS de 01_schema.sql
-- =====================================================

-- Habilitar RLS en todas las tablas de usuario
alter table public.profiles            enable row level security;
alter table public.tournaments         enable row level security;
alter table public.tournament_members  enable row level security;
alter table public.teams               enable row level security;
alter table public.matches             enable row level security;
alter table public.predictions         enable row level security;
alter table public.betting_markets     enable row level security;
alter table public.market_options      enable row level security;
alter table public.bets                enable row level security;
alter table public.point_transactions  enable row level security;

-- =====================================================
-- PROFILES: todos leen, solo dueño edita
-- =====================================================
create policy profiles_select_all on public.profiles
  for select using (true);

create policy profiles_update_own on public.profiles
  for update using (auth.uid() = id);

-- =====================================================
-- TEAMS / MATCHES: lectura pública autenticada
-- =====================================================
create policy teams_select on public.teams
  for select to authenticated using (true);

create policy matches_select on public.matches
  for select to authenticated using (true);

-- =====================================================
-- TOURNAMENTS
-- =====================================================
-- Ver: miembros del torneo o el creador
create policy tournaments_select on public.tournaments
  for select to authenticated using (
    created_by = auth.uid()
    or exists (
      select 1 from public.tournament_members tm
      where tm.tournament_id = tournaments.id and tm.user_id = auth.uid()
    )
  );

-- Crear: cualquier user autenticado, debe ser el creator
create policy tournaments_insert on public.tournaments
  for insert to authenticated with check (created_by = auth.uid());

-- Actualizar: solo el creador
create policy tournaments_update_owner on public.tournaments
  for update to authenticated using (created_by = auth.uid());

-- =====================================================
-- TOURNAMENT_MEMBERS
-- =====================================================
-- Ver: miembros del mismo torneo
create policy members_select on public.tournament_members
  for select to authenticated using (
    exists (
      select 1 from public.tournament_members tm
      where tm.tournament_id = tournament_members.tournament_id
        and tm.user_id = auth.uid()
    )
  );

-- Unirse: insertar su propia fila (app valida invite_code antes)
create policy members_insert_self on public.tournament_members
  for insert to authenticated with check (user_id = auth.uid());

-- Salir: borrar su propia fila
create policy members_delete_self on public.tournament_members
  for delete to authenticated using (user_id = auth.uid());

-- =====================================================
-- PREDICTIONS: user ve las suyas y las de sus torneos
-- =====================================================
create policy predictions_select on public.predictions
  for select to authenticated using (
    user_id = auth.uid()
    or exists (
      select 1 from public.tournament_members tm
      where tm.tournament_id = predictions.tournament_id
        and tm.user_id = auth.uid()
    )
  );

create policy predictions_insert_own on public.predictions
  for insert to authenticated with check (user_id = auth.uid());

create policy predictions_update_own on public.predictions
  for update to authenticated using (user_id = auth.uid());

create policy predictions_delete_own on public.predictions
  for delete to authenticated using (user_id = auth.uid());

-- =====================================================
-- BETTING MARKETS / OPTIONS: ver si sos miembro del torneo
-- =====================================================
create policy markets_select on public.betting_markets
  for select to authenticated using (
    exists (
      select 1 from public.tournament_members tm
      where tm.tournament_id = betting_markets.tournament_id
        and tm.user_id = auth.uid()
    )
  );

create policy options_select on public.market_options
  for select to authenticated using (
    exists (
      select 1
      from public.betting_markets bm
      join public.tournament_members tm on tm.tournament_id = bm.tournament_id
      where bm.id = market_options.market_id and tm.user_id = auth.uid()
    )
  );

-- =====================================================
-- BETS: user ve las suyas, y las del torneo (para leaderboard opcional)
-- =====================================================
create policy bets_select on public.bets
  for select to authenticated using (
    user_id = auth.uid()
    or exists (
      select 1 from public.tournament_members tm
      where tm.tournament_id = bets.tournament_id
        and tm.user_id = auth.uid()
    )
  );

create policy bets_insert_own on public.bets
  for insert to authenticated with check (user_id = auth.uid());

-- No se permite update/delete desde el cliente: apuestas se liquidan server-side
-- (con una Edge Function o un rol service_role desde backend)

-- =====================================================
-- POINT TRANSACTIONS: solo lectura propia
-- =====================================================
create policy txn_select_own on public.point_transactions
  for select to authenticated using (user_id = auth.uid());

-- Los inserts los hace una función SECURITY DEFINER, no el cliente.
