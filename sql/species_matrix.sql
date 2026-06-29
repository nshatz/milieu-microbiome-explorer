-- species_matrix.sql  (run on web-app: slzzzbptquemazhhpekr)
-- Emits ONE compact CSV cell: per sequenced profile, 20 curated clinical species (summed across
-- lineage variants), Shannon diversity, richness, 7 scan scores, and 12 harmonized lifestyle fields.
-- Paste the result into milieu_signal_explorer.html -> <script type="text/plain" id="SPECIES">.
-- TAXA SET: the explorer now carries 32 taxa = the 20 curated below + 12 added genus-level columns
--   (gemella, haemophilus, prevotella, fuso, lacto, finegoldia, actino, neisseria, moraxella, anaero,
--   peptoni, dolosi) each = round(sum(v) FILTER (WHERE k ILIKE '%g__<Genus>%'),2). They were chosen to
--   NOT overlap the curated species (don't add Corynebacterium/Cutibacterium genus totals — they double-
--   count accolens/confusum/kroppen/tuberculo and acnes/granulosum/avidum and break the CLR 'other' bucket).
--   On rebuild, emit those 12 too or the explorer loses them.
-- Notes: C. acnes lives under genus Propionibacterium; species token via split_part(key,'s__',2).
--        Dedup (by taxa vector) and test-account exclusion happen in the HTML/JS, not here.
-- AGE/SEX: as of 2026-06-26 both are CONSOLIDATED into web-app profiles, so this is a single
--        clean query — no cross-project merge needed anymore.
--          age = date_part('year', age(profiles.birthday))   (cohort birthday backfilled from infra)
--          sex = profiles.sex   (declared from quiz_web/quiz_infra; ~24 cohort rows are name_inferred)
--        profiles.sex_source records provenance ('quiz_web'|'quiz_infra'|'name_inferred'). If you only
--        want DECLARED sex in an analysis, filter sex_source <> 'name_inferred'. Coverage now ~218/221 both.
--        (Legacy: sql/backfill_age_sex_infra.sql is kept for history but is no longer part of the build.)
WITH t AS (
  SELECT r.id pid, tx.key k, split_part(tx.key,'s__',2) sp, tx.value::numeric v
  FROM raw_microbiome_data r, jsonb_each_text(r.full_taxa) tx
  WHERE r.full_taxa IS NOT NULL AND r.diversity IS NOT NULL),
a AS (SELECT pid,
  round(coalesce(sum(v) FILTER (WHERE sp='acnes'),0),2) acnes,
  round(coalesce(sum(v) FILTER (WHERE sp='epidermidis' AND k ILIKE '%g__Staphylococcus%'),0),2) epidermidis,
  round(coalesce(sum(v) FILTER (WHERE sp='granulosum'),0),2) granulosum,
  round(coalesce(sum(v) FILTER (WHERE sp='avidum'),0),2) avidum,
  round(coalesce(sum(v) FILTER (WHERE k ILIKE '%tuberculostearicum%'),0),2) tuberculo,
  round(coalesce(sum(v) FILTER (WHERE sp='kroppenstedtii'),0),2) kroppen,
  round(coalesce(sum(v) FILTER (WHERE sp='accolens'),0),2) accolens,
  round(coalesce(sum(v) FILTER (WHERE sp='confusum'),0),2) confusum,
  round(coalesce(sum(v) FILTER (WHERE sp='capitis-caprae'),0),2) capitis,
  round(coalesce(sum(v) FILTER (WHERE sp='caprae'),0),2) caprae,
  round(coalesce(sum(v) FILTER (WHERE sp='hominis' AND k ILIKE '%g__Staphylococcus%'),0),2) hominis,
  round(coalesce(sum(v) FILTER (WHERE sp='warneri'),0),2) warneri,
  round(coalesce(sum(v) FILTER (WHERE sp='saccharolyticus'),0),2) sacchar,
  round(coalesce(sum(v) FILTER (WHERE sp='argenteus-aureus'),0),2) aureusgrp,
  round(coalesce(sum(v) FILTER (WHERE sp='lugdunensis'),0),2) lugdun,
  round(coalesce(sum(v) FILTER (WHERE k ILIKE '%g__Micrococcus%'),0),2) micro,
  round(coalesce(sum(v) FILTER (WHERE k ILIKE '%g__Kocuria%'),0),2) kocuria,
  round(coalesce(sum(v) FILTER (WHERE k ILIKE '%g__Streptococcus%'),0),2) strep,
  round(coalesce(sum(v) FILTER (WHERE k ILIKE '%g__Rothia%'),0),2) rothia,
  round(coalesce(sum(v) FILTER (WHERE k ILIKE '%g__Veillonella%'),0),2) veillon
  FROM t GROUP BY pid),
