# 1. Fetch the official public deployment image as the base
FROM docker.io/vanjayak/open-design:latest

# 2. Switch to root to inject system configurations safely
USER root

# 3. Install compatibility layer for glibc-linked binary CLIs on Alpine Linux
RUN apk add --no-cache libc6-compat gcompat

# 4-6. Install the CLIs, verify the real binaries, then pin canonical symlinks --
# all in ONE layer on purpose, so a half-installed state can never be cached
# and reused by a later build.
# - npm >= 11 blocks install scripts by default; @opencode-ai/cli fetches its
#   platform binary via postinstall, so explicitly allow that package's scripts.
#   Without this, `opencode-ai` is never created and everything downstream fails.
# - Symlinks resolve via `npm prefix -g` instead of assuming /usr/local/bin,
#   then canonical names are pinned there for the detectAgents() loop.
RUN npm install -g --allow-scripts=@opencode-ai/cli @powerformer/vela-cli @opencode-ai/cli \
    && BIN_DIR="$(npm prefix -g)/bin" \
    && echo "global bin dir: $BIN_DIR" && ls -la "$BIN_DIR" \
    && test -x "$BIN_DIR/vela" \
    && test -x "$BIN_DIR/opencode-ai" \
    && ln -sf "$BIN_DIR/vela" /usr/local/bin/vela \
    && ln -sf "$BIN_DIR/vela" /usr/local/bin/vela-cli \
    && ln -sf "$BIN_DIR/opencode-ai" /usr/local/bin/opencode \
    && ln -sf "$BIN_DIR/opencode-ai" /usr/local/bin/opencode-cli \
    && chmod +x /usr/local/bin/vela* /usr/local/bin/opencode*

# 7. Fall back to the default unprivileged container layer account
USER node
