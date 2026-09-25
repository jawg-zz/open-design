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
#   a) The platform package `@openai/codex-linux-arm64` is NOT a standalone
#      registry package -- a bare `npm install -g @openai/codex-linux-arm64`
#      404s. It exists ONLY as an alias (`npm:@openai/codex@<ver>-linux-arm64`)
#      in the main package's optionalDependencies, and npm 11 global installs
#      skip optional deps, leaving `vendor/` absent. Fix: derive the exact
#      alias spec from the installed package.json and install it explicitly
#      as a direct global. (The daemon's launch.ts walks ancestors for
#      node_modules/@openai/codex-* but its candidate file list predates the
#      current vendor/<triple>/bin/ layout -- so auto-discovery is unreliable;
#      CODEX_BIN in compose is the deterministic path.)
#   b) The daemon's sandbox env points CODEX_HOME at /tmp/.codex but never
#      creates it, and the native binary hard-errors when it doesn't exist.
RUN npm uninstall -g @opencode-ai/cli || true \
    && npm install -g --allow-scripts=opencode-ai --include=optional opencode-ai@1.18 @powerformer/vela-cli @openai/codex \
    && BIN_DIR="$(npm prefix -g)/bin" \
    && LIB_DIR="$(npm prefix -g)/lib/node_modules" \
    && export CODEX_PKG_DIR="$LIB_DIR/@openai/codex" \
    && CODEX_PLATFORM_SPEC=$(node -e "const d=require(process.env.CODEX_PKG_DIR+'/package.json');const k=Object.keys(d.optionalDependencies||{}).find(n=>n.endsWith('-linux-arm64'));if(!k){console.error('no linux-arm64 platform dep');process.exit(1)}console.log(k+'@'+d.optionalDependencies[k])") \
    && echo "codex platform spec: $CODEX_PLATFORM_SPEC" \
    && npm install -g "$CODEX_PLATFORM_SPEC" \
    && CODEX_NATIVE="$LIB_DIR/@openai/codex-linux-arm64/vendor/aarch64-unknown-linux-musl/bin/codex" \
    && echo "global bin dir: $BIN_DIR" && ls -la "$BIN_DIR" \
    && echo "codex platform vendor:" && ls -la "$(dirname "$CODEX_NATIVE")" \
    && test -x "$BIN_DIR/opencode" \
    && test -x "$BIN_DIR/vela" \
    && test -x "$BIN_DIR/codex" \
    && test -x "$CODEX_NATIVE" \
    && ln -sf "$BIN_DIR/opencode" /usr/local/bin/opencode-cli \
    && ln -sf "$BIN_DIR/opencode" /usr/local/bin/opencode-ai \
    && ln -sf "$CODEX_NATIVE" /usr/local/bin/codex-native \
    && chmod +x /usr/local/bin/vela* /usr/local/bin/opencode* /usr/local/bin/codex* \
    && mkdir -p /tmp/.codex \
    && /usr/local/bin/opencode --version \
    && /usr/local/bin/opencode-cli --version \
    && /usr/local/bin/opencode run --help 2>&1 | grep -q -- --dir \
    && (/usr/local/bin/vela --version || /usr/local/bin/vela --help) \
    && /usr/local/bin/codex --version \
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
