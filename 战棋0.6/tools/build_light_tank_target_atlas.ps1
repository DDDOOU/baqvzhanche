param(
    [string]$Source = "$PSScriptRoot\..\art\source\wp_light_tank_target_master.png",
    [string]$Output = "$PSScriptRoot\..\assets\units\animated\wp_light_tank_target_4dir_4f.png"
)

Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = "Stop"

$sourcePath = [System.IO.Path]::GetFullPath($Source)
$outputPath = [System.IO.Path]::GetFullPath($Output)
$sourceBitmap = [System.Drawing.Bitmap]::FromFile($sourcePath)
$sheet = New-Object System.Drawing.Bitmap 128, 128, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$sheetGraphics = [System.Drawing.Graphics]::FromImage($sheet)
$sheetGraphics.Clear([System.Drawing.Color]::Transparent)
$sheetGraphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$sheetGraphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighSpeed
$sheetGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$sheetGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
$sheetGraphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None

# 母版从上到下：左上、右上、左下、右下。
# UnitRenderer需要：右下、左下、左上、右上。
$sourceRowsForTarget = @(3, 2, 0, 1)
# 生成母版的四排并非严格等距：第三排底部会跨入第四排的天线。
# 使用实测安全行带，避免相邻排透明像素被误计入边界而缩小当前帧。
$sourceRowTops = @(20, 320, 610, 920)
$sourceRowBottoms = @(300, 590, 900, 1225)
$frameSize = 32
$maxContentWidth = 30
$maxContentHeight = 26
$groundY = 29

for ($targetRow = 0; $targetRow -lt 4; $targetRow++) {
    $sourceRow = $sourceRowsForTarget[$targetRow]
    for ($column = 0; $column -lt 4; $column++) {
        $cellLeft = [int][Math]::Floor($column * $sourceBitmap.Width / 4.0)
        $cellRight = [int][Math]::Floor(($column + 1) * $sourceBitmap.Width / 4.0) - 1
        $cellTop = $sourceRowTops[$sourceRow]
        $cellBottom = [Math]::Min($sourceRowBottoms[$sourceRow], $sourceBitmap.Height - 1)

        $minX = $cellRight
        $maxX = $cellLeft
        $minY = $cellBottom
        $maxY = $cellTop
        for ($y = $cellTop; $y -le $cellBottom; $y++) {
            for ($x = $cellLeft; $x -le $cellRight; $x++) {
                $sourcePixel = $sourceBitmap.GetPixel($x, $y)
                if ($sourcePixel.A -le 24 `
                        -or [Math]::Max($sourcePixel.R,
                            [Math]::Max($sourcePixel.G, $sourcePixel.B)) -le 24) { continue }
                $minX = [Math]::Min($minX, $x)
                $maxX = [Math]::Max($maxX, $x)
                $minY = [Math]::Min($minY, $y)
                $maxY = [Math]::Max($maxY, $y)
            }
        }

        $contentWidth = $maxX - $minX + 1
        $contentHeight = $maxY - $minY + 1
        if ($contentWidth -le 0 -or $contentHeight -le 0) {
            throw "No visible tank pixels found in source cell ($column,$sourceRow)."
        }

        $scale = [Math]::Min($maxContentWidth / [double]$contentWidth,
            $maxContentHeight / [double]$contentHeight)
        $drawWidth = [Math]::Max(1, [int][Math]::Round($contentWidth * $scale))
        $drawHeight = [Math]::Max(1, [int][Math]::Round($contentHeight * $scale))
        $drawX = $column * $frameSize + [int][Math]::Floor(($frameSize - $drawWidth) / 2.0)
        $drawY = $targetRow * $frameSize + $groundY - $drawHeight

        $destination = New-Object System.Drawing.Rectangle $drawX, $drawY, $drawWidth, $drawHeight
        $sheetGraphics.DrawImage($sourceBitmap, $destination,
            $minX, $minY, $contentWidth, $contentHeight,
            [System.Drawing.GraphicsUnit]::Pixel)
    }
}

$sheetGraphics.Dispose()
$sourceBitmap.Dispose()

# Godot像素素材只保留二值透明度，避免缩小时产生半透明灰边。
for ($y = 0; $y -lt $sheet.Height; $y++) {
    for ($x = 0; $x -lt $sheet.Width; $x++) {
        $color = $sheet.GetPixel($x, $y)
        if ($color.A -lt 128) {
            $sheet.SetPixel($x, $y, [System.Drawing.Color]::Transparent)
        } else {
            $sheet.SetPixel($x, $y,
                [System.Drawing.Color]::FromArgb(255, $color.R, $color.G, $color.B))
        }
    }
}

$sheet.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$sheet.Dispose()
Write-Output "Saved target-derived sprite sheet: $outputPath"
