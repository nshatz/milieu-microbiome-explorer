# Milieu — Microbiome Data Mining (project memory)

This file is auto-loaded by Claude Code. It captures the conventions, schema, and decisions
for mining correlations from Milieu's Supabase data and building the interactive HTML explorers.
Read it before doing anything; it encodes hard-won corrections.

## What this project is
Milieu is a skin-microbiome company. We mine our Supabase for correlations between **16S
microbiome**, **quizzes**, **face scans**, **lifestyle**, **weather**, and **assigned products**.
Deliverables are **self-contained interactive HTML explorers** (open by double-click, no server).

## HARD RULES
- **Read-only. Never modify Supabase.** SELECT queries only — no INSERT/UPDATE/DELETE, no
  migrations, branches, or deletes. The Supabase MCP is configured with `--read-only` to enforce this.
- **Use RAW analytics, not engine-calculated values.** Exclude `superbiome_score`, the
  Balance/Defense/Structure metrics, and `biome_type` — they blend quiz + microbiome and are
  circular. Correlate against raw taxa abundances, diversity, richness, and raw scan scores only.
- **Full taxa, not the abbreviated readout.** Always parse `full_taxa` (the raw 16S genus/species
  table), never `top_taxa` or the small 6-genus subset.

## Supabase projects (via Supabase MCP)
| role | name | project_ref |
|---|---|---|
| **primary / default** | web-app | `slzzzbptquemazhhpekr` |
| fallback (older data) | infra | `lvxdnqedvsgokkyyntce` |
| sequencing | bioinformatics | `agcmtlqmbqvlfdkxnztm` |

You **cannot JOIN across projects**. Pull each separately and merge in code by **lowercased email**.
Default everything to web-app; only fall back to infra to fill gaps (see Quiz below).

## Key tables (web-app)
- **`raw_microbiome_data`** — `id` IS the profile id (one row per sequenced profile). `full_taxa`
  JSONB (lineage string → % abundance, sums to ~100), `diversity` (Shannon), `richness` (ASV count).
  Current pipeline = rows where `full_taxa IS NOT NULL AND diversity IS NOT NULL` (**221 samples**).
- **`historical_raw_microbiome_data`** — older copies; keyed by `profile_id`.
- **`quiz_submissions`** — `profile_id`, `quiz_data` JSONB, `created_at`. ~312 rows / 234 profiles.
  Latest per person: `DISTINCT ON (profile_id) ... ORDER BY profile_id, created_at DESC`.
- **`skin_analysis_scans`** — `profile_id`, `status='completed'`, `analysis_results` JSONB. Scores:
  `analysis_results#>>'{hd_acne,whole,ui_score}'` (and `hd_oiliness/hd_redness/hd_wrinkle/hd_moisture/
  hd_pore` ui_score, `{all,score}` for overall). Use `DISTINCT ON (profile_id)` latest.
- **`profiles`** — `id`, `email`, `birthday` (age = `date_part('year',age(birthday))`), `products`,
  **`sex`** (`MALE`/`FEMALE`) + **`sex_source`** (`quiz_web`|`quiz_infra`|`name_inferred`) — added 2026-06-26.
  Sex is now first-class here; for declared-only analysis filter `sex_source <> 'name_inferred'`.
- **`user_routines`** — assigned routine SKUs (products are **engine-assigned**, i.e. reverse-causal;
  `scanned_products` is a catalog with no profile link, `scanned_product_usage` is empty — so only
  *assigned* products are trackable, never *used*).

## Taxa parsing (critical)
- Genus: `lower(split_part(split_part(key,'g__',2),';',1))`
- Species: `split_part(key,'s__',2)` for keys `LIKE '%;s__%'`
- **Sum per (sample, taxon) across lineage variants** (a taxon can appear under multiple keys).
- **C. acnes lives under the OLD genus name `Propionibacterium`** in this pipeline (not
  Cutibacterium — the `cuti` column is all 0). Species token = `acnes`.
- **Resolution = species or species-GROUPS**, never strain/phylotype. Groups look like
  `capitis-caprae`, `argenteus-aureus`, `pseudogenitalium-tuberculostearicum`, `mitis-oralis-sanguinis`.
  → No *C. acnes* A/B/C phylotypes possible from 16S.
- **No fungi.** 16S is bacteria-only → Malassezia is invisible (would need ITS sequencing).
- **S. aureus can't be cleanly called.** Clean `aureus` appears in ~10 samples; mostly lumped as the
  `argenteus-aureus` group (~71 samples). Treat as an "aureus-group" flag, not a precise aureus call.
- **C. acnes ~68% mean dominance** → data is compositional. Use **CLR** (centered log-ratio) to avoid
  every correlation just tracking the C. acnes seesaw.

## Dedup (important — corrects an earlier inflation)
Many **infra** samples were re-uploaded into **web-app**, creating exact-duplicate `full_taxa`
vectors. **Dedup by taxa vector** (e.g. `md5(full_taxa::text)` or the key
`[diversity,richness,acnes,epidermidis,granulosum,capitis]`). Truth: **205 unique vectors**, only
**~16 real repeat-testers** (NOT 146). 2,414 distinct species across all samples.

## Test accounts to exclude
`/test|redteam|getastra|admintest|suiting-08|bbusermail|enrollme|example\.com|milieubio/i`

## Quiz handling
- **`value` vs `answer`:** always `coalesce(d->field->>'value', d->field->>'answer')`. (Missing this
  dropped ~half the responses once.)
- ~70 fields. **Single-selects** → ordinal-encode or one-hot. **Multi-selects** are stored as
  *stringified JSON arrays* under value (e.g. `["ECZEMA","ROSACEA"]`) → explode into **binary flags**.
