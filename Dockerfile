# 1. Fetch the official public deployment image as the base
FROM docker.io/vanjayak/open-design:latest

# 2. Switch to root to inject system configurations safely
USER root

# 3. Install compatibility layer for glibc-linked binary CLIs on Alpine Linux
RUN apk add --no-cache libc6-compat gcompat

# 4-6. Install the CLIs, verify the real binaries, then pin canonical symlinks --
# all in ONE layer on purpose, so a half-installed state can never be cached
# and reused by a later build.
# - THE OPENCODE LESSON (verified against nexu-io/open-design source):
#   the daemon spawns `opencode run --format json --dir <cwd>` and REQUIRES
#   `run --help` to advertise `--dir` (opencode-permissions.ts sends it
#   unconditionally -- "an OpenCode build without --dir should fail loudly
#   at spawn"). `@opencode-ai/cli` is a FORK (anomalyco/opencode) exposing
#   `opencode2`, whose `run` rejects `--dir`/`--pure` -- installing it breaks
#   every OpenCode run at spawn with exactly the reported error. The genuine
#   CLI is the unscoped `opencode-ai` package (opencode.ai), bin `opencode`
#   (pinned to 1.18.x, the line the daemon's defs were built against).
# - npm >= 11 blocks install scripts by default; the genuine package fetches
#   its platform binary (linux-arm64-musl on Alpine) via postinstall, so
#   explicitly allow its scripts. Without this, `opencode` never materializes.
# - The daemon prefers bin `opencode-cli` with fallback `opencode`
#   (runtimes/defs/opencode.ts), so BOTH names must resolve to the genuine binary.
# - `opencode run --help | grep -- --dir` bakes the daemon's hard requirement
#   into the build: a future package regression fails the image, not the deploy.
# - Codex: official `@openai/codex` package, bin `codex` (node launcher that
#   resolves its linux-arm64 platform binary via optionalDependencies).
#   TWO GOTCHAS, both learned the hard way:
#   a) npm 11 global installs can skip optional deps, leaving `vendor/`
#      absent -- the wrapper then fails with "Missing optional dependency".
#      Fix: install `@openai/codex-linux-arm64` EXPLICITLY as a direct dep.
#   b) The daemon resolves the native binary by walking up from the wrapper
#      (runtimes/launch.ts `tryResolveCodexNativeBinary`); the explicit
#      platform package guarantees `vendor/aarch64-unknown-linux-musl/bin/codex`
#      exists. The native binary is glibc-linked, so `gcompat` alone may not
#      suffice -- the `--version` smoke test below proves it EXECUTES on musl.
# - CODEX_HOME: the daemon's sandbox env points it at /tmp/.codex but never
#   creates it, and the native binary errors when it doesn't exist. Pre-create
#   it owned by open-design (same pattern as /app/.od above).
RUN npm uninstall -g @opencode-ai/cli || true \
    && npm install -g --allow-scripts=opencode-ai opencode-ai@1.18 @powerformer/vela-cli @openai/codex @openai/codex-linux-arm64 \
    && BIN_DIR="$(npm prefix -g)/bin" \
    && LIB_DIR="$(npm prefix -g)/lib/node_modules" \
    && echo "global bin dir: $BIN_DIR" && ls -la "$BIN_DIR" \
    && echo "codex platform vendor:" && ls -la "$LIB_DIR/@openai/codex-linux-arm64/vendor/aarch64-unknown-linux-musl/bin/" \
    && test -x "$BIN_DIR/opencode" \
    && test -x "$BIN_DIR/vela" \
    && test -x "$BIN_DIR/codex" \
    && test -x "$LIB_DIR/@openai/codex-linux-arm64/vendor/aarch64-unknown-linux-musl/bin/codex" \
    && ln -sf "$BIN_DIR/opencode" /usr/local/bin/opencode-cli \
    && ln -sf "$BIN_DIR/opencode" /usr/local/bin/opencode-ai \
    && ln -sf "$LIB_DIR/@openai/codex-linux-arm64/vendor/aarch64-unknown-linux-musl/bin/codex" /usr/local/bin/codex-native \
    && chmod +x /usr/local/bin/vela* /usr/local/bin/opencode* /usr/local/bin/codex* \
    && /usr/local/bin/opencode --version \
    && /usr/local/bin/opencode-cli --version \
    && /usr/local/bin/opencode run --help 2>&1 | grep -q -- --dir \
    && (/usr/local/bin/vela --version || /usr/local/bin/vela --help) \
    && env CODEX_HOME=/tmp/.codex /usr/local/bin/codex-native --version

# 7. Pre-create the daemon workspace and hand it to the image's own runtime
# user. The base image runs as `open-design` (not root, not node); a fresh
# named volume mounts root-owned, so without this the daemon crash-loops on
# `mkdir /app/.od/projects` with EACCES. Seeding an owned dir in the image
# lets Docker populate the empty volume with the right ownership on first mount.
RUN mkdir -p /app/.od /tmp/.codex && chown -R open-design:$(id -g open-design) /app/.od /tmp/.codex && chmod 755 /app/.od /tmp/.codex

# 8. Drop back to the base image's unprivileged runtime account (open-design),
# matching upstream -- NOT node, which owns nothing under /app.
USER open-design
