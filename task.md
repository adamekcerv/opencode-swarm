# Plán vývoje: Produkční Swarm Architektura

## Fáze 1: Inicializace a nastavení prostředí (Dokončeno)
- [x] Vytvořit základní strukturu projektu a `.opencode` adresář.
- [x] Nastavit `opencode.json` s modelem `deepseek/deepseek-v4-pro` a definovat oprávnění (curl, jq).
- [x] Připravit koordinační skripty pro Orchestrátora (vyhledávání serverů, health check).

## Fáze 2: Vývoj sub-agentů a komunikace (Probíhá)
- [x] Vytvořit profil pro `database_agent` ve složce `/agents/db/`.
- [x] Vytvořit profil pro `security_agent` ve složce `/agents/security/`.
- [x] Implementovat povinný komunikační protokol pro předávání zpráv mezi agenty.
- [x] Napsat integrační testy pro ověření komunikace přes porty 3001-3010.

## Fáze 3: Produkční standardy a zabezpečení
- [x] Implementovat rotaci logů a bezpečné ukládání API klíčů (žádné hardcoded secrets).
- [x] Přidat fallback mechanismus (pokud primární server agenta neodpovídá, přepnout na záložní).
- [x] Otestovat obnovu po chybě (Disaster Recovery) pro případ pádu jednoho z uzlů.

## Fáze 4: Příprava na nasazení (Deployment)
- [x] Vytvořit Dockerfile pro izolovaný běh každého agenta.
- [ ] Připravit CI/CD pipeline skript.
- [ ] Provést finální end-to-end (E2E) test kompletního roje (Swarm).