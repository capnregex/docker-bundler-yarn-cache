# Agent guide — docker-bundler-yarn-cache

Instructions for AI coding agents and automated tools working in this repository.

## Purpose

This monorepo is a **development test bed** for:

- Two independent Rails 8 apps: **`fred/`** and **`george/`**
- A **shared Bundler install path** at **`.cache/bundle`**
- A **shared Rubygems download cache** at **`.cache/rubygems`** (host `bundle cache`)
- **Classic Yarn 1.22.x** (this branch): offline mirror at **`.cache/yarn`**, cache folder at **`.cache/yarn-cache`**
- Host `bin/setup` warms caches; container `bin/docker-app` prefers them before network
- An **Arch Linux** Docker image with a **`dev`** user and **mise** for Ruby/Node/Yarn 1
- Docker Compose bind mounts that keep host and container caches in sync

Prefer changes that preserve this multi-app + shared-cache design over collapsing apps into one tree.

## Tooling pins

| Tool | Source of truth |
|------|-----------------|
| Ruby / Node / Yarn | `mise.toml` |
| Root gems (rails, rubocop, …) | root `Gemfile` / `Gemfile.lock` |
| App gems | `fred/Gemfile`, `george/Gemfile` (+ lockfiles) |
| JS workspaces | root `package.json`, classic `yarn.lock`, **`.yarnrc`** (Yarn 1) |
| App JS test deps | `fred/package.json`, `george/package.json` |
| Cache path SSOT | `config/cache-layout.env` (relative dirs only) |
| Host absolute paths | `bin/cache-env` |
| Container absolute paths | `docker-compose.yml` `x-cache-env` + **`bin/compose`** |
| Bundler flags SSOT | `config/bundler-flags.yml` (symlinked to each `.bundle/config`) |
| Yarn offline-mirror | `.yarnrc` from `bin/cache-env --write-yarnrc` |
| Host bootstrap | `bin/setup` |
| Container app entry | `bin/docker-app` |

Do not bump Ruby or Rails casually without updating `mise.toml`, both apps’ `.ruby-version` / Gemfiles, and verifying `bundle install` into `.cache/bundle`.

## Bundle rules

1. Change cache **directory names** only in **`config/cache-layout.env`**, then run `bin/setup` (or `bin/cache-env --write-yarnrc`).
2. Change Bundler **flags** only in **`config/bundler-flags.yml`** (symlinks pick it up).
3. Always `source bin/cache-env` on the host before `bundle` / app commands.
4. Always use **`bin/compose`** instead of raw `docker compose` so layout env is loaded.
5. Run app commands from the app directory with the correct Gemfile:
   - `source bin/cache-env && cd fred && bundle exec rails …`
6. After Gemfile changes: `bundle install` + `bundle cache --all-platforms`; commit lockfiles, not `.cache/*`.

## Docker rules

1. Image user is **`dev`**, not root. Avoid Dockerfile steps that force root-owned files under `/workspace` after `USER dev`.
2. Prefer Compose services `fred` / `george` / `dev` over ad-hoc `docker run` unless debugging the image.
3. Keep mounts for `.cache/bundle`, `.cache/yarn`, `fred`, and `george` intact.
4. Match host UID/GID with `DEV_UID` / `DEV_GID` build args when bind-mount permission issues appear.
5. **Never** set `BUNDLE_APP_CONFIG` to the monorepo root while running app Gemfiles.
6. Do not commit `.cache/**` contents (only `.gitkeep` placeholders).
7. Preferred flow: `bin/setup` → `bin/compose up fred george`.
8. Do **not** introduce Yarn Berry on this branch.
9. Do **not** re-duplicate path strings in app configs; layout + flags files only.

## Rails apps (Fred & George)

- SQLite in development; no external DB service required.
- Tailwind via `tailwindcss-rails`; importmap + Hotwire (Turbo/Stimulus).
- Stimulus controllers: `app/javascript/controllers/*_controller.js` (e.g. `hello_controller.js`).
- JS unit tests: Vitest + jsdom under `test/javascript/`; run via Yarn workspaces from the monorepo root.
- Browser JS stays on importmap; `@hotwired/stimulus` in `package.json` is for Node tests only—keep versions roughly aligned with the importmap pin.
- Default routes: `root "home#index"`, health at `/up`.
- Prefer symmetric changes: if you add a concern, route, gem, or Stimulus controller to one app for demo purposes, either mirror it in the other or document the intentional difference in the PR/commit message.

## Yarn / JS test rules (classic 1.x)

1. Install from the **repo root**: `yarn install` (classic workspaces + offline mirror).
2. Expect `yarn --version` → `1.22.x` (mise pin). Setup exits if major ≠ 1.
3. Run tests with `yarn test`, `yarn test:fred`, or `yarn test:george`.
4. Commit classic `yarn.lock` and workspace `package.json` files; do **not** commit `node_modules`, `.cache/yarn`, or `.cache/yarn-cache`.
5. Prefer classic flags: `--frozen-lockfile`, `--offline`, `--prefer-offline` (not Berry `--immutable*`).
6. New Stimulus controllers should ship with a Vitest example under `test/javascript/controllers/`.

## What to commit

**Commit:** source, Gemfiles/lockfiles, `package.json` / `yarn.lock`, Docker/Compose, `mise.toml`, docs (README, AGENTS.md), app config (except secrets).

**Do not commit:**

- `.cache/bundle/**`, `.cache/rubygems/**`, `.cache/yarn/**`
- `**/config/master.key`, credential keys
- `**/log/**`, `**/tmp/**`, `**/node_modules/**`
- Nested `.git` directories under `fred/` or `george/` (this is a single monorepo)

## Common tasks

```bash
# Fresh clone / re-bootstrap (mise, gems, yarn, db:prepare)
bin/setup
bin/setup --docker-build   # also build Arch image
bin/setup --help

# Boot both apps in Docker
bin/compose up --build fred george

# Shell in Arch+mise image
bin/compose --profile dev run --rm dev

# Lint (root RuboCop)
bundle exec rubocop

# JS (Stimulus controller unit tests)
yarn test

# App console
(cd fred && bin/rails console)
```

## Safety

- Do not force-push or rewrite published history unless the user asks.
- Do not delete `.cache` wholesale without regenerating via `bundle install` afterward.
- Do not check in production secrets or overwrite `config/master.key` without user confirmation.
