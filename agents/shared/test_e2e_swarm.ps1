# End-to-End Swarm Test Suite
# Fáze 4, Úkol 3: Kompletní E2E test celého roje

$ErrorActionPreference = "Stop"
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path (Split-Path $ScriptDir -Parent) -Parent

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  SWARM E2E TEST SUITE" -ForegroundColor Cyan
Write-Host "  OpenCode Swarm Architecture" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$global:passed  = 0
$global:failed  = 0
$global:suites  = @()

function Start-Suite {
    param([string]$name)
    $global:suitePassed = 0
    $global:suiteFailed = 0
    Write-Host "═══ ${name} ═══" -ForegroundColor Yellow
}

function End-Suite {
    param([string]$name)
    $global:suites += @{ Name = $name; Passed = $global:suitePassed; Failed = $global:suiteFailed }
    $global:passed += $global:suitePassed
    $global:failed += $global:suiteFailed
    Write-Host ""
}

function Assert { param([string]$n, [bool]$c); if ($c) { Write-Host "  + $n" -ForegroundColor Green; $global:suitePassed++; $global:passed++ } else { Write-Host "  - $n" -ForegroundColor Red; $global:suiteFailed++; $global:failed++ } }

# ================================================================
# SUITE 1: Project Structure Integrity
# ================================================================
Start-Suite "SUITE 1: Project Structure"

$requiredFiles = @(
    ".opencode/opencode.json",
    ".opencode/agent/orchestrator.md",
    ".opencode/agents/database_agent.md",
    ".opencode/agents/security_agent.md",
    "agents/db/AGENTS.md",
    "agents/db/.opencode/opencode.json",
    "agents/security/AGENTS.md",
    "agents/security/.opencode/opencode.json",
    "agents/shared/swarm_protocol.ps1",
    "agents/shared/fallback_manager.ps1",
    "agents/shared/log_rotator.ps1",
    "agents/shared/secrets_manager.ps1",
    ".env.example",
    ".gitignore",
    ".dockerignore",
    "Dockerfile",
    "agents/db/Dockerfile",
    "agents/security/Dockerfile",
    "docker-compose.yml",
    ".github/workflows/ci.yml",
    "task.md"
)

foreach ($f in $requiredFiles) {
    $exists = Test-Path (Join-Path $ProjectRoot $f)
    Assert $f $exists
}

End-Suite "SUITE 1: Project Structure"

# ================================================================
# SUITE 2: Agent Profiles Validation
# ================================================================
Start-Suite "SUITE 2: Agent Profiles"

$agentFiles = @(
    @{Name="orchestrator"; Path=".opencode/agent/orchestrator.md"; Folder="root"},
    @{Name="database_agent"; Path=".opencode/agents/database_agent.md"; Folder="db"},
    @{Name="security_agent"; Path=".opencode/agents/security_agent.md"; Folder="security"}
)

foreach ($agent in $agentFiles) {
    $content = Get-Content (Join-Path $ProjectRoot $agent.Path) -Raw
    $hasModel = $content -match "model:\s+openrouter/deepseek/deepseek-v4-(pro|flash)"
    $hasMode  = $content -match "mode:\s+(primary|subagent|all)"
    $hasProto = $content -match "I am the .+ from the '"
    Assert "$($agent.Name): has model" $hasModel
    Assert "$($agent.Name): has mode" $hasMode
    Assert "$($agent.Name): has protocol" $hasProto
}

End-Suite "SUITE 2: Agent Profiles"

# ================================================================
# SUITE 3: Communication Protocol
# ================================================================
Start-Suite "SUITE 3: Communication Protocol"

. (Join-Path $ScriptDir "swarm_protocol.ps1")

# Introduction format
$intro = Format-AgentIntroduction -AgentName "E2E Agent" -FolderName "e2e" -Reason "testing" -Request "verify" -ExpectedFormat "JSON"
Assert "Introduction format correct" (Test-SwarmProtocolFormat -Message $intro)

# Protocol rejection
$result = Receive-SwarmMessage -Message "bad message" -RecipientName "E2E" -RecipientFolder "e2e"
Assert "Invalid protocol rejected" (-not $result.Accepted)

# Send to dead port
$result = Send-SwarmMessage -TargetUrl "http://localhost:29999" -FromAgent "E2E" -FromFolder "e2e" -Reason "test" -Request "ping" -ExpectedFormat "text" -SessionId "e2e" -TimeoutSec 1 -MaxRetries 0
Assert "Dead port handled gracefully" (-not $result.Success)

