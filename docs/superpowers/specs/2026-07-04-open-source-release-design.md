# 开源发布完善设计

## 目标

将 `cqu-campus-net-auto-login` 完善为可公开维护、可自动验证、具备清晰安全边界的 GitHub 开源项目，并准备首个 `v0.1.0` 标签。

## 许可证

项目采用 MIT License，版权署名为 `Copyright (c) 2026 lok1`。

MIT 允许任何人使用、复制、修改、合并、发布、分发、再许可和销售本软件，但必须保留版权与许可声明。软件按原样提供，不附带任何明示或暗示担保。README 使用通俗中文解释上述权利和免责边界，并链接到完整 `LICENSE`。

## 仓库文件

- `LICENSE`：标准 MIT License 正文，不添加非标准限制。
- `CONTRIBUTING.md`：开发环境、分支和提交建议、测试命令、隐私要求及 PR 检查表。
- `SECURITY.md`：支持版本、安全报告渠道、禁止公开的敏感数据类型和响应预期。
- `CHANGELOG.md`：采用 Keep a Changelog 风格，记录 `0.1.0` 首发内容。
- `.gitattributes`：PowerShell 文件使用 CRLF，Markdown/YAML 使用 LF，统一文本归一化。
- `.github/workflows/test.yml`：Windows CI。
- `.github/ISSUE_TEMPLATE/bug_report.yml`：结构化缺陷报告，要求脱敏。
- `.github/ISSUE_TEMPLATE/feature_request.yml`：功能建议模板。
- `.github/ISSUE_TEMPLATE/config.yml`：关闭空白 Issue，并指向安全报告说明。
- `.github/pull_request_template.md`：测试、安全与隐私检查表。

不加入行为准则和 Dependabot。当前是单维护者、无第三方运行依赖的小型项目，这两项暂时不会带来相称收益。

## 持续集成

GitHub Actions 在 `main` 推送和 Pull Request 时运行，使用 `windows-latest` 与 Windows PowerShell。

工作流只执行：

1. 检出仓库。
2. 使用 PowerShell 解析器检查 `.ps1` 与 `.psm1` 语法。
3. 运行 Pester 离线测试。
4. 确保测试失败时工作流返回非零状态。

CI 不访问重庆大学门户，不创建计划任务，不读写 Windows 凭据管理器，不需要任何 Secret。测试使用自身的小型断言函数，避免 Pester 3、4、5 的 `Should` 语法差异；本地与 CI 可直接使用环境预装的 Pester，不需要联网安装模块。

## 安全与隐私

README、贡献指南和 Issue 模板统一禁止提交账号、密码、完整 IP、MAC、原始门户 URL、未经脱敏的日志或截图。

安全漏洞通过 GitHub Security Advisory 私下报告。`SECURITY.md` 说明维护者会尽快确认，但不承诺固定服务等级。若仓库尚未开启 Private vulnerability reporting，报告者应先通过维护者 GitHub 主页建立联系，不在公开 Issue 透露细节。

所有示例网络地址使用 RFC 5737/3849 文档保留地址。项目继续声明其为个人工具，与重庆大学不存在官方隶属关系。

## README 改进

README 顶部增加 CI、许可证、平台徽章，并补充：

- 当前版本和项目状态。
- 最短安装路径。
- 安装前安全提醒。
- 指向贡献指南、安全政策、变更日志和许可证的链接。
- 开源许可的通俗说明。

不添加会误导用户的下载量、覆盖率或官方认证徽章。

## 发布流程

1. 本地完成语法检查、Pester 测试、隐私扫描与 `git diff --check`。
2. 提交并推送开源治理文件。
3. 确认远程 `main` 与本地一致。
4. 创建带注释标签 `v0.1.0`，标签信息概述首次发布能力。
5. 推送标签。

本轮不自动创建 GitHub Release 页面，因为 Release 正文和二进制附件并非脚本分发所必需；标签足以建立稳定版本点，后续可从该标签手动生成 Release。

## 验收标准

- GitHub 识别仓库为 MIT 许可项目。
- PR 和 `main` 推送触发 Windows 离线测试。
- Issue 与 PR 模板明确阻止敏感信息泄漏。
- README 能让新用户完成安装并理解安全边界。
- 所有本地测试通过，工作区无日志或个人标识。
- `main` 与远程同步，`v0.1.0` 标签可在 GitHub 查看。
