FROM node:24-slim@sha256:55fb5f5a527ea2c5c4a95f963e48ef90aa38c7b346054fdc8ee9957a2b55d205

# curl for the healthcheck, tini as a proper init process
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl tini && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /usr/local/app

COPY package*.json ./

# Reproducible install from package-lock.json, production dependencies only
RUN npm ci --omit=dev && \
    npm cache clean --force && \
    mv /usr/local/app/node_modules /node_modules

COPY --chown=node:node . .

ENV PORT=8000
EXPOSE 8000

USER 1000:1000
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["node", "server.js"]