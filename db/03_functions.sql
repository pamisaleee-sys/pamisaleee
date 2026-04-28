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
