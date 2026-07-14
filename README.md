# docker-bundler-yarn-cache

Test bed for running **two Rails apps** (Fred and George) in a shared Docker development environment with a **host-mounted Bundler gem cache** and Yarn cache.

## Layout

```
.
├── .bundle/config          # Root BUNDLE_PATH → .cache/bundle
├── .cache/
│   ├── bundle/             # Shared gem *install* tree (host + containers)
│   ├── rubygems/           # Shared gem *download* cache (.gem files)
│   └── yarn/               # Shared Yarn download cache
├── .yarnrc.yml             # Yarn cacheFolder → .cache/yarn
├── package.json            # Yarn workspaces (fred + george)
├── yarn.lock
├── bin/setup               # Fresh clone: install + warm download caches
├── bin/docker-app          # Container entry: prefer local caches
├── fred/                   # Rails 8 + Hotwire app (port 3000)
│   ├── app/javascript/controllers/hello_controller.js
│   └── test/javascript/    # Vitest + jsdom Stimulus unit tests
├── george/                 # Rails 8 + Hotwire app (port 3001)
├── Dockerfile              # Arch Linux + `dev` user + mise
├── docker-compose.yml
├── Gemfile                 # Root tooling: rails, rubocop
├── mise.toml               # Pinned Ruby / Node / Yarn
├── AGENTS.md               # Guidance for coding agents
└── README.md
```

## Stack

| Piece | Version / notes |
|-------|-----------------|
| Ruby | 4.0.5 via [mise](https://mise.jdx.dev) |
| Rails | ~> 8.1 (8.1.3) |
| Hotwire | Turbo + Stimulus (importmap) |
| Node / Yarn | 25.7.0 / 4.16.0 via mise |
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

1. Trust/install tools from `mise.toml` (Ruby, Node, Yarn)
2. Create `.cache/bundle`, `.cache/rubygems`, and `.cache/yarn`
3. `bundle install` for root, Fred, and George into `.cache/bundle`
4. `bundle cache --all-platforms` → package `.gem` files into `.cache/rubygems`
5. `yarn install` (+ offline verify) → downloads into `.cache/yarn`, link `node_modules`
6. `bin/rails db:prepare` (and clear log/tmp) for both apps

Options: `bin/setup --help` (e.g. `--reset`, `--docker-build`, `--skip-js`, `--skip-cache`).

### Host-warmed caches → Docker

Run setup **on the host before** starting containers so downloads are already local:

```bash
bin/setup
docker compose up fred george
```

| Cache | Role |
|-------|------|
| `.cache/rubygems` | Packaged gems (`bundle cache`); `bin/docker-app` runs `bundle install --local` first |
| `.cache/bundle` | Installed gem tree (extensions may rebuild inside the container) |
| `.cache/yarn` | Yarn package tarballs; `--immutable-cache` preferred when `node_modules` is missing |
| `node_modules` | Linked on the host and bind-mounted into the container |

Containers use `bin/docker-app`: prefer local caches, fall back to the network only on a cache miss.

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
yarn install          # once, from repo root
yarn test             # fred + george
yarn test:fred        # one workspace
yarn workspace fred test:watch
```

Tests live in `fred|george/test/javascript/**/*.test.js` and import controllers from `app/javascript/controllers/`.

## Docker

Build and start both apps:

```bash
# Optional: match host UID/GID (defaults to 1000)
cp .env.example .env

docker compose build
docker compose up fred george
```

- **Fred:** http://localhost:3000  
- **George:** http://localhost:3001  
- Health checks: `/up` on each app  

Interactive shell in the Arch image:

```bash
docker compose --profile dev run --rm dev
```

### Volume mounts

| Host path | Container path | Purpose |
|-----------|----------------|---------|
| `.` | `/workspace` | Full monorepo (includes `node_modules`) |
| `.cache/bundle` | `/workspace/.cache/bundle` | Bundler install tree |
| `.cache/rubygems` | `/workspace/.cache/rubygems` | Packaged `.gem` download cache |
| `.cache/yarn` | `/workspace/.cache/yarn` | Yarn download cache |
| `fred` | `/workspace/fred` | Fred app |
| `george` | `/workspace/george` | George app |

Compose sets `BUNDLE_PATH`, `BUNDLE_CACHE_PATH`, and `YARN_CACHE_FOLDER` to those absolute paths. App `.bundle/config` uses `../.cache/bundle` and `../.cache/rubygems` on the host.

**Native extensions:** host-built native gems may not load in the container. `bin/docker-app` reinstalls from `.cache/rubygems` with `bundle install --local` (no re-download when the cache is complete), compiling extensions inside the image as needed.

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
