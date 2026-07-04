[CmdletBinding()]
param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$requiredFiles = @(
    'CquCampusNet.psm1',
    'config.psd1',
    'install.ps1',
    'uninstall.ps1',
    'cqu-campus-net.ps1'
)
$missingFiles = @($requiredFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $root $_)) })
if ($missingFiles.Count -gt 0) {
    $message = '缺少必要文件：' + ($missingFiles -join '、') + "`r`n请重新下载完整项目。"
    if ($SelfTest) { throw $message }
    [System.Windows.Forms.MessageBox]::Show($message, 'CQU 校园网自动登录', 'OK', 'Error') | Out-Null
    return
}

Import-Module (Join-Path $root 'CquCampusNet.psm1') -Force
$config = Read-CquConfig -Path (Join-Path $root 'config.psd1')

function Show-LauncherMessage {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Title = 'CQU 校园网自动登录',
        [ValidateSet('Information', 'Warning', 'Error')][string]$Icon = 'Information'
    )
    [System.Windows.Forms.MessageBox]::Show($Message, $Title, 'OK', $Icon) | Out-Null
}

function Set-LauncherBusy {
    param([bool]$Busy, [string]$Message = '')
    foreach ($button in $script:operationButtons) { $button.Enabled = -not $Busy }
    $script:statusLabel.Text = if ($Message) { $Message } else { '就绪' }
    $script:form.UseWaitCursor = $Busy
    [System.Windows.Forms.Application]::DoEvents()
}

function Invoke-LauncherChildScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptName,
        [string]$Arguments = ''
    )
    $scriptPath = Join-Path $root $ScriptName
    $argumentLine = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" {1}' -f $scriptPath, $Arguments
    $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentLine -WindowStyle Hidden -Wait -PassThru
    return $process.ExitCode
}

function Update-LauncherTaskStatus {
    try {
        $taskName = Get-CquTaskName
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($null -eq $task) {
            $script:taskLabel.Text = '后台任务：未安装'
            $script:taskLabel.ForeColor = [System.Drawing.Color]::DimGray
        }
        else {
            $script:taskLabel.Text = '后台任务：' + [string]$task.State
            $script:taskLabel.ForeColor = if ($task.State -eq 'Running') {
                [System.Drawing.Color]::ForestGreen
            } else {
                [System.Drawing.Color]::DarkOrange
            }
        }
    }
    catch {
        $script:taskLabel.Text = '后台任务：无法读取'
        $script:taskLabel.ForeColor = [System.Drawing.Color]::DarkOrange
    }
}

$script:form = New-Object System.Windows.Forms.Form
$script:form.Text = 'CQU 校园网自动登录'
$script:form.StartPosition = 'CenterScreen'
$script:form.ClientSize = New-Object System.Drawing.Size(520, 420)
$script:form.FormBorderStyle = 'FixedDialog'
$script:form.MaximizeBox = $false
$script:form.MinimizeBox = $true
$script:form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Text = '重庆大学校园网自动登录工具'
$titleLabel.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 16, [System.Drawing.FontStyle]::Bold)
$titleLabel.AutoSize = $true
$titleLabel.Location = New-Object System.Drawing.Point(36, 24)
$script:form.Controls.Add($titleLabel)

$subtitleLabel = New-Object System.Windows.Forms.Label
$subtitleLabel.Text = '双击即可管理后台自动登录。个人项目，非重庆大学官方工具。'
$subtitleLabel.AutoSize = $true
$subtitleLabel.ForeColor = [System.Drawing.Color]::DimGray
$subtitleLabel.Location = New-Object System.Drawing.Point(39, 62)
$script:form.Controls.Add($subtitleLabel)

$script:taskLabel = New-Object System.Windows.Forms.Label
$script:taskLabel.Text = '后台任务：正在读取…'
$script:taskLabel.AutoSize = $true
$script:taskLabel.Location = New-Object System.Drawing.Point(40, 94)
$script:form.Controls.Add($script:taskLabel)

function New-LauncherButton {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width = 205)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Size = New-Object System.Drawing.Size($Width, 48)
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $script:form.Controls.Add($button)
    return $button
}

$installButton = New-LauncherButton '安装并立即启动' 40 125
$statusButton = New-LauncherButton '检查当前状态' 275 125
$updateButton = New-LauncherButton '更新账号密码' 40 188
$uninstallButton = New-LauncherButton '卸载自动登录' 275 188
$logsButton = New-LauncherButton '打开日志目录' 40 251
$closeButton = New-LauncherButton '关闭' 275 251
$script:operationButtons = @($installButton, $statusButton, $updateButton, $uninstallButton, $logsButton, $closeButton)

$separator = New-Object System.Windows.Forms.Label
$separator.BorderStyle = 'Fixed3D'
$separator.AutoSize = $false
$separator.Size = New-Object System.Drawing.Size(440, 2)
$separator.Location = New-Object System.Drawing.Point(40, 323)
$script:form.Controls.Add($separator)

