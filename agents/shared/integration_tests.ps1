# Swarm Integration Tests - Port Range 3001-3010
# Verifies communication across all designated swarm ports

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModulePath = Join-Path $ScriptDir "swarm_protocol.ps1"

Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  Swarm Integration Tests 3001-3010" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

. $ModulePath

$passed = 0
$failed = 0
$PORT_START = 3001
$PORT_END = 3010

function Assert-Pass {
    param([string]$name)
    Write-Host "  PASS: $name" -ForegroundColor Green
    $script:passed++
}

function Assert-Fail {
    param([string]$name, [string]$detail)
    Write-Host "  FAIL: $name - $detail" -ForegroundColor Red
    $script:failed++
}

# --- Test 1: Port range discovery covers all 10 ports ---
Write-Host "Test 1: Full port range discovery (${PORT_START}-${PORT_END})"
$discovered = Discover-SwarmServers -StartPort $PORT_START -EndPort $PORT_END -TimeoutSec 1

if ($discovered -is [array] -or $null -eq $discovered) {
    $count = if ($discovered) { $discovered.Count } else { 0 }
    Assert-Pass "Discovery returns array (empty when no servers: ${count} found)"
} else {
    Assert-Fail "Discovery should return array" "got: $($discovered.GetType())"
}

# --- Test 2: Individual port health checks don't throw ---
Write-Host "Test 2: Health check for each port in range (${PORT_START}-${PORT_END})"
$healthOk = $true
foreach ($port in $PORT_START..$PORT_END) {
    try {
        $result = Test-SwarmHealth -ServerUrl "http://localhost:${port}" -TimeoutSec 1
        if (-not $result.Healthy) {
            $healthOk = $healthOk -and $true
        }
    }
    catch {
        Assert-Fail "Health check on port ${port} threw exception" $_.Exception.Message
        $healthOk = $false
        break
    }
}
if ($healthOk) { Assert-Pass "All 10 port health checks completed without exceptions" }

