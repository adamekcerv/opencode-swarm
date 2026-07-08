# Security Agent Dockerfile
# Port 3002 - Vulnerability scanning and security audits

FROM node:22-alpine

RUN apk add --no-cache curl jq bash && \
    curl -sfL https://github.com/aquasecurity/trivy/releases/download/v0.72.0/trivy_0.72.0_Linux-64bit.tar.gz -o trivy.tar.gz && \
    tar xzf trivy.tar.gz trivy && \
    mv trivy /usr/local/bin/trivy && \
    rm trivy.tar.gz

WORKDIR /app

COPY agents/shared/ ./agents/shared/
COPY agents/security/AGENTS.md ./
COPY agents/security/.opencode/opencode.json ./opencode.json
COPY .env.example ./

RUN addgroup -S swarm && adduser -S swarm -G swarm && \
    chown -R swarm:swarm /app
USER swarm

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:3002/config || exit 1

EXPOSE 3002

ENV AGENT_PORT=3002 \
    AGENT_NAME=security_agent \
    AGENT_FOLDER=security \
    AGENT_MODE=all \
    LOG_LEVEL=INFO

CMD ["node", "server.js"]