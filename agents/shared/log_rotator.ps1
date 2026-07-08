# Swarm Log Rotator Module
# Automatic log rotation with size-based triggers and retention policies

$Script:DefaultMaxSizeMB = 10
$Script:DefaultMaxFiles  = 5

function Get-LogFileSize {
    param([Parameter(Mandatory)] [string]$LogPath)
    if (Test-Path $LogPath) {
        return (Get-Item $LogPath).Length
    }
    return 0
}

function Format-LogTimestamp {
    return Get-Date -Format "yyyyMMdd_HHmmss"
}

function Rotate-LogFile {
    param(
        [Parameter(Mandatory)] [string]$LogPath,
        [int]$MaxSizeMB = $Script:DefaultMaxSizeMB,
        [int]$MaxFiles  = $Script:DefaultMaxFiles
    )

    if (-not (Test-Path $LogPath)) {
        Write-Host "[ROTATOR] Log file not found: ${LogPath} - skipping rotation"
        return @{ Rotated = $false; Reason = "File not found" }
    }

    $sizeBytes = Get-LogFileSize -LogPath $LogPath
    $maxBytes  = $MaxSizeMB * 1MB

    if ($sizeBytes -lt $maxBytes) {
        Write-Host "[ROTATOR] Log size ${sizeBytes} bytes under ${maxBytes} bytes threshold - no rotation needed"
        return @{ Rotated = $false; SizeBytes = $sizeBytes; MaxBytes = $maxBytes }
    }

    $dir       = Split-Path $LogPath -Parent
    $baseName  = [IO.Path]::GetFileNameWithoutExtension($LogPath)
    $ext       = [IO.Path]::GetExtension($LogPath)
    $timestamp = Format-LogTimestamp

    $rotatedPath = Join-Path $dir "${baseName}_${timestamp}${ext}"

    try {
        Move-Item -Path $LogPath -Destination $rotatedPath -Force
        Write-Host "[ROTATOR] Rotated log: ${LogPath} -> ${rotatedPath}"
    }
    catch {
        Write-Host "[ROTATOR] ERROR: Failed to rotate log: $($_.Exception.Message)"
        return @{ Rotated = $false; Error = $_.Exception.Message }
    }

    $cleanupResult = Remove-OldLogs -LogDir $dir -BaseName $baseName -Extension $ext -MaxFiles $MaxFiles
    $cleanupResult.Rotated = $true
    $cleanupResult.RotatedPath = $rotatedPath
    return $cleanupResult
}

function Remove-OldLogs {
    param(
        [Parameter(Mandatory)] [string]$LogDir,
        [Parameter(Mandatory)] [string]$BaseName,
        [Parameter(Mandatory)] [string]$Extension,
        [int]$MaxFiles = $Script:DefaultMaxFiles
    )

    $pattern = "${BaseName}_*${Extension}"
    $oldLogs = Get-ChildItem -Path $LogDir -Filter $pattern -ErrorAction SilentlyContinue |
               Sort-Object LastWriteTime -Descending

    $deletedCount = 0
    $deletedFiles = @()

    if ($oldLogs.Count -gt $MaxFiles) {
        $toDelete = $oldLogs | Select-Object -Skip $MaxFiles
        foreach ($file in $toDelete) {
            try {
                Remove-Item -Path $file.FullName -Force
                $deletedFiles += $file.Name
                $deletedCount++
                Write-Host "[ROTATOR] Removed old log: $($file.Name)"
            }
            catch {
                Write-Host "[ROTATOR] WARN: Could not delete $($file.Name): $($_.Exception.Message)"
            }
        }
    }

    return @{
        Rotated      = $false
        DeletedCount = $deletedCount
        DeletedFiles = $deletedFiles
        Remaining    = ($oldLogs.Count - $deletedCount)
    }
}

function Invoke-LogRotation {
    param(
        [Parameter(Mandatory)] [string[]]$LogPaths,
        [int]$MaxSizeMB = $Script:DefaultMaxSizeMB,
        [int]$MaxFiles  = $Script:DefaultMaxFiles
    )

    $results = @()
    foreach ($logPath in $LogPaths) {
        $result = Rotate-LogFile -LogPath $logPath -MaxSizeMB $MaxSizeMB -MaxFiles $MaxFiles
        $result.LogPath = $logPath
        $results += $result
    }

    return $results
}

function Get-LogRotationStatus {
    param([Parameter(Mandatory)] [string[]]$LogPaths)

    $status = @()
    foreach ($logPath in $LogPaths) {
        $sizeBytes = Get-LogFileSize -LogPath $logPath
        $status += @{
            Path      = $logPath
            SizeBytes = $sizeBytes
            SizeMB    = [math]::Round($sizeBytes / 1MB, 2)
            Exists    = Test-Path $logPath
        }
    }
    return $status
}