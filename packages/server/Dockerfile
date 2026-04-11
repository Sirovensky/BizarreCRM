# ─── Stage 1: Build shared + web frontend ────────────────────────────
FROM node:22-alpine AS web-builder

WORKDIR /app

# Copy workspace root config
COPY package.json package-lock.json ./

# Copy package.json files for all workspaces
COPY packages/shared/package.json packages/shared/
COPY packages/web/package.json packages/web/
COPY packages/server/package.json packages/server/

# Install all dependencies (need devDependencies for build)
RUN npm ci

# Copy shared source and build it first
COPY packages/shared/ packages/shared/
RUN npm run build --workspace=packages/shared

# Copy web source and build frontend
COPY packages/web/ packages/web/
RUN npm run build --workspace=packages/web

# ─── Stage 2: Build server ──────────────────────────────────────────
FROM node:22-alpine AS server-builder

WORKDIR /app

COPY package.json package-lock.json ./
COPY packages/shared/package.json packages/shared/
COPY packages/server/package.json packages/server/
# Web package.json needed for workspace resolution
COPY packages/web/package.json packages/web/

RUN npm ci

COPY packages/shared/ packages/shared/
RUN npm run build --workspace=packages/shared

COPY packages/server/src/ packages/server/src/
COPY packages/server/tsconfig.json packages/server/
RUN npm run build --workspace=packages/server

# ─── Stage 3: Production runtime ────────────────────────────────────
FROM node:22-alpine

WORKDIR /app

# Install only production dependencies
COPY package.json package-lock.json ./
COPY packages/shared/package.json packages/shared/
COPY packages/server/package.json packages/server/
COPY packages/web/package.json packages/web/

RUN npm ci --omit=dev && npm cache clean --force

# Copy built shared package
COPY --from=server-builder /app/packages/shared/dist/ packages/shared/dist/
COPY packages/shared/package.json packages/shared/

# Copy built server
COPY --from=server-builder /app/packages/server/dist/ packages/server/dist/
COPY packages/server/src/db/migrations/ packages/server/src/db/migrations/
COPY packages/server/src/admin/ packages/server/src/admin/

# Copy built web frontend (served by Express in production)
COPY --from=web-builder /app/packages/web/dist/ packages/web/dist/

# Copy SSL certs if present (optional — will fall back to HTTP)
COPY packages/server/certs/ packages/server/certs/

# Create data and uploads directories
RUN mkdir -p packages/server/data packages/server/uploads

# @audit-fixed: Deployment audit (section 34) — Dockerfile previously had no
# USER directive, so the container ran as root. The Alpine `node` base image
# already ships a `node` user (uid 1000) for exactly this purpose. We chown the
# directories the server writes to and drop privileges before launch.
#
# IMPORTANT: port 443 is privileged on Linux (<1024), so the non-root `node`
# user cannot bind to it directly. The recommended deployment is to publish the
# host port via `-p 443:8443` (host:container) and have Express listen on 8443
# inside the container — set PORT=8443 in your .env / docker-compose. The
# default below stays at 443 so bare-metal installs that already configure
# CAP_NET_BIND_SERVICE keep working, but you SHOULD switch container deploys
# to a high port.
RUN chown -R node:node /app/packages/server/data /app/packages/server/uploads /app/packages/server/certs 2>/dev/null || true
USER node

ENV NODE_ENV=production
EXPOSE 443

CMD ["node", "packages/server/dist/index.js"]
