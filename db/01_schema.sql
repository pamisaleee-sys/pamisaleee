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
