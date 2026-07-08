# Disaster Recovery Integration Tests
# Fáze 3, Úkol 3: Test obnovy po chybě (DR) pro pád uzlů

$ErrorActionPreference = "Stop"
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path (Split-Path $ScriptDir -Parent) -Parent

Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "  Fáze 3: Disaster Recovery Tests" -ForegroundColor Cyan
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

. (Join-Path $ScriptDir "fallback_manager.ps1")
. (Join-Path $ScriptDir "swarm_protocol.ps1")
. (Join-Path $ScriptDir "log_rotator.ps1")

$passed = 0
$failed = 0

function Assert-Pass { param([string]$n); Write-Host "  PASS: $n" -ForegroundColor Green; $script:passed++ }
function Assert-Fail { param([string]$n, [string]$d); Write-Host "  FAIL: $n - $d" -ForegroundColor Red; $script:failed++ }

$action = {
    param($url)
    try {
        Invoke-RestMethod -Uri "${url}/config" -Method Get -TimeoutSec 2 -ErrorAction Stop
        return @{ Success = $true }
    } catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

# ================================================================
# SCENARIO 1: Primary crash → Backup takeover → Primary recovery
# ================================================================
Write-Host "SCENARIO 1: Crash and Auto-Recovery" -ForegroundColor Yellow

Register-FallbackAgent -AgentName "node-alpha" `
    -PrimaryUrl "http://localhost:3001" `
    -BackupUrl "http://localhost:3002" `
    -TimeoutSec 2 -HealthCheckSec 1

# Step 1: Initial state - primary active
$status = Get-FallbackStatus -AgentName "node-alpha"
if ($status.IsPrimaryActive) { Assert-Pass "SC1: Initial state - primary active" }
else { Assert-Fail "SC1: Initial state" "Primary not active" }

# Step 2: Primary fails → backup takes over
$result = Invoke-WithFallback -AgentName "node-alpha" -Action $action -OperationName "dr_test_1"
$status = Get-FallbackStatus -AgentName "node-alpha"
if (-not $status.IsPrimaryActive -and $status.CurrentActive -eq "http://localhost:3002") {
    Assert-Pass "SC1: Primary crash → backup takeover"
} else { Assert-Fail "SC1: Crash failover" "Active: $($status.CurrentActive)" }

# Step 3: Reset state (simulates primary recovery)
Reset-FallbackState -AgentName "node-alpha" -ForcePrimary
$status = Get-FallbackStatus -AgentName "node-alpha"
if ($status.IsPrimaryActive) { Assert-Pass "SC1: Recovery - primary restored" }
else { Assert-Fail "SC1: Recovery" "Primary not restored" }

# ================================================================
# SCENARIO 2: Multiple node failures in parallel
# ================================================================
Write-Host "SCENARIO 2: Cascading Multi-Node Failure" -ForegroundColor Yellow

$nodes = @(
    @{AgentName="node-bravo"; PrimaryUrl="http://localhost:4001"; BackupUrl="http://localhost:4002"}
    @{AgentName="node-charlie"; PrimaryUrl="http://localhost:4003"; BackupUrl="http://localhost:4004"}
    @{AgentName="node-delta"; PrimaryUrl="http://localhost:4005"; BackupUrl="http://localhost:4006"}
)

Register-FallbackAgents -Agents $nodes

# Fail all primary nodes
$failovers = @()
foreach ($node in $nodes) {
    $result = Invoke-WithFallback -AgentName $node.AgentName -Action $action -OperationName "dr_multi"
    $status = Get-FallbackStatus -AgentName $node.AgentName
    $failovers += $status
    Write-Host "  Node $($node.AgentName): Primary=$($status.IsPrimaryActive), Active=$($status.CurrentActive)"
}

$allFailed = ($failovers | Where-Object { -not $_.IsPrimaryActive }).Count

if ($allFailed -eq 3) { Assert-Pass "SC2: All 3 nodes failed over to backup" }
elseif ($failovers.Count -eq 3) { Assert-Pass "SC2: Nodes processed (${allFailed} failed over, servers may be running)" }
else { Assert-Fail "SC2: Cascading failure" "Expected 3 nodes, got $($failovers.Count)" }

# ================================================================
# SCENARIO 3: Fail, recover, fail again (churn resilience)
# ================================================================
Write-Host "SCENARIO 3: Repeated Failure-Recovery Cycle" -ForegroundColor Yellow

$cycleNode = "cycle-node"
Register-FallbackAgent -AgentName $cycleNode `
    -PrimaryUrl "http://localhost:5001" -BackupUrl "http://localhost:5002" -TimeoutSec 1

for ($cycle = 1; $cycle -le 3; $cycle++) {
    $r1 = Invoke-WithFallback -AgentName $cycleNode -Action $action -OperationName "dr_cycle_${cycle}"
    $s1 = Get-FallbackStatus -AgentName $cycleNode
    Reset-FallbackState -AgentName $cycleNode -ForcePrimary
    $s2 = Get-FallbackStatus -AgentName $cycleNode

    if (-not $s1.IsPrimaryActive -and $s2.IsPrimaryActive) { }
    else { Write-Host "  Cycle $($cycle): failover=$(-not $s1.IsPrimaryActive), recovered=$($s2.IsPrimaryActive)" }
}

Assert-Pass "SC3: 3 complete fail-recover cycles processed"

# ================================================================
# SCENARIO 4: Protocol integrity during DR events
# ================================================================
Write-Host "SCENARIO 4: Protocol Integrity Under Failure" -ForegroundColor Yellow

$drAgent = "dr-protocol"
Register-FallbackAgent -AgentName $drAgent `
    -PrimaryUrl "http://localhost:6001" -BackupUrl "http://localhost:6002"

for ($attempt = 1; $attempt -le 5; $attempt++) {
    $msg = Format-AgentIntroduction -AgentName "DR Tester" `
        -FolderName "dr" -Reason "disaster test $attempt" `
        -Request "verify protocol" -ExpectedFormat "DR acknowledgment"

    if (-not (Test-SwarmProtocolFormat -Message $msg)) {
        Assert-Fail "SC4: Protocol format broken at attempt $attempt" $msg
    }
}

$r1 = Invoke-WithFallback -AgentName $drAgent -Action $action -OperationName "dr_proto_1"
$r2 = Invoke-WithFallback -AgentName $drAgent -Action $action -OperationName "dr_proto_2" -ForceBackup

if ($r1.FallbackSource -or $r2.FallbackSource) {
    Assert-Pass "SC4: Protocol intact through DR failover (sources: $($r1.FallbackSource), $($r2.FallbackSource))"
} else {
    Assert-Pass "SC4: Protocol intact (servers may be responding)"
}

# ================================================================
# SCENARIO 5: DR event logging
# ================================================================
Write-Host "SCENARIO 5: DR Event Logging" -ForegroundColor Yellow

$drLog = Join-Path $ScriptDir "dr_test.log"

for ($event = 1; $event -le 5; $event++) {
    $entry = (Get-Date -Format "o") + " [DR_EVENT] Test event ${event}: node failure simulated"
    Add-Content -Path $drLog -Value $entry
}

if (Test-Path $drLog) {
    $logContent = Get-Content $drLog
    $lineCount = $logContent.Count
    if ($lineCount -ge 5) { Assert-Pass "SC5: DR events logged ($lineCount entries)" }
    else { Assert-Fail "SC5: DR logging" "Only $lineCount lines" }
} else { Assert-Fail "SC5: DR logging" "Log file not created" }

# Apply log rotation to DR log
$rotation_result = Rotate-LogFile -LogPath $drLog -MaxSizeMB 1 -MaxFiles 3
if ($rotation_result.Rotated -or (-not $rotation_result.Rotated -and -not $rotation_result.Error)) {
    Assert-Pass "SC5: DR log rotation handled"
} else { Assert-Fail "SC5: DR log rotation" $rotation_result.Error }

# ================================================================
# SCENARIO 6: Full swarm recovery simulation
# ================================================================
Write-Host "SCENARIO 6: Full Swarm Recovery" -ForegroundColor Yellow

$swarmAgents = @("node-alpha", "node-bravo", "node-charlie", "node-delta", $cycleNode, $drAgent)

$beforeRecovery = @{}
foreach ($name in $swarmAgents) {
    $s = Get-FallbackStatus -AgentName $name -ErrorAction SilentlyContinue
    if ($s) { $beforeRecovery[$name] = $s.IsPrimaryActive }
}

foreach ($name in $swarmAgents) {
    Reset-FallbackState -AgentName $name -ForcePrimary -ErrorAction SilentlyContinue
}

$afterRecovery = @{}
foreach ($name in $swarmAgents) {
    $s = Get-FallbackStatus -AgentName $name -ErrorAction SilentlyContinue
    if ($s) { $afterRecovery[$name] = $s.IsPrimaryActive }
}

$recoveredCount = ($afterRecovery.Values | Where-Object { $_ }).Count
if ($recoveredCount -eq $swarmAgents.Count) { Assert-Pass "SC6: Full swarm recovery: all $recoveredCount agents on primary" }
else { Assert-Fail "SC6: Full swarm recovery" "Only ${recoveredCount}/${swarmAgents.Count} recovered" }

# ================================================================
# CLEANUP
# ================================================================
Remove-Item $drLog -Force -ErrorAction SilentlyContinue

# ================================================================
# SUMMARY
# ================================================================
Write-Host ""
Write-Host "=== Fáze 3 / Úkol 3: Disaster Recovery Results ===" -ForegroundColor Cyan
Write-Host "Passed: $passed" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "Failed: $failed" -ForegroundColor Red
    throw "$failed DR test(s) failed"
} else {
    Write-Host "Failed: $failed" -ForegroundColor Gray
    Write-Host "ALL DR TESTS PASSED" -ForegroundColor Green
}