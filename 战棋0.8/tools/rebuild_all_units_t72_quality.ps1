param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$UnitId = ''
)

Add-Type -AssemblyName System.Drawing

$sourceDir = Join-Path $ProjectRoot 'art\source\unit_animation_individual_v3'
$outputDir = Join-Path $ProjectRoot 'assets\units\animated\all_units_v2'
New-Item -ItemType Directory -Force -Path $sourceDir, $outputDir | Out-Null

$units = @(
    @{ id='INFANTRY_SQUAD'; kind='personnel' }, @{ id='MOTOR_RIFLE'; kind='personnel' },
    @{ id='BMP2_IFV'; kind='vehicle' }, @{ id='BM21_ROCKET'; kind='vehicle' },
    @{ id='SA13_AA'; kind='vehicle' }, @{ id='RECON_PLATOON'; kind='personnel' },
    @{ id='SAPPERS'; kind='personnel' }, @{ id='COMMAND_ELEMENT'; kind='personnel' },
    @{ id='RESERVE'; kind='vehicle' }, @{ id='ATGM_TEAM'; kind='personnel' },
    @{ id='BRDM2_RECON'; kind='vehicle' }, @{ id='ZSU23_AA'; kind='vehicle' },
    @{ id='GVOZDIKA_ARTILLERY'; kind='vehicle' }, @{ id='M1A1_TANK'; kind='vehicle' },
    @{ id='M2_IFV'; kind='vehicle' }, @{ id='MECH_INFANTRY'; kind='personnel' },
    @{ id='AH64_HELICOPTER'; kind='air' }, @{ id='NATO_ENGINEER'; kind='personnel' },
    @{ id='M901_ITV'; kind='vehicle' }, @{ id='M109_ARTILLERY'; kind='vehicle' },
    @{ id='M113_APC'; kind='vehicle' }, @{ id='NATO_RECON_SECTION'; kind='personnel' },
    @{ id='CIVILIAN_CONVOY'; kind='vehicle' }, @{ id='UNKNOWN_CONTACT'; kind='vehicle' }
)
if ($UnitId) {
    $units = @($units | Where-Object { $_.id -eq $UnitId.ToUpperInvariant() })
    if ($units.Count -eq 0) { throw "Unknown unit id: $UnitId" }
}

function Test-BackgroundPixel([System.Drawing.Color]$Color) {
    if ($Color.A -le 32) { return $true }
    $max = [Math]::Max($Color.R, [Math]::Max($Color.G, $Color.B))
    $min = [Math]::Min($Color.R, [Math]::Min($Color.G, $Color.B))
    $brightness = ($Color.R + $Color.G + $Color.B) / 3.0
    # 兼容透明母版，以及图像工具偶尔烘焙进图片的浅灰/白色棋盘格。
    return (($max - $min) -le 20 -and $brightness -ge 176)
}

