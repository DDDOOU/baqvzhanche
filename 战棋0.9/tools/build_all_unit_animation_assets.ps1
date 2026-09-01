param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Add-Type -AssemblyName System.Drawing

$masterDir = Join-Path $ProjectRoot 'art\source\unit_animation_masters_v2'
$outputDir = Join-Path $ProjectRoot 'assets\units\animated\all_units_v2'
$effectDir = Join-Path $ProjectRoot 'assets\effects\unit_attacks_v2'
$configDir = Join-Path $ProjectRoot 'data\units'
New-Item -ItemType Directory -Force -Path $outputDir, $effectDir, $configDir | Out-Null

$masters = @{
    wp_personnel = @{ path = (Join-Path $masterDir 'wp_personnel_low_master.png'); rows = 5; cols = 4 }
    wp_vehicles  = @{ path = (Join-Path $masterDir 'wp_vehicles_low_master.png'); rows = 4; cols = 4 }
    wp_weapons   = @{ path = (Join-Path $masterDir 'wp_weapons_low_master.png'); rows = 4; cols = 4 }
    nato_front   = @{ path = (Join-Path $masterDir 'nato_frontline_master.png'); rows = 5; cols = 4 }
    nato_support = @{ path = (Join-Path $masterDir 'nato_support_master.png'); rows = 4; cols = 4 }
}

$units = @(
    @{ id='INFANTRY_SQUAD'; group='wp_personnel'; row=0; fx='small_arms'; kind='personnel' },
    @{ id='MOTOR_RIFLE'; group='wp_personnel'; row=1; fx='small_arms'; kind='personnel' },
    @{ id='BMP2_IFV'; group='wp_vehicles'; row=0; fx='autocannon'; kind='vehicle' },
    @{ id='BM21_ROCKET'; group='wp_vehicles'; row=1; fx='rocket_salvo'; kind='vehicle' },
    @{ id='SA13_AA'; group='wp_vehicles'; row=2; fx='missile'; kind='vehicle' },
    @{ id='RECON_PLATOON'; group='wp_personnel'; row=2; fx='small_arms'; kind='personnel' },
    @{ id='SAPPERS'; group='wp_personnel'; row=3; fx='small_arms'; kind='personnel' },
    @{ id='COMMAND_ELEMENT'; group='wp_personnel'; row=4; fx='small_arms'; kind='personnel' },
    @{ id='RESERVE'; group='wp_weapons'; row=3; fx='small_arms'; kind='vehicle' },
    @{ id='ATGM_TEAM'; group='wp_weapons'; row=0; fx='missile'; kind='personnel' },
    @{ id='BRDM2_RECON'; group='wp_vehicles'; row=3; fx='small_arms'; kind='vehicle' },
    @{ id='ZSU23_AA'; group='wp_weapons'; row=1; fx='autocannon'; kind='vehicle' },
    @{ id='GVOZDIKA_ARTILLERY'; group='wp_weapons'; row=2; fx='artillery'; kind='vehicle' },
    @{ id='M1A1_TANK'; group='nato_front'; row=0; fx='heavy_cannon'; kind='vehicle' },
    @{ id='M2_IFV'; group='nato_front'; row=1; fx='autocannon'; kind='vehicle' },
    @{ id='MECH_INFANTRY'; group='nato_front'; row=2; fx='small_arms'; kind='personnel' },
    @{ id='AH64_HELICOPTER'; group='nato_front'; row=3; fx='rocket_salvo'; kind='air' },
    @{ id='NATO_ENGINEER'; group='nato_front'; row=4; fx='small_arms'; kind='personnel' },
    @{ id='M901_ITV'; group='nato_support'; row=0; fx='missile'; kind='vehicle' },
    @{ id='M109_ARTILLERY'; group='nato_support'; row=1; fx='artillery'; kind='vehicle' },
    @{ id='M113_APC'; group='nato_support'; row=2; fx='small_arms'; kind='vehicle' },
    @{ id='NATO_RECON_SECTION'; group='nato_support'; row=3; fx='small_arms'; kind='personnel' }
)

