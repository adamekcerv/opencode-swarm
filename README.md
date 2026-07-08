# OpenCode Swarm

Production-ready swarm architektura pro OpenCode. Orchestrátor + specializovaní agenti pro build produkčních aplikací.

## Požadavky

- [Node.js 22+](https://nodejs.org/)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (pro Docker režim)
- [OpenRouter API klíč](https://openrouter.ai/keys)
- npm balíček `@opencode/cli` (instaluje se níže)

---

## 1. Instalace OpenCode

```powershell
npm install -g @opencode/cli
opencode --version
# Mělo by vypsat: 1.x.x
```

## 2. Stažení swarm repozitáře

```powershell
git clone https://github.com/adamekcerv/opencode-swarm.git
cd opencode-swarm
```

## 3. Nastavení API klíče

```powershell
cp .env.example .env
# Otevři .env a vyplň:
# OPENROUTER_API_KEY=sk-or-v1-...
```

---

## 4. Práce se swarmem

Máš **2 režimy** – podle toho, co potřebuješ:

### Režim A: Orchestrátor (doporučeno)

Otevři **druhé okno terminálu** a spusť:

```powershell
opencode C:\Users\cervad92\opencode-swarm
```

Otevře se interaktivní rozhraní, kde zadáváš úkoly. Orchestrátor (DeepSeek V4 Pro) automaticky:
- Čte `task.md` a postupuje po milnících
- Vytváří projekty do složky `apps/nazev-aplikace/`
- Každý projekt má vlastní `git init`
- Podle potřeby zapojuje sub-agenty (database, security, code-review)
- Commituje po každém hotovém úkolu

**Příklad úkolu:**
> Vytvoř production-ready REST API pro správu úkolů s PostgreSQL, JWT autentizací a Docker nasazením.

### Režim B: Docker swarm

Spustí každého agenta v izolovaném kontejneru s vlastním API serverem:

```powershell
docker compose up -d
```

| Agent | Port | URL |
|-------|------|-----|
| Orchestrátor | 3000 | http://localhost:3000 |
| Database | 3001 | http://localhost:3001 |
| Security | 3002 | http://localhost:3002 |

Zastavení:

```powershell
docker compose down
```

---

## 5. Struktura repozitáře

```
opencode-swarm/
├── .opencode/                    # Konfigurace swarmu
│   ├── opencode.json             # Hlavní nastavení (model, oprávnění)
│   ├── agent/orchestrator.md     # Definice orchestrátora
│   └── agents/                   # Sub-agenti
│       ├── database_agent.md
│       ├── security_agent.md
│       └── code_review_agent.md
├── agents/                       # Složky agentů pro standalone běh
│   ├── db/
│   ├── security/
│   └── code-review/
├── apps/                         # Sem se vytvářejí projekty (vlastní git)
├── .opencodecontext               # Instrukce pro orchestrátora
├── task.md                        # Milníky a úkoly
└── docker-compose.yml             # Swarm nasazení
```

---

## 6. Přidání nového agenta

1. Vytvoř `.opencode/agents/muj_agent.md`:
   ```yaml
   ---
   description: Co agent dělá
   mode: subagent
   model: openrouter/deepseek/deepseek-v4-flash
   ---
   Instrukce pro agenta...
   ```

2. Vytvoř `agents/muj-agent/AGENTS.md` a `.opencode/opencode.json`

3. Hotovo – orchestrátor ho bude znát.

---

## 7. Testy

```powershell
# Všechny testy
powershell -File agents/shared/test_e2e_swarm.ps1

# Jednotlivé sady
powershell -File agents/shared/test_protocol.ps1
powershell -File agents/shared/test_fallback.ps1
```

---

## 8. Tipy

- **Přepínání módu** – v opencode okně stiskni `ctrl+p` → `mode: plan/build`
- **Task.md** – definuje co se má postavit. Orchestrátor postupuje popořadě.
- **.opencodecontext** – říká orchestrátorovi JAK pracovat (standardy, nástroje, git)
- **Commit** – orchestrátor commituje sám, pushování musíš povolit ty

---

## Technologie

| Vrstva | Technologie |
|--------|-------------|
| Runtime | Node.js 22, TypeScript (strict) |
| API | Express.js / Fastify + Zod |
| DB | PostgreSQL + migrační framework |
| Auth | JWT (access + refresh), bcrypt, RBAC |
| Testy | Vitest, Supertest |
| Logování | pino (JSON structured) |
| Kontejnery | Docker, Docker Compose |
| Modely | DeepSeek V4 Pro / V4 Flash (OpenRouter) |
