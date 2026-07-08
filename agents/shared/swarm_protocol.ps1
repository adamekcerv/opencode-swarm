# Swarm Communication Protocol Module
# Enforces mandatory introduction format for inter-agent communication via HTTP

$Script:LogFile = Join-Path $PSScriptRoot "swarm_communication.log"

function Write-SwarmLog {
    param([string]$Level, [string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $entry = "$timestamp [$Level] $Message"
    Add-Content -Path $Script:LogFile -Value $entry
    Write-Host $entry
}

function Format-AgentIntroduction {
    param(
        [Parameter(Mandatory)] [string]$AgentName,
        [Parameter(Mandatory)] [string]$FolderName,
        [Parameter(Mandatory)] [string]$Reason,
        [Parameter(Mandatory)] [string]$Request,
        [Parameter(Mandatory)] [string]$ExpectedFormat
    )
    return "I am the $AgentName agent from the '$FolderName' folder. I am contacting you because $Reason. I need you to $Request. Please respond with $ExpectedFormat."
}

function Test-SwarmProtocolFormat {
    param([Parameter(Mandatory)] [string]$Message)

    $MustStart  = $Message.StartsWith("I am the ")
    $HasFolder  = $Message -match "from the '.+' folder"
    $HasBecause = $Message -match "I am contacting you because "
    $HasNeed    = $Message -match "I need you to "
    $HasRespond = $Message -match "Please respond with "
    $EndsDot    = $Message.EndsWith(".")

    return ($MustStart -and $HasFolder -and $HasBecause -and $HasNeed -and $HasRespond -and $EndsDot)
}

function Send-SwarmMessage {
    param(
        [Parameter(Mandatory)] [string]$TargetUrl,
        [Parameter(Mandatory)] [string]$FromAgent,
        [Parameter(Mandatory)] [string]$FromFolder,
        [Parameter(Mandatory)] [string]$Reason,
        [Parameter(Mandatory)] [string]$Request,
        [Parameter(Mandatory)] [string]$ExpectedFormat,
        [Parameter(Mandatory)] [string]$SessionId,
        [string]$Agent = "general",
        [string]$ModelProvider = "openrouter",
        [string]$ModelId = "deepseek/deepseek-v4-flash",
        [int]$TimeoutSec = 30,
        [int]$MaxRetries = 3
    )

    $message = Format-AgentIntroduction -AgentName $FromAgent -FolderName $FromFolder -Reason $Reason -Request $Request -ExpectedFormat $ExpectedFormat

    Write-SwarmLog "INFO" "Sending message from ${FromAgent} (${FromFolder}) to ${TargetUrl}"

    $body = @{
        agent = $Agent
        model = @{
            providerID = $ModelProvider
            modelID    = $ModelId
        }
        parts = @(
            @{
                type = "text"
                text = $message
            }
        )
    } | ConvertTo-Json -Depth 3

    $retryCount = 0
    while ($retryCount -le $MaxRetries) {
        try {
            $response = Invoke-RestMethod -Uri "${TargetUrl}/session/${SessionId}/message" `
                -Method Post `
                -ContentType "application/json" `
                -Body $body `
                -TimeoutSec $TimeoutSec `
                -ErrorAction Stop

            $responseText = ($response.parts | Where-Object { $_.type -eq "text" }).text

            if ($responseText -and (Test-SwarmProtocolFormat -Message $responseText)) {
                Write-SwarmLog "INFO" "Received valid protocol response from ${TargetUrl}"
                return @{ Success = $true; Message = $responseText; Retries = $retryCount }
            }
            elseif ($responseText) {
                Write-SwarmLog "WARN" "Response from ${TargetUrl} does not follow protocol format"
                return @{ Success = $true; Message = $responseText; ProtocolValid = $false; Retries = $retryCount }
            }

            Write-SwarmLog "WARN" "Empty response from ${TargetUrl}, retry ${retryCount}/${MaxRetries}"
            $retryCount++
            if ($retryCount -le $MaxRetries) {
                Start-Sleep -Seconds ([Math]::Pow(2, $retryCount))
            }
        }
        catch {
            $errorMsg = $_.Exception.Message
            Write-SwarmLog "ERROR" "HTTP request to ${TargetUrl} failed: ${errorMsg} (retry ${retryCount}/${MaxRetries})"
            $retryCount++
            if ($retryCount -le $MaxRetries) {
                Start-Sleep -Seconds ([Math]::Pow(2, $retryCount))
            }
        }
    }

    Write-SwarmLog "ERROR" "All retries exhausted for ${TargetUrl}"
    return @{ Success = $false; Error = "Max retries ($MaxRetries) exhausted"; Retries = $MaxRetries }
}

function Receive-SwarmMessage {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [Parameter(Mandatory)] [string]$RecipientName,
        [Parameter(Mandatory)] [string]$RecipientFolder
    )

    if (Test-SwarmProtocolFormat -Message $Message) {
        Write-SwarmLog "INFO" "Received valid protocol message at ${RecipientName} (${RecipientFolder})"
        return @{ Accepted = $true; Message = $Message }
    }

    Write-SwarmLog "WARN" "Received invalid protocol message at ${RecipientName}: rejecting"
    return @{
        Accepted  = $false
        Error     = @"
ERROR: Invalid communication protocol.
Expected format: "I am the [Agent_Name] agent from the [folder_name] folder. I am contacting you because [specific reason]. I need you to [specific request]. Please respond with [expected format]."
Please resend your message using the mandatory introduction format.
"@
        RawMessage = $Message
    }
}

function Discover-SwarmServers {
    param(
        [int]$StartPort = 3001,
        [int]$EndPort = 3010,
        [int]$TimeoutSec = 5
    )

    $servers = @()

    for ($port = $StartPort; $port -le $EndPort; $port++) {
        $serverUrl = "http://localhost:${port}"
        try {
            $response = Invoke-RestMethod -Uri "${serverUrl}/config" `
                -Method Get `
                -TimeoutSec $TimeoutSec `
                -ErrorAction Stop

            $agentInfo = try {
                Invoke-RestMethod -Uri "${serverUrl}/agent" `
                    -Method Get `
                    -TimeoutSec $TimeoutSec `
                    -ErrorAction Stop
            } catch { $null }

            $servers += @{
                Port    = $port
                Url     = $serverUrl
                Config  = $response
                Agents  = $agentInfo
            }

            Write-SwarmLog "INFO" "Discovered server on port ${port}"
        }
        catch {
            Write-SwarmLog "DEBUG" "No server on port ${port}"
        }
    }

    Write-SwarmLog "INFO" "Discovery complete: $($servers.Count) servers found in range ${StartPort}-${EndPort}"
    return $servers
}

function Test-SwarmHealth {
    param(
        [Parameter(Mandatory)] [string]$ServerUrl,
        [int]$TimeoutSec = 5
    )

    try {
        $response = Invoke-RestMethod -Uri "${ServerUrl}/config" `
            -Method Get `
            -TimeoutSec $TimeoutSec `
            -ErrorAction Stop

        Write-SwarmLog "INFO" "Health check passed: ${ServerUrl}"
        return @{ Healthy = $true; Server = $ServerUrl; Config = $response }
    }
    catch {
        $errMsg = $_.Exception.Message
        Write-SwarmLog "ERROR" "Health check failed: ${ServerUrl} - ${errMsg}"
        return @{ Healthy = $false; Server = $ServerUrl; Error = $errMsg }
    }
}

# When dot-sourced, all functions are automatically available to the caller