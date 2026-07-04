Set-StrictMode -Version 2.0

$script:PortalBaseUri = 'https://login.cqu.edu.cn'
$script:CredentialTarget = 'CQUCampusNetAutoLogin'
$script:TaskName = 'CQU Campus Network Auto Login'

function Get-CquCredentialTarget { $script:CredentialTarget }
function Get-CquTaskName { $script:TaskName }

function ConvertFrom-CquJsonp {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Text)

    $content = $Text.Trim()
    if ($content -match '^\s*[A-Za-z_$][\w.$]*\s*\((.*)\)\s*;?\s*$') {
        $content = $Matches[1]
    }

    try {
        return $content | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw 'The portal returned an invalid JSON or JSONP response.'
    }
}

function Get-CquPortalState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Response)

    $ipv4 = ''
    foreach ($name in @('v4ip', 'v46ip', 'ss5', 'client_ip', 'userip')) {
        if ($Response.PSObject.Properties[$name] -and $Response.$name) {
            $candidate = [string]$Response.$name
            if ($candidate -match '^\d{1,3}(\.\d{1,3}){3}$' -and $candidate -ne '000.000.000.000') {
                $ipv4 = $candidate
                break
            }
        }
    }

    $ipv6 = ''
    foreach ($name in @('v6ip', 'ipv6', 'UserV6IP')) {
        if ($Response.PSObject.Properties[$name] -and $Response.$name) {
            $candidate = [string]$Response.$name
            if ($candidate.Contains(':') -and $candidate -notmatch '^0+(:0+)+$') {
                $ipv6 = $candidate
                break
            }
        }
    }

    $result = if ($Response.PSObject.Properties['result']) { [string]$Response.result } else { '' }
    $online = $result -eq '1' -or $result.ToLowerInvariant() -eq 'ok'
    $message = if ($Response.PSObject.Properties['msg']) { [string]$Response.msg } else { '' }

    [pscustomobject]@{
        Reachable = $true
        Online    = $online
        IPv4      = $ipv4
        IPv6      = $ipv6
        Message   = $message
    }
}

function Read-CquConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $defaults = @{
        CheckIntervalSeconds  = 30
        FailureBackoffSeconds = @(10, 30, 60, 120, 300)
        RequestTimeoutSeconds = 10
        LogMaxBytes            = 1048576
    }

    $loaded = @{}
    if (Test-Path -LiteralPath $Path) {
        try { $loaded = Import-PowerShellDataFile -LiteralPath $Path -ErrorAction Stop }
        catch { $loaded = @{} }
    }

    $interval = if ($loaded.ContainsKey('CheckIntervalSeconds')) { [int]$loaded.CheckIntervalSeconds } else { $defaults.CheckIntervalSeconds }
    if ($interval -lt 5 -or $interval -gt 86400) { $interval = $defaults.CheckIntervalSeconds }

    $timeout = if ($loaded.ContainsKey('RequestTimeoutSeconds')) { [int]$loaded.RequestTimeoutSeconds } else { $defaults.RequestTimeoutSeconds }
    if ($timeout -lt 2 -or $timeout -gt 60) { $timeout = $defaults.RequestTimeoutSeconds }

    $logMax = if ($loaded.ContainsKey('LogMaxBytes')) { [long]$loaded.LogMaxBytes } else { $defaults.LogMaxBytes }
    if ($logMax -lt 65536 -or $logMax -gt 104857600) { $logMax = $defaults.LogMaxBytes }

    $backoff = @()
    if ($loaded.ContainsKey('FailureBackoffSeconds')) {
        $backoff = @($loaded.FailureBackoffSeconds | ForEach-Object { [int]$_ } | Where-Object { $_ -ge 5 -and $_ -le 3600 })
    }
    if ($backoff.Count -eq 0) { $backoff = $defaults.FailureBackoffSeconds }

    [pscustomobject]@{
        CheckIntervalSeconds  = $interval
        FailureBackoffSeconds = $backoff
        RequestTimeoutSeconds = $timeout
        LogMaxBytes            = $logMax
    }
}

function Get-CquBackoffSeconds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$FailureCount,
        [Parameter(Mandatory = $true)][int[]]$Schedule
    )

    if ($Schedule.Count -eq 0) { return 30 }
    $index = [Math]::Max(0, [Math]::Min($FailureCount - 1, $Schedule.Count - 1))
    return [int]$Schedule[$index]
}

function New-CquLoginParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Management.Automation.PSCredential]$Credential,
        [Parameter(Mandatory = $true)]$PortalState
    )

    $plainPassword = $Credential.GetNetworkCredential().Password
    try {
        return [ordered]@{
            DDDDD         = $Credential.UserName
            upass         = $plainPassword
            '0MKKey'      = '123456'
            R1            = '0'
            R2            = '0'
            R3            = '0'
            R6            = '0'
            para          = '00'
            v4ip          = [string]$PortalState.IPv4
            v6ip          = [string]$PortalState.IPv6
            terminal_type = 1
            lang          = 'zh-cn'
            jsVersion     = '4.2.2'
        }
    }
    finally {
        $plainPassword = $null
    }
}

