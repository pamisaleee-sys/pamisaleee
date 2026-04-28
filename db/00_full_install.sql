-- =====================================================
-- pamisaleee — Schema base
-- Ejecutar en el SQL Editor de Supabase
-- =====================================================

-- Extensiones
create extension if not exists "pgcrypto";

-- =====================================================
-- PROFILES (extiende auth.users)
-- =====================================================
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null check (char_length(username) between 3 and 20),
  avatar_url text,
  created_at timestamptz not null default now()
);

-- Trigger: cuando se crea un user en auth, crea perfil vacío
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', 'user_' || substr(new.id::text, 1, 8))
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- =====================================================
-- TOURNAMENTS
-- =====================================================
create table public.tournaments (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  invite_code text unique not null default upper(substr(md5(random()::text), 1, 6)),
  created_by uuid not null references public.profiles(id) on delete cascade,
  starting_points integer not null default 100,
  created_at timestamptz not null default now()
);

-- =====================================================
-- TOURNAMENT MEMBERS (junction)
-- =====================================================
create table public.tournament_members (
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  points_balance integer not null default 0,
  joined_at timestamptz not null default now(),
  primary key (tournament_id, user_id)
);

-- =====================================================
-- TEAMS
-- =====================================================
create table public.teams (
  id serial primary key,
  name text not null unique,
  code text not null unique,   -- ej: ARG, BRA
  flag_emoji text,
  group_letter char(1)         -- A, B, C...
);

-- =====================================================
-- MATCHES
-- =====================================================
create type match_stage as enum ('group', 'r16', 'qf', 'sf', 'third', 'final');
create type match_status as enum ('scheduled', 'live', 'finished', 'cancelled');

create table public.matches (
  id serial primary key,
  home_team_id int not null references public.teams(id),
  away_team_id int not null references public.teams(id),
  stage match_stage not null default 'group',
  match_date timestamptz not null,
  status match_status not null default 'scheduled',
  home_score int,
  away_score int,
  created_at timestamptz not null default now(),
  check (home_team_id <> away_team_id)
);

create index on public.matches (match_date);
create index on public.matches (status);

-- =====================================================
-- PREDICTIONS
-- =====================================================
create table public.predictions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  match_id int not null references public.matches(id) on delete cascade,
  predicted_home int not null check (predicted_home >= 0),
  predicted_away int not null check (predicted_away >= 0),
  points_awarded int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, tournament_id, match_id)
);

-- =====================================================
-- BETTING MARKETS
-- =====================================================
create type market_type as enum ('top_scorer', 'first_goal', 'total_cards', 'exact_score', 'match_winner');
create type market_status as enum ('open', 'closed', 'settled', 'cancelled');

create table public.betting_markets (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  match_id int references public.matches(id) on delete cascade, -- null si es mercado de torneo completo
  type market_type not null,
  title text not null,
  description text,
  status market_status not null default 'open',
  closes_at timestamptz,
  winning_option_id uuid,
  created_at timestamptz not null default now()
);

-- Opciones del mercado con cuotas
create table public.market_options (
  id uuid primary key default gen_random_uuid(),
  market_id uuid not null references public.betting_markets(id) on delete cascade,
  label text not null,               -- ej: "Messi", "Más de 3 tarjetas", "2-1"
  odds numeric(6,2) not null check (odds >= 1.01),
  created_at timestamptz not null default now()
);

alter table public.betting_markets
  add constraint betting_markets_winning_option_fk
  foreign key (winning_option_id) references public.market_options(id) on delete set null;

-- =====================================================
-- BETS
-- =====================================================
create type bet_status as enum ('pending', 'won', 'lost', 'refunded');

create table public.bets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  market_id uuid not null references public.betting_markets(id) on delete cascade,
  option_id uuid not null references public.market_options(id) on delete cascade,
  points_wagered int not null check (points_wagered > 0),
  odds_at_bet numeric(6,2) not null,
  potential_payout int not null,
  status bet_status not null default 'pending',
  created_at timestamptz not null default now(),
  settled_at timestamptz
);

create index on public.bets (user_id);
create index on public.bets (market_id);

-- =====================================================
-- POINT TRANSACTIONS (log auditable)
-- =====================================================
create type txn_type as enum ('prediction_reward', 'bet_placed', 'bet_won', 'bet_refunded', 'tournament_join', 'admin_adjust');