End-Suite "SUITE 3: Communication Protocol"

# ================================================================
# SUITE 4: Fallback & Disaster Recovery
# ================================================================
Start-Suite "SUITE 4: Fallback & DR"

. (Join-Path $ScriptDir "fallback_manager.ps1")

Register-FallbackAgent -AgentName "e2e-dr" -PrimaryUrl "http://localhost:31001" -BackupUrl "http://localhost:31002" -TimeoutSec 1
$s1 = Get-FallbackStatus -AgentName "e2e-dr"
Assert "Primary active by default" $s1.IsPrimaryActive

$action = { param($url); try { Invoke-RestMethod "${url}/config" -TimeoutSec 1; @{Success=$true} } catch { @{Success=$false} } }
$r = Invoke-WithFallback -AgentName "e2e-dr" -Action $action -OperationName "e2e"
$s2 = Get-FallbackStatus -AgentName "e2e-dr"
Assert "Failover triggered" (-not $s2.IsPrimaryActive -or $r.Success)
Assert "Fail count incremented" ($s2.FailCount -gt 0 -or $r.Success)

Reset-FallbackState -AgentName "e2e-dr" -ForcePrimary
$s3 = Get-FallbackStatus -AgentName "e2e-dr"
Assert "Recovery restores primary" $s3.IsPrimaryActive

End-Suite "SUITE 4: Fallback & DR"

# ================================================================
# SUITE 5: Secrets & Security
# ================================================================
Start-Suite "SUITE 5: Secrets & Security"

. (Join-Path $ScriptDir "secrets_manager.ps1")

$scan = Scan-ForHardcodedSecrets -Directory $ProjectRoot
$safeFiles = $scan.Findings | Where-Object { $_.File -notmatch "test_" -and $_.File -notmatch "\.env\.example" }
Assert "No hardcoded secrets in source" ($safeFiles.Count -eq 0)

Set-Secret -Key "E2E_TEST_KEY" -Value "e2e-value"
$val = Get-Secret -Key "E2E_TEST_KEY"
Assert "Secret store/retrieve" ($val -eq "e2e-value")

$masked = Format-SecretSafe -Value "abcdefgh-secret-key-1234"
Assert "Secret masking" ($masked -match "\*{4}")

Assert ".env.example exists" (Test-Path (Join-Path $ProjectRoot ".env.example"))
Assert ".gitignore covers .env" ((Get-Content (Join-Path $ProjectRoot ".gitignore") -Raw) -match "\.env")

End-Suite "SUITE 5: Secrets & Security"

# ================================================================
# SUITE 6: Log Rotation
# ================================================================
Start-Suite "SUITE 6: Log Rotation"

. (Join-Path $ScriptDir "log_rotator.ps1")

$e2eLog = Join-Path $ScriptDir "e2e_test.log"
"content" | Out-File $e2eLog
$size = Get-LogFileSize -LogPath $e2eLog
Assert "Log file size detection" ($size -gt 0)

$result = Rotate-LogFile -LogPath $e2eLog -MaxSizeMB 100
Assert "Log rotation (under threshold)" (-not $result.Rotated)

Remove-Item $e2eLog -Force -ErrorAction SilentlyContinue
Assert "Log cleanup" (-not (Test-Path $e2eLog))

End-Suite "SUITE 6: Log Rotation"

# ================================================================
# SUITE 7: Docker & Deployment
# ================================================================
Start-Suite "SUITE 7: Docker & Deployment"

$composeContent = Get-Content (Join-Path $ProjectRoot "docker-compose.yml") -Raw
$services = @("orchestrator", "database_agent", "security_agent")
foreach ($svc in $services) {
    Assert "docker-compose: $svc" ($composeContent -match $svc)
}

$dockerfiles = @("Dockerfile", "agents/db/Dockerfile", "agents/security/Dockerfile")
foreach ($df in $dockerfiles) {
    $content = Get-Content (Join-Path $ProjectRoot $df) -Raw
    Assert "$df has FROM" ($content -match "FROM node:22-alpine")
    Assert "$df has HEALTHCHECK" ($content -match "HEALTHCHECK")
    Assert "$df has EXPOSE" ($content -match "EXPOSE")
}

