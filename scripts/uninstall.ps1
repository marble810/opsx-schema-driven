<#
.SYNOPSIS
    Uninstall the 'proposal-driven' OpenSpec schema from the user global directory or a target project.
    Never deletes the source repository.
#>
function Invoke-OpsxSchemaUninstall {
    [CmdletBinding()]
    param(
        [string]$TargetProject = ""
    )

    $ErrorActionPreference = "Stop"
    $SchemaName = "proposal-driven"

function Get-UserSchemaDir {
    if ($env:LOCALAPPDATA) {
        return Join-Path $env:LOCALAPPDATA "openspec\schemas\$SchemaName"
    }
    if ($env:XDG_DATA_HOME) {
        return Join-Path $env:XDG_DATA_HOME "openspec/schemas/$SchemaName"
    }
    return Join-Path $HOME ".local/share/openspec/schemas/$SchemaName"
}

function Remove-SafeTarget([string]$PathToRemove) {
    if (-not (Test-Path -LiteralPath $PathToRemove)) {
        Write-Host "  - Nothing to remove at '$PathToRemove' (already absent)." -ForegroundColor Gray
        return
    }
    $item = Get-Item -LiteralPath $PathToRemove -Force
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        if ($IsWindows -or $env:OS -match "Windows") {
            cmd /c rmdir "`"$PathToRemove`"" | Out-Null
        } else {
            Remove-Item -LiteralPath $PathToRemove -Force
        }
        Write-Host "  ✓ Removed link '$PathToRemove' (source repository untouched)." -ForegroundColor Green
    } else {
        Remove-Item -LiteralPath $PathToRemove -Recurse -Force
        Write-Host "  ✓ Removed installed schema copy at '$PathToRemove'." -ForegroundColor Green
    }
}

if (-not [string]::IsNullOrWhiteSpace($TargetProject)) {
    $resolved = (Resolve-Path -LiteralPath $TargetProject).Path
    $dest = Join-Path $resolved "openspec\schemas\$SchemaName"
    Remove-SafeTarget -PathToRemove $dest
} else {
    $userDest = Get-UserSchemaDir
    Remove-SafeTarget -PathToRemove $userDest
}
}

Invoke-OpsxSchemaUninstall @args