create table public.point_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  amount int not null,             -- positivo o negativo
  type txn_type not null,
  reference_id uuid,               -- id de bet, prediction, etc
  created_at timestamptz not null default now()
);

create index on public.point_transactions (user_id, tournament_id);
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
-- =====================================================
-- pamisaleee — Funciones de negocio (SECURITY DEFINER)
-- Ejecutar DESPUÉS de 02_rls_policies.sql
-- =====================================================

-- Unirse a un torneo por invite_code (valida y crea membership atómicamente)
create or replace function public.join_tournament(p_invite_code text)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_tournament_id uuid;
  v_starting_points int;
begin
  select id, starting_points
    into v_tournament_id, v_starting_points
    from public.tournaments
   where invite_code = upper(p_invite_code);

  if v_tournament_id is null then
    raise exception 'Código de invitación inválido';
  end if;

  insert into public.tournament_members (tournament_id, user_id, points_balance)
  values (v_tournament_id, auth.uid(), v_starting_points)
  on conflict (tournament_id, user_id) do nothing;

  insert into public.point_transactions (user_id, tournament_id, amount, type)
  values (auth.uid(), v_tournament_id, v_starting_points, 'tournament_join');

  return v_tournament_id;
end;
$$;

grant execute on function public.join_tournament(text) to authenticated;

-- =====================================================
-- Calcular puntos de una predicción vs resultado real
-- Regla:
--   resultado exacto     = 5
--   ganador correcto     = 2
--   diferencia de goles  = +1 extra
-- =====================================================
create or replace function public.score_prediction(
  p_pred_home int, p_pred_away int,
  p_real_home int, p_real_away int
) returns int
language plpgsql immutable
as $$
declare
  v_points int := 0;
  v_pred_winner int;
  v_real_winner int;
begin
  if p_pred_home = p_real_home and p_pred_away = p_real_away then
    return 5;
  end if;

  v_pred_winner := sign(p_pred_home - p_pred_away);
  v_real_winner := sign(p_real_home - p_real_away);

  if v_pred_winner = v_real_winner then
    v_points := v_points + 2;
    if (p_pred_home - p_pred_away) = (p_real_home - p_real_away) then
      v_points := v_points + 1;
    end if;
  end if;

  return v_points;
end;
$$;

-- =====================================================
-- Liquidar todas las predicciones de un partido finalizado
-- Corre cuando matches.status pasa a 'finished'
-- =====================================================
create or replace function public.settle_match_predictions()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  r record;
  v_points int;
begin
  if new.status = 'finished' and (old.status is distinct from 'finished') then
    for r in
      select id, user_id, tournament_id, predicted_home, predicted_away
      from public.predictions
      where match_id = new.id
    loop
      v_points := public.score_prediction(
        r.predicted_home, r.predicted_away,
        new.home_score, new.away_score
      );

      update public.predictions
         set points_awarded = v_points
       where id = r.id;

      if v_points > 0 then
        update public.tournament_members
           set points_balance = points_balance + v_points
         where tournament_id = r.tournament_id and user_id = r.user_id;

        insert into public.point_transactions (user_id, tournament_id, amount, type, reference_id)
        values (r.user_id, r.tournament_id, v_points, 'prediction_reward', r.id);
      end if;
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_settle_match on public.matches;
create trigger trg_settle_match
  after update on public.matches
  for each row execute function public.settle_match_predictions();

-- =====================================================
-- Colocar apuesta: descuenta puntos y crea fila en bets
-- =====================================================
create or replace function public.place_bet(
  p_market_id uuid,
  p_option_id uuid,
  p_points int
) returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  v_tournament_id uuid;
  v_odds numeric(6,2);
  v_balance int;
  v_bet_id uuid;
  v_status market_status;
begin
  if p_points <= 0 then
    raise exception 'Monto inválido';
  end if;

  select m.tournament_id, m.status, o.odds
    into v_tournament_id, v_status, v_odds
    from public.betting_markets m
    join public.market_options o on o.market_id = m.id
   where m.id = p_market_id and o.id = p_option_id;

  if v_tournament_id is null then
    raise exception 'Mercado u opción inexistente';
  end if;

  if v_status <> 'open' then
    raise exception 'Mercado cerrado';
  end if;

  select points_balance into v_balance
    from public.tournament_members
   where tournament_id = v_tournament_id and user_id = auth.uid();

  if v_balance is null then
    raise exception 'No sos miembro del torneo';
  end if;

  if v_balance < p_points then
    raise exception 'Saldo insuficiente';
  end if;

  update public.tournament_members
     set points_balance = points_balance - p_points
   where tournament_id = v_tournament_id and user_id = auth.uid();

  insert into public.bets (
    user_id, tournament_id, market_id, option_id,
    points_wagered, odds_at_bet, potential_payout
  ) values (
    auth.uid(), v_tournament_id, p_market_id, p_option_id,
    p_points, v_odds, floor(p_points * v_odds)::int
  ) returning id into v_bet_id;

  insert into public.point_transactions (user_id, tournament_id, amount, type, reference_id)
  values (auth.uid(), v_tournament_id, -p_points, 'bet_placed', v_bet_id);

  return v_bet_id;
