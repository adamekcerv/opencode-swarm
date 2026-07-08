# Database Agent Dockerfile
# Port 3001 - Data storage and retrieval specialist

FROM node:22-alpine

RUN apk add --no-cache curl jq bash sqlite

WORKDIR /app

COPY agents/shared/ ./agents/shared/
COPY agents/db/AGENTS.md ./
COPY agents/db/.opencode/opencode.json ./opencode.json
COPY .env.example ./

RUN mkdir -p /data && \
    addgroup -S swarm && adduser -S swarm -G swarm && \
    chown -R swarm:swarm /app /data
USER swarm

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:3001/config || exit 1

VOLUME ["/data"]

EXPOSE 3001

ENV AGENT_PORT=3001 \
    AGENT_NAME=database_agent \
    AGENT_FOLDER=db \
    AGENT_MODE=all \
    DB_PATH=/data/swarm.db \
    LOG_LEVEL=INFO

CMD ["node", "server.js"]