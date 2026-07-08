# Orchestrator Agent Dockerfile
# Port 3000 - Main coordination node

FROM node:22-alpine

RUN apk add --no-cache curl jq bash

WORKDIR /app

COPY agents/shared/ ./agents/shared/
COPY .opencode/agent/orchestrator.md ./
COPY .opencode/opencode.json ./
COPY .opencode/agents/ ./agents/
COPY .env.example ./

RUN addgroup -S swarm && adduser -S swarm -G swarm && \
    chown -R swarm:swarm /app
USER swarm

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:3000/config || exit 1

EXPOSE 3000

ENV AGENT_PORT=3000 \
    AGENT_NAME=orchestrator \
    AGENT_FOLDER=root \
    AGENT_MODE=primary \
    LOG_LEVEL=INFO \
    LOG_MAX_SIZE_MB=10 \
    LOG_MAX_FILES=5

CMD ["node", "server.js"]