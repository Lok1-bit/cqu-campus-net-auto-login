# 贡献指南

感谢你愿意改进 CQU Campus Net Auto Login。项目体量不大，最有价值的贡献是可复现的问题、兼容性修复、测试和清晰文档。

## 开始之前

- 本项目是个人工具，不是重庆大学官方项目。
- 请勿提交账号、密码、完整 IP 地址、MAC 地址、原始门户 URL、未脱敏日志或未脱敏截图。
- 安全漏洞不要创建公开 Issue，请遵循 [安全政策](SECURITY.md)。
- 功能修改应保持 Windows PowerShell 5.1 兼容，且不得增加不必要的运行依赖。

## 开发流程

1. Fork 仓库并从 `main` 创建短期分支。
2. 让每次提交只解决一个清晰问题。
3. 为行为变化补充离线测试；测试不得调用真实登录接口。
4. 在提交 Pull Request 前运行全部检查。

语法检查：

```powershell
$files = @('CquCampusNet.psm1', 'cqu-campus-net.ps1', 'install.ps1', 'uninstall.ps1', 'tests\CquCampusNet.Tests.ps1')
foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file), [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count) { throw "$file contains syntax errors." }
}
```

测试：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester '.\tests\CquCampusNet.Tests.ps1'"
```

## Pull Request 检查表

- [ ] PowerShell 5.1 语法检查通过。
- [ ] 所有 Pester 测试通过。
- [ ] 新行为有对应测试或明确说明无法自动测试的原因。
- [ ] 文档与实际命令一致。
- [ ] 没有凭据、个人网络标识或未经脱敏的诊断资料。
- [ ] 没有让 CI 或测试访问真实校园网认证接口。

提交贡献即表示你同意按本项目的 [MIT License](LICENSE) 授权你的贡献。
