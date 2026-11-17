# syntax=docker/dockerfile:1
#
# DeepSeek Harness rootfs for Droidspaces (Android containers).
#
# The image carries the complete DeepSeek Harness repository with its
# dependencies installed, the published DeepSeek Harness command, and an init
# that publishes both when the container starts:
#
#   - the Web UI on port 3080
#   - the repository over git on port 9418
#   - the repository over HTTP on port 8080
#
# The build context is the repository root, so every template copies the same
# scripts from droidspaces/scripts/. The export stage holds the finished root
# filesystem, and the build writes that stage as a flat tarball.

FROM node:24.9.0-bookworm-slim AS runtime

ARG DSH_REPO_URL=https://github.com/camillanapoles/deepseek-harness.git
ARG DSH_REF=master
ARG DSH_CLI_VERSION=0.2.2-rc.3

LABEL droidspaces.name="DeepSeek Harness 0.2.2-rc.3"
LABEL droidspaces.distro="DeepSeek Harness"
LABEL droidspaces.description="DeepSeek Harness agent harness with the complete repository installed and configured, the published dsh command, and an init that serves the Web UI and publishes the repository over git and HTTP."
LABEL droidspaces.author="DeepSeek-Dsh-Agent"

ENV DEBIAN_FRONTEND=noninteractive \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    PNPM_HOME=/opt/pnpm \
    DSH_HOME=/var/lib/dsh \
    DSH_REPO_DIR=/opt/deepseek-harness \
    DSH_WEB_PORT=3080 \
    DSH_REPO_HTTP_PORT=8080 \
    DSH_GIT_PORT=9418 \
    PATH=/opt/pnpm:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash \
      build-essential \
      busybox-static \
      ca-certificates \
      curl \
      git \
      iproute2 \
      less \
      locales \
      openssh-client \
      pkg-config \
      procps \
      python3 \
      tzdata \
      xz-utils \
    && rm -rf /var/lib/apt/lists/*

# pnpm manages the repository workspace; the version is the one the
# repository's own packageManager field pins.
RUN npm install --global pnpm@11.28.5 && pnpm --version

# The published command is the supported runtime. The repository below is the
# working tree it operates on.
RUN npm install --global "@deepseek-ai/dsh@${DSH_CLI_VERSION}" && dsh --version

# The complete repository, with the commit it was built from recorded next to
# it so the container reports which tree it hosts.
WORKDIR /opt/deepseek-harness
RUN git init . \
    && git remote add origin "$DSH_REPO_URL" \
    && git fetch --depth 1 origin "$DSH_REF" \
    && git checkout --detach FETCH_HEAD \
    && git rev-parse HEAD > .dsh-commit \
    && git config --global --add safe.directory /opt/deepseek-harness

# The workspace dependencies, so the hosted repository is configured and ready
# to build, test, or edit.
RUN pnpm config set store-dir /opt/pnpm/store \
    && pnpm install --frozen-lockfile \
    && rm -rf /opt/pnpm/store /root/.cache /root/.npm

# A plain user for the terminal the app offers, next to root. The base image
# already owns uid 1000, so this one takes the next free number.
RUN useradd --create-home --shell /bin/bash droid

# Droidspaces executes /sbin/init as PID 1. The image replaces the distribution
# init with the one that publishes the harness and the repository.
COPY droidspaces/scripts/dsh-init.sh /usr/local/lib/dsh/dsh-init.sh
COPY droidspaces/scripts/dsh-entrypoint.sh /usr/local/lib/dsh/dsh-entrypoint.sh
COPY droidspaces/scripts/udhcpc.script /usr/local/lib/dsh/udhcpc.script
COPY droidspaces/scripts/serve-repo.mjs /usr/local/lib/dsh/serve-repo.mjs
RUN chmod 0755 /usr/local/lib/dsh/dsh-init.sh /usr/local/lib/dsh/dsh-entrypoint.sh \
      /usr/local/lib/dsh/udhcpc.script /usr/local/lib/dsh/serve-repo.mjs \
    && rm -f /sbin/init \
    && ln -s /usr/local/lib/dsh/dsh-init.sh /sbin/init \
    && mkdir -p "$DSH_HOME" \
    && chmod 0700 "$DSH_HOME"

EXPOSE 3080 8080 9418

CMD ["/sbin/init"]

FROM scratch AS export
COPY --from=runtime / /
