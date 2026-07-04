Describe 'CQU campus network core functions' {
    BeforeAll {
        $script:testRoot = Split-Path -Parent $PSScriptRoot
        Import-Module (Join-Path $script:testRoot 'CquCampusNet.psm1') -Force

        function Assert-Equal {
            param($Actual, $Expected)
            if ($Actual -ne $Expected) { throw "Expected '$Expected', got '$Actual'." }
        }

        function Assert-Matches {
            param([string]$Actual, [string]$Pattern)
            if ($Actual -notmatch $Pattern) { throw "Expected value to match '$Pattern'." }
        }

        function Assert-NotMatches {
            param([string]$Actual, [string]$Pattern)
            if ($Actual -match $Pattern) { throw "Expected value not to match '$Pattern'." }
        }

        function Assert-Throws {
            param([scriptblock]$Action)
            $didThrow = $false
            try { & $Action } catch { $didThrow = $true }
            if (-not $didThrow) { throw 'Expected action to throw.' }
        }

        function Assert-DoesNotThrow {
            param([scriptblock]$Action)
            & $Action
        }

        function Assert-GreaterThan {
            param($Actual, $Expected)
            if ($Actual -le $Expected) { throw "Expected '$Actual' to be greater than '$Expected'." }
        }
    }

    Context 'JSON and JSONP parsing' {
        It 'parses plain JSON' {
            $value = ConvertFrom-CquJsonp '{"result":1,"v4ip":"192.0.2.11"}'
            Assert-Equal $value.result 1
        }

        It 'parses JSONP' {
            $value = ConvertFrom-CquJsonp 'dr123({"result":0,"msg":"offline"});'
            Assert-Equal $value.msg 'offline'
        }

        It 'rejects malformed input' {
            Assert-Throws { ConvertFrom-CquJsonp 'not-json' }
        }
    }

    Context 'portal state normalization' {
        It 'recognizes an online response' {
            $state = Get-CquPortalState ([pscustomobject]@{ result = 1; v4ip = '192.0.2.11'; v6ip = '' })
            Assert-Equal $state.Reachable $true
            Assert-Equal $state.Online $true
            Assert-Equal $state.IPv4 '192.0.2.11'
        }

        It 'recognizes an offline response and alternate address field' {
            $state = Get-CquPortalState ([pscustomobject]@{ result = 0; ss5 = '192.0.2.12'; msg = 'offline' })
            Assert-Equal $state.Reachable $true
            Assert-Equal $state.Online $false
            Assert-Equal $state.IPv4 '192.0.2.12'
        }
    }

    Context 'login parameters' {
        It 'builds required Dr.COM fields without exposing unrelated data' {
            $secure = ConvertTo-SecureString 'sample-password' -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential('sample-user', $secure)
            $state = [pscustomobject]@{ IPv4 = '192.0.2.12'; IPv6 = '2001:db8::1' }
            $parameters = New-CquLoginParameters -Credential $credential -PortalState $state

            Assert-Equal $parameters.DDDDD 'sample-user'
            Assert-Equal $parameters.upass 'sample-password'
            Assert-Equal $parameters.'0MKKey' '123456'
            Assert-Equal $parameters.v4ip '192.0.2.12'
            Assert-Equal $parameters.terminal_type 1
        }
    }

    Context 'configuration and backoff' {
        It 'loads valid defaults' {
            $config = Read-CquConfig -Path (Join-Path $script:testRoot 'config.psd1')
            Assert-Equal $config.CheckIntervalSeconds 30
            Assert-Equal $config.RequestTimeoutSeconds 10
        }

        It 'caps backoff at the last value' {
            Assert-Equal (Get-CquBackoffSeconds -FailureCount 99 -Schedule @(10, 30, 60)) 60
        }
    }

    Context 'log redaction' {
        It 'redacts credentials, MAC addresses, and full addresses' {
            $message = 'user=sample-user password=sample-password ip=192.0.2.10 mac=02-00-00-00-00-01'
            $safe = Protect-CquLogMessage -Message $message -SensitiveValues @('sample-user', 'sample-password')

            Assert-NotMatches $safe 'sample-user'
            Assert-NotMatches $safe 'sample-password'
            Assert-NotMatches $safe '192\.0\.2\.10'
            Assert-NotMatches $safe '02-00-00-00-00-01'
        }
    }

    Context 'HTTP wrappers' {
        It 'normalizes a mocked status response without network access' {
            $invoker = { param($Uri, $TimeoutSeconds) 'mockCallback({"result":1,"v4ip":"192.0.2.13"});' }
            $state = Invoke-CquStatusRequest -TimeoutSeconds 2 -RequestInvoker $invoker
            Assert-Equal $state.Reachable $true
            Assert-Equal $state.Online $true
            Assert-Equal $state.IPv4 '192.0.2.13'
        }

        It 'sends a mocked login request only to the HTTPS CQU endpoint' {
            $script:capturedUri = ''
            $invoker = {
                param($Uri, $TimeoutSeconds)
                $script:capturedUri = $Uri
                'mockCallback({"result":1,"msg":"ok"});'
            }
            $secure = ConvertTo-SecureString 'sample-password' -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential('sample-user', $secure)
            $state = [pscustomobject]@{ Reachable = $true; IPv4 = '192.0.2.13'; IPv6 = '' }

            $result = Invoke-CquLoginRequest -Credential $credential -PortalState $state -TimeoutSeconds 2 -RequestInvoker $invoker

            Assert-Equal $result.Success $true
            Assert-Matches $script:capturedUri '^https://login\.cqu\.edu\.cn/drcom/login\?'
            Assert-Matches $script:capturedUri 'DDDDD=sample-user'
            Assert-Matches $script:capturedUri 'upass=sample-password'
        }

        It 'refuses to send credentials without a client address' {
            $secure = ConvertTo-SecureString 'sample-password' -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential('sample-user', $secure)
            $state = [pscustomobject]@{ Reachable = $true; IPv4 = ''; IPv6 = '' }
            Assert-Throws { Invoke-CquLoginRequest -Credential $credential -PortalState $state -RequestInvoker { throw 'must not run' } }
        }
    }

    Context 'Windows integration constants' {
        It 'uses stable symmetric names' {
            Assert-Equal (Get-CquCredentialTarget) 'CQUCampusNetAutoLogin'
            Assert-Equal (Get-CquTaskName) 'CQU Campus Network Auto Login'
        }

        It 'can query the credential manager without storing a secret' {
            Assert-DoesNotThrow { Get-CquCredential }
        }
    }

    Context 'script safety and lifecycle wiring' {
        It 'imports the local module and guards status-only mode before credential access' {
            $content = Get-Content -LiteralPath (Join-Path $script:testRoot 'cqu-campus-net.ps1') -Raw
            Assert-Matches $content 'Import-Module.*CquCampusNet\.psm1'
            $statusPosition = $content.IndexOf('if ($StatusOnly)')
            $credentialPosition = $content.IndexOf('$credential = Get-CquCredential')
            Assert-GreaterThan $statusPosition -1
            Assert-GreaterThan $credentialPosition $statusPosition
        }

        It 'registers a hidden logon task with non-parallel execution' {
            $content = Get-Content -LiteralPath (Join-Path $script:testRoot 'install.ps1') -Raw
            Assert-Matches $content '-WindowStyle Hidden'
            Assert-Matches $content 'New-ScheduledTaskTrigger -AtLogOn'
            Assert-Matches $content '-MultipleInstances IgnoreNew'
            Assert-Matches $content 'Set-CquCredential'
        }

        It 'removes the same task and credential during uninstall' {
            $content = Get-Content -LiteralPath (Join-Path $script:testRoot 'uninstall.ps1') -Raw
            Assert-Matches $content 'Get-CquTaskName'
            Assert-Matches $content 'Unregister-ScheduledTask'
            Assert-Matches $content 'Remove-CquCredential'
        }
    }
}
