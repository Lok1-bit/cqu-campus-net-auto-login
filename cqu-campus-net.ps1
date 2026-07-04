[CmdletBinding()]
param(
    [switch]$Once,
    [switch]$StatusOnly
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $root 'CquCampusNet.psm1') -Force

$config = Read-CquConfig -Path (Join-Path $root 'config.psd1')
$logPath = Join-Path $root 'logs\monitor.log'

if ($StatusOnly) {
    $state = Invoke-CquStatusRequest -TimeoutSeconds $config.RequestTimeoutSeconds
    if (-not $state.Reachable) {
        Write-Output 'CQU portal is unreachable. You may be off campus or the network is not ready.'
        return
    }
    if ($state.Online) {
        Write-Output 'Campus network status: online.'
        return
    }
    Write-Output 'Campus network status: authentication required.'
    return
}

$mutex = New-Object System.Threading.Mutex($false, 'Local\CQUCampusNetAutoLogin')
$ownsMutex = $false

try {
    try { $ownsMutex = $mutex.WaitOne(0, $false) }
    catch [System.Threading.AbandonedMutexException] { $ownsMutex = $true }

    if (-not $ownsMutex) {
        exit 0
    }

    $failureCount = 0
    $lastStatus = ''

    do {
        $state = Invoke-CquStatusRequest -TimeoutSeconds $config.RequestTimeoutSeconds
        $sleepSeconds = $config.CheckIntervalSeconds

        if (-not $state.Reachable) {
            $failureCount++
            $sleepSeconds = Get-CquBackoffSeconds -FailureCount $failureCount -Schedule $config.FailureBackoffSeconds
            if ($lastStatus -ne 'unreachable' -or $failureCount -eq 1) {
                Write-CquLog -Path $logPath -Level WARN -Message ('CQU portal unreachable ({0}); retry in {1}s.' -f $state.Message, $sleepSeconds) -MaxBytes $config.LogMaxBytes
            }
            $lastStatus = 'unreachable'
        }
        elseif ($state.Online) {
            if ($lastStatus -ne 'online') {
                Write-CquLog -Path $logPath -Level INFO -Message 'Campus network is online.' -MaxBytes $config.LogMaxBytes
            }
            $failureCount = 0
            $lastStatus = 'online'
        }
        else {
            $credential = Get-CquCredential
            if ($null -eq $credential) {
                $failureCount++
                $sleepSeconds = Get-CquBackoffSeconds -FailureCount $failureCount -Schedule $config.FailureBackoffSeconds
                if ($lastStatus -ne 'missing-credential') {
                    Write-CquLog -Path $logPath -Level ERROR -Message 'Credential is missing. Run install.ps1 to configure it.' -MaxBytes $config.LogMaxBytes
                }
                $lastStatus = 'missing-credential'
            }
            else {
                $sensitive = @($credential.UserName, $credential.GetNetworkCredential().Password)
                $loginResult = Invoke-CquLoginRequest -Credential $credential -PortalState $state -TimeoutSeconds $config.RequestTimeoutSeconds
                $credential = $null

                if ($loginResult.Success) {
                    Start-Sleep -Seconds 2
                    $verified = Invoke-CquStatusRequest -TimeoutSeconds $config.RequestTimeoutSeconds
                    if ($verified.Reachable -and $verified.Online) {
                        Write-CquLog -Path $logPath -Level INFO -Message 'Campus network login succeeded and was verified.' -MaxBytes $config.LogMaxBytes
                        $failureCount = 0
                        $lastStatus = 'online'
                        $sleepSeconds = $config.CheckIntervalSeconds
                    }
                    else {
                        $failureCount++
                        $sleepSeconds = Get-CquBackoffSeconds -FailureCount $failureCount -Schedule $config.FailureBackoffSeconds
                        Write-CquLog -Path $logPath -Level WARN -Message 'Login response was successful, but the follow-up status check failed.' -MaxBytes $config.LogMaxBytes
                        $lastStatus = 'verification-failed'
                    }
                }
                else {
                    $failureCount++
                    $sleepSeconds = Get-CquBackoffSeconds -FailureCount $failureCount -Schedule $config.FailureBackoffSeconds
                    Write-CquLog -Path $logPath -Level WARN -Message ('Login failed: {0}' -f $loginResult.Message) -MaxBytes $config.LogMaxBytes -SensitiveValues $sensitive
                    $lastStatus = 'login-failed'
                }
                $sensitive = $null
            }
        }

        if (-not $Once) { Start-Sleep -Seconds $sleepSeconds }
    } while (-not $Once)
}
catch {
    $safeMessage = Protect-CquLogMessage -Message $_.Exception.Message
    Write-CquLog -Path $logPath -Level ERROR -Message ('Monitor stopped unexpectedly: {0}' -f $safeMessage) -MaxBytes $config.LogMaxBytes
    throw
}
finally {
    if ($ownsMutex) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
