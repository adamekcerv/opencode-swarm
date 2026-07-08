# Swarm Protocol Integration Tests
# Tests the communication protocol without requiring running servers

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ModulePath = Join-Path $ScriptDir "swarm_protocol.ps1"

Write-Host "=== Swarm Protocol Integration Tests ===" -ForegroundColor Cyan
Write-Host ""

# Load module
. $ModulePath

$passed = 0
$failed = 0

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

# --- Test 1: Format-AgentIntroduction generates correct format ---
Write-Host "Test 1: Agent introduction format generation"
$intro = Format-AgentIntroduction -AgentName "Database Agent" -FolderName "db" -Reason "data retrieval" -Request "fetch records" -ExpectedFormat "JSON array"
$expected = "I am the Database Agent agent from the 'db' folder. I am contacting you because data retrieval. I need you to fetch records. Please respond with JSON array."
if ($intro -eq $expected) { Assert-Pass "Format-AgentIntroduction" }
else { Assert-Fail "Format-AgentIntroduction" "mismatch: $intro" }

# --- Test 2: Test-SwarmProtocolFormat validates correct format ---
Write-Host "Test 2: Protocol format validation"
$validMsg = "I am the Security Agent agent from the 'security' folder. I am contacting you because security audit. I need you to scan code. Please respond with report."
if (Test-SwarmProtocolFormat -Message $validMsg) { Assert-Pass "Valid format accepted" }
else { Assert-Fail "Valid format rejected" }

# --- Test 3: Test-SwarmProtocolFormat rejects invalid format ---
Write-Host "Test 3: Invalid format rejection"
$invalidMsgs = @(
    "Hello, can you help me?",
    "I am Agent from folder. I need help.",
    "Missing introduction entirely and no format at all"
)
$allRejected = $true
foreach ($msg in $invalidMsgs) {
    if (Test-SwarmProtocolFormat -Message $msg) {
        $allRejected = $false
        Assert-Fail "Invalid format not rejected" "Message: $msg"
    }
}
if ($allRejected) { Assert-Pass "All invalid formats rejected" }

# --- Test 4: Receive-SwarmMessage accepts valid protocol message ---
Write-Host "Test 4: Receive-SwarmMessage processing"
$result = Receive-SwarmMessage -Message $validMsg -RecipientName "Database Agent" -RecipientFolder "db"
if ($result.Accepted) { Assert-Pass "Valid message accepted by recipient" }
else { Assert-Fail "Valid message rejected" $result.Error }

# --- Test 5: Receive-SwarmMessage rejects invalid protocol message ---
Write-Host "Test 5: Invalid message rejection"
$result = Receive-SwarmMessage -Message "Hey there!" -RecipientName "Security Agent" -RecipientFolder "security"
if (-not $result.Accepted -and $result.Error -like "*ERROR*") { Assert-Pass "Invalid message rejected with error" }
else { Assert-Fail "Invalid message should be rejected" }

# --- Test 6: Send-SwarmMessage timeout handling (no server running) ---
Write-Host "Test 6: HTTP timeout and fallback"
$result = Send-SwarmMessage -TargetUrl "http://localhost:9999" -FromAgent "Test Agent" -FromFolder "test" -Reason "testing" -Request "verify" -ExpectedFormat "text" -SessionId "test_session" -TimeoutSec 2 -MaxRetries 1
if (-not $result.Success) { Assert-Pass "Timeout handled correctly (server unreachable)" }
else { Assert-Fail "Should fail on unreachable server" }

# --- Test 7: Agent profiles contain mandatory protocol format ---
Write-Host "Test 7: Agent profile protocol compliance"
$agentFolders = @(
    @{ Name = "database_agent"; Folder = "db"; Path = Join-Path $ScriptDir "..\db\AGENTS.md" },
    @{ Name = "security_agent"; Folder = "security"; Path = Join-Path $ScriptDir "..\security\AGENTS.md" }
)
foreach ($agent in $agentFolders) {
    if (Test-Path $agent.Path) {
        $content = Get-Content $agent.Path -Raw
        $pattern = "I am the .+ from the '$($agent.Folder)' folder"
        if ($content -match $pattern) { Assert-Pass "$($agent.Name) has protocol in AGENTS.md" }
        else { Assert-Fail "$($agent.Name) missing protocol" }
    }
    else { Assert-Fail "$($agent.Name) AGENTS.md not found" }
}

# --- Test 8: Log file is created ---
Write-Host "Test 8: Communication logging"
$logPath = Join-Path $ScriptDir "swarm_communication.log"
if (Test-Path $logPath) { Assert-Pass "Log file exists" }
else { Assert-Fail "Log file not created" }

# --- Test 9: Mandatory protocol fields present in all formats ---
Write-Host "Test 9: Required protocol fields"
$requiredFields = @("I am the", "agent from the", "I am contacting you because", "I need you to", "Please respond with")
$allPresent = $true
foreach ($field in $requiredFields) {
    if ($validMsg -notmatch [regex]::Escape($field)) {
        $allPresent = $false
        Assert-Fail "Missing required field" $field
    }
}
if ($allPresent) { Assert-Pass "All required protocol fields present" }

# --- Summary ---
Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan
Write-Host "Passed: $passed" -ForegroundColor Green
if ($failed -gt 0) { Write-Host "Failed: $failed" -ForegroundColor Red }
else { Write-Host "Failed: $failed" -ForegroundColor Gray }

if ($failed -eq 0) { Write-Host "ALL TESTS PASSED" -ForegroundColor Green }
else { throw "$failed test(s) failed" }