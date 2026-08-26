param(
    [string]$Output = "$PSScriptRoot\..\assets\units\animated\wp_light_tank_4dir_4f_chunky.png"
)

Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = "Stop"

function New-Color([int]$r, [int]$g, [int]$b) {
    return [System.Drawing.Color]::FromArgb(255, $r, $g, $b)
}

$outline = New-Color 25 26 17
$track = New-Color 57 48 31
$shadow = New-Color 71 73 39
$base = New-Color 111 113 59
$light = New-Color 164 158 84
$highlight = New-Color 203 190 108
$red = New-Color 224 47 28

function New-Brush([System.Drawing.Color]$color) {
    return New-Object System.Drawing.SolidBrush $color
}

function New-Points([int[][]]$coords) {
    $points = New-Object 'System.Drawing.Point[]' $coords.Count
    for ($index = 0; $index -lt $coords.Count; $index++) {
        $points[$index] = New-Object System.Drawing.Point $coords[$index][0], $coords[$index][1]
    }
    return $points
}

function Fill-Shape($graphics, [System.Drawing.Color]$color, [int[][]]$coords) {
    $brush = New-Brush $color
    $graphics.FillPolygon($brush, (New-Points $coords))
    $brush.Dispose()
}

function Build-BaseFrame([int]$animationFrame) {
    $bitmap = New-Object System.Drawing.Bitmap 16, 16, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
    $graphics.Clear([System.Drawing.Color]::Transparent)

    # 整体轮廓：所有结构都使用连续色块，不使用抖动或孤立纹理。
    Fill-Shape $graphics $outline @(@(1,7), @(6,3), @(12,5), @(13,9), @(8,13), @(2,11))
    Fill-Shape $graphics $track @(@(1,8), @(7,11), @(7,13), @(2,10))
    Fill-Shape $graphics $track @(@(7,11), @(12,5), @(13,8), @(8,13))
    Fill-Shape $graphics $shadow @(@(2,7), @(6,4), @(12,6), @(12,8), @(8,11), @(3,9))
    Fill-Shape $graphics $base @(@(3,7), @(6,4), @(11,6), @(7,9))
    Fill-Shape $graphics $light @(@(4,7), @(6,5), @(9,6), @(7,8))
    Fill-Shape $graphics $shadow @(@(7,9), @(11,6), @(12,8), @(8,11))

    # 炮塔与炮管。
    Fill-Shape $graphics $outline @(@(4,5), @(7,3), @(10,5), @(7,8), @(4,7))
    Fill-Shape $graphics $base @(@(5,5), @(7,4), @(9,5), @(7,7), @(5,6))
    $bitmap.SetPixel(6, 4, $light)
    $barrelPixels = @(@(8,5), @(9,5), @(10,6), @(11,6), @(12,7), @(13,7), @(14,8), @(15,8))
    foreach ($point in $barrelPixels) { $bitmap.SetPixel($point[0], $point[1], $outline) }
    foreach ($point in @(@(9,5), @(10,6), @(11,6), @(12,7), @(13,7), @(14,8))) {
        $bitmap.SetPixel($point[0], $point[1], $base)
    }

    # 华约识别点保持为一个2×2输出像素块。
    $bitmap.SetPixel(7, 9, $red)

    # 四帧只改变履带亮块和车体高光，不改变轮廓与接地点。
    if ($animationFrame -eq 1) {
        $bitmap.SetPixel(3, 10, $highlight)
        $bitmap.SetPixel(5, 11, $light)
    } elseif ($animationFrame -eq 2) {
        $bitmap.SetPixel(6, 5, $highlight)
        $bitmap.SetPixel(10, 9, $light)
    } elseif ($animationFrame -eq 3) {
        $bitmap.SetPixel(11, 10, $highlight)
        $bitmap.SetPixel(13, 8, $light)
    }

    $graphics.Dispose()
    return $bitmap
}

$outputPath = [System.IO.Path]::GetFullPath($Output)
$sheet = New-Object System.Drawing.Bitmap 128, 128, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

for ($row = 0; $row -lt 4; $row++) {
    for ($column = 0; $column -lt 4; $column++) {
        $baseFrame = Build-BaseFrame $column
        for ($sourceY = 0; $sourceY -lt 16; $sourceY++) {
            for ($sourceX = 0; $sourceX -lt 16; $sourceX++) {
                $color = $baseFrame.GetPixel($sourceX, $sourceY)
                if ($color.A -eq 0) { continue }

                $targetX = $sourceX
                $targetY = $sourceY
                if ($row -eq 1) {
                    $targetX = 15 - $sourceX
                } elseif ($row -eq 2) {
                    $targetX = 15 - $sourceX
                    $targetY = 16 - $sourceY
                } elseif ($row -eq 3) {
                    $targetY = 16 - $sourceY
                }
                if ($targetY -lt 0 -or $targetY -ge 16) { continue }

                $sheetX = $column * 32 + $targetX * 2
                $sheetY = $row * 32 + $targetY * 2
                for ($pixelY = 0; $pixelY -lt 2; $pixelY++) {
                    for ($pixelX = 0; $pixelX -lt 2; $pixelX++) {
                        $sheet.SetPixel($sheetX + $pixelX, $sheetY + $pixelY, $color)
                    }
                }
            }
        }
        $baseFrame.Dispose()
    }
}

$sheet.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()
Write-Output "Saved chunky light-tank sprite sheet: $outputPath"
