# docker-bundler-yarn-cache

Test bed for running **two Rails apps** (Fred and George) in a shared Docker development environment with a **host-mounted Bundler gem cache** and **classic Yarn 1.x** offline mirror.

> **Branch note:** this branch (`classic-yarn-1`) uses **Yarn 1.22.x** (classic). The `master` line may use Yarn Berry (2+).

## Layout

```
.
├── config/
│   ├── cache-layout.env    # SSOT: relative cache paths
│   └── bundler-flags.yml   # SSOT: Bundler behavior (symlinked as .bundle/config)
├── .bundle/config → config/bundler-flags.yml
├── .cache/                 # Materialized caches (names from cache-layout.env)
├── .yarnrc                 # Classic Yarn 1 offline-mirror (from layout via setup)
├── package.json            # Classic Yarn workspaces (fred + george)
├── yarn.lock               # Classic Yarn v1 lockfile
├── bin/setup               # Fresh clone: install + warm download caches
├── bin/cache-env           # Export absolute BUNDLE_* / YARN_* from layout
├── bin/compose             # docker compose --env-file config/cache-layout.env
├── bin/docker-app          # Container entry: prefer local caches
├── fred/                   # Rails 8 + Hotwire app (port 3000)
│   ├── app/javascript/controllers/hello_controller.js
│   └── test/javascript/    # Vitest + jsdom Stimulus unit tests
├── george/                 # Rails 8 + Hotwire app (port 3001)
├── Dockerfile              # Arch Linux + `dev` user + mise
├── docker-compose.yml
├── Gemfile                 # Root tooling: rails, rubocop
├── mise.toml               # Pinned Ruby / Node / Yarn 1.22.22
├── AGENTS.md               # Guidance for coding agents
└── README.md
```

## Stack

| Piece | Version / notes |
|-------|-----------------|
| Ruby | 4.0.5 via [mise](https://mise.jdx.dev) |
| Rails | ~> 8.1 (8.1.3) |
| Hotwire | Turbo + Stimulus (importmap) |
| Node / Yarn | 25.7.0 / **1.22.22 classic** via mise |
| JS tests | Vitest + jsdom (Stimulus controllers) |
| RuboCop | ~> 1.88 (root tooling) |
| Base image | `archlinux:latest` |
| Container user | `dev` (UID/GID 1000 by default) |

## Local (host) setup

Requires [mise](https://mise.jdx.dev) (recommended) or compatible Ruby / Node / Yarn on `PATH`, plus Docker Compose if you use containers.

After a fresh clone:

```bash
bin/setup
```

That script is idempotent and will:

1. Trust/install tools from `mise.toml` (Ruby, Node, **Yarn 1.22**)
2. Create `.cache/bundle`, `.cache/rubygems`, `.cache/yarn`, `.cache/yarn-cache`
3. `bundle install` for root, Fred, and George into `.cache/bundle`
4. `bundle cache --all-platforms` → package `.gem` files into `.cache/rubygems`
5. Classic `yarn install` → fill **yarn-offline-mirror** (`.cache/yarn`) + link `node_modules`
6. Verify with `yarn install --frozen-lockfile --offline`
7. `bin/rails db:prepare` (and clear log/tmp) for both apps

Options: `bin/setup --help` (e.g. `--reset`, `--docker-build`, `--skip-js`, `--skip-cache`).

### Host-warmed caches → Docker

Run setup **on the host before** starting containers so downloads are already local:

```bash
bin/setup
bin/compose up fred george    # prefer bin/compose over plain docker compose
```

| Cache | Role |
|-------|------|
| `.cache/rubygems` | Packaged gems; `bundle install --local` first in the container |
| `.cache/bundle` | Installed gem tree |
| `.cache/yarn` | Classic offline-mirror tarballs |
| `.cache/yarn-cache` | Classic `YARN_CACHE_FOLDER` |
| `node_modules` | Host install, bind-mounted via monorepo mount |

**Where settings live (DRY)**

| Setting | Single source |
|---------|----------------|
| Relative cache dirs | **`config/cache-layout.env`** |
| Absolute paths on host | **`bin/cache-env`** (prefix layout with monorepo root) |
| Absolute paths in Docker | **`docker-compose.yml`** `x-cache-env` → `/workspace/${CACHE_*}` via **`bin/compose`** |
| Bundler flags (non-path) | **`config/bundler-flags.yml`** (symlinked as each `.bundle/config`) |
| Yarn offline-mirror | **`.yarnrc`** generated from layout (`bin/cache-env --write-yarnrc`) |
| `PORT` / `HOME` | Compose only (context-dependent) |

```bash
# Run apps on the host
(cd fred && bin/rails server -p 3000)
(cd george && bin/rails server -p 3001)
```

Bundler installs for both apps resolve into **`.cache/bundle`**, so gems are shared across Fred, George, and the root tooling Gemfile.

## Hotwire + Stimulus

Both apps load **Turbo** and **Stimulus** through importmap (`config/importmap.rb`, `app/javascript/application.js`). Controllers live under `app/javascript/controllers/` and are eager-loaded by `controllers/index.js`.

Each home page mounts a **`hello`** Stimulus controller:

```html
<div data-controller="hello" data-hello-name="Fred">
  <p data-hello-target="output">Loading…</p>
</div>
```

On connect it greets with `Hello, Fred!` (or `Hello World!` when no name is set).

## JavaScript unit tests

Stimulus controllers are tested with **Node + Vitest + jsdom** (browser packages still ship via importmap; npm is for tests only).

```bash
yarn install          # once, from repo root (classic 1.x workspaces)
yarn test             # fred + george (yarn workspaces run test)
yarn test:fred        # one workspace
yarn workspace fred test --watch
```

Tests live in `fred|george/test/javascript/**/*.test.js` and import controllers from `app/javascript/controllers/`.

## Docker

Build and start both apps:

```bash
# Optional: match host UID/GID (defaults to 1000)
cp .env.example .env

bin/compose build
bin/compose up fred george
```

- **Fred:** http://localhost:3000  
- **George:** http://localhost:3001  
- Health checks: `/up` on each app  

Interactive shell:

```bash
bin/compose --profile dev run --rm dev
```

### Volume mounts

| Host path | Container path | Purpose |
|-----------|----------------|---------|
| `.` | `/workspace` | Full monorepo (apps, `.cache`, `node_modules`, config) |

One bind is enough; subpaths are not re-mounted. Cache locations still come from **`config/cache-layout.env`** → env vars.

**Native extensions:** host-built native gems may not load in the container. `bin/docker-app` reinstalls from `BUNDLE_CACHE_PATH` with `bundle install --local` when needed.

## RuboCop

From the repo root (uses the local bundle):

```bash
bundle exec rubocop fred george
```

Each app also has `bin/rubocop` and a Rails-generated `.rubocop.yml`.

## Design notes

1. **One gem tree** — `.cache/bundle` is the single install location for root, Fred, and George. Faster installs and easy inspection of what Bundler materializes.
2. **mise everywhere** — Host and image pin the same Ruby/Node via `mise.toml`.
3. **Arch + non-root** — Development image is Arch-based with a passwordless-sudo `dev` user for realistic local permissions on bind mounts.
4. **Two apps** — Fred and George are intentionally separate Rails trees so multi-app compose, cache sharing, and agent workflows can be exercised.

## License

Private test bed; no license asserted.