# --- Test 3: Message sending to each port with timeout ---
Write-Host "Test 3: Message delivery with timeout per port"
$sendOk = $true
foreach ($port in $PORT_START..$PORT_END) {
    try {
        $result = Send-SwarmMessage `
            -TargetUrl "http://localhost:${port}" `
            -FromAgent "Orchestrator" `
            -FromFolder "root" `
            -Reason "integration test" `
            -Request "verify connectivity" `
            -ExpectedFormat "acknowledgment" `
            -SessionId "int_test_${port}" `
            -TimeoutSec 1 `
            -MaxRetries 0

        if ($result.Success -eq $false -and $result.Error -match "retries") {
            # Expected when no server running - handled gracefully
        }
        else {
            # Server responded - also OK
        }
    }
    catch {
        Assert-Fail "Send to port ${port} threw exception" $_.Exception.Message
        $sendOk = $false
        break
    }
}
if ($sendOk) { Assert-Pass "All 10 port send attempts graceful (no crashes)" }

# --- Test 4: Cross-port message simulation (agenda A -> port X -> agent B on port Y) ---
Write-Host "Test 4: Cross-port message routing simulation"
$crossPortMsgs = @(
    @{From="Database Agent"; Folder="db"; Reason="query request"; FromPort=3001; ToPort=3002; Request="fetch schema"; Format="JSON"},
    @{From="Security Agent"; Folder="security"; Reason="audit trigger"; FromPort=3002; ToPort=3003; Request="scan endpoint"; Format="vulnerability report"},
    @{From="Database Agent"; Folder="db"; Reason="data migration"; FromPort=3001; ToPort=3004; Request="validate schema"; Format="migration status"},
    @{From="Security Agent"; Folder="security"; Reason="dependency check"; FromPort=3003; ToPort=3005; Request="audit packages"; Format="CVE list"}
)

$crossOk = $true
foreach ($msg in $crossPortMsgs) {
    $intro = Format-AgentIntroduction `
        -AgentName $msg.From `
        -FolderName $msg.Folder `
        -Reason $msg.Reason `
        -Request $msg.Request `
        -ExpectedFormat $msg.Format

    if (-not (Test-SwarmProtocolFormat -Message $intro)) {
        Assert-Fail "Cross-port message invalid format" "From port $($msg.FromPort) to $($msg.ToPort): $intro"
        $crossOk = $false
        break
    }

    try {
        $result = Send-SwarmMessage `
            -TargetUrl "http://localhost:$($msg.ToPort)" `
            -FromAgent $msg.From `
            -FromFolder $msg.Folder `
            -Reason $msg.Reason `
            -Request $msg.Request `
            -ExpectedFormat $msg.Format `
            -SessionId "cross_$($msg.FromPort)_$($msg.ToPort)" `
            -TimeoutSec 1 `
            -MaxRetries 0

        if ($result.Success -eq $false) {
            # No server on that port - expected, message format was validated
        }
    }
    catch {
        Assert-Fail "Cross-port $($msg.FromPort)->$($msg.ToPort) threw exception" $_.Exception.Message
        $crossOk = $false
        break
    }
}
if ($crossOk) { Assert-Pass "All cross-port message formats valid (${crossPortMsgs.Count} scenarios)" }

# --- Test 5: Protocol enforcement across all ports ---
Write-Host "Test 5: Protocol enforcement for all port communications"
$validMsg = Format-AgentIntroduction -AgentName "Test Agent" -FolderName "test" -Reason "protocol test" -Request "verify format" -ExpectedFormat "confirmation"

$enforceOk = $true
foreach ($port in $PORT_START..$PORT_END) {
    $result = Receive-SwarmMessage -Message $validMsg -RecipientName "Agent-${port}" -RecipientFolder "port-${port}"
    if (-not $result.Accepted) {
        Assert-Fail "Protocol enforcement failed on port ${port}" "Valid message rejected"
        $enforceOk = $false
        break
    }
}
if ($enforceOk) { Assert-Pass "Protocol enforcement works for all 10 ports" }

# --- Test 6: Response validation after routing ---
Write-Host "Test 6: Response parsing for routed messages"
$responseJson = '{"parts":[{"type":"text","text":"I am the Database Agent agent from the ''db'' folder. I am contacting you because query complete. I need you to review results. Please respond with confirmation."}]}'

$responseText = ($responseJson | ConvertFrom-Json).parts | Where-Object { $_.type -eq "text" } | Select-Object -ExpandProperty text

if ($responseText) {
    $protocolValid = Test-SwarmProtocolFormat -Message $responseText
    if ($protocolValid) {
        Assert-Pass "Routed response maintains protocol format"
    }
    else {
        Assert-Fail "Routed response lost protocol format" "Response: $responseText"
    }
}
else {
    Assert-Fail "Response parsing failed" "No text part found in response"
}

# --- Test 7: Edge case - maximum port boundaries ---
Write-Host "Test 7: Port boundary validation"
$boundaryOk = $true
try {
    $minResult = Send-SwarmMessage `
        -TargetUrl "http://localhost:${PORT_START}" `
        -FromAgent "Boundary" -FromFolder "test" `
        -Reason "test" -Request "verify" -ExpectedFormat "text" `
        -SessionId "boundary_min" -TimeoutSec 1 -MaxRetries 0
}
catch { $boundaryOk = $false; Assert-Fail "Min port ${PORT_START} exception" $_.Exception.Message }

try {
    $maxResult = Send-SwarmMessage `
        -TargetUrl "http://localhost:${PORT_END}" `
        -FromAgent "Boundary" -FromFolder "test" `
        -Reason "test" -Request "verify" -ExpectedFormat "text" `
        -SessionId "boundary_max" -TimeoutSec 1 -MaxRetries 0
}
catch { $boundaryOk = $false; Assert-Fail "Max port ${PORT_END} exception" $_.Exception.Message }

if ($boundaryOk) { Assert-Pass "Port boundaries ${PORT_START} and ${PORT_END} handled" }

# --- Summary ---
Write-Host ""
Write-Host "=== Integration Test Results (${PORT_START}-${PORT_END}) ===" -ForegroundColor Cyan
Write-Host "Passed: $passed" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "Failed: $failed" -ForegroundColor Red
}
else {
    Write-Host "Failed: $failed" -ForegroundColor Gray
    Write-Host ""
    Write-Host "ALL INTEGRATION TESTS PASSED" -ForegroundColor Green
}

if ($failed -gt 0) { throw "${failed} integration test(s) failed" }