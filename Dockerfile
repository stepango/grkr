# syntax=docker/dockerfile:1.7
# grkr runtime image — supervisor + workers for GitHub/Linear issue automation.
# Easy path: docker compose up  |  helm install grkr ./deploy/helm/grkr

ARG NODE_VERSION=22
ARG GLEAM_VERSION=1.16.0
ARG GH_CLI_VERSION=2.74.1

FROM node:${NODE_VERSION}-bookworm-slim

ARG GLEAM_VERSION
ARG GH_CLI_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    GRKR_HOME=/opt/grkr \
    GRKR_GLEAM_PROJECT_ROOT=/opt/grkr \
    LANG=C.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      curl \
      git \
      jq \
      openssh-client \
      util-linux \
      coreutils \
      findutils \
      grep \
      sed \
      gawk \
      tar \
      gzip \
      xz-utils \
      procps \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) gh_arch=amd64 ;; \
      arm64) gh_arch=arm64 ;; \
      *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/gh.deb \
      "https://github.com/cli/cli/releases/download/v${GH_CLI_VERSION}/gh_${GH_CLI_VERSION}_linux_${gh_arch}.deb"; \
    dpkg -i /tmp/gh.deb; \
    rm -f /tmp/gh.deb; \
    gh --version

# Gleam (musl static linux binary → /usr/local/bin/gleam)
RUN set -eux; \
    arch="$(uname -m)"; \
    case "$arch" in \
      x86_64) gleam_arch=x86_64-unknown-linux-musl ;; \
      aarch64) gleam_arch=aarch64-unknown-linux-musl ;; \
      *) echo "unsupported arch: $arch" >&2; exit 1 ;; \
    esac; \
    tmp="$(mktemp -d)"; \
    curl -fsSL \
      "https://github.com/gleam-lang/gleam/releases/download/v${GLEAM_VERSION}/gleam-v${GLEAM_VERSION}-${gleam_arch}.tar.gz" \
      | tar -xz -C "$tmp"; \
    gleambin="$(find "$tmp" -type f -name gleam | head -n1)"; \
    install -m 0755 "$gleambin" /usr/local/bin/gleam; \
    rm -rf "$tmp"; \
    gleam --version

WORKDIR /opt/grkr

COPY gleam.toml manifest.toml package.json ./
COPY src ./src
COPY bin ./bin
COPY scripts ./scripts
COPY deploy ./deploy

# Pre-fetch deps + compile JS target so cold start is fast
RUN gleam deps download \
 && gleam build \
 && chmod +x bin/grkr bin/*.sh bin/lib/* deploy/docker/entrypoint.sh \
 && git config --system --add safe.directory '*' \
 && useradd --create-home --shell /bin/bash --uid 10001 grkr \
 && mkdir -p /workspace /home/grkr/.config/gh /home/grkr/.linear \
 && chown -R grkr:grkr /opt/grkr /workspace /home/grkr

USER grkr
WORKDIR /workspace

ENV HOME=/home/grkr \
    GRKR_ROOT=/workspace \
    GRKR_CONFIG_FILE=/workspace/.grkr/config.sh \
    GRKR_GLEAM_PROJECT_ROOT=/opt/grkr \
    GRKR_HOME=/opt/grkr \
    PATH="/opt/grkr/bin:/usr/local/bin:${PATH}"

VOLUME ["/workspace"]

ENTRYPOINT ["/opt/grkr/deploy/docker/entrypoint.sh"]
CMD ["supervisor"]
