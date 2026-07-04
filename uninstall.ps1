[CmdletBinding()]
param([switch]$RemoveLogs)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $root 'CquCampusNet.psm1') -Force

$taskName = Get-CquTaskName
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Output ('Removed scheduled task: {0}' -f $taskName)
}
else {
    Write-Output 'Scheduled task was not installed.'
}

Remove-CquCredential | Out-Null
Write-Output 'Removed the saved Windows credential.'

if ($RemoveLogs) {
    $logDirectory = Join-Path $root 'logs'
    if (Test-Path -LiteralPath $logDirectory) {
        Remove-Item -LiteralPath $logDirectory -Recurse -Force
        Write-Output 'Removed local logs.'
    }
}
else {
    Write-Output 'Logs were preserved. Pass -RemoveLogs to delete them during uninstall.'
}
