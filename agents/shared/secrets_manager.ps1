# Swarm Secrets Manager
# Secure handling of API keys, tokens, and credentials via environment variables
# Production Rule: NEVER hardcode secrets - always use this module

function Initialize-Secrets {
    param([string]$EnvFile = ".env")

    $envPath = Join-Path $PSScriptRoot "..\..\$EnvFile"

    if (-not (Test-Path $envPath)) {
        Write-Host "[SECRETS] No ${EnvFile} file found at ${envPath} - using system environment variables only"
        return
    }

    Write-Host "[SECRETS] Loading secrets from ${envPath}"
    Get-Content $envPath | Where-Object { $_ -match '^\s*[^#]' -and $_ -match '=' } | ForEach-Object {
        $line = $_.Trim()
        $delimiterIndex = $line.IndexOf('=')
        if ($delimiterIndex -gt 0) {
            $key = $line.Substring(0, $delimiterIndex).Trim()
            $value = $line.Substring($delimiterIndex + 1).Trim().Trim('"').Trim("'")

            if (-not [Environment]::GetEnvironmentVariable($key, 'Process')) {
                [Environment]::SetEnvironmentVariable($key, $value, 'Process')
                Write-Host "[SECRETS] Loaded: ${key}=***"
            }
        }
    }
}

function Get-Secret {
    param(
        [Parameter(Mandatory)] [string]$Key,
        [switch]$Required
    )

    $value = [Environment]::GetEnvironmentVariable($key, 'Process')
    if (-not $value) {
        $value = [Environment]::GetEnvironmentVariable($key, 'User')
    }
    if (-not $value) {
        $value = [Environment]::GetEnvironmentVariable($key, 'Machine')
    }

    if (-not $value -and $Required) {
        throw "SECRETS_ERROR: Required secret '${Key}' is not set. Add it to .env or environment variables."
    }

    return $value
}

function Set-Secret {
    param(
        [Parameter(Mandatory)] [string]$Key,
        [Parameter(Mandatory)] [string]$Value
    )

    [Environment]::SetEnvironmentVariable($Key, $Value, 'Process')
    Write-Host "[SECRETS] Set: ${Key}=***"
}

function Test-SecretsConfigured {
    param([Parameter(Mandatory)] [string[]]$RequiredKeys)

    $missing = @()
    foreach ($key in $RequiredKeys) {
        $value = Get-Secret -Key $key
        if (-not $value) { $missing += $key }
    }

    return @{
        AllConfigured = ($missing.Count -eq 0)
        Missing       = $missing
        RequiredCount = $RequiredKeys.Count
    }
}

function Format-SecretSafe {
    param([string]$Value)

    if (-not $Value) { return "[NOT SET]" }
    if ($Value.Length -le 8) { return "****" }
    return $Value.Substring(0, 4) + "****" + $Value.Substring($Value.Length - 4)
}

function Scan-ForHardcodedSecrets {
    param([Parameter(Mandatory)] [string]$Directory)

    $patterns = @(
        '(?i)api[_]?key\s*[=:]\s*["\x27][A-Za-z0-9_\-]{8,}["\x27]',
        '(?i)password\s*[=:]\s*["\x27][^"\x27]{3,}["\x27]',
        '(?i)secret\s*[=:]\s*["\x27][A-Za-z0-9_\-]{8,}["\x27]',
        '(?i)token\s*[=:]\s*["\x27][A-Za-z0-9_\-\.]{8,}["\x27]',
        '(?i)ghp_[A-Za-z0-9]{36}',
        '(?i)gho_[A-Za-z0-9]{36}',
        '(?i)sk-[A-Za-z0-9]{32,}',
        '(?i)Bearer\s+[A-Za-z0-9_\-\.]{20,}'
    )

    $findings = @()
    $excludePaths = @('.git', 'node_modules', '.venv', '__pycache__')

    Get-ChildItem -Path $Directory -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
        $fullPath = $_.FullName
        $excluded = $false
        foreach ($ex in $excludePaths) {
            if ($fullPath -match [regex]::Escape($ex)) { $excluded = $true; break }
        }
        -not $excluded
    } | ForEach-Object {
        $filePath = $_.FullName
        $relativePath = $filePath.Replace($Directory, '.').Replace('\', '/')
        try {
            $content = Get-Content $filePath -Raw -ErrorAction Stop
            foreach ($pattern in $patterns) {
                $matches = [regex]::Matches($content, $pattern)
                foreach ($match in $matches) {
                    $finding = @{
                        File     = $relativePath
                        Line     = (1..($content.Substring(0, $match.Index).Split("`n").Count))[-1]
                        Pattern  = $pattern
                        Match    = $match.Value.Substring(0, [Math]::Min(4, $match.Value.Length)) + "[REDACTED]"
                    }
                    $findings += $finding
                }
            }
        }
        catch { }
    }

    return @{
        Findings    = $findings
        Count       = $findings.Count
        IsSecure    = ($findings.Count -eq 0)
        ScannedPath = $Directory
    }
}