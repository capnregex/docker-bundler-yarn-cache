# Agent guide — docker-bundler-yarn-cache

Instructions for AI coding agents and automated tools working in this repository.

## Purpose

This monorepo is a **development test bed** for:

- Two independent Rails 8 apps: **`fred/`** and **`george/`**
- A **shared Bundler path** at **`.cache/bundle`**
- A **shared Yarn cache** at **`.cache/yarn`**
- An **Arch Linux** Docker image with a **`dev`** user and **mise** for Ruby/Node
- Docker Compose bind mounts that keep host and container caches in sync

Prefer changes that preserve this multi-app + shared-cache design over collapsing apps into one tree.

## Tooling pins

| Tool | Source of truth |
|------|-----------------|
| Ruby / Node | `mise.toml` |
| Root gems (rails, rubocop, …) | root `Gemfile` / `Gemfile.lock` |
| App gems | `fred/Gemfile`, `george/Gemfile` (+ lockfiles) |
| Bundler path | `.bundle/config` and `fred|george/.bundle/config` → `.cache/bundle` |
| Compose / image | `docker-compose.yml`, `Dockerfile` |

Do not bump Ruby or Rails casually without updating `mise.toml`, both apps’ `.ruby-version` / Gemfiles, and verifying `bundle install` into `.cache/bundle`.

## Bundle rules

1. **Always** install gems into `.cache/bundle` (already configured via `.bundle/config`).
2. Run app commands from the app directory so the correct Gemfile is used:
   - `cd fred && bundle exec rails …`
   - `cd george && bundle exec rails …`
3. Root-level `bundle exec` is for **tooling only** (e.g. generators, RuboCop from the root Gemfile).
4. After changing any Gemfile, run `bundle install` for that Gemfile and commit the lockfile. Do **not** commit `.cache/bundle` contents.
5. App-level config uses a relative path:

   ```yaml
   # fred/.bundle/config and george/.bundle/config
   BUNDLE_PATH: "../.cache/bundle"
   ```

## Docker rules

1. Image user is **`dev`**, not root. Avoid Dockerfile steps that force root-owned files under `/workspace` after `USER dev`.
2. Prefer Compose services `fred` / `george` / `dev` over ad-hoc `docker run` unless debugging the image.
3. Keep mounts for `.cache/bundle`, `.cache/yarn`, `fred`, and `george` intact.
4. Match host UID/GID with `DEV_UID` / `DEV_GID` build args when bind-mount permission issues appear.
5. Container `BUNDLE_PATH` must remain `/workspace/.cache/bundle`.
6. **Never** set `BUNDLE_APP_CONFIG` to the monorepo root `.bundle` while running app Gemfiles. That makes Bundler apply root `path: ".cache/bundle"` relative to the app root and creates stray `fred/.cache/bundle` / `george/.cache/bundle` trees. Each app keeps its own `.bundle/config` with `path: "../.cache/bundle"`.
7. Do not commit per-app `.cache/` directories; only the monorepo `.cache/bundle` (gitignored contents) is shared.

## Rails apps (Fred & George)

- SQLite in development; no external DB service required.
- Tailwind via `tailwindcss-rails`; importmap + Hotwire (Turbo/Stimulus).
- Default routes: `root "home#index"`, health at `/up`.
- Prefer symmetric changes: if you add a concern, route, or gem to one app for demo purposes, either mirror it in the other or document the intentional difference in the PR/commit message.

## What to commit

**Commit:** source, Gemfiles/lockfiles, Docker/Compose, `mise.toml`, docs (README, AGENTS.md), app config (except secrets).

**Do not commit:**

- `.cache/bundle/**`, `.cache/yarn/**`
- `**/config/master.key`, credential keys
- `**/log/**`, `**/tmp/**`, `**/node_modules/**`
- Nested `.git` directories under `fred/` or `george/` (this is a single monorepo)

## Common tasks

```bash
# Install all gems into shared cache
bundle install
(cd fred && bundle install)
(cd george && bundle install)

# Boot both apps in Docker
docker compose up --build fred george

# Shell in Arch+mise image
docker compose --profile dev run --rm dev

# Lint (root RuboCop)
bundle exec rubocop

# App console
(cd fred && bin/rails console)
```

## Safety

- Do not force-push or rewrite published history unless the user asks.
- Do not delete `.cache` wholesale without regenerating via `bundle install` afterward.
- Do not check in production secrets or overwrite `config/master.key` without user confirmation.
