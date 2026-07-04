# CQU Campus Network Auto Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a dependency-free Windows PowerShell utility that starts at user logon, monitors Chongqing University Dr.COM status, and safely reconnects after a drop.

**Architecture:** Put reusable protocol, configuration, logging, and Windows Credential Manager functions in `CquCampusNet.psm1`. Keep the resident loop in `cqu-campus-net.ps1`, lifecycle operations in `install.ps1` and `uninstall.ps1`, and verify pure behavior with Pester 3-compatible tests before any optional live check.

**Tech Stack:** Windows PowerShell 5.1, .NET Framework HTTP APIs, Windows Credential Manager (`advapi32.dll`), Task Scheduler cmdlets, Pester 3.4+

## Global Constraints

- Support Windows PowerShell 5.1 without third-party runtime dependencies.
- Send credentials only to `https://login.cqu.edu.cn/drcom/login`.
- Store credentials only in the current user's Windows Credential Manager.
- Never log account names, passwords, MAC addresses, or complete IP addresses.
- Default online check interval is exactly 30 seconds and remains editable in `config.psd1`.
- Never issue concurrent status or login requests.
- Tests must not send real credentials or invoke the real login endpoint.

---

## File Map

- `CquCampusNet.psm1`: reusable configuration, JSONP parsing, protocol, redaction, logging, backoff, and credential functions.
- `cqu-campus-net.ps1`: single-instance monitor loop and one-shot diagnostic modes.
- `config.psd1`: user-editable intervals, timeout, and log size.
- `install.ps1`: credential enrollment and current-user scheduled-task registration.
- `uninstall.ps1`: task removal and credential deletion.
- `tests/CquCampusNet.Tests.ps1`: offline unit tests.
- `README.md`: user-facing install, configuration, diagnostics, security, and uninstall guide.

### Task 1: Pure protocol and configuration module

**Files:**
- Create: `CquCampusNet.psm1`
- Create: `config.psd1`
- Test: `tests/CquCampusNet.Tests.ps1`

**Interfaces:**
- Produces: `Read-CquConfig`, `ConvertFrom-CquJsonp`, `Get-CquPortalState`, `New-CquLoginParameters`, `Get-CquBackoffSeconds`, `Protect-CquLogMessage`, and `Write-CquLog`.
- `Get-CquPortalState` returns a PSCustomObject with `Reachable`, `Online`, `IPv4`, `IPv6`, and `Message` properties.

- [ ] Write failing Pester tests for JSONP parsing, online/offline state, protocol parameters, configuration bounds, backoff capping, and redaction.
- [ ] Run `Invoke-Pester .\tests\CquCampusNet.Tests.ps1` and verify failures identify missing functions.
- [ ] Implement the minimal pure functions and default configuration.
- [ ] Run `Invoke-Pester .\tests\CquCampusNet.Tests.ps1` and verify all tests pass.
- [ ] Commit with `git commit -m "feat: add CQU portal protocol module"`.

### Task 2: HTTP status and login operations

**Files:**
- Modify: `CquCampusNet.psm1`
- Modify: `tests/CquCampusNet.Tests.ps1`

**Interfaces:**
- Produces: `Invoke-CquStatusRequest -TimeoutSeconds <int>` and `Invoke-CquLoginRequest -Credential <PSCredential> -PortalState <pscustomobject> -TimeoutSeconds <int>`.
- Both functions return sanitized structured objects; callers do not inspect raw response text.

- [ ] Add tests using injected request scriptblocks so no test reaches the network.
- [ ] Verify tests fail because HTTP wrapper functions are absent.
- [ ] Implement HTTPS-only endpoints, bounded timeout, JSONP parsing, URL encoding, and response normalization.
- [ ] Run the full Pester suite and verify it passes without network access.
- [ ] Commit with `git commit -m "feat: add status and login requests"`.

### Task 3: Windows Credential Manager integration

**Files:**
- Modify: `CquCampusNet.psm1`
- Modify: `tests/CquCampusNet.Tests.ps1`

**Interfaces:**
- Produces: `Set-CquCredential`, `Get-CquCredential`, and `Remove-CquCredential` using target `CQUCampusNetAutoLogin`.
- `Get-CquCredential` returns `PSCredential` or `$null`.

- [ ] Add safe tests for target-name constants and missing-credential behavior without storing a real secret.
- [ ] Implement the minimal `CredWriteW`, `CredReadW`, `CredDeleteW`, and `CredFree` interop wrapper.
- [ ] Ensure unmanaged credential memory is always released and plaintext variables are short-lived.
- [ ] Run the full Pester suite.
- [ ] Commit with `git commit -m "feat: store credentials in Windows Credential Manager"`.

### Task 4: Monitor process

**Files:**
- Create: `cqu-campus-net.ps1`
- Modify: `tests/CquCampusNet.Tests.ps1`

**Interfaces:**
- Supports `-Once` for one monitor cycle and `-StatusOnly` for a credential-free status check.
- Default execution holds a named mutex and runs the configured monitor loop.

- [ ] Add static tests proving `-StatusOnly` cannot call `Invoke-CquLoginRequest` and that the script imports the local module.
- [ ] Implement single-instance control, online interval sleep, failure backoff, missing-credential handling, and post-login verification.
- [ ] Run one local `-StatusOnly` check; it may report online, offline, or unreachable but must not prompt or submit credentials.
- [ ] Run the full Pester suite.
- [ ] Commit with `git commit -m "feat: add resilient background monitor"`.

### Task 5: Install and uninstall lifecycle

**Files:**
- Create: `install.ps1`
- Create: `uninstall.ps1`
- Modify: `tests/CquCampusNet.Tests.ps1`

**Interfaces:**
- `install.ps1` prompts with `Get-Credential`, stores it, and registers task `CQU Campus Network Auto Login` for the current user.
- `uninstall.ps1` unregisters the task, removes the credential, and leaves logs unless `-RemoveLogs` is supplied.

- [ ] Add static tests for hidden PowerShell launch, logon trigger, non-parallel task policy, and symmetric target/task names.
- [ ] Implement idempotent installer and uninstaller with clear errors and no automatic live login.
- [ ] Parse all scripts with the PowerShell parser and verify zero syntax errors.
- [ ] Run the full Pester suite.
- [ ] Commit with `git commit -m "feat: add Windows installation lifecycle"`.

### Task 6: Documentation and release readiness

**Files:**
- Create: `README.md`
- Modify: `.gitignore`

**Interfaces:**
- Documents installation, configuration, immediate diagnostic commands, logs, security, updating credentials, uninstalling, and GitHub usage.

- [ ] Write concise Chinese documentation with copy-paste commands.
- [ ] Verify every documented file and command exists.
- [ ] Run parser checks, the full Pester suite, `git diff --check`, and a credential-free status check.
- [ ] Confirm `git status` contains no logs or secrets.
- [ ] Commit with `git commit -m "docs: add setup and troubleshooting guide"`.
- [ ] Push `main` with `git push -u origin main`.
