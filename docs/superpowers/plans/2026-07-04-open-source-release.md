# Open Source Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the repository ready for public collaboration under MIT and publish the tested `v0.1.0` version tag.

**Architecture:** Keep governance in root Markdown files, contributor interactions in `.github` templates, and offline Windows validation in one GitHub Actions workflow. No workflow may contact the CQU portal, access credentials, or mutate the runner's scheduled tasks.

**Tech Stack:** MIT License, Markdown, GitHub Issue Forms, GitHub Actions, Windows PowerShell 5.1, Pester

## Global Constraints

- Copyright text is exactly `Copyright (c) 2026 lok1`.
- License identifier is MIT and the standard OSI text is used without extra restrictions.
- CI runs only parser checks and mocked Pester tests on `windows-latest`.
- Public templates prohibit account names, passwords, complete IP addresses, MAC addresses, raw portal URLs, unredacted logs, and unredacted screenshots.
- The project remains clearly marked as unofficial and unaffiliated with Chongqing University.
- The release tag is exactly `v0.1.0` and is created only after local checks and push succeed.

---

### Task 1: License and governance documents

**Files:**
- Create: `LICENSE`
- Create: `CONTRIBUTING.md`
- Create: `SECURITY.md`
- Create: `CHANGELOG.md`
- Create: `.gitattributes`

**Interfaces:**
- Produces: GitHub-detectable MIT licensing, contribution rules, private security reporting instructions, initial release history, and normalized text files.

- [ ] **Step 1: Add the standard MIT grant and warranty disclaimer**

Use the OSI text with only the placeholder replaced:

```text
MIT License

Copyright (c) 2026 lok1

Permission is hereby granted, free of charge, to any person obtaining a copy...
```

- [ ] **Step 2: Add contributor and security rules**

Document the exact local validation command:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester '.\tests\CquCampusNet.Tests.ps1'"
```

Require all diagnostic material to be redacted and route vulnerabilities to `https://github.com/Lok1-bit/cqu-campus-net-auto-login/security/advisories/new`.

- [ ] **Step 3: Add changelog and line-ending policy**

Record `0.1.0 - 2026-07-04` and configure:

```gitattributes
* text=auto
*.ps1 text eol=crlf
*.psm1 text eol=crlf
*.psd1 text eol=crlf
*.md text eol=lf
*.yml text eol=lf
```

- [ ] **Step 4: Verify license and privacy text**

Run: `rg -n "Copyright \(c\) 2026 lok1|password|MAC|Security Advisory" LICENSE CONTRIBUTING.md SECURITY.md CHANGELOG.md`

Expected: the copyright is present, and password/MAC references are warnings rather than real identifiers.

- [ ] **Step 5: Commit**

```bash
git add LICENSE CONTRIBUTING.md SECURITY.md CHANGELOG.md .gitattributes
git commit -m "docs: add MIT license and project governance"
```

### Task 2: GitHub collaboration and CI

**Files:**
- Create: `.github/workflows/test.yml`
- Create: `.github/ISSUE_TEMPLATE/bug_report.yml`
- Create: `.github/ISSUE_TEMPLATE/feature_request.yml`
- Create: `.github/ISSUE_TEMPLATE/config.yml`
- Create: `.github/pull_request_template.md`
- Modify: `tests/CquCampusNet.Tests.ps1`

**Interfaces:**
- Produces: Windows CI on push/PR and structured, privacy-aware contributor forms.

- [ ] **Step 1: Normalize Pester assertions**

Convert legacy forms such as `Should Be 1` to cross-version forms such as:

```powershell
$value.result | Should -Be 1
$safe | Should -Not -Match 'sample-password'
```

- [ ] **Step 2: Add offline Windows workflow**

Use `actions/checkout@v4`, parse repository scripts with `System.Management.Automation.Language.Parser`, then run:

```powershell
$result = Invoke-Pester -Path '.\tests\CquCampusNet.Tests.ps1' -PassThru
if ($result.FailedCount -gt 0) { throw "$($result.FailedCount) tests failed." }
```

- [ ] **Step 3: Add issue and PR forms**

Each bug form must include a required confirmation:

```yaml
- type: checkboxes
  attributes:
    options:
      - label: I removed accounts, passwords, IP/MAC addresses, portal URLs, and unredacted logs/screenshots.
        required: true
```

- [ ] **Step 4: Validate YAML and tests**

Run parser checks, `Invoke-Pester`, and `git diff --check`.

Expected: all scripts parse, all tests pass, and no whitespace errors are reported.

- [ ] **Step 5: Commit**

```bash
git add .github tests/CquCampusNet.Tests.ps1
git commit -m "ci: add Windows tests and contribution templates"
```

### Task 3: README, push, and version tag

**Files:**
- Modify: `README.md`

**Interfaces:**
- Produces: visible status/license/platform badges and links to every governance document; publishes `v0.1.0`.

- [ ] **Step 1: Add accurate badges and project links**

Use badges for the `Test` workflow, MIT license, Windows, and PowerShell 5.1+, plus links to `CONTRIBUTING.md`, `SECURITY.md`, `CHANGELOG.md`, and `LICENSE`.

- [ ] **Step 2: Add release and license explanations**

State that MIT permits reuse, modification, redistribution, and commercial use when notices are retained, and that the software is provided without warranty.

- [ ] **Step 3: Run the release gate**

Run syntax checks, Pester, identifier scans, `git diff --check`, and `git status --short`.

Expected: checks pass and only intentional open-source readiness files are changed.

- [ ] **Step 4: Commit and push**

```bash
git add README.md
git commit -m "docs: prepare v0.1.0 open-source release"
git push origin main
```

- [ ] **Step 5: Tag and publish the version point**

```bash
git tag -a v0.1.0 -m "CQU Campus Net Auto Login v0.1.0"
git push origin v0.1.0
```

Verify local `HEAD`, `origin/main`, and `v0.1.0^{}` resolve to the same commit.
