param(
    [string]$Source = "C:\Users\Lenovo\.codex\generated_images\019ffb61-7f6c-7931-86ac-50c9da14edb0\exec-aad3a3f8-037b-4a3b-a590-77924b4cebe4.png",
    [string]$Output = "$PSScriptRoot\..\assets\units\animated\wp_light_tank_4dir_4f_trench_style.png"
)

Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = "Stop"

function New-Color([int]$r, [int]$g, [int]$b) {
    return [System.Drawing.Color]::FromArgb(255, $r, $g, $b)
}

$palette = @{
    Outline   = New-Color 22 23 15
    Track     = New-Color 54 46 31
    Shadow    = New-Color 67 68 37
    Base      = New-Color 103 105 57
    Light     = New-Color 148 145 79
    Highlight = New-Color 190 181 108
    Red       = New-Color 220 45 28
}

function Convert-Color([double]$r, [double]$g, [double]$b) {
    if ($r -gt 75 -and $r -gt ($g * 1.35) -and $r -gt ($b * 1.25)) {
        return $palette.Red
    }
    $luma = 0.299 * $r + 0.587 * $g + 0.114 * $b
    if ($luma -lt 35)  { return $palette.Outline }
    if ($luma -lt 58)  { return $palette.Track }
    if ($luma -lt 83)  { return $palette.Shadow }
    if ($luma -lt 116) { return $palette.Base }
    if ($luma -lt 158) { return $palette.Light }
    return $palette.Highlight
}

$sourcePath = [System.IO.Path]::GetFullPath($Source)
$outputPath = [System.IO.Path]::GetFullPath($Output)
$sourceBitmap = [System.Drawing.Bitmap]::FromFile($sourcePath)
$outputBitmap = New-Object System.Drawing.Bitmap 128, 128, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)

# 图像参考稿的方向行依次为左上、右上、左下、右下；项目行顺序为右下、左下、左上、右上。
$sourceRowsForTarget = @(3, 2, 0, 1)
$logicalSize = 16
$maxTankWidth = 15
$maxTankHeight = 13

for ($targetRow = 0; $targetRow -lt 4; $targetRow++) {
    $sourceRow = $sourceRowsForTarget[$targetRow]
    for ($column = 0; $column -lt 4; $column++) {
        $cellLeft = [int][Math]::Floor($column * $sourceBitmap.Width / 4.0)
        $cellRight = [int][Math]::Floor(($column + 1) * $sourceBitmap.Width / 4.0) - 1
        $cellTop = [int][Math]::Floor($sourceRow * $sourceBitmap.Height / 4.0)
        $cellBottom = [int][Math]::Floor(($sourceRow + 1) * $sourceBitmap.Height / 4.0) - 1

        $minX = $cellRight
        $maxX = $cellLeft
        $minY = $cellBottom
        $maxY = $cellTop
        for ($y = $cellTop; $y -le $cellBottom; $y++) {
            for ($x = $cellLeft; $x -le $cellRight; $x++) {
                $color = $sourceBitmap.GetPixel($x, $y)
                if ([Math]::Max($color.R, [Math]::Max($color.G, $color.B)) -le 24) { continue }
                $minX = [Math]::Min($minX, $x)
                $maxX = [Math]::Max($maxX, $x)
                $minY = [Math]::Min($minY, $y)
                $maxY = [Math]::Max($maxY, $y)
            }
        }

        $sourceWidth = $maxX - $minX + 1
        $sourceHeight = $maxY - $minY + 1
        $fitScale = [Math]::Min($maxTankWidth / [double]$sourceWidth,
            $maxTankHeight / [double]$sourceHeight)
        $targetWidth = [Math]::Max(1, [int][Math]::Round($sourceWidth * $fitScale))
        $targetHeight = [Math]::Max(1, [int][Math]::Round($sourceHeight * $fitScale))
        $targetLeft = [int][Math]::Floor(($logicalSize - $targetWidth) / 2.0)
        # 底部落在逻辑像素13，放大后正好接近项目的y=28地面锚点。
        $targetTop = 14 - $targetHeight

        for ($logicalY = 0; $logicalY -lt $targetHeight; $logicalY++) {
            for ($logicalX = 0; $logicalX -lt $targetWidth; $logicalX++) {
                $sampleLeft = $minX + [int][Math]::Floor($logicalX * $sourceWidth / [double]$targetWidth)
                $sampleRight = $minX + [int][Math]::Ceiling(($logicalX + 1) * $sourceWidth / [double]$targetWidth) - 1
                $sampleTop = $minY + [int][Math]::Floor($logicalY * $sourceHeight / [double]$targetHeight)
                $sampleBottom = $minY + [int][Math]::Ceiling(($logicalY + 1) * $sourceHeight / [double]$targetHeight) - 1

                $redTotal = 0.0
                $greenTotal = 0.0
                $blueTotal = 0.0
                $opaqueSamples = 0
                $allSamples = 0
                for ($sampleY = $sampleTop; $sampleY -le $sampleBottom; $sampleY++) {
                    for ($sampleX = $sampleLeft; $sampleX -le $sampleRight; $sampleX++) {
                        $allSamples++
                        $sample = $sourceBitmap.GetPixel($sampleX, $sampleY)
                        if ([Math]::Max($sample.R, [Math]::Max($sample.G, $sample.B)) -le 24) { continue }
                        $opaqueSamples++
                        $redTotal += $sample.R
                        $greenTotal += $sample.G
                        $blueTotal += $sample.B
                    }
                }
                if ($opaqueSamples -eq 0 -or ($opaqueSamples / [double]$allSamples) -lt 0.28) { continue }

                $mapped = Convert-Color ($redTotal / $opaqueSamples) `
                    ($greenTotal / $opaqueSamples) ($blueTotal / $opaqueSamples)
                $outputX = $column * 32 + ($targetLeft + $logicalX) * 2
                $outputY = $targetRow * 32 + ($targetTop + $logicalY) * 2
                for ($pixelY = 0; $pixelY -lt 2; $pixelY++) {
                    for ($pixelX = 0; $pixelX -lt 2; $pixelX++) {
                        $outputBitmap.SetPixel($outputX + $pixelX, $outputY + $pixelY, $mapped)
                    }
                }
            }
        }
    }
}

$sourceBitmap.Dispose()
$outputBitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$outputBitmap.Dispose()
Write-Output "Saved trench-style sprite sheet: $outputPath"
