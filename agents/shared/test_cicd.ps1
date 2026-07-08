# CI/CD Pipeline Validation Tests
# Fáze 4, Úkol 2: Ověření CI/CD pipeline konfigurace

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Fáze 4: CI/CD Pipeline Tests" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$passed = 0
$failed = 0

function Assert-Pass { param([string]$n); Write-Host "  PASS: $n" -ForegroundColor Green; $script:passed++ }
function Assert-Fail { param([string]$n, [string]$d); Write-Host "  FAIL: $n - $d" -ForegroundColor Red; $script:failed++ }

$ciPath = Join-Path $ProjectRoot ".github\workflows\ci.yml"
$ciContent = Get-Content $ciPath -Raw

# --- Test 1: CI file exists ---
Write-Host "Test 1: CI file existence"
if (Test-Path $ciPath) { Assert-Pass ".github/workflows/ci.yml exists" }
else { Assert-Fail "ci.yml" "Not found" }

# --- Test 2: Triggers on push to master ---
Write-Host "Test 2: Push triggers"
if ($ciContent -match 'push:') { Assert-Pass "CI triggers on push" }
else { Assert-Fail "Push trigger" "Missing" }

# --- Test 3: Triggers on PR ---
Write-Host "Test 3: PR triggers"
if ($ciContent -match 'pull_request:') { Assert-Pass "CI triggers on pull_request" }
else { Assert-Fail "PR trigger" "Missing" }

# --- Test 4: Multi-OS matrix (Windows + Ubuntu) ---
Write-Host "Test 4: Multi-OS support"
if ($ciContent -match 'windows-latest' -and $ciContent -match 'ubuntu-latest') {
    Assert-Pass "CI matrix: Windows + Ubuntu"
} else { Assert-Fail "Multi-OS" "Missing" }

# --- Test 5: All test scripts referenced ---
Write-Host "Test 5: Test script coverage"
$testScripts = @(
    "test_protocol.ps1",
    "test_production_standards.ps1",
    "test_fallback.ps1",
    "test_disaster_recovery.ps1",
    "integration_tests.ps1",
    "test_docker.ps1"
)
$allFound = $true
foreach ($test in $testScripts) {
    if ($ciContent -notmatch [regex]::Escape($test)) {
        Assert-Fail "Missing test" $test
        $allFound = $false
    }
}
if ($allFound) { Assert-Pass "All 6 test scripts referenced in CI" }

# --- Test 6: Docker build steps ---
Write-Host "Test 6: Docker build in pipeline"
if ($ciContent -match 'docker-build' -and $ciContent -match 'build-push-action') {
    Assert-Pass "Docker build job configured"
} else { Assert-Fail "Docker build" "Missing" }

# --- Test 7: 3 Docker images built ---
Write-Host "Test 7: Docker image count"
$imageTags = ([regex]::Matches($ciContent, 'tags: opencode-swarm/(\S+)')).Count
if ($imageTags -ge 3) { Assert-Pass "3 Docker images tagged in build ($imageTags found)" }
else { Assert-Fail "Docker images" "Only $imageTags found" }

# --- Test 8: E2E verification step ---
Write-Host "Test 8: E2E verification"
if ($ciContent -match 'e2e-check') { Assert-Pass "E2E verification job exists" }
else { Assert-Fail "E2E verification" "Missing" }

# --- Test 9: Deployment asset verification ---
Write-Host "Test 9: Deployment asset check"
if ($ciContent -match 'docker-compose.yml' -and $ciContent -match '.env.example') {
    Assert-Pass "Deployment assets verified in pipeline"
} else { Assert-Fail "Deployment assets" "Not verified" }

# --- Test 10: GitHub Actions workflow is valid YAML ---
Write-Host "Test 10: YAML validity"
try {
    $firstLine = (Get-Content $ciPath)[0]
    if ($firstLine -match '^name:' -and $ciContent -match '\bon:') { Assert-Pass "YAML has valid structure (name, on)" }
    else { Assert-Fail "YAML structure" "Missing name/on" }
} catch { Assert-Fail "YAML parse" $_.Exception.Message }

# --- Test 11: Cache configuration ---
Write-Host "Test 11: Docker cache"
if ($ciContent -match 'cache-from: type=gha') { Assert-Pass "Docker cache-from: gha configured" }
else { Assert-Fail "Docker cache" "No GHA cache" }

# --- Test 12: Node version pinned ---
Write-Host "Test 12: Node version"
if ($ciContent -match 'NODE_VERSION.*"22"' -or $ciContent -match 'node-version.+22') {
    Assert-Pass "Node.js 22 specified"
} else { Assert-Fail "Node version" "Not 22 or missing" }

# --- Summary ---
Write-Host ""
Write-Host "=== Fáze 4 / Úkol 2 Results ===" -ForegroundColor Cyan
Write-Host "Passed: $passed" -ForegroundColor Green
if ($failed -gt 0) { Write-Host "Failed: $failed" -ForegroundColor Red; throw "$failed test(s) failed" }
else { Write-Host "Failed: $failed" -ForegroundColor Gray; Write-Host "ALL TESTS PASSED" -ForegroundColor Green }