- **Current-product / routine fields** (added to the explorer 2026-06-26, exploded to binary flags like the
  med_*/cond_* pattern): `products_used_regularly` → `prod_*` (cleanser, moisturizer, spf, serum, micellar,
  toner, exfoliant, medicated, eyecream, mask, faceoil); `exfoliation_types` → `act_*` (aha, bha, retinoid,
  physical); `routine_complexity_preference` → `routinecx` ordinal (0=minimalist→2=advanced). These are
  SELF-REPORTED current usage → **reverse-causal / confounded by indication** (people pick products for the
  skin they already have), so read correlations as associations, not product effects.
- High-signal fields that must not be dropped: `recent_medications` (ANTIBIOTICS, ACCUTANE),
  `diagnosed_conditions` (ECZEMA, ROSACEA, FUNGAL_ACNE, DERMATITIS, PSORIASIS), `antimicrobial_use_frequency`,
  `shower_habits` (ANTIBACTERIAL_HARSH_SOAPS), `animal_contact`, `hygiene_habits`, `family_history`.
- **Default = web-app `quiz_submissions`.** Only ~108 people have both quiz + microbiome. Fall back to
  infra **only** for basic lifestyle/age/sex when a sequenced person has no web quiz (rich fields are web-only).

## Age/sex coverage (CONSOLIDATED into web-app — 2026-06-26)
- Age + sex now live directly on web-app `profiles`, so `species_matrix.sql` is a single clean query —
  **no cross-project merge needed.** Coverage ~218/221 both. The earlier "no sex column / backfill from
  infra at build time" workflow is obsolete.
- What was done (all on web-app, fill-NULL-only, reversible — see `backups/`):
  1. **birthday**: backfilled 95 cohort profiles from infra `profiles.birthday` (123→218 cohort, 352→447 global).
  2. **sex column added** + backfilled: `quiz_web` (declared, this DB) → `quiz_infra` (declared, legacy) →
     `name_inferred` (24 cohort guesses from first_name). 3 cohort rows left NULL (ambiguous/test).
- Revert artifacts: `backups/REVERT_birthday_backfill_2026-06-26.sql`, `backups/REVERT_sex_columns_2026-06-26.sql`.
- **Trust note:** `name_inferred` sex is a heuristic guess — exclude it (`sex_source <> 'name_inferred'`)
  for anything where a wrong sex call matters.

## Stats conventions (all client-side JS — no server, no Python needed at runtime)
- **Presence** threshold default **≥0.1%** (sparse rare strains → presence/absence is the right unit).
- **CLR:** `ln(x + 0.01) − mean(ln over the 20 curated species + an "other" bucket)`; pseudocount 0.01.
- **Tests:** Spearman ρ (rankdata + Pearson-on-ranks, p via incomplete beta) for anything
  continuous/ordinal; **Fisher exact + φ** for binary×binary. **Benjamini-Hochberg FDR** across all
  pairs in a view. Guards: **min n = 20**, **≥3 in the minority class** for any binary.
- **Multivariate:** OLS with **standardized β** (Gauss-Jordan inverse of XʹX, tiny ridge 1e-8).
  Report focus predictor **unadjusted vs adjusted** for age + sex (+ chosen covariates); auto-drop
  zero-variance covariates; flag collinearity. Verdict logic: holds / attenuated / confounded.
- Verify direction/magnitude of headline signals in SQL (`corr()`, group means) before trusting JS.

## Deliverables (in this folder)
- **`milieu_signal_explorer.html`** — CURRENT main tool. Species-level curated clinical strains,
  full quiz, presence/CLR/raw toggle, Signal-finder table, heatmap (triangle-masked for same-domain),
  **Multivariate** regression tab, Method & caveats. Embedded data: `#SPECIES` (221 rows) + `#QUIZ`
  (~107 rows) in `<script type="text/plain">` blocks; everything computed in JS.
- Earlier iterations (superseded, kept for reference): `milieu_explorer.html`,
  `milieu_taxa_explorer.html`, `milieu_unified.html`, `milieu_samples_master.html`,
  `milieu_dashboard.html`.

## Build pattern (how to regenerate the embedded data)
1. Run the SQL in `sql/` via the Supabase MCP (web-app project).
2. SQL emits **one compact CSV cell** via `string_agg(concat_ws(...))` — this dodges the MCP result-size
   limit. If a result still exceeds the limit, split into buckets with `ntile(n) OVER (...)` and run per bucket.
3. Paste the CSV into the matching `<script type="text/plain" id="SPECIES|QUIZ">` block in the HTML.
4. Open the HTML by double-click. No build step, no dependencies.
(If you'd rather automate: a `build.py` that reads exported CSVs and injects them into a template
would work since Python is available locally — not yet built.)

## Headline findings so far
- **Strain×strain co-occurrence** is the strong, reliable story (compositional; C. acnes ↔ Staph /
  diversity negative). Use CLR + the co-occurrence preset.
- **Antibiotics → lower diversity** (2.33 vs 2.73) and **eczema dx → lower diversity** (2.30 vs 2.74);
  both **survive age/sex adjustment** (each is ~uncorrelated with age/sex).
- **Lifestyle → microbiome is mostly null** — that's a real finding, not a bug, given ~100 people and
  coarse categorical answers.

## Good next steps
- Fold infra cohort into the rich quiz fields (currently web-only) to lift n.
- Logistic regression for *presence* outcomes (current multivariate is OLS / continuous outcomes only).
- Bring in weather + longitudinal once collection is consistent.
