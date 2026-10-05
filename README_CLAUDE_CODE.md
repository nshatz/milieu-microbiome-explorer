# Porting this project to Claude Code

Everything Claude Code needs is in this folder. Three steps.

## 1. Put the folder somewhere permanent and (optionally) make it a git repo
```bash
mkdir -p ~/milieu-microbiome && cp -R ./* ~/milieu-microbiome/   # include CLAUDE.md, mcp.json, sql/, *.html
cd ~/milieu-microbiome
mv mcp.json .mcp.json        # Claude Code reads project MCP servers from .mcp.json (leading dot)
git init && git add -A && git commit -m "Milieu microbiome explorer + project memory"   # optional
```

## 2. Connect Supabase (read-only)
- Get a **personal access token**: Supabase dashboard → account → Access Tokens.
- A `.mcp.json` template is included; paste your token into `SUPABASE_ACCESS_TOKEN`.
- Or, get the token from `~/milieu-crm/.env` if you have access: `grep SUPABASE_SERVICE_ROLE_KEY ~/milieu-crm/.env`
- The config uses `--read-only`, so Claude Code can query all your projects but **cannot modify** them.
  (No `--project-ref` is set, so all three projects are reachable; pass one if you want to scope it.)
- Requires Node/npx installed (`node -v`). The token is a secret — `.mcp.json` is git-ignored by
  default patterns; double-check before committing, or keep the token in your shell env instead.

## 3. Open Claude Code in the folder
```bash
cd ~/milieu-microbiome
claude
```
- It **auto-loads `CLAUDE.md`** as project memory (all the schema, conventions, and corrections).
- Run **`/mcp`** to confirm the `supabase` server connected; approve it if prompted.
- Try: *"Using CLAUDE.md, regenerate the SPECIES data block in milieu_signal_explorer.html from sql/species_matrix.sql."*

## What's in here
- **`CLAUDE.md`** — project memory: the hard rules (read-only, raw analytics, full taxa), Supabase
  project refs, table/column map, taxa-parsing gotchas (C. acnes = Propionibacterium, species-groups,
  no fungi, aureus-group), dedup logic, the stats conventions, and the build pattern.
- **`mcp.json`** — Supabase MCP config (rename to `.mcp.json`).
- **`sql/species_matrix.sql`** — regenerates the `#SPECIES` data block.
- **`sql/quiz_full.sql`** — regenerates the `#QUIZ` data block (bucket it if the result is too big).
- **`sql/explore_and_verify.sql`** — quiz-schema dump, species prevalence, dedup counts, signal checks.
- **`milieu_signal_explorer.html`** — the current tool (open by double-click). Other `milieu_*.html`
  are earlier iterations.

## The build loop (no server, no runtime deps)
1. Ask Claude Code to run a `sql/*.sql` query through the Supabase MCP.
2. It returns one compact CSV cell.
3. Paste/replace the matching `<script type="text/plain" id="SPECIES|QUIZ">` block in the HTML.
4. Double-click the HTML — all stats run client-side in the browser.

## Tips for Claude Code specifically
- Keep `CLAUDE.md` updated as conventions evolve — it's the single source of truth the agent reads
  every session. Add new findings/decisions there.
- `claude-code-guide` questions (hooks, slash commands, settings) are best asked inside Claude Code.
- If you later want a one-command rebuild, ask it to write a `build.py` that reads exported CSVs and
  injects them into the HTML template (Python is available locally; we kept runtime JS-only on purpose).
