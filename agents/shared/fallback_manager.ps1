# Swarm Fallback Manager
# Automatic failover when primary agent server is unreachable

$Script:AgentRegistry = @{}
$Script:FallbackConfigPath = Join-Path $PSScriptRoot "fallback_config.json"
$Script:HealthCache = @{}
$Script:DefaultHealthTTL = 30  # seconds

function Register-FallbackAgent {
    param(
        [Parameter(Mandatory)] [string]$AgentName,
        [Parameter(Mandatory)] [string]$PrimaryUrl,
        [Parameter(Mandatory)] [string]$BackupUrl,
        [int]$TimeoutSec = 30,
        [int]$MaxRetries = 3,
        [int]$HealthCheckSec = 10
    )

    $Script:AgentRegistry[$AgentName] = @{
        PrimaryUrl      = $PrimaryUrl.TrimEnd('/')
        BackupUrl       = $BackupUrl.TrimEnd('/')
        TimeoutSec      = $TimeoutSec
        MaxRetries      = $MaxRetries
        HealthCheckSec  = $HealthCheckSec
        FailCount       = 0
        CurrentActive   = $PrimaryUrl.TrimEnd('/')
        IsPrimaryActive = $true
        LastHealthCheck = [DateTime]::MinValue
    }

    Write-Host "[FALLBACK] Registered ${AgentName}: primary=${PrimaryUrl}, backup=${BackupUrl}"
}

function Register-FallbackAgents {
    param(
        [Parameter(Mandatory)] [array]$Agents
    )

    foreach ($agent in $Agents) {
        Register-FallbackAgent @agent
    }
}

function Get-ActiveUrl {
    param([Parameter(Mandatory)] [string]$AgentName)

    if (-not $Script:AgentRegistry.ContainsKey($AgentName)) {
        return $null
    }

    $info = $Script:AgentRegistry[$AgentName]

    if (-not $info.IsPrimaryActive) {
        $now = Get-Date
        if (($now - $info.LastHealthCheck).TotalSeconds -gt $info.HealthCheckSec) {
            if (Test-ServerHealth -Url $info.PrimaryUrl -TimeoutSec 3) {
                Write-Host "[FALLBACK] ${AgentName}: Primary recovered, switching back"
                $info.IsPrimaryActive = $true
                $info.CurrentActive = $info.PrimaryUrl
                $info.FailCount = 0
                $info.LastHealthCheck = $now
            }
        }
    }

    return $info.CurrentActive
}

function Test-ServerHealth {
    param(
        [Parameter(Mandatory)] [string]$Url,
        [int]$TimeoutSec = 5
    )

    $cacheKey = "${Url}_${TimeoutSec}"

    if ($Script:HealthCache.ContainsKey($cacheKey)) {
        $cached = $Script:HealthCache[$cacheKey]
        $age = (Get-Date) - $cached.Timestamp
        if ($age.TotalSeconds -lt $Script:DefaultHealthTTL) {
            return $cached.Healthy
        }
    }

    try {
        $response = Invoke-RestMethod -Uri "${Url}/config" `
            -Method Get `
            -TimeoutSec $TimeoutSec `
            -ErrorAction Stop `
            -MaximumRedirection 0

        $Script:HealthCache[$cacheKey] = @{
            Healthy   = $true
            Timestamp = Get-Date
        }
        return $true
    }
    catch {
        $Script:HealthCache[$cacheKey] = @{
            Healthy   = $false
            Timestamp = Get-Date
        }
        return $false
    }
}

