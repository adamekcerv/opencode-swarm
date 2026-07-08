# Docker Configuration Validation Tests
# Fáze 4, Úkol 1: Ověření Dockerfile struktury

$ErrorActionPreference = "Stop"
$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path (Split-Path $ScriptDir -Parent) -Parent

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Fáze 4: Docker Configuration Tests" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$passed = 0
$failed = 0

function Assert-Pass { param([string]$n); Write-Host "  PASS: $n" -ForegroundColor Green; $script:passed++ }
function Assert-Fail { param([string]$n, [string]$d); Write-Host "  FAIL: $n - $d" -ForegroundColor Red; $script:failed++ }

# --- Test 1: All Dockerfiles exist ---
Write-Host "Test 1: Dockerfile inventory"
$dockerfiles = @{
    "Orchestrator"    = Join-Path $ProjectRoot "Dockerfile"
    "Base"            = Join-Path $ProjectRoot "Dockerfile.base"
    "Database Agent"  = Join-Path $ProjectRoot "agents\db\Dockerfile"
    "Security Agent"  = Join-Path $ProjectRoot "agents\security\Dockerfile"
}

foreach ($name in $dockerfiles.Keys) {
    if (Test-Path $dockerfiles[$name]) { Assert-Pass "$name Dockerfile exists" }
    else { Assert-Fail "$name Dockerfile" "Not found" }
}

# --- Test 2: Dockerfiles have FROM instruction ---
Write-Host "Test 2: Dockerfiles contain FROM"
foreach ($name in $dockerfiles.Keys) {
    $content = Get-Content $dockerfiles[$name] -Raw
    if ($content -match "FROM\s+node:22-alpine") { Assert-Pass "$name has FROM node:22-alpine" }
    else { Assert-Fail "$name FROM" "Missing or wrong base image" }
}

# --- Test 3: Dockerfiles have HEALTHCHECK ---
Write-Host "Test 3: Dockerfiles have HEALTHCHECK"
$healthOk = $true
foreach ($name in $dockerfiles.Keys) {
    if ($name -eq "Base") { continue }
    $content = Get-Content $dockerfiles[$name] -Raw
    if ($content -match "HEALTHCHECK") { }
    else { Assert-Fail "$name HEALTHCHECK" "Missing"; $healthOk = $false }
}
if ($healthOk) { Assert-Pass "All agent Dockerfiles have HEALTHCHECK" }

# --- Test 4: Ports are correctly assigned ---
Write-Host "Test 4: Port assignments"
$ports = @{
    "Dockerfile"           = "3000"
    "agents\db\Dockerfile" = "3001"
    "agents\security\Dockerfile" = "3002"
}
$portOk = $true
foreach ($file in $ports.Keys) {
    $content = Get-Content (Join-Path $ProjectRoot $file) -Raw
    $expectedPort = $ports[$file]
    if ($content -match "EXPOSE\s+${expectedPort}") { }
    else { Assert-Fail "$file port" "Expected EXPOSE ${expectedPort}"; $portOk = $false }
}
if ($portOk) { Assert-Pass "All Dockerfiles expose correct ports (3000, 3001, 3002)" }

# --- Test 5: docker-compose.yml exists and is valid ---
Write-Host "Test 5: docker-compose.yml validity"
$composePath = Join-Path $ProjectRoot "docker-compose.yml"
if (Test-Path $composePath) {
    Assert-Pass "docker-compose.yml exists"
} else { Assert-Fail "docker-compose.yml" "Not found" }

# --- Test 6: docker-compose defines all 3 services ---
Write-Host "Test 6: docker-compose service count"
$composeContent = Get-Content $composePath -Raw
$services = @("orchestrator", "database_agent", "security_agent")
$allPresent = $true
foreach ($svc in $services) {
    if ($composeContent -match $svc) { }
    else { Assert-Fail "docker-compose service" $svc; $allPresent = $false }
}
if ($allPresent) { Assert-Pass "All 3 services defined in docker-compose.yml" }

# --- Test 7: .dockerignore exists ---
Write-Host "Test 7: .dockerignore"
if (Test-Path (Join-Path $ProjectRoot ".dockerignore")) { Assert-Pass ".dockerignore exists" }
else { Assert-Fail ".dockerignore" "Not found" }

# --- Test 8: Network configuration ---
Write-Host "Test 8: Docker network config"
if ($composeContent -match "swarm-net" -and $composeContent -match "10\.10\.0\.0") {
    Assert-Pass "Swarm network configured (10.10.0.0/24)"
} else { Assert-Fail "Swarm network" "Not configured" }

# --- Test 9: Volume for database agent ---
Write-Host "Test 9: Persistent volume"
$dbDockerfile = Get-Content (Join-Path $ProjectRoot "agents\db\Dockerfile") -Raw
if ($composeContent -match "db_data" -and $dbDockerfile -match "VOLUME") {
    Assert-Pass "Persistent volume for database agent"
} else { Assert-Fail "Persistent volume" "Not found" }

# --- Test 10: Restart policy ---
Write-Host "Test 10: Restart policies"
$restartCount = ([regex]::Matches($composeContent, "restart: unless-stopped")).Count
if ($restartCount -ge 3) { Assert-Pass "3 services have restart: unless-stopped" }
else { Assert-Fail "Restart policies" "Only found $restartCount" }

# --- Summary ---
Write-Host ""
Write-Host "=== Fáze 4 / Úkol 1 Results ===" -ForegroundColor Cyan
Write-Host "Passed: $passed" -ForegroundColor Green
if ($failed -gt 0) { Write-Host "Failed: $failed" -ForegroundColor Red; throw "$failed test(s) failed" }
else { Write-Host "Failed: $failed" -ForegroundColor Gray; Write-Host "ALL TESTS PASSED" -ForegroundColor Green }