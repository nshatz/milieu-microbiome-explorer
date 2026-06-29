-- backfill_age_sex_infra.sql  (run on INFRA: lvxdnqedvsgokkyyntce)
-- Companion to species_matrix.sql. web-app fills age for only ~123/221 sequenced profiles and sex for
-- ~108/221 (profiles has no sex column; sex lives in the quiz). Infra has older copies that fill most
-- of the gap. Cross-project JOINs are impossible, so: run species_matrix.sql on web-app, run THIS on
-- infra, then COALESCE the blank age/sex into the SPECIES rows by lowercased email (web value wins).
-- Lift: age ~123 -> ~219, sex ~108 -> ~194. infra stores lowercase female/male -> upper-cased here.
-- Emits one compact CSV cell: email,age,sex  (age = years from profiles.birthday; sex = latest quiz).
WITH bd AS (
  SELECT lower(email) AS email, date_part('year', age(birthday))::int AS age
  FROM profiles
  WHERE birthday IS NOT NULL AND date_part('year', age(birthday)) BETWEEN 5 AND 100
),
sx AS (
  SELECT DISTINCT ON (lower(p.email)) lower(p.email) AS email,
         upper(coalesce(q.data->'sex_at_birth'->>'value', q.data->'sex_at_birth'->>'answer',
                        q.data->>'sex_at_birth')) AS sex
  FROM profiles p
  JOIN quizzes q ON q.profile_id = p.id
  WHERE coalesce(q.data->'sex_at_birth'->>'value', q.data->'sex_at_birth'->>'answer',
                 q.data->>'sex_at_birth') IS NOT NULL
  ORDER BY lower(p.email), q.updated_at DESC NULLS LAST, q.created_at DESC NULLS LAST
),
m AS (
  SELECT coalesce(bd.email, sx.email) AS email, bd.age,
         CASE WHEN sx.sex IN ('FEMALE','MALE') THEN sx.sex
              WHEN sx.sex LIKE 'F%' THEN 'FEMALE'
              WHEN sx.sex LIKE 'M%' THEN 'MALE' END AS sex
  FROM bd FULL OUTER JOIN sx ON bd.email = sx.email
)
SELECT string_agg(concat_ws(',', email, coalesce(age::text,''), coalesce(sex,'')), E'\n') AS csv
FROM m WHERE age IS NOT NULL OR sex IS NOT NULL;
