# Production image for Hangman · in Phoenix.
# Built by Render (see ../render.yaml) — or anywhere: `docker build -t hangman .`
#
# Stage 1 compiles the app, bundles assets (GSAP + Three.js via npm) and
# builds an OTP release. Stage 2 is a slim Debian with just the release.

ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27.3.4.16
ARG DEBIAN_VERSION=bookworm-20260824-slim
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends build-essential git ca-certificates nodejs npm \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app
ENV MIX_ENV="prod"

RUN mix local.hex --force && mix local.rebar --force

# Dependencies first, so they're cached between deploys.
COPY mix.exs mix.lock* ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY assets/package.json assets/package-lock.json assets/
RUN npm ci --prefix assets --no-audit --no-fund

COPY priv priv
COPY lib lib
COPY assets assets

RUN mix compile
RUN mix assets.deploy

COPY config/runtime.exs config/
RUN mix release

# ── Runtime image ───────────────────────────────────────────────────────
FROM ${RUNNER_IMAGE}

RUN apt-get update -y \
  && apt-get install -y --no-install-recommends libstdc++6 openssl libncurses5 locales ca-certificates \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody /app
ENV MIX_ENV="prod" PHX_SERVER=true PORT=4000

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/hangman ./
USER nobody

EXPOSE 4000
CMD ["/app/bin/hangman", "start"]
