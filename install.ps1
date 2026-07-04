[CmdletBinding()]
param(
    [System.Management.Automation.PSCredential]$Credential,
    [switch]$StartNow
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $root 'CquCampusNet.psm1') -Force

if ($env:OS -ne 'Windows_NT') {
    throw 'This installer supports Windows only.'
}

$requiredFiles = @('CquCampusNet.psm1', 'cqu-campus-net.ps1', 'config.psd1', 'uninstall.ps1')
foreach ($file in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $file))) {
        throw ('Required file is missing: {0}' -f $file)
    }
}

if ($null -eq $Credential) {
    $Credential = Get-Credential -Message 'Enter your CQU campus network account and password.'
}
if ($null -eq $Credential -or [string]::IsNullOrWhiteSpace($Credential.UserName)) {
    throw 'Installation cancelled: no credential was supplied.'
}

Set-CquCredential -Credential $Credential
$Credential = $null

$taskName = Get-CquTaskName
$scriptPath = Join-Path $root 'cqu-campus-net.ps1'
$arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f $scriptPath
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arguments -WorkingDirectory $root
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $identity
$principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet `
    -MultipleInstances IgnoreNew `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'Monitor and reconnect the CQU Dr.COM campus network.' -Force | Out-Null

Write-Output ('Installed scheduled task: {0}' -f $taskName)
& $scriptPath -StatusOnly

if ($StartNow) {
    Start-ScheduledTask -TaskName $taskName
    Write-Output 'Background monitor started.'
}
else {
    Write-Output 'The monitor will start at the next Windows sign-in. Use -StartNow to start it immediately.'
}
