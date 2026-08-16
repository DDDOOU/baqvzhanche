param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$ProjectRoot = [IO.Path]::GetFullPath($ProjectRoot)
$sourcePath = Join-Path $ProjectRoot "config\source\unit_config.xlsx"
$outputPath = Join-Path $ProjectRoot "data\units\unit_config.json"

if (-not (Test-Path -LiteralPath $sourcePath)) {
    throw "Unit config workbook not found: $sourcePath"
}

$fieldMap = [ordered]@{
    "阵营" = "faction"
    "单位枚举" = "enum_id"
    "单位名称" = "name"
    "单位类别" = "class"
    "部署费用" = "cost"
    "最大生命" = "health"
    "最大弹药" = "ammo"
    "攻击力" = "attack"
    "装甲值" = "armor"
    "穿透力" = "penetration"
    "基础命中率" = "accuracy"
    "攻击射程" = "range"
    "移动范围" = "movement"
    "移动动画速度" = "move_speed"
    "视野范围" = "vision"
    "侦察加成" = "recon_bonus"
    "占地宽" = "size_cols"
    "占地高" = "size_rows"
    "可运输" = "can_transport"
    "运输容量" = "transport_capacity"
    "防空单位" = "anti_air"
    "防空命中加成" = "anti_air_bonus"
    "范围效果半径" = "area_effect"
    "可布雷" = "can_lay_mines"
    "可排雷" = "can_clear_mines"
    "可修桥" = "can_repair_bridge"
    "可毁桥" = "can_destroy_bridge"
    "可跨河" = "can_cross_river"
    "可越山" = "can_cross_mountain"
    "指挥单位" = "is_command"
    "指挥半径" = "command_radius"
    "基础行动点" = "base_action_points"
    "可储存行动点" = "can_store_action_points"
    "最大储存AP" = "max_stored_action_points"
    "每回合最大攻击次数" = "max_attacks_per_turn"
    "先手值" = "initiative"
    "行动顺序" = "action_order"
    "允许移动后攻击" = "can_attack_after_move"
    "允许攻击后移动" = "can_move_after_attack"
    "攻击要求本回合静止" = "requires_stationary_attack"
    "反应行动类型" = "reaction_action_type"
    "特殊行动取代攻击" = "special_action_replaces_attack"
    "特性名称" = "trait_name"
    "触发条件" = "trait_trigger"
    "特性效果" = "trait_effect"
    "特性限制" = "trait_limit"
    "配置状态" = "config_status"
}

$integerFields = @(
    "cost", "health", "ammo", "attack", "armor", "penetration", "range",
    "movement", "vision", "recon_bonus", "size_cols", "size_rows",
    "transport_capacity", "area_effect", "command_radius", "base_action_points",
    "max_stored_action_points", "max_attacks_per_turn", "initiative"
)
$floatFields = @("accuracy", "move_speed", "anti_air_bonus")
$booleanFields = @(
    "can_transport", "anti_air", "can_lay_mines", "can_clear_mines",
    "can_repair_bridge", "can_destroy_bridge", "can_cross_river",
    "can_cross_mountain", "is_command", "can_store_action_points",
    "can_attack_after_move", "can_move_after_attack", "requires_stationary_attack",
    "special_action_replaces_attack"
)

function Convert-ToBoolean([object]$Value, [string]$Field, [int]$Row) {
    if ($Value -is [bool]) { return [bool]$Value }
    if ($Value -is [double] -or $Value -is [int]) { return ([double]$Value -ne 0) }
    $text = ([string]$Value).Trim().ToLowerInvariant()
    if ($text -in @("true", "1", "yes", "是")) { return $true }
    if ($text -in @("false", "0", "no", "否", "")) { return $false }
    throw "Invalid boolean '$Value' for $Field at Excel row $Row"
}

function Convert-FieldValue([string]$Field, [object]$Value, [int]$Row) {
    if ($integerFields -contains $Field) {
        if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return 0 }
        return [int][Math]::Round([double]$Value)
    }
    if ($floatFields -contains $Field) {
        if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return 0.0 }
        return [double]$Value
    }
    if ($booleanFields -contains $Field) {
        return Convert-ToBoolean $Value $Field $Row
    }
    if ($null -eq $Value) { return "" }
    return ([string]$Value).Trim()
}

$excel = $null
$workbook = $null
$sheet = $null
try {
    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    $workbook = $excel.Workbooks.Open($sourcePath, 0, $true)
    $sheet = $workbook.Worksheets.Item("单位属性配置")

    $headerRow = 4
    $headerColumns = @{}
    $columnCount = $sheet.UsedRange.Columns.Count
    for ($column = 1; $column -le $columnCount; $column++) {
        $header = ([string]$sheet.Cells.Item($headerRow, $column).Text).Trim()
        if (-not [string]::IsNullOrWhiteSpace($header)) {
            $headerColumns[$header] = $column
        }
    }

    foreach ($requiredHeader in $fieldMap.Keys) {
        if (-not $headerColumns.ContainsKey($requiredHeader)) {
            throw "Required column is missing: $requiredHeader"
        }
    }

    $units = [ordered]@{}
    $rowCount = $sheet.UsedRange.Rows.Count
    for ($row = 5; $row -le $rowCount; $row++) {
        $enumValue = ([string]$sheet.Cells.Item($row, $headerColumns["单位枚举"]).Text).Trim()
        if ([string]::IsNullOrWhiteSpace($enumValue)) { continue }
        if ($enumValue -notmatch '^[A-Z][A-Z0-9_]*$') {
            throw "Invalid unit enum '$enumValue' at Excel row $row"
        }
        if ($units.Contains($enumValue)) {
            throw "Duplicate unit enum '$enumValue' at Excel row $row"
        }

        $unit = [ordered]@{}
        foreach ($header in $fieldMap.Keys) {
            $field = $fieldMap[$header]
            $rawValue = $sheet.Cells.Item($row, $headerColumns[$header]).Value2
            $unit[$field] = Convert-FieldValue $field $rawValue $row
        }

        if ($unit.health -le 0) { throw "$enumValue health must be greater than 0" }
        if ($unit.accuracy -lt 0.0 -or $unit.accuracy -gt 1.0) { throw "$enumValue accuracy must be between 0 and 1" }
        if ($unit.initiative -lt 1 -or $unit.initiative -gt 5) { throw "$enumValue initiative must be between 1 and 5" }
        if ($unit.size_cols -lt 1 -or $unit.size_rows -lt 1) { throw "$enumValue footprint must be at least 1x1" }
        $units[$enumValue] = $unit
    }

    if ($units.Count -ne 23) {
        throw "Expected 23 Warsaw Pact/NATO units, but found $($units.Count)"
    }

    $payload = [ordered]@{
        schema_version = 1
        source_workbook = "res://config/source/unit_config.xlsx"
        generated_at = [DateTime]::Now.ToString("yyyy-MM-ddTHH:mm:ssK")
        unit_count = $units.Count
        units = $units
    }
    $json = $payload | ConvertTo-Json -Depth 8
    $outputDirectory = Split-Path -Parent $outputPath
    [IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
    [IO.File]::WriteAllText($outputPath, $json, [Text.UTF8Encoding]::new($false))
    Write-Output "UNIT_CONFIG_SYNC_OK units=$($units.Count) output=$outputPath"
}
finally {
    if ($null -ne $workbook) { $workbook.Close($false) }
    if ($null -ne $excel) { $excel.Quit() }
    if ($null -ne $sheet) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($sheet) }
    if ($null -ne $workbook) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) }
    if ($null -ne $excel) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}
