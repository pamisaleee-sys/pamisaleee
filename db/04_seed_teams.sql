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
