# Production Standards Tests - Log Rotation & Secrets Management
# Fáze 3, Úkol 1: Rotace logů + Bezpečné ukládání API klíčů

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path (Split-Path $ScriptDir -Parent) -Parent

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  Fáze 3: Produkční Standardy - Test 1" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

. (Join-Path $ScriptDir "log_rotator.ps1")
. (Join-Path $ScriptDir "secrets_manager.ps1")

$passed = 0
$failed = 0

function Assert-Pass { param([string]$n); Write-Host "  PASS: $n" -ForegroundColor Green; $script:passed++ }
function Assert-Fail { param([string]$n, [string]$d); Write-Host "  FAIL: $n - $d" -ForegroundColor Red; $script:failed++ }

# =============================================
# LOG ROTATION TESTS
# =============================================
Write-Host "--- Log Rotation ---"

# Test 1: Log size detection for existing file
$testLog = Join-Path $ScriptDir "test_rotation.log"
"test content" | Out-File $testLog
$size = Get-LogFileSize -LogPath $testLog
if ($size -gt 0) { Assert-Pass "Log file size detection: ${size} bytes" }
else { Assert-Fail "Log file size detection" "Returned 0 for existing file" }

# Test 2: Log size for non-existent file returns 0
$size = Get-LogFileSize -LogPath (Join-Path $ScriptDir "nonexistent.log")
if ($size -eq 0) { Assert-Pass "Non-existent log returns 0 bytes" }
else { Assert-Fail "Non-existent log" "Expected 0, got ${size}" }

# Test 3: Small log not rotated
$result = Rotate-LogFile -LogPath $testLog -MaxSizeMB 1
if (-not $result.Rotated) { Assert-Pass "Small log (under threshold) not rotated" }
else { Assert-Fail "Log rotation threshold" "Small log was rotated incorrectly" }

# Test 4: Rotation creates timestamped backup
$bigLog = Join-Path $ScriptDir "test_big.log"
$content = "x" * (2 * 1024 * 1024)  # 2MB content
[IO.File]::WriteAllText($bigLog, $content)
$result = Rotate-LogFile -LogPath $bigLog -MaxSizeMB 1 -MaxFiles 2
if ($result.Rotated) {
    $rotatedExists = Test-Path $result.RotatedPath
    if ($rotatedExists) { Assert-Pass "Log rotated with timestamped backup" }
    else { Assert-Fail "Log rotation" "Backup file not found: $($result.RotatedPath)" }
}
else { Assert-Fail "Log rotation" "Should have rotated 2MB log with 1MB threshold" }

# Test 5: Old logs cleanup keeps max N files
$oldLog1 = Join-Path $ScriptDir "test_cleanup_1.log"
$oldLog2 = Join-Path $ScriptDir "test_cleanup_2.log"
$oldLog3 = Join-Path $ScriptDir "test_cleanup_3.log"
"" | Out-File $oldLog1; "" | Out-File $oldLog2; "" | Out-File $oldLog3
$result = Remove-OldLogs -LogDir $ScriptDir -BaseName "test_cleanup" -Extension ".log" -MaxFiles 1
if ($result.DeletedCount -ge 2) { Assert-Pass "Old log cleanup: removed $($result.DeletedCount) excess files" }
else { Assert-Fail "Old log cleanup" "Expected >=2 deleted, got $($result.DeletedCount)" }

# Test 6: Log rotation status report
$status = @(Get-LogRotationStatus -LogPaths @($testLog))
if ($status.Count -gt 0 -and $status[0].Exists) { Assert-Pass "Log rotation status report generated" }
else { Assert-Fail "Log rotation status" "Status not generated (Count: $($status.Count))" }

# Test 7: Invoke-LogRotation processes multiple paths
$logs = @($testLog, $bigLog)
$results = Invoke-LogRotation -LogPaths $logs -MaxSizeMB 100
if ($results.Count -eq 2) { Assert-Pass "Batch log rotation processes all paths" }
else { Assert-Fail "Batch log rotation" "Expected 2 results, got $($results.Count)" }

# =============================================
# SECRETS MANAGEMENT TESTS
# =============================================
Write-Host "--- Secrets Management ---"

# Test 8: Get-Secret returns null for unset key
$value = Get-Secret -Key "NONEXISTENT_SWARM_KEY_12345"
if (-not $value) { Assert-Pass "Unset key returns null" }
else { Assert-Fail "Unset key" "Should return null" }

# Test 9: Get-Secret -Required throws for unset key
try {
    Get-Secret -Key "NONEXISTENT_SWARM_KEY_XYZ" -Required
    Assert-Fail "Required secret" "Should have thrown exception"
} catch {
    if ($_.Exception.Message -match "Required secret") {
        Assert-Pass "Required secret throws descriptive error"
    } else { Assert-Fail "Required secret" "Wrong error message" }
}