end;
$$;

grant execute on function public.place_bet(uuid, uuid, int) to authenticated;

-- =====================================================
-- Liquidar un mercado: admin setea winning_option_id
-- y esta función paga ganadores
-- =====================================================
create or replace function public.settle_market(p_market_id uuid, p_winning_option uuid)
returns void
language plpgsql
security definer set search_path = public
as $$
declare
  r record;
begin
  -- Solo el creador del torneo puede liquidar
  if not exists (
    select 1 from public.betting_markets bm
    join public.tournaments t on t.id = bm.tournament_id
    where bm.id = p_market_id and t.created_by = auth.uid()
  ) then
    raise exception 'No autorizado';
  end if;

  update public.betting_markets
     set winning_option_id = p_winning_option,
         status = 'settled'
   where id = p_market_id;

  for r in
    select id, user_id, tournament_id, option_id, points_wagered, potential_payout
      from public.bets
     where market_id = p_market_id and status = 'pending'
  loop
    if r.option_id = p_winning_option then
      update public.bets set status = 'won', settled_at = now() where id = r.id;

      update public.tournament_members
         set points_balance = points_balance + r.potential_payout
       where tournament_id = r.tournament_id and user_id = r.user_id;

      insert into public.point_transactions (user_id, tournament_id, amount, type, reference_id)
      values (r.user_id, r.tournament_id, r.potential_payout, 'bet_won', r.id);
    else
      update public.bets set status = 'lost', settled_at = now() where id = r.id;
    end if;
  end loop;
end;
$$;

grant execute on function public.settle_market(uuid, uuid) to authenticated;
-- =====================================================
-- Seed de equipos (referencia — ajustar al fixture oficial)
-- Mundial 2026: 48 equipos. Grupos y fixture se publican cuando FIFA los defina.
-- Por ahora cargo los 32 más probables clasificados; podés editar.
-- =====================================================
insert into public.teams (name, code, flag_emoji) values
  ('Argentina','ARG','🇦🇷'),
  ('Brasil','BRA','🇧🇷'),
  ('Uruguay','URU','🇺🇾'),
  ('Colombia','COL','🇨🇴'),
  ('Ecuador','ECU','🇪🇨'),
  ('Paraguay','PAR','🇵🇾'),
  ('Estados Unidos','USA','🇺🇸'),
  ('México','MEX','🇲🇽'),
  ('Canadá','CAN','🇨🇦'),
  ('Costa Rica','CRC','🇨🇷'),
  ('Francia','FRA','🇫🇷'),
  ('Inglaterra','ENG','🏴󠁧󠁢󠁥󠁮󠁧󠁿'),
  ('España','ESP','🇪🇸'),
  ('Portugal','POR','🇵🇹'),
  ('Alemania','GER','🇩🇪'),
  ('Italia','ITA','🇮🇹'),
  ('Países Bajos','NED','🇳🇱'),
  ('Bélgica','BEL','🇧🇪'),
  ('Croacia','CRO','🇭🇷'),
  ('Suiza','SUI','🇨🇭'),
  ('Dinamarca','DEN','🇩🇰'),
  ('Polonia','POL','🇵🇱'),
  ('Serbia','SRB','🇷🇸'),
  ('Marruecos','MAR','🇲🇦'),
  ('Senegal','SEN','🇸🇳'),
  ('Egipto','EGY','🇪🇬'),
  ('Nigeria','NGA','🇳🇬'),
  ('Japón','JPN','🇯🇵'),
  ('Corea del Sur','KOR','🇰🇷'),
  ('Irán','IRN','🇮🇷'),
  ('Australia','AUS','🇦🇺'),
  ('Arabia Saudita','KSA','🇸🇦')
on conflict (code) do nothing;
