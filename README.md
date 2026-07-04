# CQU Campus Net Auto Login

[![Test](https://github.com/Lok1-bit/cqu-campus-net-auto-login/actions/workflows/test.yml/badge.svg)](https://github.com/Lok1-bit/cqu-campus-net-auto-login/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/platform-Windows-0078D6.svg)](#系统要求)
[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE.svg)](#系统要求)

重庆大学 Dr.COM 校园网自动登录工具。它在 Windows 用户登录后静默运行，定期检查认证状态，并在掉线后自动重新登录。

当前稳定版本为 `v0.1.0`。这是个人维护的非官方项目，与重庆大学不存在隶属或授权关系。

## 功能

- Windows 登录后后台自动启动
- 在线状态定期复查，默认每 30 秒一次
- 掉线后自动登录，失败时逐步延长重试间隔
- 账号密码保存在当前用户的 Windows 凭据管理器中
- 不在重大校园网时不会提交账号密码
- 日志自动脱敏和滚动，不记录账号、密码、MAC 或完整 IP
- 纯 PowerShell 5.1 实现，无第三方运行依赖

## 系统要求

- Windows 10 或 Windows 11
- Windows PowerShell 5.1
- 重庆大学校园网 Dr.COM 门户：`https://login.cqu.edu.cn/`

## 安装

克隆仓库并进入项目目录：

```powershell
git clone https://github.com/Lok1-bit/cqu-campus-net-auto-login.git
cd cqu-campus-net-auto-login
```

请先查看脚本内容并确认仓库来源可信。然后运行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -StartNow
```

系统会弹出安全凭据输入框。输入校园网上网账号和密码后，安装脚本会：

1. 将凭据写入当前用户的 Windows 凭据管理器；
2. 创建登录触发的计划任务 `CQU Campus Network Auto Login`；
3. 执行一次不提交密码的状态检查；
4. 使用 `-StartNow` 时立即启动后台监控。

安装不需要把账号或密码写进任何配置文件。计划任务默认以当前用户、最低权限运行。

## 检查状态

以下命令只读取在线状态，不读取或提交凭据：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\cqu-campus-net.ps1 -StatusOnly
```

可能的结果：

- `online`：已认证；
- `authentication required`：门户可达，但需要登录；
- `unreachable`：不在校园网、网络尚未就绪或门户暂时不可用。

## 修改检查间隔

编辑 [config.psd1](config.psd1)：

```powershell
@{
    CheckIntervalSeconds  = 30
    FailureBackoffSeconds = @(10, 30, 60, 120, 300)
    RequestTimeoutSeconds = 10
    LogMaxBytes            = 1048576
}
```

`CheckIntervalSeconds` 的单位是秒，允许范围为 5–86400。修改后重启计划任务：

```powershell
Stop-ScheduledTask -TaskName 'CQU Campus Network Auto Login'
Start-ScheduledTask -TaskName 'CQU Campus Network Auto Login'
```

## 更新账号或密码

重新运行安装脚本即可覆盖凭据并更新计划任务：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install.ps1 -StartNow
```

## 日志与排错

日志位于 `logs/monitor.log`。达到 `config.psd1` 设置的大小后，旧日志会轮换为 `monitor.log.old`。

查看最近日志：

```powershell
Get-Content .\logs\monitor.log -Tail 30
```

如果后台没有运行，可检查任务状态：

```powershell
Get-ScheduledTask -TaskName 'CQU Campus Network Auto Login'
Get-ScheduledTaskInfo -TaskName 'CQU Campus Network Auto Login'
```

常见情况：

- `Credential is missing`：重新运行 `install.ps1`；
- `portal unreachable`：确认已连接重大校园网；
- 持续登录失败：先在浏览器中手动登录，确认账号状态和密码有效。

## 卸载

删除计划任务和 Windows 凭据，保留日志：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

同时删除日志：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1 -RemoveLogs
```

卸载不会更改 Windows 网络配置，也不会主动注销当前校园网会话。

## 测试

测试使用模拟门户响应，不调用真实登录接口：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester '.\tests\CquCampusNet.Tests.ps1'"
```

## 安全说明

普通登录遵循重大当前 Dr.COM 网页的协议，通过 HTTPS 向 `login.cqu.edu.cn/drcom/login` 提交认证参数。脚本只在重大门户可达、且状态显示未认证时读取凭据。请仅从你信任的副本运行本项目，并在提交修改前确认日志和配置中没有个人信息。

本项目是个人工具，不是重庆大学官方项目。

## 参与项目

- 提交修改前请阅读 [贡献指南](CONTRIBUTING.md)。
- 安全漏洞请按照 [安全政策](SECURITY.md) 私下报告，不要创建公开 Issue。
- 版本变化见 [CHANGELOG](CHANGELOG.md)。

公开讨论和附件中请勿包含校园网账号、密码、完整 IP/MAC、原始门户 URL、未脱敏日志或截图。

## 许可证

项目采用 [MIT License](LICENSE)。在保留版权与许可声明的前提下，你可以使用、修改、分发或商用本软件。软件按原样提供，不附带担保；使用者需自行承担风险。
