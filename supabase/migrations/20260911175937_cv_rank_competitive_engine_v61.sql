-- CV Coach V61 — Competitive Rank Engine contract alignment
-- Production migration: supabase_migrations 20260911175937 / cv_rank_competitive_engine_v61.
-- Core objects were applied through Supabase migration management before this repository mirror.
-- This file is intentionally idempotent and pins the approved league/rating contract.

do $$
begin
  if to_regclass('public.client_competitive_rank_v61') is null
     or to_regclass('public.cv_rank_rules_v61') is null
     or to_regclass('public.cv_rank_level_thresholds_v61') is null
     or to_regclass('public.cv_rank_weekly_snapshots_v61') is null
     or to_regclass('public.cv_rank_rating_ledger_v61') is null
     or to_regclass('public.cv_rank_transitions_v61') is null
     or to_regclass('public.cv_seasons_v61') is null
     or to_regclass('public.cv_challenges_v61') is null then
    raise exception 'CV Rank V61 core engine is missing; apply migration cv_rank_competitive_engine_v61 first';
  end if;
end $$;

-- Approved scale: tutorial level 0 has no badge. Every league has five levels except Legend.
-- ('bronze',1,5) ('silver',6,10) ('gold',11,15) ('platinum',16,20) ('diamond',21,25) ('legend',26,26)
insert into public.cv_rank_rules_v61(
  rank_key,rank_name,order_index,min_level,max_level,maintenance_pct,progress_pct,
  loss_factor,loss_cap,gain_base,gain_factor,gain_cap,color_primary,color_secondary,badge_path,tagline,is_terminal
) values
('bronze','BRONCE',1,1,5,55,70,8,250,180,14,600,'#C47A3A','#6E351E','./assets/ranks/cv-rank-bronze-v61.webp','El primer paso también cuenta.',false),
('silver','PLATA',2,6,10,65,75,10,300,160,13,500,'#D8E0E6','#71808A','./assets/ranks/cv-rank-silver-v61.webp','La constancia empieza a notarse.',false),
('gold','ORO',3,11,15,75,82,12,350,150,12,450,'#F4B942','#8A5A12','./assets/ranks/cv-rank-gold-v61.webp','Tus hábitos ya empiezan a notarse.',false),
('platinum','PLATINO',4,16,20,82,87,15,400,140,11,380,'#28D7E9','#0B7786','./assets/ranks/cv-rank-platinum-v61.webp','Ya no dependes solo de la motivación.',false),
('diamond','DIAMANTE',5,21,25,88,92,18,450,120,10,300,'#5596FF','#173F9C','./assets/ranks/cv-rank-diamond-v61.webp','Tu adherencia ya está por encima del promedio.',false),
('legend','LEYENDA',6,26,26,93,96,20,500,80,8,160,'#F5F7FA','#FF2037','./assets/ranks/cv-rank-legend-v61.webp','La disciplina ya es parte de quién eres.',true)
on conflict(rank_key) do update set
 rank_name=excluded.rank_name,order_index=excluded.order_index,min_level=excluded.min_level,max_level=excluded.max_level,
 maintenance_pct=excluded.maintenance_pct,progress_pct=excluded.progress_pct,loss_factor=excluded.loss_factor,loss_cap=excluded.loss_cap,
 gain_base=excluded.gain_base,gain_factor=excluded.gain_factor,gain_cap=excluded.gain_cap,color_primary=excluded.color_primary,
 color_secondary=excluded.color_secondary,badge_path=excluded.badge_path,tagline=excluded.tagline,is_terminal=excluded.is_terminal;

-- Rating floors approved for levels 1..26. Level 26 still requires the Legend discipline gate.
insert into public.cv_rank_level_thresholds_v61(level_number,rank_key,rating_floor,label) values
(1,'bronze',0,'Bronce 1'),(2,'bronze',200,'Bronce 2'),(3,'bronze',450,'Bronce 3'),(4,'bronze',750,'Bronce 4'),(5,'bronze',1100,'Bronce 5'),
(6,'silver',1500,'Plata 6'),(7,'silver',1950,'Plata 7'),(8,'silver',2450,'Plata 8'),(9,'silver',3000,'Plata 9'),(10,'silver',3600,'Plata 10'),
(11,'gold',4250,'Oro 11'),(12,'gold',4950,'Oro 12'),(13,'gold',5700,'Oro 13'),(14,'gold',6500,'Oro 14'),(15,'gold',7350,'Oro 15'),
(16,'platinum',8250,'Platino 16'),(17,'platinum',9200,'Platino 17'),(18,'platinum',10200,'Platino 18'),(19,'platinum',11250,'Platino 19'),(20,'platinum',12350,'Platino 20'),
(21,'diamond',13500,'Diamante 21'),(22,'diamond',14700,'Diamante 22'),(23,'diamond',16000,'Diamante 23'),(24,'diamond',17400,'Diamante 24'),(25,'diamond',18900,'Diamante 25'),
(26,'legend',20500,'Leyenda')
on conflict(level_number) do update set rank_key=excluded.rank_key,rating_floor=excluded.rating_floor,label=excluded.label;

-- Required V61 backend API contracts:
-- public.get_client_rank_dashboard_v61
-- public.get_cv_ranking_v61
-- public.get_client_challenges_v61
-- public.get_coach_rank_dashboard_v61
-- public.create_cv_challenge_v61
-- public.set_cv_challenge_status_v61
-- public.process_due_rank_weeks_v61
-- public.ack_rank_tutorial_v61
-- public.sync_rank_tutorial_v61
-- Tables also required: cv_rank_pause_periods_v61, cv_rank_tutorial_ack_v61,
-- cv_season_weekly_points_v61, cv_challenge_entries_v61, cv_challenge_winners_v61.
