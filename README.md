# OpenCode Swarm

Production-ready swarm architecture for OpenCode with orchestrator, specialized agents, and automated DevOps pipeline.

## Architecture

```
┌──────────────────────────────────────────────┐
│                Orchestrator                   │
│              (Port 3000)                      │
│         deepseek-v4-pro                       │
│    Task distribution & coordination           │
└──────┬───────────────────────┬───────────────┘
       │                       │
       ▼                       ▼
┌──────────────┐       ┌──────────────┐
│ Database     │       │ Security     │
│ Agent        │       │ Agent        │
│ (Port 3001)  │       │ (Port 3002)  │
│ v4-flash     │       │ v4-flash     │
└──────────────┘       └──────────────┘
```

## Project Structure

```
.
├── .opencode/
│   ├── opencode.json                  # Main config
│   ├── agent/
│   │   └── orchestrator.md            # Primary agent definition
│   └── agents/
│       ├── database_agent.md          # DB sub-agent
│       └── security_agent.md          # Security sub-agent
├── agents/
│   ├── db/
│   │   ├── AGENTS.md                  # Database agent profile
│   │   ├── Dockerfile
│   │   └── .opencode/opencode.json
│   ├── security/
│   │   ├── AGENTS.md                  # Security agent profile
│   │   ├── Dockerfile
│   │   └── .opencode/opencode.json
│   └── shared/
│       ├── swarm_protocol.ps1         # Communication protocol
│       ├── fallback_manager.ps1       # Failover logic
│       ├── log_rotator.ps1            # Log rotation
│       ├── secrets_manager.ps1        # Secrets handling
│       └── test_*.ps1                 # Test suites
├── .github/workflows/ci.yml           # CI/CD pipeline
├── Dockerfile                          # Orchestrator image
├── docker-compose.yml                  # Swarm deployment
├── .env.example                        # Environment template
└── task.md                             # Development plan
```

## Features

- **Swarm Communication Protocol** — Mandatory introduction format for all inter-agent messages
- **Auto-Failover** — Automatic backup server activation when primary fails
- **Disaster Recovery** — Full recovery after node crash with state resets
- **Log Rotation** — Size-based rotation with configurable retention
- **Secrets Management** — Environment-based, zero hardcoded credentials
- **Docker Support** — Isolated containers per agent with health checks
- **CI/CD Pipeline** — GitHub Actions, multi-OS (Windows + Ubuntu), Docker builds

## Quick Start

### Clone & Setup

```bash
git clone https://github.com/adamekcerv/opencode-swarm.git
cd opencode-swarm
cp .env.example .env
# Edit .env with your API keys
```

### Run Tests

```powershell
# All tests (158 checks, 9 suites)
powershell -File agents/shared/test_e2e_swarm.ps1

# Individual suites
powershell -File agents/shared/test_protocol.ps1
powershell -File agents/shared/test_fallback.ps1
powershell -File agents/shared/test_production_standards.ps1
powershell -File agents/shared/test_disaster_recovery.ps1
powershell -File agents/shared/test_docker.ps1
powershell -File agents/shared/test_cicd.ps1
```

### Docker Deployment

```bash
docker compose up -d
# Orchestrator: http://localhost:3000
# Database:     http://localhost:3001
# Security:     http://localhost:3002
```

## Agents

| Agent | Port | Model | Role |
|-------|------|-------|------|
| Orchestrator | 3000 | deepseek-v4-pro | Task distribution, swarm coordination |
| Database | 3001 | deepseek-v4-flash | Data storage, SQL, schema design |
| Security | 3002 | deepseek-v4-flash | Vulnerability scanning, audits |

## Communication Protocol

All inter-agent messages must follow:

```
I am the [Agent_Name] agent from the [folder_name] folder.
I am contacting you because [specific reason].
I need you to [specific request].
Please respond with [expected format].
```

## Using as a Template

This repo works as a template for any OpenCode project:

1. Clone it
2. Replace agents in `.opencode/agents/` and `agents/`
3. Update `task.md` with your development plan
4. Edit `.opencodecontext` for your project rules

## Tech Stack

- **Runtime**: Node.js 22
- **Orchestration**: Docker Compose
- **CI/CD**: GitHub Actions
- **Communication**: HTTP/REST + curl/jq
- **Models**: OpenRouter (deepseek-v4-pro / deepseek-v4-flash)

## License

MIT