$script:statusLabel = New-Object System.Windows.Forms.Label
$script:statusLabel.Text = '就绪'
$script:statusLabel.AutoEllipsis = $true
$script:statusLabel.Size = New-Object System.Drawing.Size(440, 45)
$script:statusLabel.Location = New-Object System.Drawing.Point(40, 340)
$script:statusLabel.ForeColor = [System.Drawing.Color]::DimGray
$script:form.Controls.Add($script:statusLabel)

$installButton.Add_Click({
    Set-LauncherBusy $true '正在安装，请在凭据窗口中输入校园网账号和密码…'
    try {
        $exitCode = Invoke-LauncherChildScript 'install.ps1' '-StartNow'
        if ($exitCode -eq 0) {
            Show-LauncherMessage '安装完成，后台自动登录已经启动。'
            $script:statusLabel.Text = '安装成功'
        } else {
            Show-LauncherMessage '安装未完成。请确认凭据输入正确，并查看系统提示。' -Icon Error
            $script:statusLabel.Text = '安装失败'
        }
    }
    catch {
        Show-LauncherMessage ('安装失败：' + $_.Exception.Message) -Icon Error
        $script:statusLabel.Text = '安装失败'
    }
    finally {
        Set-LauncherBusy $false $script:statusLabel.Text
        Update-LauncherTaskStatus
    }
})

$statusButton.Add_Click({
    Set-LauncherBusy $true '正在检查校园网状态…'
    try {
        $state = Invoke-CquStatusRequest -TimeoutSeconds $config.RequestTimeoutSeconds
        if (-not $state.Reachable) {
            $message = '校园网门户不可达。可能尚未连接校园网，或网络还未就绪。'
            $icon = 'Warning'
        } elseif ($state.Online) {
            $message = '校园网当前已在线。'
            $icon = 'Information'
        } else {
            $message = '校园网门户可达，但当前需要认证。后台程序会尝试自动登录。'
            $icon = 'Warning'
        }
        Show-LauncherMessage $message -Icon $icon
        $script:statusLabel.Text = $message
    }
    catch {
        Show-LauncherMessage ('检查失败：' + $_.Exception.Message) -Icon Error
        $script:statusLabel.Text = '状态检查失败'
    }
    finally { Set-LauncherBusy $false $script:statusLabel.Text }
})

$updateButton.Add_Click({
    Set-LauncherBusy $true '正在更新，请在凭据窗口中输入新的账号和密码…'
    try {
        $exitCode = Invoke-LauncherChildScript 'install.ps1' '-StartNow'
        if ($exitCode -eq 0) {
            Show-LauncherMessage '账号密码已更新。后台程序会使用新的凭据。'
            $script:statusLabel.Text = '凭据更新成功'
        } else {
            Show-LauncherMessage '凭据更新未完成。' -Icon Error
            $script:statusLabel.Text = '凭据更新失败'
        }
    }
    catch {
        Show-LauncherMessage ('更新失败：' + $_.Exception.Message) -Icon Error
        $script:statusLabel.Text = '凭据更新失败'
    }
    finally {
        Set-LauncherBusy $false $script:statusLabel.Text
        Update-LauncherTaskStatus
    }
})

$uninstallButton.Add_Click({
    $answer = [System.Windows.Forms.MessageBox]::Show(
        '确定要删除后台任务和保存的校园网凭据吗？日志会保留。',
        '确认卸载',
        'YesNo',
        'Warning'
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    Set-LauncherBusy $true '正在卸载…'
    try {
        $exitCode = Invoke-LauncherChildScript 'uninstall.ps1'
        if ($exitCode -eq 0) {
            Show-LauncherMessage '卸载完成。计划任务和保存的凭据已删除。'
            $script:statusLabel.Text = '卸载成功'
        } else {
            Show-LauncherMessage '卸载未完成，请重试。' -Icon Error
            $script:statusLabel.Text = '卸载失败'
        }
    }
    catch {
        Show-LauncherMessage ('卸载失败：' + $_.Exception.Message) -Icon Error
        $script:statusLabel.Text = '卸载失败'
    }
    finally {
        Set-LauncherBusy $false $script:statusLabel.Text
        Update-LauncherTaskStatus
    }
})

$logsButton.Add_Click({
    $logDirectory = Join-Path $root 'logs'
    if (-not (Test-Path -LiteralPath $logDirectory)) {
        Show-LauncherMessage '暂时没有日志。后台程序运行后会自动创建日志目录。'
        return
    }
    Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $logDirectory) | Out-Null
})

$closeButton.Add_Click({ $script:form.Close() })

if ($SelfTest) {
    if ($script:operationButtons.Count -ne 6) { throw 'Launcher button count is invalid.' }
    $script:form.Dispose()
    Write-Output 'Launcher self-test passed.'
    return
}

Update-LauncherTaskStatus
[void]$script:form.ShowDialog()
$script:form.Dispose()
