# Production App - Milníky

## Milník 0: Architektura a plán
- [ ] Definovat architekturu (C4 model: kontext, kontejnery, komponenty, kód)
- [ ] Vybrat tech stack a zdůvodnit volby
- [ ] Navrhnout API specifikaci (OpenAPI 3.0)
- [ ] Naplánovat datové modelování (ERD)
- [ ] Rozhodnout deployment strategii (cloud, hosting, CI/CD)
- [ ] Security review architektury (threat modeling)

## Milník 1: Projektový setup a základy
- [ ] Inicializovat projekt v `./apps/nazev-aplikace/` s `git init`
- [ ] Nastavit TypeScript (strict mode), ESLint + Prettier
- [ ] Nastavit testovací framework (Vitest)
- [ ] Vytvořit základní Dockerfile (multi-stage, non-root, healthcheck)
- [ ] Vytvořit docker-compose pro lokální vývoj (app + DB + Redis)
- [ ] Nastavit structured logging (pino)
- [ ] Nastavit error handling middleware (global error handler)
- [ ] Security review setupu

## Milník 2: API vrstva
- [ ] Implementovat REST API router a controllers
- [ ] Input validation (Zod schémata)
- [ ] Response serializace a strukturované odpovědi
- [ ] Middleware: CORS, helmet, rate-limiting, request ID
- [ ] Middleware: autentizace a autorizace
- [ ] Error handling: konzistentní API chybové odpovědi
- [ ] Health check endpoint (liveness + readiness)
- [ ] Graceful shutdown
- [ ] Security review API

## Milník 3: Databáze a persistence
- [ ] Vytvořit databázové schéma (migrační framework)
- [ ] Implementovat repository pattern
- [ ] Seed data pro vývoj a testy
- [ ] Connection pooling a retry logika
- [ ] Transakční zpracování a ACID
- [ ] Security review (SQL injection prevence, least privilege)

## Milník 4: Autentizace a autorizace
- [ ] JWT access + refresh tokeny
- [ ] Password hashing (bcrypt/argon2)
- [ ] Login, register, logout, refresh endpointy
- [ ] Role-based access control (RBAC)
- [ ] Rate limiting na auth endpointy
- [ ] Security review autentizace

## Milník 5: Testování (všechny vrstvy)
- [ ] Unit testy pro služby a utility
- [ ] Integration testy (API + DB)
- [ ] E2E testy kritických scénářů
- [ ] Security testy (SQL injection, XSS, CSRF, dependency audit)
- [ ] Load/performance testy (k6/artillery)
- [ ] Code review agenta na pokrytí testů

## Milník 6: Dokumentace
- [ ] README (jak spustit, struktura, technologie)
- [ ] API dokumentace (OpenAPI/Swagger UI)
- [ ] ADR (Architecture Decision Records) pro klíčová rozhodnutí
- [ ] DEVELOPMENT.md (jak přidat nový endpoint, migraci, atd.)
- [ ] Deployment runbook

## Milník 7: Monitoring a observabilita
- [ ] Structured logging (JSON, correlation ID, request/response log)
- [ ] Metriky (počet requestů, latence, chybovost, DB query time)
- [ ] Alerting na kritické chyby (5xx, pomalé dotazy, auth failures)
- [ ] Health check endpoint detailní (závislosti: DB, cache, atd.)
- [ ] Graceful shutdown + signal handling

## Milník 8: Production readiness
- [ ] Docker compose pro produkci (bez vývojových volumů)
- [ ] CI/CD pipeline (lint → test → build → deploy)
- [ ] Secrets management (žádné .env v obraze)
- [ ] Final security audit (celá aplikace)
- [ ] Performance benchmark
- [ ] Final code review (všichni agenti + orchestrátor)