# Test 10: Set-Secret and Get-Secret round-trip
Set-Secret -Key "SWARM_TEST_KEY" -Value "test_value_123"
$val = Get-Secret -Key "SWARM_TEST_KEY"
if ($val -eq "test_value_123") { Assert-Pass "Secret set/get round-trip" }
else { Assert-Fail "Secret round-trip" "Got: $val" }

# Test 11: Format-SecretSafe masks values
$masked = Format-SecretSafe -Value "sk-thisismysecretkey1234"
if ($masked -match "\*{4}") {
    Assert-Pass "Secret masking: $masked"
} else { Assert-Fail "Secret masking" "Got: $masked" }

# Test 12: Format-SecretSafe for empty value
$masked = Format-SecretSafe -Value ""
if ($masked -eq "[NOT SET]") { Assert-Pass "Empty secret shows [NOT SET]" }
else { Assert-Fail "Empty secret" "Got: $masked" }

# Test 13: Test-SecretsConfigured reports missing keys
$result = Test-SecretsConfigured -RequiredKeys @("SWARM_MISSING_KEY_A", "SWARM_MISSING_KEY_B")
if (-not $result.AllConfigured -and $result.Missing.Count -eq 2) {
    Assert-Pass "Secrets check reports 2 missing"
} else { Assert-Fail "Secrets check" "Wrong missing count" }

# Test 14: Test-SecretsConfigured with existing key
Set-Secret -Key "SWARM_PRESENT_KEY" -Value "exists"
$result = Test-SecretsConfigured -RequiredKeys @("SWARM_PRESENT_KEY")
if ($result.AllConfigured) { Assert-Pass "Secrets check passes when all present" }
else { Assert-Fail "Secrets check" "Failed with present key" }

# Test 15: Scan-ForHardcodedSecrets finds no secrets in source code
$sourceDir = Join-Path $ProjectRoot ".opencode"
$scan = Scan-ForHardcodedSecrets -Directory $sourceDir
if ($scan.IsSecure) { Assert-Pass "Source scan: no hardcoded secrets (.opencode/)" }
else {
    $detail = ($scan.Findings | ForEach-Object { "$($_.File):$($_.Line): $($_.Match)" }) -join " | "
    Assert-Fail "Hardcoded secrets found" "$($scan.Count) finding(s): $detail"
}

# Test 16: Scan-ForHardcodedSecrets detects real hardcoded pattern
$testDir = Join-Path $env:TEMP "swarm_secret_test"
New-Item -ItemType Directory -Path $testDir -Force | Out-Null
@'
const API_KEY = "sk-abcdefghijklmnop12345678"
const normal = "hello"
'@ | Out-File (Join-Path $testDir "test_file.js") -Encoding UTF8

$scan = Scan-ForHardcodedSecrets -Directory $testDir
if (-not $scan.IsSecure -and $scan.Count -ge 1) {
    Assert-Pass "Hardcoded secret detection: found $($scan.Count) violation(s)"
} else { Assert-Fail "Hardcoded secret detection" "Should have detected API key" }

Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue

# Test 17: .env.example exists
$envExample = Join-Path $ProjectRoot ".env.example"
if (Test-Path $envExample) { Assert-Pass ".env.example template exists" }
else { Assert-Fail ".env.example" "Not found" }

# Test 18: .gitignore exists and covers .env
$gitignore = Join-Path $ProjectRoot ".gitignore"
if (Test-Path $gitignore) {
    $content = Get-Content $gitignore -Raw
    if ($content -match "\.env") { Assert-Pass ".gitignore covers .env" }
    else { Assert-Fail ".gitignore" "Does not cover .env" }
    if ($content -match "\.log") { Assert-Pass ".gitignore covers log files" }
    else { Assert-Fail ".gitignore" "Does not cover log files" }
} else { Assert-Fail ".gitignore" "Not found" }

# =============================================
# CLEANUP
# =============================================
$cleanupFiles = @($testLog, (Join-Path $ScriptDir "test_big.log"))
Get-ChildItem -Path $ScriptDir -Filter "test_*.log" -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
}

# =============================================
# SUMMARY
# =============================================
Write-Host ""
Write-Host "=== Fáze 3 / Úkol 1 Results ===" -ForegroundColor Cyan
Write-Host "Passed: $passed" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "Failed: $failed" -ForegroundColor Red
    throw "$failed test(s) failed"
} else {
    Write-Host "Failed: $failed" -ForegroundColor Gray
    Write-Host "ALL TESTS PASSED" -ForegroundColor Green
}