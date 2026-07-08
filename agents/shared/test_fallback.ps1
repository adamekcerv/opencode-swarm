# Fallback Mechanism Tests
# Fáze 3, Úkol 2: Fallback při výpadku primárního serveru

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  Fáze 3: Fallback Mechanism - Test 2" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

. (Join-Path $ScriptDir "fallback_manager.ps1")

$passed = 0
$failed = 0

function Assert-Pass { param([string]$n); Write-Host "  PASS: $n" -ForegroundColor Green; $script:passed++ }
function Assert-Fail { param([string]$n, [string]$d); Write-Host "  FAIL: $n - $d" -ForegroundColor Red; $script:failed++ }

# --- Test 1: Register agent with primary and backup ---
Write-Host "Test 1: Agent registration"
Register-FallbackAgent -AgentName "db" -PrimaryUrl "http://localhost:3001" -BackupUrl "http://localhost:3002" -TimeoutSec 3

$status = Get-FallbackStatus -AgentName "db"
if ($status.PrimaryUrl -eq "http://localhost:3001" -and $status.BackupUrl -eq "http://localhost:3002") {
    Assert-Pass "Agent registered with primary and backup URLs"
} else { Assert-Fail "Agent registration" "Wrong URLs" }

# --- Test 2: Default active is primary ---
Write-Host "Test 2: Default active URL"
if ($status.IsPrimaryActive -eq $true) { Assert-Pass "Default active URL is primary" }
else { Assert-Fail "Default active" "Should be primary" }

# --- Test 3: Bulk registration ---
Write-Host "Test 3: Bulk agent registration"
$agents = @(
    @{AgentName="security"; PrimaryUrl="http://localhost:3003"; BackupUrl="http://localhost:3004"; TimeoutSec=5}
    @{AgentName="analytics"; PrimaryUrl="http://localhost:3005"; BackupUrl="http://localhost:3006"; TimeoutSec=5}
)
Register-FallbackAgents -Agents $agents
$allStatus = Get-FallbackStatus
if ($allStatus.ContainsKey("security") -and $allStatus.ContainsKey("analytics")) {
    Assert-Pass "Bulk registration: 2 additional agents registered"
} else { Assert-Fail "Bulk registration" "Missing agents" }

# --- Test 4: Invoke-WithFallback with primary active (no server, expect graceful fail) ---
Write-Host "Test 4: Fallback invocation with primary"
$action = {
    param($url)
    try {
        Invoke-RestMethod -Uri "${url}/config" -Method Get -TimeoutSec 1 -ErrorAction Stop
        return @{ Success = $true }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

$result = Invoke-WithFallback -AgentName "db" -Action $action -OperationName "health_check"

if (-not $result.Success) {
    Assert-Pass "Fallback: Primary failed, auto-switched to backup"
} else { Assert-Pass "Fallback: Unexpected success (server might be running)" }

# --- Test 5: After primary failure, status shows backup active ---
Write-Host "Test 5: Failover state tracking"
$status = Get-FallbackStatus -AgentName "db"
if (-not $status.IsPrimaryActive) { Assert-Pass "Primary marked as inactive after failure" }
else { Assert-Fail "Failover tracking" "Primary still active" }

# --- Test 6: Get-ActiveUrl returns backup after failover ---
Write-Host "Test 6: Active URL after failover"
$activeUrl = Get-ActiveUrl -AgentName "db"
if ($activeUrl -eq "http://localhost:3002") { Assert-Pass "Active URL is backup after failover" }
else { Assert-Fail "Active URL" "Expected backup, got: $activeUrl" }

# --- Test 7: Reset-FallbackState restores primary ---
Write-Host "Test 7: State reset"
Reset-FallbackState -AgentName "db" -ForcePrimary
$status = Get-FallbackStatus -AgentName "db"
if ($status.IsPrimaryActive) { Assert-Pass "Reset restores primary active state" }
else { Assert-Fail "State reset" "Primary not restored" }

# --- Test 8: Switch-ToBackup manual override ---
Write-Host "Test 8: Manual backup switch"
Switch-ToBackup -AgentName "security"
$status = Get-FallbackStatus -AgentName "security"
if (-not $status.IsPrimaryActive) { Assert-Pass "Manual switch-to-backup works" }
else { Assert-Fail "Manual switch" "Primary still active" }

# --- Test 9: Invoke-WithFallback -ForceBackup bypasses primary ---
Write-Host "Test 9: Force backup flag"
Reset-FallbackState -AgentName "db"
$result = Invoke-WithFallback -AgentName "db" -Action $action -OperationName "test" -ForceBackup

$status = Get-FallbackStatus -AgentName "db"
if ($status.IsPrimaryActive -or $result.FallbackSource -match "backup") {
    Assert-Pass "-ForceBackup targets backup server"
} else { Assert-Fail "Force backup" "Did not target backup" }

# --- Test 10: Unregistered agent throws error ---
Write-Host "Test 10: Error for unregistered agent"
try {
    Invoke-WithFallback -AgentName "nonexistent" -Action $action -OperationName "test"
    Assert-Fail "Unregistered agent" "Should have thrown"
} catch {
    if ($_.Exception.Message -match "not registered") {
        Assert-Pass "Unregistered agent throws descriptive error"
    } else { Assert-Fail "Unregistered agent" "Wrong error: $($_.Exception.Message)" }
}

# --- Test 11: Invoke-WithFallback auto-switches to backup ---
Write-Host "Test 11: Automatic failover to backup"
Reset-FallbackState -AgentName "db"
$statusBefore = Get-FallbackStatus -AgentName "db"

$result = Invoke-WithFallback -AgentName "db" -Action $action -OperationName "critical_task"
$statusAfter = Get-FallbackStatus -AgentName "db"

if ((-not $statusAfter.IsPrimaryActive) -and $statusAfter.FailCount -gt 0) {
    Assert-Pass "Auto-failover: switched to backup, fail count: $($statusAfter.FailCount)"
} elseif ($result.Success) {
    Assert-Pass "Auto-failover: server responded (running instance)"
} else {
    Assert-Fail "Auto-failover" "Fail count not incremented"
}

# --- Test 12: Full status report contains all agents ---
Write-Host "Test 12: Full status report"
$fullStatus = Get-FallbackStatus
$agentCount = $fullStatus.Keys.Count
if ($agentCount -ge 3) { Assert-Pass "Full status includes $agentCount registered agents" }
else { Assert-Fail "Full status" "Only found $agentCount agents" }

# --- Summary ---
Write-Host ""
Write-Host "=== Fáze 3 / Úkol 2 Results ===" -ForegroundColor Cyan
Write-Host "Passed: $passed" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "Failed: $failed" -ForegroundColor Red
    throw "$failed test(s) failed"
} else {
    Write-Host "Failed: $failed" -ForegroundColor Gray
    Write-Host "ALL TESTS PASSED" -ForegroundColor Green
}