function ConvertTo-CquQueryString {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Parameters)

    Add-Type -AssemblyName System.Web
    $pairs = foreach ($key in $Parameters.Keys) {
        $encodedKey = [System.Web.HttpUtility]::UrlEncode([string]$key)
        $encodedValue = [System.Web.HttpUtility]::UrlEncode([string]$Parameters[$key])
        '{0}={1}' -f $encodedKey, $encodedValue
    }
    return ($pairs -join '&')
}

function Invoke-CquWebRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [scriptblock]$RequestInvoker
    )

    if ($RequestInvoker) { return & $RequestInvoker $Uri $TimeoutSeconds }
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    return Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec $TimeoutSeconds -ErrorAction Stop
}

function Invoke-CquStatusRequest {
    [CmdletBinding()]
    param(
        [ValidateRange(2, 60)][int]$TimeoutSeconds = 10,
        [scriptblock]$RequestInvoker
    )

    $callback = 'cqu' + (Get-Random -Minimum 100000 -Maximum 999999)
    $uri = '{0}/drcom/chkstatus?callback={1}&v={2}' -f $script:PortalBaseUri, $callback, (Get-Random -Minimum 500 -Maximum 10499)
    try {
        $response = Invoke-CquWebRequest -Uri $uri -TimeoutSeconds $TimeoutSeconds -RequestInvoker $RequestInvoker
        $text = if ($response -is [string]) { $response } else { [string]$response.Content }
        return Get-CquPortalState (ConvertFrom-CquJsonp $text)
    }
    catch {
        return [pscustomobject]@{
            Reachable = $false
            Online    = $false
            IPv4      = ''
            IPv6      = ''
            Message   = $_.Exception.GetType().Name
        }
    }
}

function Invoke-CquLoginRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.Management.Automation.PSCredential]$Credential,
        [Parameter(Mandatory = $true)]$PortalState,
        [ValidateRange(2, 60)][int]$TimeoutSeconds = 10,
        [scriptblock]$RequestInvoker
    )

    if (-not $PortalState.Reachable) { throw 'Refusing to send credentials because the CQU portal is unreachable.' }
    if ([string]::IsNullOrWhiteSpace([string]$PortalState.IPv4) -and [string]::IsNullOrWhiteSpace([string]$PortalState.IPv6)) {
        throw 'Refusing to send credentials because the client IP address is unavailable.'
    }

    $parameters = New-CquLoginParameters -Credential $Credential -PortalState $PortalState
    $parameters.callback = 'cqu' + (Get-Random -Minimum 100000 -Maximum 999999)
    $parameters.v = Get-Random -Minimum 500 -Maximum 10499
    $uri = '{0}/drcom/login?{1}' -f $script:PortalBaseUri, (ConvertTo-CquQueryString $parameters)

    try {
        $response = Invoke-CquWebRequest -Uri $uri -TimeoutSeconds $TimeoutSeconds -RequestInvoker $RequestInvoker
        $text = if ($response -is [string]) { $response } else { [string]$response.Content }
        $parsed = ConvertFrom-CquJsonp $text
        $result = if ($parsed.PSObject.Properties['result']) { [string]$parsed.result } else { '' }
        $message = if ($parsed.PSObject.Properties['msg']) { [string]$parsed.msg } else { '' }
        return [pscustomobject]@{
            Success = ($result -eq '1' -or $result.ToLowerInvariant() -eq 'ok')
            Message = $message
        }
    }
    catch {
        return [pscustomobject]@{ Success = $false; Message = $_.Exception.GetType().Name }
    }
    finally {
        if ($parameters) {
            $parameters.upass = $null
            $parameters.Clear()
        }
        $uri = $null
    }
}

function Protect-CquLogMessage {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Message,
        [string[]]$SensitiveValues = @()
    )

    $safe = [string]$Message
    foreach ($value in $SensitiveValues) {
        if (-not [string]::IsNullOrEmpty($value)) {
            $safe = [regex]::Replace($safe, [regex]::Escape($value), '[redacted]', 'IgnoreCase')
        }
    }
    $safe = [regex]::Replace($safe, '(?<!\d)(?:\d{1,3}\.){3}\d{1,3}(?!\d)', '[redacted-ip]')
    $safe = [regex]::Replace($safe, '(?i)(?<![0-9a-f])(?:[0-9a-f]{2}[-:]){5}[0-9a-f]{2}(?![0-9a-f])', '[redacted-mac]')
    $safe = [regex]::Replace($safe, '(?i)(?<![0-9a-f:])(?:[0-9a-f]{0,4}:){2,}[0-9a-f:]{0,4}(?![0-9a-f:])', '[redacted-ipv6]')
    if ($safe.Length -gt 500) { $safe = $safe.Substring(0, 500) + '...' }
    return $safe
}

