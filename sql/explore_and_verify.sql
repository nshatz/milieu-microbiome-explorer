-- explore_and_verify.sql  (web-app: slzzzbptquemazhhpekr) — handy one-off queries.

-- 1) Enumerate the FULL quiz schema (every field, distinct values, multi-select detection)
WITH kv AS (
  SELECT k, coalesce(quiz_data->k->>'value', quiz_data->k->>'answer', (quiz_data->k)::text) v,
         jsonb_typeof(quiz_data->k) typ
  FROM quiz_submissions, jsonb_object_keys(quiz_data) k)
SELECT k AS field, count(*) n_answered, count(DISTINCT v) n_distinct_vals,
  (array_agg(DISTINCT left(v,28)))[1:12] AS example_values
FROM kv GROUP BY k ORDER BY n_answered DESC;

-- 2) Species prevalence + typical abundance (per-sample summed). Surfaces what's real vs trace.
WITH s AS (
  SELECT r.id pid, split_part(tx.key,'s__',2) sp, sum(tx.value::numeric) v
  FROM raw_microbiome_data r, jsonb_each_text(r.full_taxa) tx
  WHERE r.full_taxa IS NOT NULL AND r.diversity IS NOT NULL AND tx.key LIKE '%;s__%'
  GROUP BY r.id, split_part(tx.key,'s__',2))
SELECT sp, count(*) FILTER (WHERE v>0) present_in, count(*) FILTER (WHERE v>=0.1) n_ge_0p1,
  count(*) FILTER (WHERE v>=1) n_ge_1, round(avg(v) FILTER (WHERE v>0)::numeric,2) avg_when_present
FROM s WHERE sp<>'' GROUP BY sp ORDER BY present_in DESC LIMIT 60;

-- 3) Dedup truth: unique taxa vectors and real repeat-testers (combine web + historical)
WITH allt AS (
  SELECT id::text pid, md5(full_taxa::text) h FROM raw_microbiome_data WHERE full_taxa IS NOT NULL
  UNION ALL
  SELECT profile_id::text, md5(full_taxa::text) FROM historical_raw_microbiome_data WHERE full_taxa IS NOT NULL)
SELECT count(*) total_rows, count(DISTINCT h) unique_vectors FROM allt;

-- 4) Verify a quiz->microbiome signal in SQL before trusting the JS (group means + corr).
WITH t AS (
  SELECT r.id pid, r.diversity div,
    coalesce(sum(tx.value::numeric) FILTER (WHERE split_part(tx.key,'s__',2)='acnes'),0) acnes
  FROM raw_microbiome_data r, jsonb_each_text(r.full_taxa) tx
  WHERE r.full_taxa IS NOT NULL AND r.diversity IS NOT NULL GROUP BY r.id, r.diversity),
q AS (SELECT DISTINCT ON (profile_id) profile_id pid, quiz_data d FROM quiz_submissions ORDER BY profile_id, created_at DESC),
j AS (SELECT t.*, (coalesce(q.d->'recent_medications'->>'value',q.d->'recent_medications'->>'answer','') ILIKE '%ANTIBIOTICS%') abx
  FROM t JOIN q ON q.pid=t.pid)
SELECT abx, count(*) n, round(avg(div)::numeric,2) diversity, round(avg(acnes)::numeric,1) acnes_pct
FROM j GROUP BY abx;

-- 5) Quick partial-confound check: is a predictor entangled with age/sex? (near-0 => effect survives)
--    See the abx_age / abx_sex style corr() query pattern; if predictor~age and predictor~sex are
--    small, the multivariate adjusted beta will ~= the unadjusted one.
