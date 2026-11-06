<#
.SYNOPSIS
    Install the 'proposal-driven' OpenSpec schema or initialize a project in one click.

.DESCRIPTION
    Supports three workflows:
    1. Super One-Click Project Init (-InitProject):
       - Dynamically queries `openspec init --help` for supported AI agents
       - Interactive multi-select TUI (or non-interactive via -Tools)
       - Installs 'proposal-driven' schema (project-local or user-global)
       - Runs `openspec init` and sets `schema: proposal-driven` in `openspec/config.yaml`
    2. User-Level Global Install (default when no project flags are given):
       - Copies (or links via -Link) the schema to %LOCALAPPDATA%\openspec\schemas\proposal-driven
    3. Project-Local Schema Copy (-TargetProject <path>):
       - Copies the schema to <path>\openspec\schemas\proposal-driven and configures config.yaml

.PARAMETER InitProject
    Launch the one-click project initialization flow (schema + openspec init + agent selection + config.yaml).

.PARAMETER ProjectPath
    Target project directory for -InitProject (defaults to current working directory).

.PARAMETER TargetProject
    Copy the schema directly into the specified project's openspec/schemas/proposal-driven directory.

.PARAMETER Global
    Install the schema into the user-level global directory (%LOCALAPPDATA%\openspec\schemas\proposal-driven).

.PARAMETER Link
    Use a Windows directory junction (mklink /J) or symlink instead of copying files for user-global install.

.PARAMETER Tools
    Comma-separated list of AI tools for `openspec init --tools` (e.g. "antigravity,pi"). Skips agent prompt.

.PARAMETER Yes
    Non-interactive mode: accept defaults without prompting.

.PARAMETER RepoUrl
    GitHub raw base URL used when running the script remotely without a local clone.