function Write-CquLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level,
        [Parameter(Mandatory = $true)][string]$Message,
        [long]$MaxBytes = 1048576,
        [string[]]$SensitiveValues = @()
    )

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    if ((Test-Path -LiteralPath $Path) -and (Get-Item -LiteralPath $Path).Length -ge $MaxBytes) {
        $oldPath = $Path + '.old'
        if (Test-Path -LiteralPath $oldPath) { Remove-Item -LiteralPath $oldPath -Force }
        Move-Item -LiteralPath $Path -Destination $oldPath -Force
    }
    $safe = Protect-CquLogMessage -Message $Message -SensitiveValues $SensitiveValues
    Add-Content -LiteralPath $Path -Value ('{0:u} [{1}] {2}' -f (Get-Date), $Level, $safe) -Encoding UTF8
}

function Initialize-CquCredentialInterop {
    if ('CquCredential.NativeMethods' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace CquCredential {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct NativeCredential {
        public UInt32 Flags;
        public UInt32 Type;
        public string TargetName;
        public string Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public UInt32 CredentialBlobSize;
        public IntPtr CredentialBlob;
        public UInt32 Persist;
        public UInt32 AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }
    public static class NativeMethods {
        [DllImport("advapi32.dll", EntryPoint="CredWriteW", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern bool CredWrite(ref NativeCredential credential, UInt32 flags);
        [DllImport("advapi32.dll", EntryPoint="CredReadW", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern bool CredRead(string target, UInt32 type, UInt32 flags, out IntPtr credential);
        [DllImport("advapi32.dll", EntryPoint="CredDeleteW", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern bool CredDelete(string target, UInt32 type, UInt32 flags);
        [DllImport("advapi32.dll", SetLastError=true)]
        public static extern void CredFree(IntPtr buffer);
    }
}
'@
}

function Set-CquCredential {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][System.Management.Automation.PSCredential]$Credential)

    Initialize-CquCredentialInterop
    $password = $Credential.GetNetworkCredential().Password
    $bytes = [Text.Encoding]::Unicode.GetBytes($password)
    $handle = [Runtime.InteropServices.GCHandle]::Alloc($bytes, [Runtime.InteropServices.GCHandleType]::Pinned)
    try {
        $native = New-Object CquCredential.NativeCredential
        $native.Type = 1
        $native.TargetName = $script:CredentialTarget
        $native.CredentialBlobSize = $bytes.Length
        $native.CredentialBlob = $handle.AddrOfPinnedObject()
        $native.Persist = 2
        $native.UserName = $Credential.UserName
        if (-not [CquCredential.NativeMethods]::CredWrite([ref]$native, 0)) {
            throw ('Could not save credential. Win32 error: {0}' -f [Runtime.InteropServices.Marshal]::GetLastWin32Error())
        }
    }
    finally {
        if ($bytes) { [Array]::Clear($bytes, 0, $bytes.Length) }
        if ($handle.IsAllocated) { $handle.Free() }
        $password = $null
    }
}

function Get-CquCredential {
    [CmdletBinding()]
    param()

    Initialize-CquCredentialInterop
    $pointer = [IntPtr]::Zero
    if (-not [CquCredential.NativeMethods]::CredRead($script:CredentialTarget, 1, 0, [ref]$pointer)) {
        return $null
    }
    try {
        $native = [Runtime.InteropServices.Marshal]::PtrToStructure($pointer, [type][CquCredential.NativeCredential])
        $password = if ($native.CredentialBlobSize -gt 0) {
            [Runtime.InteropServices.Marshal]::PtrToStringUni($native.CredentialBlob, [int]($native.CredentialBlobSize / 2))
        } else { '' }
        $secure = ConvertTo-SecureString $password -AsPlainText -Force
        return New-Object System.Management.Automation.PSCredential($native.UserName, $secure)
    }
    finally {
        if ($pointer -ne [IntPtr]::Zero) { [CquCredential.NativeMethods]::CredFree($pointer) }
        $password = $null
    }
}

function Remove-CquCredential {
    [CmdletBinding()]
    param()

    Initialize-CquCredentialInterop
    if ([CquCredential.NativeMethods]::CredDelete($script:CredentialTarget, 1, 0)) { return $true }
    $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if ($errorCode -eq 1168) { return $true }
    throw ('Could not remove credential. Win32 error: {0}' -f $errorCode)
}

Export-ModuleMember -Function @(
    'Get-CquCredentialTarget', 'Get-CquTaskName', 'ConvertFrom-CquJsonp', 'Get-CquPortalState',
    'Read-CquConfig', 'Get-CquBackoffSeconds', 'New-CquLoginParameters', 'Invoke-CquStatusRequest',
    'Invoke-CquLoginRequest', 'Protect-CquLogMessage', 'Write-CquLog', 'Set-CquCredential',
    'Get-CquCredential', 'Remove-CquCredential'
)