function Test-BackgroundPixel([System.Drawing.Color]$c) {
    $max = [Math]::Max($c.R, [Math]::Max($c.G, $c.B))
    $min = [Math]::Min($c.R, [Math]::Min($c.G, $c.B))
    $brightness = ($c.R + $c.G + $c.B) / 3.0
    return (($max - $min) -le 18 -and $brightness -ge 188)
}

function Get-CellSprite($bitmap, [int]$columns, [int]$rows, [int]$column, [int]$row, [string]$kind) {
    $x0 = [int][Math]::Floor($column * $bitmap.Width / [double]$columns)
    $x1 = [int][Math]::Floor(($column + 1) * $bitmap.Width / [double]$columns) - 1
    $y0 = [int][Math]::Floor($row * $bitmap.Height / [double]$rows)
    $y1 = [int][Math]::Floor(($row + 1) * $bitmap.Height / [double]$rows) - 1
    $width = $x1 - $x0 + 1
    $height = $y1 - $y0 + 1
    $background = New-Object 'bool[,]' $width, $height
    $queue = New-Object 'System.Collections.Generic.Queue[int]'

    function Try-Background([int]$lx, [int]$ly) {
        if ($lx -lt 0 -or $ly -lt 0 -or $lx -ge $width -or $ly -ge $height -or $background[$lx,$ly]) { return }
        if (Test-BackgroundPixel $bitmap.GetPixel($x0 + $lx, $y0 + $ly)) {
            $background[$lx,$ly] = $true
            $queue.Enqueue($ly * $width + $lx)
        }
    }

    for ($x = 0; $x -lt $width; $x++) { Try-Background $x 0; Try-Background $x ($height - 1) }
    for ($y = 0; $y -lt $height; $y++) { Try-Background 0 $y; Try-Background ($width - 1) $y }
    while ($queue.Count -gt 0) {
        $value = $queue.Dequeue(); $cx = $value % $width; $cy = [int][Math]::Floor($value / $width)
        Try-Background ($cx - 1) $cy; Try-Background ($cx + 1) $cy
        Try-Background $cx ($cy - 1); Try-Background $cx ($cy + 1)
    }

    # 图像母版偶尔会在单元格边缘留下天线尖点、邻格碎片或预览背景残点。
    # 先计算前景连通块，只保留相对主体足够大的部分，避免一个远端像素把整组单位缩得很小。
    $foregroundVisited = New-Object 'bool[,]' $width, $height
    $components = New-Object 'System.Collections.Generic.List[object]'
    $largestComponent = 0
    for ($scanY = 0; $scanY -lt $height; $scanY++) {
        for ($scanX = 0; $scanX -lt $width; $scanX++) {
            if ($background[$scanX,$scanY] -or $foregroundVisited[$scanX,$scanY]) { continue }
            $componentQueue = New-Object 'System.Collections.Generic.Queue[int]'
            $component = New-Object 'System.Collections.Generic.List[int]'
            $componentQueue.Enqueue($scanY * $width + $scanX)
            $foregroundVisited[$scanX,$scanY] = $true
            while ($componentQueue.Count -gt 0) {
                $componentValue = $componentQueue.Dequeue()
                $componentX = $componentValue % $width
                $componentY = [int][Math]::Floor($componentValue / $width)
                $component.Add($componentValue)
                $neighbors = @(
                    @(($componentX - 1), $componentY), @(($componentX + 1), $componentY),
                    @($componentX, ($componentY - 1)), @($componentX, ($componentY + 1))
                )
                foreach ($neighbor in $neighbors) {
                    $neighborX = [int]$neighbor[0]; $neighborY = [int]$neighbor[1]
                    if ($neighborX -lt 0 -or $neighborY -lt 0 -or $neighborX -ge $width -or $neighborY -ge $height) { continue }
                    if ($background[$neighborX,$neighborY] -or $foregroundVisited[$neighborX,$neighborY]) { continue }
                    $foregroundVisited[$neighborX,$neighborY] = $true
                    $componentQueue.Enqueue($neighborY * $width + $neighborX)
                }
            }
            $components.Add($component)
            $largestComponent = [Math]::Max($largestComponent, $component.Count)
        }
    }
    $minimumComponent = [Math]::Max(12, [int][Math]::Floor($largestComponent * 0.055))
    foreach ($component in $components) {
        if ($component.Count -ge $minimumComponent) { continue }
        foreach ($componentValue in $component) {
            $componentX = $componentValue % $width
            $componentY = [int][Math]::Floor($componentValue / $width)
            $background[$componentX,$componentY] = $true
        }
    }

    $left=$width; $right=-1; $top=$height; $bottom=-1
    for ($y=0; $y -lt $height; $y++) {
        for ($x=0; $x -lt $width; $x++) {
            if (-not $background[$x,$y]) {
                $left=[Math]::Min($left,$x); $right=[Math]::Max($right,$x)
                $top=[Math]::Min($top,$y); $bottom=[Math]::Max($bottom,$y)
            }
        }
    }
    if ($right -lt $left) { return New-Object Drawing.Bitmap 32,32 }

    $sourceWidth=$right-$left+1; $sourceHeight=$bottom-$top+1
    $maxWidth = 28; $maxHeight = if ($kind -eq 'personnel') { 25 } elseif ($kind -eq 'air') { 22 } else { 23 }
    $scale=[Math]::Min($maxWidth/[double]$sourceWidth,$maxHeight/[double]$sourceHeight)
    $targetWidth=[Math]::Max(1,[int][Math]::Round($sourceWidth*$scale))
    $targetHeight=[Math]::Max(1,[int][Math]::Round($sourceHeight*$scale))
    $frame=New-Object Drawing.Bitmap 32,32,([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $destX=[int][Math]::Floor((32-$targetWidth)/2.0); $destY=29-$targetHeight
    for ($dy=0; $dy -lt $targetHeight; $dy++) {
        $sy=$top+[Math]::Min($sourceHeight-1,[int][Math]::Floor($dy*$sourceHeight/[double]$targetHeight))
        for ($dx=0; $dx -lt $targetWidth; $dx++) {
            $sx=$left+[Math]::Min($sourceWidth-1,[int][Math]::Floor($dx*$sourceWidth/[double]$targetWidth))
            if (-not $background[$sx,$sy]) {
                $c=$bitmap.GetPixel($x0+$sx,$y0+$sy)
                # 颜色按32级量化，保持T-72B式的大色块，而不是高分辨率细碎纹理。
                $r=[Math]::Min(255,[int]([Math]::Round($c.R/32.0)*32))
                $g=[Math]::Min(255,[int]([Math]::Round($c.G/32.0)*32))
                $b=[Math]::Min(255,[int]([Math]::Round($c.B/32.0)*32))
                $frame.SetPixel($destX+$dx,$destY+$dy,[Drawing.Color]::FromArgb(255,$r,$g,$b))
            }
        }
    }
    return $frame
}

function Add-Frame($sheet, $frame, [int]$column, [int]$row, [int]$shiftX, [int]$shiftY) {
    for ($y=0; $y -lt 32; $y++) {
        for ($x=0; $x -lt 32; $x++) {
            $c=$frame.GetPixel($x,$y)
            if ($c.A -eq 0) { continue }
            $dx=$column*32+$x+$shiftX; $dy=$row*32+$y+$shiftY
            if ($dx -ge $column*32 -and $dx -lt ($column+1)*32 -and $dy -ge $row*32 -and $dy -lt ($row+1)*32) {
                $sheet.SetPixel($dx,$dy,$c)
            }
        }
    }
}

function Write-UnitSheets([string]$id, [System.Drawing.Bitmap[]]$directions, [string]$kind) {
    $move=New-Object Drawing.Bitmap 128,128,([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $attack=New-Object Drawing.Bitmap 128,128,([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $forward=@(@(1,1),@(-1,1),@(-1,-1),@(1,-1))
    $seed=[Math]::Abs($id.GetHashCode())
    for ($row=0; $row -lt 4; $row++) {
        $fx=[int]$forward[$row][0]; $fy=[int]$forward[$row][1]
        $bob = if (($seed + $row) % 2 -eq 0) { -1 } else { 0 }
        Add-Frame $move $directions[$row] 0 $row 0 0
        Add-Frame $move $directions[$row] 1 $row $fx $bob
        Add-Frame $move $directions[$row] 2 $row 0 0
        Add-Frame $move $directions[$row] 3 $row (-$fx) $bob
        Add-Frame $attack $directions[$row] 0 $row 0 0
        Add-Frame $attack $directions[$row] 1 $row (-$fx) (-$fy)
        Add-Frame $attack $directions[$row] 2 $row (-$fx) (-$fy + $bob)
        Add-Frame $attack $directions[$row] 3 $row 0 0
    }
    $slug=$id.ToLowerInvariant()
    $move.Save((Join-Path $outputDir ($slug+'_move_4dir_4f.png')),[Drawing.Imaging.ImageFormat]::Png)
    $attack.Save((Join-Path $outputDir ($slug+'_attack_4dir_4f.png')),[Drawing.Imaging.ImageFormat]::Png)
    $move.Dispose(); $attack.Dispose()
}

$loadedMasters=@{}
foreach ($key in $masters.Keys) { $loadedMasters[$key]=[Drawing.Bitmap]::FromFile($masters[$key].path) }

foreach ($unit in $units) {
    $master=$loadedMasters[$unit.group]; $definition=$masters[$unit.group]
    [Drawing.Bitmap[]]$directions=@()
    for ($direction=0; $direction -lt 4; $direction++) {
        $directions += Get-CellSprite $master $definition.cols $definition.rows $direction $unit.row $unit.kind
    }
    Write-UnitSheets $unit.id $directions $unit.kind
    foreach ($frame in $directions) { $frame.Dispose() }
}

# T-72B严格保留用户确认的128x128基准图，并使用已确认的攻击后坐图。
Copy-Item -Force -LiteralPath (Join-Path $ProjectRoot 'assets\units\animated\wp_light_tank_target_4dir_4f.png') -Destination (Join-Path $outputDir 't72b_tank_move_4dir_4f.png')
Copy-Item -Force -LiteralPath (Join-Path $ProjectRoot 'assets\units\animated\wp_light_tank_attack_4dir_4f.png') -Destination (Join-Path $outputDir 't72b_tank_attack_4dir_4f.png')

# 中立单位复用已缩小的轮廓并重新着色；未知接触刻意保持暗色剪影。
$m113Move=[Drawing.Bitmap]::FromFile((Join-Path $outputDir 'm113_apc_move_4dir_4f.png'))
$m113Attack=[Drawing.Bitmap]::FromFile((Join-Path $outputDir 'm113_apc_attack_4dir_4f.png'))
function Save-Recolored($source,[string]$path,[double]$rMul,[double]$gMul,[double]$bMul) {
    $result=New-Object Drawing.Bitmap $source.Width,$source.Height,([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    for($y=0;$y -lt $source.Height;$y++){for($x=0;$x -lt $source.Width;$x++){$c=$source.GetPixel($x,$y);if($c.A -gt 0){$result.SetPixel($x,$y,[Drawing.Color]::FromArgb(255,[Math]::Min(255,[int]($c.R*$rMul)),[Math]::Min(255,[int]($c.G*$gMul)),[Math]::Min(255,[int]($c.B*$bMul))))}}}
    $result.Save($path,[Drawing.Imaging.ImageFormat]::Png);$result.Dispose()
}
Save-Recolored $m113Move (Join-Path $outputDir 'civilian_convoy_move_4dir_4f.png') 1.15 0.92 0.70
Save-Recolored $m113Attack (Join-Path $outputDir 'civilian_convoy_attack_4dir_4f.png') 1.15 0.92 0.70
Save-Recolored $m113Move (Join-Path $outputDir 'unknown_contact_move_4dir_4f.png') 0.38 0.42 0.46
Save-Recolored $m113Attack (Join-Path $outputDir 'unknown_contact_attack_4dir_4f.png') 0.38 0.42 0.46
$m113Move.Dispose();$m113Attack.Dispose()

foreach ($master in $loadedMasters.Values) { $master.Dispose() }

function Set-Block($bitmap,[int]$x,[int]$y,[int]$w,[int]$h,[Drawing.Color]$color) {
    for($py=$y;$py -lt $y+$h;$py++){for($px=$x;$px -lt $x+$w;$px++){if($px-ge 0-and$px-lt$bitmap.Width-and$py-ge 0-and$py-lt$bitmap.Height){$bitmap.SetPixel($px,$py,$color)}}}
}
function Write-Effect([string]$name,[string]$mode) {
    $fx=New-Object Drawing.Bitmap 128,32,([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $white=[Drawing.Color]::FromArgb(255,255,248,210);$yellow=[Drawing.Color]::FromArgb(255,255,216,48)
    $orange=[Drawing.Color]::FromArgb(255,240,120,24);$red=[Drawing.Color]::FromArgb(255,176,48,16)
    $smoke=[Drawing.Color]::FromArgb(210,96,96,80);$cyan=[Drawing.Color]::FromArgb(255,160,232,255)
    $length = switch($mode){'small'{4}'auto'{7}'rocket'{12}'missile'{14}'artillery'{10}default{9}}
    $primary = if($mode -eq 'missile'){$cyan}else{$yellow}
    Set-Block $fx 16 15 2 2 $primary; Set-Block $fx 18 15 2 1 $orange
    Set-Block $fx (32+15) 14 ([Math]::Min(10,$length)) 5 $orange
    Set-Block $fx (32+17) 15 ([Math]::Min(7,$length)) 3 $white
    if($mode -eq 'auto'){Set-Block $fx (32+18) 11 2 2 $yellow;Set-Block $fx (32+18) 20 2 2 $yellow}
    Set-Block $fx (64+15) 15 $length 3 $primary; Set-Block $fx (64+20) 14 ([Math]::Max(2,$length-5)) 5 $orange
    if($mode -in @('rocket','missile','artillery')){Set-Block $fx (64+19) 10 4 3 $smoke;Set-Block $fx (64+25) 20 4 2 $smoke}
    Set-Block $fx (96+18) 15 2 2 $orange;Set-Block $fx (96+23) 12 2 2 $red;Set-Block $fx (96+28) 18 2 2 $smoke
    $fx.Save((Join-Path $effectDir ($name+'_4f.png')),[Drawing.Imaging.ImageFormat]::Png);$fx.Dispose()
}
Write-Effect 'fx_small_arms' 'small'; Write-Effect 'fx_autocannon' 'auto'
Write-Effect 'fx_heavy_cannon' 'heavy'; Write-Effect 'fx_rocket_salvo' 'rocket'
Write-Effect 'fx_missile' 'missile'; Write-Effect 'fx_artillery' 'artillery'

$allUnits=@($units)+@(
    @{id='T72B_TANK';fx='heavy_cannon'},@{id='CIVILIAN_CONVOY';fx='small_arms'},@{id='UNKNOWN_CONTACT';fx='small_arms'}
)
$animationConfig=[ordered]@{schema_version=2;frame_size=@(32,32);directions=4;frames_per_action=4;units=[ordered]@{}}
foreach($unit in $allUnits){
    $slug=$unit.id.ToLowerInvariant()
    $animationConfig.units[$unit.id]=[ordered]@{
        move_path="res://assets/units/animated/all_units_v2/${slug}_move_4dir_4f.png"
        attack_path="res://assets/units/animated/all_units_v2/${slug}_attack_4dir_4f.png"
        effect_path="res://assets/effects/unit_attacks_v2/fx_$($unit.fx)_4f.png"
        ground_anchor=@(16,29);native_world_scale=2.0;attack_duration=0.32
        muzzle_offsets=@(@(14,-7),@(-14,-7),@(-14,-21),@(14,-21))
    }
}
$animationConfig | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $configDir 'unit_animation_config.json') -Encoding UTF8
Write-Output "Generated $($allUnits.Count) unit animation sets in $outputDir"
