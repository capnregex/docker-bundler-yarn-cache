# docker-bundler-yarn-cache

Test bed for running **two Rails apps** (Fred and George) in a shared Docker development environment with a **host-mounted Bundler gem cache** and Yarn cache.

## Layout

```
.
├── .bundle/config          # Root BUNDLE_PATH → .cache/bundle
├── .cache/
│   ├── bundle/             # Shared gem install path (host + containers)
│   └── yarn/               # Shared Yarn cache
├── fred/                   # Rails 8 app (port 3000)
├── george/                 # Rails 8 app (port 3001)
├── Dockerfile              # Arch Linux + `dev` user + mise
├── docker-compose.yml
├── Gemfile                 # Root tooling: rails, rubocop
├── mise.toml               # Pinned Ruby / Node versions
├── AGENTS.md               # Guidance for coding agents
└── README.md
```

## Stack

| Piece | Version / notes |
|-------|-----------------|
| Ruby | 4.0.5 via [mise](https://mise.jdx.dev) |
| Rails | ~> 8.1 (8.1.3) |
| RuboCop | ~> 1.88 (root tooling) |
| Base image | `archlinux:latest` |
| Container user | `dev` (UID/GID 1000 by default) |

## Local (host) setup

Requires Ruby via mise (or compatible), Bundler, and Docker Compose.

```bash
# Trust and install pinned tools
mise trust
mise install

# Shared gem path is already configured in .bundle/config
bundle install                 # root: rails + rubocop → .cache/bundle
(cd fred && bundle install)
(cd george && bundle install)

# Run apps on the host
(cd fred && bin/rails server -p 3000)
(cd george && bin/rails server -p 3001)
```

Bundler installs for both apps resolve into **`.cache/bundle`**, so gems are shared across Fred, George, and the root tooling Gemfile.

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
| `.` | `/workspace` | Full monorepo |
| `.cache/bundle` | `/workspace/.cache/bundle` | Shared Bundler path |
| `.cache/yarn` | `/workspace/.cache/yarn` | Shared Yarn cache |
| `fred` | `/workspace/fred` | Fred app |
| `george` | `/workspace/george` | George app |

`BUNDLE_PATH` and `YARN_CACHE_FOLDER` are set in Compose so container installs write into the same host caches you use locally.

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