sc AS (SELECT DISTINCT ON (profile_id) profile_id pid, analysis_results ar
  FROM skin_analysis_scans WHERE status='completed' AND analysis_results IS NOT NULL
  ORDER BY profile_id, created_at DESC),
q AS (SELECT DISTINCT ON (profile_id) profile_id pid, quiz_data d
  FROM quiz_submissions ORDER BY profile_id, created_at DESC)
SELECT 'email,age,sex,diversity,richness,acnes,epidermidis,granulosum,avidum,tuberculo,kroppen,accolens,confusum,capitis,caprae,hominis,warneri,sacchar,aureusgrp,lugdun,micro,kocuria,strep,rothia,veillon,scan_acne,scan_oili,scan_red,scan_wrinkle,scan_moist,scan_pore,scan_overall,ls_stress,ls_screen,ls_sleepcons,ls_sunscreen,ls_pollution,ls_bedding,ls_water,ls_meat,ls_sugar,ls_dairy,ls_alcohol,ls_caffeine' || E'\n' ||
string_agg(concat_ws(',',
 lower(p.email), coalesce(date_part('year',age(p.birthday))::text,''),
 coalesce(p.sex,''),
 round(r.diversity::numeric,3)::text, round(r.richness::numeric,1)::text,
 a.acnes::text,a.epidermidis::text,a.granulosum::text,a.avidum::text,a.tuberculo::text,a.kroppen::text,a.accolens::text,a.confusum::text,a.capitis::text,a.caprae::text,a.hominis::text,a.warneri::text,a.sacchar::text,a.aureusgrp::text,a.lugdun::text,a.micro::text,a.kocuria::text,a.strep::text,a.rothia::text,a.veillon::text,
 coalesce(sc.ar#>>'{hd_acne,whole,ui_score}',sc.ar#>>'{hd_acne,ui_score}',''),coalesce(sc.ar#>>'{hd_oiliness,ui_score}',''),coalesce(sc.ar#>>'{hd_redness,ui_score}',''),coalesce(sc.ar#>>'{hd_wrinkle,whole,ui_score}',''),coalesce(sc.ar#>>'{hd_moisture,ui_score}',''),coalesce(sc.ar#>>'{hd_pore,whole,ui_score}',sc.ar#>>'{hd_pore,ui_score}',''),coalesce(sc.ar#>>'{all,score}',''),
 coalesce((CASE coalesce(q.d->'stress_levels'->>'value',q.d->'stress_levels'->>'answer') WHEN 'LOW' THEN 0 WHEN 'MODERATE' THEN 33 WHEN 'HIGH' THEN 67 WHEN 'VERY_HIGH' THEN 100 END)::text,''),
 coalesce((CASE coalesce(q.d->'screen_time'->>'value',q.d->'screen_time'->>'answer') WHEN 'LESS_THAN_FOUR' THEN 0 WHEN 'FOUR_TO_EIGHT' THEN 50 WHEN 'MORE_THAN_EIGHT' THEN 100 END)::text,''),
 coalesce((CASE coalesce(q.d->'sleep_consistency'->>'value',q.d->'sleep_consistency'->>'answer') WHEN 'NOT_CONSISTENT' THEN 0 WHEN 'SOMEWHAT_CONSISTENT' THEN 50 WHEN 'VERY_CONSISTENT' THEN 100 END)::text,''),
 coalesce((CASE coalesce(q.d->'sunscreen_frequency'->>'value',q.d->'sunscreen_frequency'->>'answer') WHEN 'NEVER' THEN 0 WHEN 'SUNNY_DAYS' THEN 33 WHEN 'BEACH_POOL_ONLY' THEN 33 WHEN 'MOST_DAYS' THEN 67 WHEN 'EVERY_DAY' THEN 100 END)::text,''),
 coalesce((CASE coalesce(q.d->'pollution_exposure'->>'value',q.d->'pollution_exposure'->>'answer') WHEN 'LOW' THEN 0 WHEN 'MODERATE' THEN 50 WHEN 'HIGH' THEN 100 END)::text,''),
 coalesce((CASE coalesce(q.d->'bedding_hygiene'->>'value',q.d->'bedding_hygiene'->>'answer') WHEN 'MORE_THAN_WEEKLY' THEN 0 WHEN 'WEEKLY' THEN 33 WHEN 'BIWEEKLY' THEN 67 WHEN 'LESS_THAN_BIWEEKLY' THEN 100 END)::text,''),
 coalesce((CASE coalesce(q.d->'daily_water_intake'->>'value',q.d->'daily_water_intake'->>'answer') WHEN 'LESS_THAN_FOUR' THEN 0 WHEN 'FOUR_TO_SIX' THEN 33 WHEN 'SEVEN_TO_EIGHT' THEN 67 WHEN 'MORE_THAN_EIGHT' THEN 100 END)::text,''),
 coalesce((CASE coalesce(q.d->'meat_consumption'->>'value',q.d->'meat_consumption'->>'answer') WHEN 'RARELY_NEVER' THEN 0 WHEN 'WEEKLY' THEN 33 WHEN 'FEW_TIMES_WEEK' THEN 67 WHEN 'DAILY' THEN 100 END)::text,''),
 coalesce((CASE coalesce(q.d->'sugar_consumption'->>'value',q.d->'sugar_consumption'->>'answer') WHEN 'VERY_LITTLE' THEN 0 WHEN 'MODERATE' THEN 50 WHEN 'HIGH' THEN 100 END)::text,''),
 coalesce((CASE coalesce(q.d->'dairy_consumption'->>'value',q.d->'dairy_consumption'->>'answer') WHEN 'NEVER_RARELY' THEN 0 WHEN 'OCCASIONALLY' THEN 33 WHEN 'DAILY' THEN 67 WHEN 'SEVERAL_TIMES_WEEKLY' THEN 100 END)::text,''),
 coalesce((CASE coalesce(q.d->'alcohol_consumption'->>'value',q.d->'alcohol_consumption'->>'answer') WHEN 'NEVER_RARELY' THEN 0 WHEN 'ONE_TWO_WEEKLY' THEN 33 WHEN 'THREE_FIVE_WEEKLY' THEN 67 WHEN 'SIX_PLUS_WEEKLY' THEN 100 END)::text,''),
 coalesce((CASE coalesce(q.d->'caffeine_consumption'->>'value',q.d->'caffeine_consumption'->>'answer') WHEN 'NONE' THEN 0 WHEN 'ONE_CUP' THEN 33 WHEN 'TWO_THREE_CUPS' THEN 67 WHEN 'FOUR_PLUS_CUPS' THEN 100 END)::text,'')
), E'\n') AS csv
FROM a JOIN raw_microbiome_data r ON r.id=a.pid JOIN profiles p ON p.id=a.pid
LEFT JOIN sc ON sc.pid=a.pid LEFT JOIN q ON q.pid=a.pid WHERE p.email IS NOT NULL;
