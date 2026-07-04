$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$modulePath = Join-Path $root 'CquCampusNet.psm1'

Describe 'CQU campus network core functions' {
    BeforeAll {
        Import-Module $modulePath -Force
    }

    Context 'JSON and JSONP parsing' {
        It 'parses plain JSON' {
            $value = ConvertFrom-CquJsonp '{"result":1,"v4ip":"192.0.2.11"}'
            $value.result | Should Be 1
        }

        It 'parses JSONP' {
            $value = ConvertFrom-CquJsonp 'dr123({"result":0,"msg":"offline"});'
            $value.msg | Should Be 'offline'
        }

        It 'rejects malformed input' {
            { ConvertFrom-CquJsonp 'not-json' } | Should Throw
        }
    }

    Context 'portal state normalization' {
        It 'recognizes an online response' {
            $state = Get-CquPortalState ([pscustomobject]@{ result = 1; v4ip = '192.0.2.11'; v6ip = '' })
            $state.Reachable | Should Be $true
            $state.Online | Should Be $true
            $state.IPv4 | Should Be '192.0.2.11'
        }

        It 'recognizes an offline response and alternate address field' {
            $state = Get-CquPortalState ([pscustomobject]@{ result = 0; ss5 = '192.0.2.12'; msg = 'offline' })
            $state.Reachable | Should Be $true
            $state.Online | Should Be $false
            $state.IPv4 | Should Be '192.0.2.12'
        }
    }

    Context 'login parameters' {
        It 'builds required Dr.COM fields without exposing unrelated data' {
            $secure = ConvertTo-SecureString 'sample-password' -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential('sample-user', $secure)
            $state = [pscustomobject]@{ IPv4 = '192.0.2.12'; IPv6 = '2001:db8::1' }
            $parameters = New-CquLoginParameters -Credential $credential -PortalState $state

            $parameters.DDDDD | Should Be 'sample-user'
            $parameters.upass | Should Be 'sample-password'
            $parameters.'0MKKey' | Should Be '123456'
            $parameters.v4ip | Should Be '192.0.2.12'
            $parameters.terminal_type | Should Be 1
        }
    }

    Context 'configuration and backoff' {
        It 'loads valid defaults' {
            $config = Read-CquConfig -Path (Join-Path $root 'config.psd1')
            $config.CheckIntervalSeconds | Should Be 30
            $config.RequestTimeoutSeconds | Should Be 10
        }

        It 'caps backoff at the last value' {
            Get-CquBackoffSeconds -FailureCount 99 -Schedule @(10, 30, 60) | Should Be 60
        }
    }

    Context 'log redaction' {
        It 'redacts credentials, MAC addresses, and full addresses' {
            $message = 'user=sample-user password=sample-password ip=192.0.2.10 mac=02-00-00-00-00-01'
            $safe = Protect-CquLogMessage -Message $message -SensitiveValues @('sample-user', 'sample-password')

            $safe | Should Not Match 'sample-user'
            $safe | Should Not Match 'sample-password'
            $safe | Should Not Match '192\.0\.2\.10'
            $safe | Should Not Match '02-00-00-00-00-01'
        }
    }

    Context 'HTTP wrappers' {
        It 'normalizes a mocked status response without network access' {
            $invoker = { param($Uri, $TimeoutSeconds) 'mockCallback({"result":1,"v4ip":"192.0.2.13"});' }
            $state = Invoke-CquStatusRequest -TimeoutSeconds 2 -RequestInvoker $invoker
            $state.Reachable | Should Be $true
            $state.Online | Should Be $true
            $state.IPv4 | Should Be '192.0.2.13'
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

            $result.Success | Should Be $true
            $script:capturedUri | Should Match '^https://login\.cqu\.edu\.cn/drcom/login\?'
            $script:capturedUri | Should Match 'DDDDD=sample-user'
            $script:capturedUri | Should Match 'upass=sample-password'
        }

        It 'refuses to send credentials without a client address' {
            $secure = ConvertTo-SecureString 'sample-password' -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential('sample-user', $secure)
            $state = [pscustomobject]@{ Reachable = $true; IPv4 = ''; IPv6 = '' }
            { Invoke-CquLoginRequest -Credential $credential -PortalState $state -RequestInvoker { throw 'must not run' } } | Should Throw
        }
    }

    Context 'Windows integration constants' {
        It 'uses stable symmetric names' {
            Get-CquCredentialTarget | Should Be 'CQUCampusNetAutoLogin'
            Get-CquTaskName | Should Be 'CQU Campus Network Auto Login'
        }

        It 'can query the credential manager without storing a secret' {
            { Get-CquCredential } | Should Not Throw
        }
    }

    Context 'script safety and lifecycle wiring' {
        It 'imports the local module and guards status-only mode before credential access' {
            $content = Get-Content -LiteralPath (Join-Path $root 'cqu-campus-net.ps1') -Raw
            $content | Should Match 'Import-Module.*CquCampusNet\.psm1'
            $statusPosition = $content.IndexOf('if ($StatusOnly)')
            $credentialPosition = $content.IndexOf('$credential = Get-CquCredential')
            $statusPosition | Should BeGreaterThan -1
            $credentialPosition | Should BeGreaterThan $statusPosition
        }

        It 'registers a hidden logon task with non-parallel execution' {
            $content = Get-Content -LiteralPath (Join-Path $root 'install.ps1') -Raw
            $content | Should Match '-WindowStyle Hidden'
            $content | Should Match 'New-ScheduledTaskTrigger -AtLogOn'
            $content | Should Match '-MultipleInstances IgnoreNew'
            $content | Should Match 'Set-CquCredential'
        }

        It 'removes the same task and credential during uninstall' {
            $content = Get-Content -LiteralPath (Join-Path $root 'uninstall.ps1') -Raw
            $content | Should Match 'Get-CquTaskName'
            $content | Should Match 'Unregister-ScheduledTask'
            $content | Should Match 'Remove-CquCredential'
        }
    }
}
