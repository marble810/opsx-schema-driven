<#
.SYNOPSIS
    End-to-end verification suite for the 'proposal-driven' OpenSpec schema and scripts.
    Runs completely isolated in a temporary directory without touching the real user LOCALAPPDATA.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$SchemaName = "proposal-driven"

function Write-Section([string]$Title) {
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw "ASSERTION FAILED: $Message"
    }
    Write-Host "  ✓ $Message" -ForegroundColor Green
}

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("opsx-verify-" + [guid]::NewGuid().ToString("N"))
$OrigLocalAppData = $env:LOCALAPPDATA
$OrigXdgDataHome = $env:XDG_DATA_HOME

try {
    New-Item -ItemType Directory -Path $TempRoot -Force | Out-Null

    # -------------------------------------------------------------------------
    # 1. Repository Self-Check (validate + doctor + which)
    # -------------------------------------------------------------------------
    Write-Section "1. Repository Self-Check (validate + doctor + which)"
    Push-Location $RepoRoot
    try {
        $valOut = (& openspec schema validate $SchemaName 2>&1) -join "`n"
        Assert-True ($LASTEXITCODE -eq 0 -and $valOut -match "is valid") "openspec schema validate $SchemaName passed"

        $docOut = (& openspec doctor 2>&1) -join "`n"
        Assert-True ($LASTEXITCODE -eq 0 -and $docOut -match "OpenSpec root:\s*ok") "openspec doctor reports OpenSpec root: ok"

        $whichOut = (& openspec schema which $SchemaName 2>&1) -join "`n"
        Assert-True ($LASTEXITCODE -eq 0 -and $whichOut -match "Source:\s*project") "openspec schema which resolves to project source inside repo"
    } finally {
        Pop-Location
    }

    # -------------------------------------------------------------------------
    # 2. User-Level Global Install (Copy & Junction) via Fake LOCALAPPDATA
    # -------------------------------------------------------------------------
    Write-Section "2. User-Level Global Install & Resolution E2E (Isolated Fake Root)"
    $FakeAppData = Join-Path $TempRoot "fake-appdata"
    $EmptyProbe = Join-Path $TempRoot "empty-probe"
    New-Item -ItemType Directory -Path $FakeAppData -Force | Out-Null
    New-Item -ItemType Directory -Path $EmptyProbe -Force | Out-Null

    $env:LOCALAPPDATA = $FakeAppData
    $env:XDG_DATA_HOME = $FakeAppData

    # 2a. Copy install + idempotency check
    & (Join-Path $PSScriptRoot "install.ps1") -Global
    & (Join-Path $PSScriptRoot "install.ps1") -Global # Second run to verify idempotency

    Push-Location $EmptyProbe
    try {
        $whichUserCopy = (& openspec schema which $SchemaName 2>&1) -join "`n"
        Assert-True ($LASTEXITCODE -eq 0 -and $whichUserCopy -match "Source:\s*user") "User-level COPY install resolves as 'Source: user' in empty directory"
    } finally {
        Pop-Location
    }

    # 2b. Link (Junction) install + idempotency check
    & (Join-Path $PSScriptRoot "install.ps1") -Link
    & (Join-Path $PSScriptRoot "install.ps1") -Link # Second run to verify idempotency

    Push-Location $EmptyProbe
    try {
        $whichUserLink = (& openspec schema which $SchemaName 2>&1) -join "`n"
        Assert-True ($LASTEXITCODE -eq 0 -and $whichUserLink -match "Source:\s*user") "User-level LINK (junction) install resolves as 'Source: user' in empty directory"
    } finally {
        Pop-Location
    }

    # -------------------------------------------------------------------------
    # 3. Cold-Start Workflow E2E (new change -> status -> validate -> apply)
    # -------------------------------------------------------------------------
    Write-Section "3. Cold-Start Change Lifecycle E2E (smoke change)"
    $SmokeProbe = Join-Path $TempRoot "probe"
    New-Item -ItemType Directory -Path $SmokeProbe -Force | Out-Null

    Push-Location $SmokeProbe
    try {
        & openspec new change smoke --schema $SchemaName | Out-Null
        Assert-True ($LASTEXITCODE -eq 0) "openspec new change smoke --schema $SchemaName succeeded"

        $statusInitJson = (& openspec status --change smoke --json) | ConvertFrom-Json
        Assert-True ($statusInitJson.schemaName -eq $SchemaName) "Change uses schema '$SchemaName'"
        Assert-True ($statusInitJson.artifacts.Count -eq 4) "Status reports 4 artifacts (proposal, design, tasks, for-human)"

        $blockedIds = @($statusInitJson.artifacts | Where-Object { $_.status -eq "blocked" } | ForEach-Object { $_.id })
        Assert-True (($blockedIds -contains "design") -and ($blockedIds -contains "tasks") -and ($blockedIds -contains "for-human")) "design, tasks, and for-human are initially blocked by proposal"

        # Write minimal proposal.md and tasks.md
        $changeDir = Join-Path $SmokeProbe "openspec\changes\smoke"
        $proposalContent = @"
# Proposal

## Why

Verify that the proposal-driven schema works end-to-end in an isolated smoke environment.

## What Changes

- Add smoke verification check in temporary workspace.

## Behavior

- When `openspec validate --all` runs -> validation passes with exit code 0.

## Impact

- Scoped strictly to temporary probe directory.
"@
        $tasksContent = @"
# Tasks

## 1. Core Implementation

- [x] 1.1 Create proposal.md and verify heading contract
- [ ] 1.2 Run apply instructions check and verify progress tracker
"@
        Set-Content -LiteralPath (Join-Path $changeDir "proposal.md") -Value $proposalContent -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $changeDir "tasks.md") -Value $tasksContent -Encoding UTF8

        $valAllOut = (& openspec validate --all 2>&1) -join "`n"
        Assert-True ($LASTEXITCODE -eq 0) "openspec validate --all passed (exit code 0)"

        $statusMidJson = (& openspec status --change smoke --json) | ConvertFrom-Json
        $doneIds = @($statusMidJson.artifacts | Where-Object { $_.status -eq "done" } | ForEach-Object { $_.id })
        Assert-True (($doneIds.Count -eq 2) -and ($doneIds -contains "proposal") -and ($doneIds -contains "tasks")) "openspec status reports 2/4 artifacts done (proposal, tasks)"

        $applyJson = (& openspec instructions apply --change smoke --json) | ConvertFrom-Json
        Assert-True ($applyJson.progress.total -eq 2 -and $applyJson.progress.complete -eq 1 -and $applyJson.progress.remaining -eq 1) "openspec instructions apply tracks tasks.md progress (1/2 complete)"
        Assert-True ($applyJson.instruction -match "FOR-HUMAN\.md") "apply instruction enforces FOR-HUMAN.md context isolation"
    } finally {
        Pop-Location
    }

    # -------------------------------------------------------------------------
    # 4. Super One-Click Project Init E2E (-InitProject)
    # -------------------------------------------------------------------------
    Write-Section "4. Super One-Click Project Init E2E (-InitProject)"
    $InitProbe = Join-Path $TempRoot "init-probe"
    & (Join-Path $PSScriptRoot "install.ps1") -InitProject -ProjectPath $InitProbe -Tools "antigravity,pi" -Yes
    Assert-True (Test-Path (Join-Path $InitProbe "openspec\schemas\$SchemaName\schema.yaml")) "One-click init copied schema into project"
    $cfgText = Get-Content (Join-Path $InitProbe "openspec\config.yaml") -Raw
    Assert-True ($cfgText -match "(?m)^schema:\s*$SchemaName") "One-click init set 'schema: $SchemaName' in openspec/config.yaml"

    # -------------------------------------------------------------------------
    # 5. Uninstall E2E
    # -------------------------------------------------------------------------
    Write-Section "5. Uninstall E2E"
    & (Join-Path $PSScriptRoot "uninstall.ps1")
    & (Join-Path $PSScriptRoot "uninstall.ps1") # Second run to verify idempotency
    Assert-True (-not (Test-Path (Join-Path $FakeAppData "openspec\schemas\$SchemaName"))) "uninstall.ps1 removed user-level schema cleanly"
    Assert-True (Test-Path (Join-Path $RepoRoot "openspec\schemas\$SchemaName\schema.yaml")) "Source repository schema files remain completely intact"

    Write-Host "`n============================================================" -ForegroundColor Green
    Write-Host "  ALL VERIFICATION CHECKS PASSED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host "============================================================`n" -ForegroundColor Green
} finally {
    $env:LOCALAPPDATA = $OrigLocalAppData
    $env:XDG_DATA_HOME = $OrigXdgDataHome
    if (Test-Path -LiteralPath $TempRoot) {
        # Safely remove any junction inside FakeAppData before recursive removal
        $possibleJunction = Join-Path $TempRoot "fake-appdata\openspec\schemas\$SchemaName"
        if (Test-Path -LiteralPath $possibleJunction) {
            $item = Get-Item -LiteralPath $possibleJunction -Force
            if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
                if ($IsWindows -or $env:OS -match "Windows") {
                    cmd /c rmdir "`"$possibleJunction`"" | Out-Null
                }
            }
        }
        Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