function Get-CleanCell([System.Drawing.Bitmap]$Bitmap, [int]$Column, [int]$Row, [string]$Kind) {
    $x0 = [int][Math]::Floor($Column * $Bitmap.Width / 4.0)
    $x1 = [int][Math]::Floor(($Column + 1) * $Bitmap.Width / 4.0) - 1
    $y0 = [int][Math]::Floor($Row * $Bitmap.Height / 4.0)
    $y1 = [int][Math]::Floor(($Row + 1) * $Bitmap.Height / 4.0) - 1
    $width = $x1 - $x0 + 1
    $height = $y1 - $y0 + 1
    $background = New-Object 'bool[,]' $width, $height
    $queue = New-Object 'System.Collections.Generic.Queue[int]'

    function Try-Background([int]$X, [int]$Y) {
        if ($X -lt 0 -or $Y -lt 0 -or $X -ge $width -or $Y -ge $height -or $background[$X,$Y]) { return }
        if (Test-BackgroundPixel $Bitmap.GetPixel($x0 + $X, $y0 + $Y)) {
            $background[$X,$Y] = $true
            $queue.Enqueue($Y * $width + $X)
        }
    }

    for ($x = 0; $x -lt $width; $x++) { Try-Background $x 0; Try-Background $x ($height - 1) }
    for ($y = 0; $y -lt $height; $y++) { Try-Background 0 $y; Try-Background ($width - 1) $y }
    while ($queue.Count -gt 0) {
        $value = $queue.Dequeue(); $cx = $value % $width; $cy = [int][Math]::Floor($value / $width)
        Try-Background ($cx - 1) $cy; Try-Background ($cx + 1) $cy
        Try-Background $cx ($cy - 1); Try-Background $cx ($cy + 1)
    }

    # 清除孤立噪点，但保留武器、天线、旋翼等与主体相连的细轮廓。
    $visited = New-Object 'bool[,]' $width, $height
    $components = New-Object 'System.Collections.Generic.List[object]'
    $largest = 0
    for ($sy = 0; $sy -lt $height; $sy++) {
        for ($sx = 0; $sx -lt $width; $sx++) {
            if ($background[$sx,$sy] -or $visited[$sx,$sy]) { continue }
            $component = New-Object 'System.Collections.Generic.List[int]'
            $componentQueue = New-Object 'System.Collections.Generic.Queue[int]'
            $componentQueue.Enqueue($sy * $width + $sx); $visited[$sx,$sy] = $true
            while ($componentQueue.Count -gt 0) {
                $v = $componentQueue.Dequeue(); $px = $v % $width; $py = [int][Math]::Floor($v / $width)
                $component.Add($v)
                $neighbors = @(
                    @(($px - 1), $py), @(($px + 1), $py),
                    @($px, ($py - 1)), @($px, ($py + 1))
                )
                foreach ($n in $neighbors) {
                    $nx=[int]$n[0]; $ny=[int]$n[1]
                    if($nx-lt 0-or$ny-lt 0-or$nx-ge$width-or$ny-ge$height-or$background[$nx,$ny]-or$visited[$nx,$ny]){continue}
                    $visited[$nx,$ny]=$true; $componentQueue.Enqueue($ny*$width+$nx)
                }
            }
            $components.Add($component); $largest=[Math]::Max($largest,$component.Count)
        }
    }
    $minimum=[Math]::Max(10,[int][Math]::Floor($largest*0.025))
    foreach($component in $components){
        if($component.Count -lt $minimum){
            foreach($v in $component){
                $componentX = [int]($v % $width)
                $componentY = [int][Math]::Floor($v / $width)
                $background[$componentX,$componentY] = $true
            }
        }
    }

    $left=$width; $right=-1; $top=$height; $bottom=-1
    for($y=0;$y-lt$height;$y++){for($x=0;$x-lt$width;$x++){if(-not$background[$x,$y]){$left=[Math]::Min($left,$x);$right=[Math]::Max($right,$x);$top=[Math]::Min($top,$y);$bottom=[Math]::Max($bottom,$y)}}}
    $frame = New-Object Drawing.Bitmap 32,32,([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    if($right-lt$left){return $frame}

    $sourceWidth=$right-$left+1; $sourceHeight=$bottom-$top+1
    $maxWidth = if($Kind -eq 'air'){30}elseif($Kind -eq 'personnel'){27}else{28}
    $maxHeight = if($Kind -eq 'air'){23}elseif($Kind -eq 'personnel'){26}else{23}
    $scale=[Math]::Min($maxWidth/[double]$sourceWidth,$maxHeight/[double]$sourceHeight)
    $targetWidth=[Math]::Max(1,[int][Math]::Round($sourceWidth*$scale))
    $targetHeight=[Math]::Max(1,[int][Math]::Round($sourceHeight*$scale))
    $destX=[int][Math]::Floor((32-$targetWidth)/2.0); $destY=29-$targetHeight

    for($dy=0;$dy-lt$targetHeight;$dy++){
        $srcY=$top+[Math]::Min($sourceHeight-1,[int][Math]::Floor(($dy+0.5)*$sourceHeight/$targetHeight))
        for($dx=0;$dx-lt$targetWidth;$dx++){
            $srcX=$left+[Math]::Min($sourceWidth-1,[int][Math]::Floor(($dx+0.5)*$sourceWidth/$targetWidth))
            if(-not$background[$srcX,$srcY]){
                $c=$Bitmap.GetPixel($x0+$srcX,$y0+$srcY)
                # 采用与T-72B相同的有限色阶，减少缩小后的碎色噪声。
                $r=[Math]::Min(255,[int]([Math]::Round($c.R/24.0)*24))
                $g=[Math]::Min(255,[int]([Math]::Round($c.G/24.0)*24))
                $b=[Math]::Min(255,[int]([Math]::Round($c.B/24.0)*24))
                $frame.SetPixel($destX+$dx,$destY+$dy,[Drawing.Color]::FromArgb(255,$r,$g,$b))
            }
        }
    }
    return $frame
}

function Add-Frame([System.Drawing.Bitmap]$Sheet,[System.Drawing.Bitmap]$Frame,[int]$Column,[int]$Row,[int]$ShiftX,[int]$ShiftY){
    for($y=0;$y-lt 32;$y++){for($x=0;$x-lt 32;$x++){$c=$Frame.GetPixel($x,$y);if($c.A-eq 0){continue};$dx=$Column*32+$x+$ShiftX;$dy=$Row*32+$y+$ShiftY;if($dx-ge$Column*32-and$dx-lt($Column+1)*32-and$dy-ge$Row*32-and$dy-lt($Row+1)*32){$Sheet.SetPixel($dx,$dy,$c)}}}
}

function Get-PixelWorkCopy([System.Drawing.Bitmap]$Source) {
    # 先把离线母版按原始宽高比缩至工作分辨率。母版中的“逻辑像素”本来就是大色块，
    # 这一步不会改变最终32x32质量，却能避免对数百万像素逐点遍历。
    $workWidth = 320
    $workHeight = [Math]::Max(64, [int][Math]::Round($Source.Height * $workWidth / [double]$Source.Width))
    $work = New-Object Drawing.Bitmap $workWidth,$workHeight,([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($work)
    $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::Half
    $graphics.DrawImage($Source,0,0,$workWidth,$workHeight)
    $graphics.Dispose()
    return $work
}

foreach($unit in $units){
    $slug=$unit.id.ToLowerInvariant()
    $masterPath=Join-Path $sourceDir ($slug+'_master.png')
    if(-not(Test-Path -LiteralPath $masterPath)){throw "Missing master: $masterPath"}
    $originalMaster=[Drawing.Bitmap]::FromFile($masterPath)
    $master=Get-PixelWorkCopy $originalMaster
    $originalMaster.Dispose()
    $move=New-Object Drawing.Bitmap 128,128,([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $attack=New-Object Drawing.Bitmap 128,128,([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    [Drawing.Bitmap[]]$baseDirections=@()
    for($row=0;$row-lt 4;$row++){
        for($column=0;$column-lt 4;$column++){
            $frame=Get-CleanCell $master $column $row $unit.kind
            Add-Frame $move $frame $column $row 0 0
            if($column-eq 0){$baseDirections+=$frame}else{$frame.Dispose()}
        }
    }
    $forward=@(@(1,1),@(-1,1),@(-1,-1),@(1,-1))
    for($row=0;$row-lt 4;$row++){
        $fx=[int]$forward[$row][0];$fy=[int]$forward[$row][1]
        Add-Frame $attack $baseDirections[$row] 0 $row 0 0
        Add-Frame $attack $baseDirections[$row] 1 $row (-$fx) (-$fy)
        Add-Frame $attack $baseDirections[$row] 2 $row (-2*$fx) (-$fy)
        Add-Frame $attack $baseDirections[$row] 3 $row 0 0
    }
    $move.Save((Join-Path $outputDir ($slug+'_move_4dir_4f.png')),[Drawing.Imaging.ImageFormat]::Png)
    $attack.Save((Join-Path $outputDir ($slug+'_attack_4dir_4f.png')),[Drawing.Imaging.ImageFormat]::Png)
    foreach($frame in $baseDirections){$frame.Dispose()};$move.Dispose();$attack.Dispose();$master.Dispose()
    Write-Output "rebuilt $($unit.id)"
}

# 唯一保留项：T-72B继续使用用户确认的原始移动与攻击表。
Copy-Item -Force -LiteralPath (Join-Path $ProjectRoot 'assets\units\animated\wp_light_tank_target_4dir_4f.png') -Destination (Join-Path $outputDir 't72b_tank_move_4dir_4f.png')
Copy-Item -Force -LiteralPath (Join-Path $ProjectRoot 'assets\units\animated\wp_light_tank_attack_4dir_4f.png') -Destination (Join-Path $outputDir 't72b_tank_attack_4dir_4f.png')
Write-Output "rebuilt $($units.Count) requested units; preserved T72B_TANK"
