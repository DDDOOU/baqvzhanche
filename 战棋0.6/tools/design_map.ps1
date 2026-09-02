param(
    [string]$Recipe,
    [switch]$DryRun,
    [switch]$ListTerrains,
    [switch]$ListEdgeRules,
    [string]$GodotPath = 'D:\steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe'
)

$ErrorActionPreference = 'Stop'
$ProjectPath = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path -LiteralPath $GodotPath)) {
    throw "Godot executable not found: $GodotPath"
}

$GodotArgs = @('--headless', '--path', $ProjectPath, '--script', 'res://tools/map_designer.gd', '--')
if ($ListTerrains) {
    $GodotArgs += '--list-terrains'
} elseif ($ListEdgeRules) {
    $GodotArgs += '--list-edge-rules'
} else {
    if ([string]::IsNullOrWhiteSpace($Recipe)) {
        throw 'Specify a map recipe with -Recipe, or use -ListTerrains.'
    }
    $ResolvedRecipe = (Resolve-Path -LiteralPath $Recipe).Path
    $GodotArgs += "--recipe=$ResolvedRecipe"
}
if ($DryRun) {
    $GodotArgs += '--dry-run'
}

$QuotedArgs = $GodotArgs | ForEach-Object {
    if ($_ -match '[\s"]') {
        '"' + $_.Replace('"', '\"') + '"'
    } else {
        $_
    }
}
$GodotProcess = Start-Process -FilePath $GodotPath -ArgumentList $QuotedArgs -NoNewWindow -Wait -PassThru
if ($GodotProcess.ExitCode -ne 0) {
    throw "Map generation failed. Godot exit code: $($GodotProcess.ExitCode)"
}