function Invoke-WithFallback {
    param(
        [Parameter(Mandatory)] [string]$AgentName,
        [Parameter(Mandatory)] [scriptblock]$Action,
        [string]$OperationName = "operation",
        [switch]$ForceBackup
    )

    if (-not $Script:AgentRegistry.ContainsKey($AgentName)) {
        throw "FALLBACK_ERROR: Agent '${AgentName}' is not registered for fallback"
    }

    $info = $Script:AgentRegistry[$AgentName]

    if ($ForceBackup) {
        Write-Host "[FALLBACK] ${AgentName}: Forced backup mode"
        return Invoke-OnUrl -Url $info.BackupUrl -Action $Action -OperationName $OperationName -Info $info -Source "backup (forced)"
    }

    $activeUrl = Get-ActiveUrl -AgentName $AgentName
    $isPrimary = ($activeUrl -eq $info.PrimaryUrl)
    $source = if ($isPrimary) { "primary" } else { "backup (auto-failover)" }

    Write-Host "[FALLBACK] ${AgentName}: Trying ${source}: ${activeUrl}"

    $result = Invoke-OnUrl -Url $activeUrl -Action $Action -OperationName $OperationName -Info $info -Source $source

    if (-not $result.Success -and $source -eq "primary") {
        Write-Host "[FALLBACK] ${AgentName}: Primary failed, switching to backup: $($info.BackupUrl)"
        $info.FailCount++
        $info.IsPrimaryActive = $false
        $info.CurrentActive = $info.BackupUrl
        $info.LastHealthCheck = Get-Date

        $result = Invoke-OnUrl -Url $info.BackupUrl -Action $Action -OperationName $OperationName -Info $info -Source "backup (failover)"
    }

    return $result
}

function Invoke-OnUrl {
    param(
        [Parameter(Mandatory)] [string]$Url,
        [Parameter(Mandatory)] [scriptblock]$Action,
        [string]$OperationName,
        $Info,
        [string]$Source
    )

    try {
        $result = & $Action $Url
        if ($result -is [hashtable] -and $result.ContainsKey('Success')) {
            $result.FallbackSource = $Source
            return $result
        }
        return @{ Success = $true; Data = $result; FallbackSource = $Source }
    }
    catch {
        Write-Host "[FALLBACK] ${AgentName}: ${OperationName} failed on ${Url}: $($_.Exception.Message)"
        return @{ Success = $false; Error = $_.Exception.Message; FallbackSource = $Source }
    }
}

function Get-FallbackStatus {
    param([string]$AgentName)

    if ($AgentName -and $Script:AgentRegistry.ContainsKey($AgentName)) {
        $info = $Script:AgentRegistry[$AgentName]
        return @{
            AgentName      = $AgentName
            PrimaryUrl     = $info.PrimaryUrl
            BackupUrl      = $info.BackupUrl
            IsPrimaryActive = $info.IsPrimaryActive
            CurrentActive  = $info.CurrentActive
            FailCount      = $info.FailCount
        }
    }

    $status = @{}
    foreach ($key in $Script:AgentRegistry.Keys) {
        $info = $Script:AgentRegistry[$key]
        $status[$key] = @{
            PrimaryUrl      = $info.PrimaryUrl
            BackupUrl       = $info.BackupUrl
            IsPrimaryActive = $info.IsPrimaryActive
            CurrentActive   = $info.CurrentActive
            FailCount       = $info.FailCount
        }
    }
    return $status
}

function Reset-FallbackState {
    param(
        [Parameter(Mandatory)] [string]$AgentName,
        [switch]$ForcePrimary
    )

    if ($Script:AgentRegistry.ContainsKey($AgentName)) {
        $info = $Script:AgentRegistry[$AgentName]
        $info.IsPrimaryActive = $true
        $info.CurrentActive = $info.PrimaryUrl
        $info.FailCount = 0
        $info.LastHealthCheck = [DateTime]::MinValue
        Write-Host "[FALLBACK] ${AgentName}: State reset to primary"
    }

    if ($ForcePrimary) {
        $Script:HealthCache = @{}
    }
}

function Switch-ToBackup {
    param(
        [Parameter(Mandatory)] [string]$AgentName,
        [switch]$Force
    )

    if (-not $Script:AgentRegistry.ContainsKey($AgentName)) {
        throw "FALLBACK_ERROR: Agent '${AgentName}' not registered"
    }

    $info = $Script:AgentRegistry[$AgentName]
    $info.IsPrimaryActive = $false
    $info.CurrentActive = $info.BackupUrl
    $info.LastHealthCheck = Get-Date
    Write-Host "[FALLBACK] ${AgentName}: Manually switched to backup: $($info.BackupUrl)"
}