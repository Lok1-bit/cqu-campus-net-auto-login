# Double-Click GUI Launcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a double-click Windows GUI that installs, checks, updates, and uninstalls the campus network monitor without command-line input.

**Architecture:** A minimal CRLF CMD file launches a Windows PowerShell 5.1 WinForms script with the console hidden. The GUI imports the existing module for read-only status and delegates all system mutations to the existing install/uninstall scripts in child PowerShell processes.

**Tech Stack:** Windows batch, Windows PowerShell 5.1, System.Windows.Forms, System.Drawing, Pester 3–5

## Global Constraints

- The only double-click entry file is `CQU校园网工具.cmd`.
- The launcher must work from paths containing spaces or Chinese characters by using `%~dp0` and quoted paths.
- The launcher must never receive, parse, display, log, or save a password.
- Status checks must not call the login endpoint or read credentials.
- Install/update/uninstall reuse `install.ps1` and `uninstall.ps1`; no lifecycle logic is duplicated.
- Automated tests must not show a GUI, prompt for credentials, create tasks, or call the live login endpoint.
- `v0.1.1` is tagged only after local checks and GitHub CI succeed.

---

### Task 1: Launcher and offline wiring tests

**Files:**
- Create: `CQU校园网工具.cmd`
- Create: `launcher.ps1`
- Modify: `.gitattributes`
- Modify: `tests/CquCampusNet.Tests.ps1`

**Interfaces:**
- `CQU校园网工具.cmd` invokes `launcher.ps1` through `powershell.exe`.
- `launcher.ps1 -SelfTest` validates required files and constructs/disposes the form without showing it.
- GUI mutation buttons call `install.ps1 -StartNow` or `uninstall.ps1`; status calls `Invoke-CquStatusRequest`.

- [ ] **Step 1: Add failing static launcher tests**

Add tests that require these exact properties:

```powershell
Assert-Matches $cmdContent 'powershell\.exe'
Assert-Matches $cmdContent '-ExecutionPolicy Bypass'
Assert-Matches $cmdContent '-WindowStyle Hidden'
Assert-Matches $cmdContent '%~dp0launcher\.ps1'
Assert-Matches $guiContent 'Invoke-CquStatusRequest'
Assert-NotMatches $statusBlock 'Invoke-CquLoginRequest'
```

- [ ] **Step 2: Run tests and verify the missing files fail**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester '.\tests\CquCampusNet.Tests.ps1'"
```

Expected: launcher tests fail because the two launcher files do not exist.

- [ ] **Step 3: Implement the CMD entry and WinForms UI**

The batch file launches and exits:

```bat
@echo off
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0launcher.ps1"
exit /b 0
```

The PowerShell script imports WinForms, validates required files, builds the six-button form, disables controls while an operation runs, delegates child scripts through `Start-Process -Wait -PassThru`, and supports `-SelfTest` before `ShowDialog()`.

- [ ] **Step 4: Run syntax, self-test, and Pester checks**

Run parser checks, `launcher.ps1 -SelfTest`, Pester, and `git diff --check`.

Expected: no GUI opens; self-test exits 0; all tests pass.

- [ ] **Step 5: Commit**

```bash
git add "CQU校园网工具.cmd" launcher.ps1 .gitattributes tests/CquCampusNet.Tests.ps1
git commit -m "feat: add double-click GUI launcher"
```

### Task 2: Documentation and v0.1.1 release

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- README presents double-click launch as the default route and retains PowerShell commands under advanced usage.
- CHANGELOG records `0.1.1 - 2026-07-04`.

- [ ] **Step 1: Update user documentation**

Document this primary flow:

```text
1. Download and extract the repository ZIP.
2. Double-click CQU校园网工具.cmd.
3. Click 安装并立即启动 and enter the credential in the Windows dialog.
```

- [ ] **Step 2: Add the patch release changelog**

Record the GUI launcher, status display, credential-update button, and uninstall confirmation under `0.1.1`.

- [ ] **Step 3: Run the release gate**

Run PowerShell syntax parsing, launcher self-test, Pester, privacy identifier scan, YAML parsing, and `git diff --check`.

- [ ] **Step 4: Commit, push, and await CI**

```bash
git add README.md CHANGELOG.md
git commit -m "docs: make the GUI launcher the default setup path"
git push origin main
```

Wait for the `Test` workflow conclusion to become `success`.

- [ ] **Step 5: Tag and publish the patch version**

```bash
git tag -a v0.1.1 -m "CQU Campus Net Auto Login v0.1.1"
git push origin v0.1.1
```

Verify `HEAD`, `origin/main`, and `v0.1.1^{}` resolve to the same commit.