Assert "Swarm network configured" ($composeContent -match "swarm-net")
Assert "Persistent volume (db_data)" ($composeContent -match "db_data")
Assert "All restart: unless-stopped" (([regex]::Matches($composeContent, "restart: unless-stopped")).Count -ge 3)

End-Suite "SUITE 7: Docker & Deployment"

# ================================================================
# SUITE 8: CI/CD Pipeline
# ================================================================
Start-Suite "SUITE 8: CI/CD Pipeline"

$ci = Get-Content (Join-Path $ProjectRoot ".github\workflows\ci.yml") -Raw
Assert "Push trigger" ($ci -match 'push:')
Assert "PR trigger" ($ci -match 'pull_request:')
Assert "Multi-OS matrix" ($ci -match 'ubuntu-latest' -and $ci -match 'windows-latest')
Assert "Docker build job" ($ci -match 'docker-build')
Assert "E2E verification" ($ci -match 'e2e-check')
Assert "All tests referenced" (
    ($ci -match 'test_protocol') -and ($ci -match 'test_production_standards') -and
    ($ci -match 'test_fallback') -and ($ci -match 'test_disaster_recovery') -and
    ($ci -match 'integration_tests') -and ($ci -match 'test_docker')
)

End-Suite "SUITE 8: CI/CD Pipeline"

# ================================================================
# SUITE 9: Swarm Integration Scenarios
# ================================================================
Start-Suite "SUITE 9: Swarm Integration"

# Scenario: Orchestrator discovers and routes to agents
$orchestratorPrompt = Get-Content (Join-Path $ProjectRoot ".opencode\agent\orchestrator.md") -Raw
Assert "Orchestrator: discovery" ($orchestratorPrompt -match "Discover")
Assert "Orchestrator: session mgmt" ($orchestratorPrompt -match "Session")
Assert "Orchestrator: protocol enforcement" ($orchestratorPrompt -match "protocol")

# Scenario: Database agent communicates with orchestrator
$dbAgent = Get-Content (Join-Path $ProjectRoot "agents\db\AGENTS.md") -Raw
Assert "DB Agent: identity" ($dbAgent -match "Database Agent")
Assert "DB Agent: protocol" ($dbAgent -match "I am the Database Agent")
Assert "DB Agent: security" ($dbAgent -match "NEVER hardcode")
Assert "DB Agent: reliability" ($dbAgent -match "timeout")

# Scenario: Security agent communicates with orchestrator
$secAgent = Get-Content (Join-Path $ProjectRoot "agents\security\AGENTS.md") -Raw
Assert "Sec Agent: identity" ($secAgent -match "Security Agent")
Assert "Sec Agent: protocol" ($secAgent -match "I am the Security Agent")
Assert "Sec Agent: redaction" ($secAgent -match "REDACTED")
Assert "Sec Agent: timeout" ($secAgent -match "timeout")

# Scenario: Cross-agent message format
$crossMsg = Format-AgentIntroduction -AgentName "Database Agent" -FolderName "db" -Reason "schema update" -Request "review changes" -ExpectedFormat "approval"
$dbValid = Test-SwarmProtocolFormat -Message $crossMsg
$received = Receive-SwarmMessage -Message $crossMsg -RecipientName "Security Agent" -RecipientFolder "security"
Assert "Cross-agent message valid" $dbValid
Assert "Cross-agent accepted" $received.Accepted

End-Suite "SUITE 9: Swarm Integration"

# ================================================================
# FINAL REPORT
# ================================================================
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  E2E SWARM TEST REPORT" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

foreach ($suite in $global:suites) {
    $status = if ($suite.Failed -eq 0) { "PASS" } else { "FAIL" }
    $color = if ($suite.Failed -eq 0) { "Green" } else { "Red" }
    Write-Host ("  {0,-20} +{1,2} -{2,2} [{3}]" -f $suite.Name, $suite.Passed, $suite.Failed, $status) -ForegroundColor $color
}

Write-Host "==========================================" -ForegroundColor Cyan
$totalStatus = if ($global:failed -eq 0) { "ALL PASSED" } else { "FAILURES DETECTED" }
$totalColor = if ($global:failed -eq 0) { "Green" } else { "Red" }
Write-Host ("  TOTAL:  Passed={0}  Failed={1}  [{2}]" -f $global:passed, $global:failed, $totalStatus) -ForegroundColor $totalColor
Write-Host "==========================================" -ForegroundColor Cyan

if ($global:failed -gt 0) { throw "E2E Swarm Test: $global:failed failure(s)" }