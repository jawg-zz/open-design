# 1. Fetch the official public deployment image as the base
FROM docker.io/vanjayak/open-design:latest

# 2. Switch to root to inject system configurations safely
USER root

# 3. Install compatibility layer for glibc-linked binary CLIs on Alpine Linux
RUN apk add --no-cache libc6-compat gcompat

# 4. Install the native ARM64 CLI tools directly onto the system's global PATH
RUN npm install -g @powerformer/vela-cli @opencode-ai/cli --unsafe-perm

# 5. Generate the absolute canonical symlinks that the detectAgents() loop searches for
RUN ln -sf /usr/local/bin/vela /usr/local/bin/vela-cli \
    && ln -sf /usr/local/bin/opencode-ai /usr/local/bin/opencode \
    && ln -sf /usr/local/bin/opencode-ai /usr/local/bin/opencode-cli

# 6. Open binary flags for seamless sub-process spawning loops
RUN chmod +x /usr/local/bin/vela* /usr/local/bin/opencode*

# 7. Fall back to the default unprivileged container layer account
USER node