#>
function Invoke-OpsxSchemaInstall {
    [CmdletBinding()]
    param(
        [switch]$InitProject,
        [string]$ProjectPath = ".",
        [string]$TargetProject = "",
        [switch]$Global,
        [switch]$Link,
        [string]$Tools = "",
        [switch]$Yes,
        [string]$RepoUrl = "https://raw.githubusercontent.com/marble810/opsx-proposal-driven/main"
    )

    $ErrorActionPreference = "Stop"
    $SchemaName = "proposal-driven"
    $ScriptDir = $PSScriptRoot

function Write-Step([string]$Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Ok([string]$Message) {
    Write-Host "  ✓ $Message" -ForegroundColor Green
}

function Write-Warn([string]$Message) {
    Write-Host "  ! $Message" -ForegroundColor Yellow
}

# 1. Resolve Schema Source (local repo or remote download)
$TempDownloadDir = $null
function Resolve-SchemaSource {
    if ($ScriptDir) {
        $candidate = Join-Path (Split-Path -Parent $ScriptDir) "openspec\schemas\$SchemaName"
        if (Test-Path (Join-Path $candidate "schema.yaml")) {
            return (Resolve-Path $candidate).Path
        }
    }

    if ($Link) {
        throw "Cannot use -Link mode when running remotely without a local repository clone."
    }

    Write-Step "Local repository not detected; fetching '$SchemaName' schema from GitHub..."
    $script:TempDownloadDir = Join-Path ([System.IO.Path]::GetTempPath()) ("opsx-schema-" + [guid]::NewGuid().ToString("N"))
    $dest = Join-Path $script:TempDownloadDir $SchemaName
    $tplDest = Join-Path $dest "templates"
    New-Item -ItemType Directory -Path $tplDest -Force | Out-Null

    $files = @(
        "schema.yaml",
        "templates/proposal.md",
        "templates/design.md",
        "templates/tasks.md",
        "templates/for-human.md"
    )
    foreach ($rel in $files) {
        $url = "$RepoUrl/openspec/schemas/$SchemaName/$rel"
        $outFile = Join-Path $dest ($rel -replace '/', '\')
        Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing
    }
    Write-Ok "Downloaded schema files to temporary cache"
    return $dest
}

# 2. Resolve User Global Schema Directory
function Get-UserSchemaDir {
    if ($env:LOCALAPPDATA) {
        return Join-Path $env:LOCALAPPDATA "openspec\schemas\$SchemaName"
    }
    if ($env:XDG_DATA_HOME) {
        return Join-Path $env:XDG_DATA_HOME "openspec/schemas/$SchemaName"
    }
    return Join-Path $HOME ".local/share/openspec/schemas/$SchemaName"
}

# 3. Safely remove existing directory or junction/symlink
function Remove-ExistingTarget([string]$PathToRemove) {
    if (-not (Test-Path -LiteralPath $PathToRemove)) {
        return
    }
    $item = Get-Item -LiteralPath $PathToRemove -Force
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        if ($IsWindows -or $env:OS -match "Windows") {
            cmd /c rmdir "`"$PathToRemove`"" | Out-Null
        } else {
            Remove-Item -LiteralPath $PathToRemove -Force
        }
    } else {
        Remove-Item -LiteralPath $PathToRemove -Recurse -Force
    }
}

# 4. Install schema to a target schema directory (Copy or Link)
function Install-SchemaToDirectory([string]$SourceDir, [string]$DestDir, [bool]$UseLink) {
    $parentDir = Split-Path -Parent $DestDir
    if (-not (Test-Path -LiteralPath $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    if (Test-Path -LiteralPath $DestDir) {
        Write-Warn "Target already exists at '$DestDir' - updating in place..."
        Remove-ExistingTarget -PathToRemove $DestDir
    }

    if ($UseLink) {
        if ($IsWindows -or $env:OS -match "Windows") {
            cmd /c mklink /J "`"$DestDir`"" "`"$SourceDir`"" | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to create directory junction from '$DestDir' to '$SourceDir'."
            }
            Write-Ok "Linked (junction) '$DestDir' -> '$SourceDir'"
        } else {
            New-Item -ItemType SymbolicLink -Path $DestDir -Target $SourceDir -Force | Out-Null
            Write-Ok "Linked (symlink) '$DestDir' -> '$SourceDir'"
        }
    } else {
        Copy-Item -LiteralPath $SourceDir -Destination $DestDir -Recurse -Force
        Write-Ok "Copied '$SchemaName' schema to '$DestDir'"
    }
}

# 5. Ensure openspec/config.yaml sets `schema: proposal-driven`
function Set-ProjectSchemaConfig([string]$ProjRoot) {
    $openspecDir = Join-Path $ProjRoot "openspec"
    if (-not (Test-Path -LiteralPath $openspecDir)) {
        New-Item -ItemType Directory -Path $openspecDir -Force | Out-Null
    }
    $configFile = Join-Path $openspecDir "config.yaml"
    if (Test-Path -LiteralPath $configFile) {
        $content = Get-Content -LiteralPath $configFile -Raw
        if ($content -match '(?m)^schema:\s*\S+') {
            $updated = $content -replace '(?m)^schema:\s*\S+', "schema: $SchemaName"
            Set-Content -LiteralPath $configFile -Value $updated -NoNewline -Encoding UTF8
        } else {
            $updated = "schema: $SchemaName`n" + $content
            Set-Content -LiteralPath $configFile -Value $updated -NoNewline -Encoding UTF8
        }
    } else {
        Set-Content -LiteralPath $configFile -Value "schema: $SchemaName`n" -NoNewline -Encoding UTF8
    }
    Write-Ok "Configured '$configFile' with 'schema: $SchemaName'"
}

# 6. Dynamically query `openspec init --help` for supported AI tools
function Get-SupportedOpenSpecTools {
    $helpOut = (& openspec init --help 2>&1) -join "`n"
    $toolsList = @()
    if ($helpOut -match 'comma-separated list of:\s*([\s\S]+?)(?:\.\s*Also accepted:|\r?\n\s*--)') {
        $rawBlock = $Matches[1]
        $parsed = $rawBlock -split '[,\s]+' | Where-Object { $_ -and $_ -match '^[a-z0-9-]+$' }
        $toolsList = @($parsed | Select-Object -Unique)
    }
    if ($toolsList.Count -eq 0) {
        # Fallback if CLI help text format ever changes
        $toolsList = @("antigravity", "pi", "claude", "codex", "cursor", "github-copilot", "gemini", "opencode", "windsurf", "cline", "roocode", "trae")
    }

    # Pin frequently used agents at the top while preserving all CLI-discovered tools
    $pinned = @("antigravity", "pi", "claude", "codex", "cursor", "github-copilot", "gemini", "opencode", "oh-my-pi", "cline", "roocode", "trae")
    $ordered = New-Object System.Collections.Generic.List[string]
    foreach ($p in $pinned) {
        if ($toolsList -contains $p) {
            $ordered.Add($p)
        }
    }
    foreach ($t in $toolsList) {
        if (-not $ordered.Contains($t)) {
            $ordered.Add($t)
        }
    }
    return $ordered.ToArray()
}

# 7. Interactive Agent Multi-Select Menu
function Select-AgentsInteractive([string[]]$AllTools) {
    $selected = New-Object System.Collections.Generic.HashSet[string]
    if ($AllTools -contains "antigravity") { [void]$selected.Add("antigravity") }
    if ($AllTools -contains "pi") { [void]$selected.Add("pi") }

    # Check if console supports interactive key reading
    $canReadKey = $true
    try {
        $null = [Console]::KeyAvailable
    } catch {
        $canReadKey = $false
    }

    if (-not $canReadKey) {
        Write-Host "`nAvailable OpenSpec AI tools ($($AllTools.Count) discovered from CLI):" -ForegroundColor Cyan
        Write-Host ($AllTools -join ", ")
        $inputStr = Read-Host "Enter comma-separated tools (Press Enter for default: antigravity,pi)"
        if ([string]::IsNullOrWhiteSpace($inputStr)) {
            return "antigravity,pi"
        }
        return ($inputStr -replace '\s+', '')
    }

    $cursor = 0
    $pageSize = 12
    $total = $AllTools.Count

    Write-Host ""
    while ($true) {
        $pageStart = [Math]::Floor($cursor / $pageSize) * $pageSize
        $pageEnd = [Math]::Min($pageStart + $pageSize - 1, $total - 1)

        Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host " ? Select AI Agents for 'openspec init' (Discovered $total tools via CLI)" -ForegroundColor Cyan
        Write-Host "   [Up/Down] Move  [Space] Toggle  [A] All  [N] None  [Enter] Confirm" -ForegroundColor DarkGray
        Write-Host "   Showing items $($pageStart + 1)-$($pageEnd + 1) of $total | Selected: $(if ($selected.Count -eq 0) { 'none' } else { ($selected | Sort-Object) -join ', ' })" -ForegroundColor Yellow
        Write-Host "----------------------------------------------------------------------" -ForegroundColor DarkGray

        for ($i = $pageStart; $i -le $pageEnd; $i++) {
            $tool = $AllTools[$i]
            $isChecked = $selected.Contains($tool)
            $pointer = if ($i -eq $cursor) { ">" } else { " " }
            $box = if ($isChecked) { "[x]" } else { "[ ]" }
            $line = " $pointer $box $tool"
            if ($i -eq $cursor) {
                Write-Host $line -ForegroundColor Green
            } elseif ($isChecked) {
                Write-Host $line -ForegroundColor White
            } else {
                Write-Host $line -ForegroundColor Gray
            }
        }

        $key = [Console]::ReadKey($true)
        # Clear rendered menu block before redrawing
        $linesRendered = ($pageEnd - $pageStart + 1) + 5
        try {
            $targetTop = [Math]::Max(0, [Console]::CursorTop - $linesRendered)
            [Console]::SetCursorPosition(0, $targetTop)
            for ($l = 0; $l -lt $linesRendered; $l++) {
                Write-Host (" " * ([Math]::Max(1, [Console]::WindowWidth - 1)))
            }
            [Console]::SetCursorPosition(0, $targetTop)
        } catch {
            # Ignore cursor repositioning errors in non-standard terminals
        }

        switch ($key.Key) {
            "UpArrow" {
                $cursor = if ($cursor -gt 0) { $cursor - 1 } else { $total - 1 }
            }
            "DownArrow" {
                $cursor = if ($cursor -lt ($total - 1)) { $cursor + 1 } else { 0 }
            }
            "PageUp" {
                $cursor = [Math]::Max(0, $cursor - $pageSize)
            }
            "PageDown" {
                $cursor = [Math]::Min($total - 1, $cursor + $pageSize)
            }
            "Spacebar" {
                $curTool = $AllTools[$cursor]
                if ($selected.Contains($curTool)) {
                    [void]$selected.Remove($curTool)
                } else {
                    [void]$selected.Add($curTool)
                }
            }
            "A" {
                foreach ($t in $AllTools) { [void]$selected.Add($t) }
            }
            "N" {
                $selected.Clear()
            }
            "Enter" {
                if ($selected.Count -eq 0) {
                    return "none"
                }
                return (($selected | ForEach-Object { $_ }) -join ",")
            }
        }
    }
}

# 8. Interactive Schema Placement Choice
function Select-PlacementInteractive([bool]$CanLink) {
    Write-Host "`n? How should the '$SchemaName' schema be installed?" -ForegroundColor Cyan
    Write-Host "  [1] Project init + copy schema into current project (openspec/schemas/$SchemaName) [Recommended]" -ForegroundColor Green
    Write-Host "  [2] Project init + copy schema into user global directory ($(Get-UserSchemaDir))" -ForegroundColor Gray
    if ($CanLink) {
        Write-Host "  [3] Project init + link (Junction) schema into user global directory (-> local repo)" -ForegroundColor Gray
    }
    Write-Host "  [4] Schema only: install to user global directory without running 'openspec init' here" -ForegroundColor Gray
    $choice = Read-Host "Select option (Press Enter for 1)"
    switch ($choice.Trim()) {
        "2" { return "global-copy" }
        "3" { if ($CanLink) { return "global-link" } else { return "project" } }
        "4" { return "schema-only-global" }
        default { return "project" }
    }
}

try {
    # Verify openspec CLI is installed
    if (-not (Get-Command openspec -ErrorAction SilentlyContinue)) {
        throw "'openspec' CLI was not found in PATH. Install it first via: npm install -g @fission-ai/openspec"
    }

    $sourceSchemaDir = Resolve-SchemaSource
    $isLocalRepo = ($null -eq $TempDownloadDir)

    # Default to interactive project init when no explicit mode flag (-Global / -Link / -TargetProject) is given
    if (-not $InitProject -and -not $Global -and -not $Link -and [string]::IsNullOrWhiteSpace($TargetProject)) {
        $InitProject = $true
    }

    # MODE A: Super One-Click Project Initialization (Default for `irm ... | iex` & .\install.ps1)
    if ($InitProject) {
        if (-not (Test-Path -LiteralPath $ProjectPath)) {
            New-Item -ItemType Directory -Path $ProjectPath -Force | Out-Null
        }
        $resolvedProject = (Resolve-Path -LiteralPath $ProjectPath).Path
        Write-Step "Initializing OpenSpec with '$SchemaName' in '$resolvedProject'..."

        # Step A1: Discover tools from CLI & select
        $discoveredTools = Get-SupportedOpenSpecTools
        $chosenTools = $Tools
        if ([string]::IsNullOrWhiteSpace($chosenTools)) {
            if ($Yes) {
                $chosenTools = "antigravity,pi"
            } else {
                $chosenTools = Select-AgentsInteractive -AllTools $discoveredTools
            }
        }
        Write-Ok "Selected AI tools: $chosenTools"

        # Step A2: Determine schema placement
        $placement = "project"
        if ($Global -and $Link) {
            $placement = "global-link"
        } elseif ($Global) {
            $placement = "global-copy"
        } elseif (-not $Yes) {
            $placement = Select-PlacementInteractive -CanLink $isLocalRepo
        }

        switch ($placement) {
            "project" {
                $projSchemaDest = Join-Path $resolvedProject "openspec\schemas\$SchemaName"
                Install-SchemaToDirectory -SourceDir $sourceSchemaDir -DestDir $projSchemaDest -UseLink $false
            }
            "global-copy" {
                Install-SchemaToDirectory -SourceDir $sourceSchemaDir -DestDir (Get-UserSchemaDir) -UseLink $false
            }
            "global-link" {
                Install-SchemaToDirectory -SourceDir $sourceSchemaDir -DestDir (Get-UserSchemaDir) -UseLink $true
            }
            "schema-only-global" {
                Install-SchemaToDirectory -SourceDir $sourceSchemaDir -DestDir (Get-UserSchemaDir) -UseLink $false
                & openspec schema validate $SchemaName
                Write-Ok "User-level global schema installation complete!"
                return
            }
        }

        # Step A3: Run `openspec init`
        Write-Step "Running 'openspec init --tools $chosenTools --no-animation'..."
        & openspec init --tools $chosenTools --no-animation $resolvedProject
        if ($LASTEXITCODE -ne 0) {
            throw "'openspec init' exited with code $LASTEXITCODE"
        }

        # Step A4: Bind default schema in openspec/config.yaml
        Set-ProjectSchemaConfig -ProjRoot $resolvedProject

        # Step A5: Validate in project context
        Push-Location $resolvedProject
        try {
            & openspec schema validate $SchemaName
            if ($LASTEXITCODE -ne 0) {
                throw "Schema validation failed in '$resolvedProject'"
            }
        } finally {
            Pop-Location
        }
        Write-Ok "Project '$resolvedProject' is ready with '$SchemaName' schema!"
        return
    }

    # MODE B: Copy Schema into a Target Project (-TargetProject)
    if (-not [string]::IsNullOrWhiteSpace($TargetProject)) {
        if (-not (Test-Path -LiteralPath $TargetProject)) {
            New-Item -ItemType Directory -Path $TargetProject -Force | Out-Null
        }
        $resolvedTarget = (Resolve-Path -LiteralPath $TargetProject).Path
        $projSchemaDest = Join-Path $resolvedTarget "openspec\schemas\$SchemaName"
        Write-Step "Installing '$SchemaName' schema into project '$resolvedTarget'..."
        Install-SchemaToDirectory -SourceDir $sourceSchemaDir -DestDir $projSchemaDest -UseLink $false
        Set-ProjectSchemaConfig -ProjRoot $resolvedTarget

        Push-Location $resolvedTarget
        try {
            & openspec schema validate $SchemaName
            if ($LASTEXITCODE -ne 0) {
                throw "Schema validation failed in '$resolvedTarget'"
            }
        } finally {
            Pop-Location
        }
        Write-Ok "Installed and validated '$SchemaName' in '$resolvedTarget'"
        return
    }

    # MODE C: Default User-Level Global Installation
    $userDest = Get-UserSchemaDir
    Write-Step "Installing '$SchemaName' schema to user global directory..."
    Install-SchemaToDirectory -SourceDir $sourceSchemaDir -DestDir $userDest -UseLink $Link.IsPresent

    & openspec schema validate $SchemaName
    if ($LASTEXITCODE -ne 0) {
        throw "Schema validation failed after installation."
    }
    Write-Ok "User-level installation complete! Add 'schema: $SchemaName' to any project's openspec/config.yaml to use it."
} finally {
    if ($TempDownloadDir -and (Test-Path -LiteralPath $TempDownloadDir)) {
        Remove-Item -LiteralPath $TempDownloadDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
}

Invoke-OpsxSchemaInstall @args
