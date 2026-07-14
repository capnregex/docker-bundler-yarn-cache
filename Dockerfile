# Arch Linux development image for Fred & George Rails apps.
# Provides a non-root `dev` user with mise-managed Ruby/Node matching mise.toml.

FROM archlinux:latest

ARG DEV_UID=1000
ARG DEV_GID=1000
ARG MISE_VERSION=v2026.5.15

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    MISE_DATA_DIR=/home/dev/.local/share/mise \
    MISE_CONFIG_DIR=/home/dev/.config/mise \
    MISE_CACHE_DIR=/home/dev/.cache/mise \
    MISE_RUBY_COMPILE=false \
    PATH=/home/dev/.local/bin:/home/dev/.local/share/mise/shims:${PATH} \
    BUNDLE_PATH=/workspace/.cache/bundle \
    BUNDLE_APP_CONFIG=/workspace/.bundle \
    YARN_CACHE_FOLDER=/workspace/.cache/yarn \
    HOME=/home/dev \
    WORKSPACE=/workspace

# Base packages + build deps for native gem extensions and common tooling.
RUN pacman -Syu --noconfirm \
    && pacman -S --noconfirm \
        base-devel \
        git \
        curl \
        wget \
        unzip \
        which \
        openssh \
        ca-certificates \
        libyaml \
        libffi \
        openssl \
        zlib \
        sqlite \
        shared-mime-info \
        tzdata \
        sudo \
        bash \
        less \
        vim \
    && pacman -Scc --noconfirm \
    && rm -rf /var/cache/pacman/pkg/*

# Non-root dev user (UID/GID overridable to match host bind mounts).
RUN groupadd --gid "${DEV_GID}" dev \
    && useradd --uid "${DEV_UID}" --gid dev --create-home --shell /bin/bash dev \
    && echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev \
    && chmod 0440 /etc/sudoers.d/dev \
    && mkdir -p /workspace \
    && chown -R dev:dev /workspace /home/dev

USER dev
WORKDIR /workspace

# Install mise (https://mise.jdx.dev) for the dev user.
RUN curl -fsSL https://mise.run | MISE_VERSION="${MISE_VERSION}" sh \
    && echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bashrc \
    && echo 'eval "$(~/.local/bin/mise activate bash)"' >> ~/.bash_profile

# Copy only version pins first for better layer caching.
COPY --chown=dev:dev mise.toml /workspace/mise.toml

# Trust project config and install pinned Ruby + Node.
RUN ~/.local/bin/mise trust /workspace/mise.toml \
    && ~/.local/bin/mise install \
    && ~/.local/bin/mise reshim \
    && ruby -v \
    && node -v \
    && gem install bundler --no-document

# Default to an interactive shell; compose overrides command per service.
CMD ["bash"]
