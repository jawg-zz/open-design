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
# - The REAL binary names come from each package's `bin` map (verified via
#   `npm view`): vela exposes `vela` (a node wrapper resolving its platform
#   package at runtime); @opencode-ai/cli exposes `opencode2` ONLY -- there is
#   no `opencode-ai` binary, which is why the previous build failed. The
#   postinstall materializes the linux-arm64-musl binary in place and verifies
#   it executes before npm reports success.
# - Canonical names (opencode, opencode-cli, opencode-ai, vela-cli) are then
#   pinned for the detectAgents() loop, and both CLIs get a --version smoke
#   test so a non-executing binary fails the build instead of deploying broken.
RUN npm install -g --allow-scripts=@opencode-ai/cli @powerformer/vela-cli @opencode-ai/cli \
    && BIN_DIR="$(npm prefix -g)/bin" \
    && echo "global bin dir: $BIN_DIR" && ls -la "$BIN_DIR" \
    && test -x "$BIN_DIR/vela" \
    && test -x "$BIN_DIR/opencode2" \
    && ln -sf "$BIN_DIR/vela" /usr/local/bin/vela-cli \
    && ln -sf "$BIN_DIR/opencode2" /usr/local/bin/opencode \
    && ln -sf "$BIN_DIR/opencode2" /usr/local/bin/opencode-cli \
    && ln -sf "$BIN_DIR/opencode2" /usr/local/bin/opencode-ai \
    && chmod +x /usr/local/bin/vela* /usr/local/bin/opencode* \
    && /usr/local/bin/opencode --version \
    && (/usr/local/bin/vela --version || /usr/local/bin/vela --help)

# 7. Pre-create the daemon workspace and hand it to the image's own runtime
# user. The base image runs as `open-design` (not root, not node); a fresh
# named volume mounts root-owned, so without this the daemon crash-loops on
# `mkdir /app/.od/projects` with EACCES. Seeding an owned dir in the image
# lets Docker populate the empty volume with the right ownership on first mount.
RUN mkdir -p /app/.od && chown -R open-design:$(id -g open-design) /app/.od && chmod 755 /app/.od

# 8. Drop back to the base image's unprivileged runtime account (open-design),
# matching upstream -- NOT node, which owns nothing under /app.
USER open-design
