param(
    [string]$Source = "$PSScriptRoot\..\assets\units\animated\wp_light_tank_4dir_4f_64.png",
    [string]$Output = "$PSScriptRoot\..\assets\units\animated\wp_light_tank_4dir_4f_crisp.png",
    [string]$Output32 = "$PSScriptRoot\..\assets\units\animated\wp_light_tank_4dir_4f_crisp_32.png"
)

Add-Type -AssemblyName System.Drawing

function New-Color([int]$r, [int]$g, [int]$b) {
    return [System.Drawing.Color]::FromArgb(255, $r, $g, $b)
}

$palette = @{
    Outline    = New-Color 20 21 14
    DeepTrack  = New-Color 35 35 22
    Track      = New-Color 55 53 31
    DarkOlive  = New-Color 72 73 40
    Olive      = New-Color 105 104 54
    LightOlive = New-Color 145 139 76
    Highlight  = New-Color 188 175 103
    MetalDark  = New-Color 72 70 62
    MetalLight = New-Color 137 132 111
    White      = New-Color 211 207 182
    RedDark    = New-Color 151 38 26
    Red        = New-Color 221 62 35
}

function Convert-Pixel([System.Drawing.Color]$color) {
    if ($color.A -lt 128) {
        return [System.Drawing.Color]::Transparent
    }

    $r = [int]$color.R
    $g = [int]$color.G
    $b = [int]$color.B
    $max = [Math]::Max($r, [Math]::Max($g, $b))
    $min = [Math]::Min($r, [Math]::Min($g, $b))
    $chroma = $max - $min
    $luma = [int](0.299 * $r + 0.587 * $g + 0.114 * $b)

    # 阵营识别红色单独保留，避免被橄榄色量化吞掉。
    if ($r -gt 90 -and $r -gt ($g * 1.35) -and $r -gt ($b * 1.25)) {
        if ($luma -lt 90) { return $palette.RedDark }
        return $palette.Red
    }

    # 低饱和的履带高光和金属边缘使用一组中性灰，主体统一为橄榄色。
    if ($chroma -lt 18 -and $luma -gt 72) {
        if ($luma -lt 120) { return $palette.MetalDark }
        if ($luma -lt 180) { return $palette.MetalLight }
        return $palette.White
    }

    if ($luma -lt 27)  { return $palette.Outline }
    if ($luma -lt 48)  { return $palette.DeepTrack }
    if ($luma -lt 66)  { return $palette.Track }
    if ($luma -lt 84)  { return $palette.DarkOlive }
    if ($luma -lt 108) { return $palette.Olive }
    if ($luma -lt 139) { return $palette.LightOlive }
    if ($luma -lt 184) { return $palette.Highlight }
    return $palette.White
}

$sourcePath = [System.IO.Path]::GetFullPath($Source)
$outputPath = [System.IO.Path]::GetFullPath($Output)
$sourceBitmap = [System.Drawing.Bitmap]::FromFile($sourcePath)

if ($sourceBitmap.Width -ne 256 -or $sourceBitmap.Height -ne 256) {
    $sourceBitmap.Dispose()
    throw "Expected a 256x256 source sprite sheet, got a different size."
}

$outputBitmap = New-Object System.Drawing.Bitmap 256, 256, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [System.Drawing.Graphics]::FromImage($outputBitmap)
$graphics.Clear([System.Drawing.Color]::Transparent)
$graphics.Dispose()

# 源图由32px逻辑帧做2倍最近邻放大而来。先回到逻辑像素并压缩色阶，
# 再对完全位于轮廓内部的孤立杂色做一次邻域归并，避免小尺寸显示时形成噪点。
$logicalPixels = New-Object 'System.Drawing.Color[,]' 128, 128
for ($logicalY = 0; $logicalY -lt 128; $logicalY++) {
    for ($logicalX = 0; $logicalX -lt 128; $logicalX++) {
        $sample = $sourceBitmap.GetPixel($logicalX * 2, $logicalY * 2)
        $logicalPixels[$logicalX, $logicalY] = Convert-Pixel $sample
    }
}

$smoothedPixels = $logicalPixels.Clone()
for ($logicalY = 1; $logicalY -lt 127; $logicalY++) {
    for ($logicalX = 1; $logicalX -lt 127; $logicalX++) {
        $mapped = $logicalPixels[$logicalX, $logicalY]
        if ($mapped.A -eq 0) { continue }

        # 不跨越每个64px帧的边界，也不触碰轮廓和红色识别标记。
        if (($logicalX % 32) -eq 0 -or ($logicalX % 32) -eq 31 `
                -or ($logicalY % 32) -eq 0 -or ($logicalY % 32) -eq 31) { continue }
        if ($mapped.R -gt 130 -and $mapped.R -gt ($mapped.G * 1.5)) { continue }
        $cardinals = @(
            $logicalPixels[($logicalX - 1), $logicalY],
            $logicalPixels[($logicalX + 1), $logicalY],
            $logicalPixels[$logicalX, ($logicalY - 1)],
            $logicalPixels[$logicalX, ($logicalY + 1)]
        )
        if (($cardinals | Where-Object { $_.A -eq 0 }).Count -gt 0) { continue }

        $counts = @{}
        $colors = @{}
        for ($offsetY = -1; $offsetY -le 1; $offsetY++) {
            for ($offsetX = -1; $offsetX -le 1; $offsetX++) {
                $neighbor = $logicalPixels[($logicalX + $offsetX), ($logicalY + $offsetY)]
                if ($neighbor.A -eq 0) { continue }
                if ($neighbor.R -gt 130 -and $neighbor.R -gt ($neighbor.G * 1.5)) { continue }
                $key = $neighbor.ToArgb()
                $counts[$key] = 1 + ($counts[$key] -as [int])
                $colors[$key] = $neighbor
            }
        }
        $dominant = $counts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
        if ($null -ne $dominant -and $dominant.Value -ge 4) {
            $smoothedPixels[$logicalX, $logicalY] = $colors[$dominant.Key]
        }
    }
}

# 灰色边缘来自旧模型底部的中性阴影，不属于坦克主体。
# 边界上的中性灰直接扣成透明；主体内部偶尔出现的中性灰归并到履带/高光色，
# 确保成品不再残留灰色轮廓，也不会在车体内部挖出透明孔洞。
$cleanPixels = $smoothedPixels.Clone()
$neutralKeys = @(
    $palette.MetalDark.ToArgb(),
    $palette.MetalLight.ToArgb(),
    $palette.White.ToArgb()
)
for ($logicalY = 0; $logicalY -lt 128; $logicalY++) {
    for ($logicalX = 0; $logicalX -lt 128; $logicalX++) {
        $mapped = $smoothedPixels[$logicalX, $logicalY]
        if ($mapped.A -eq 0 -or $neutralKeys -notcontains $mapped.ToArgb()) { continue }

        $touchesTransparency = $false
        for ($offsetY = -1; $offsetY -le 1 -and -not $touchesTransparency; $offsetY++) {
            for ($offsetX = -1; $offsetX -le 1; $offsetX++) {
                if ($offsetX -eq 0 -and $offsetY -eq 0) { continue }
                $neighborX = $logicalX + $offsetX
                $neighborY = $logicalY + $offsetY
                if ($neighborX -lt 0 -or $neighborX -ge 128 `
                        -or $neighborY -lt 0 -or $neighborY -ge 128 `
                        -or $smoothedPixels[$neighborX, $neighborY].A -eq 0) {
                    $touchesTransparency = $true
                    break
                }
            }
        }
        if ($touchesTransparency) {
            $cleanPixels[$logicalX, $logicalY] = [System.Drawing.Color]::Transparent
        } elseif ($mapped.GetBrightness() -lt 0.48) {
            $cleanPixels[$logicalX, $logicalY] = $palette.Track
        } else {
            $cleanPixels[$logicalX, $logicalY] = $palette.Highlight
        }
    }
}

# 仍以2x2硬像素输出：每帧维持64x64，不产生插值或半透明边缘。
for ($logicalY = 0; $logicalY -lt 128; $logicalY++) {
    for ($logicalX = 0; $logicalX -lt 128; $logicalX++) {
        $mapped = $cleanPixels[$logicalX, $logicalY]
        if ($mapped.A -eq 0) { continue }

        $targetX = $logicalX * 2
        $targetY = $logicalY * 2
        $outputBitmap.SetPixel($targetX,     $targetY,     $mapped)
        $outputBitmap.SetPixel($targetX + 1, $targetY,     $mapped)
        $outputBitmap.SetPixel($targetX,     $targetY + 1, $mapped)
        $outputBitmap.SetPixel($targetX + 1, $targetY + 1, $mapped)
    }
}

$sourceBitmap.Dispose()
$outputBitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
$outputBitmap.Dispose()

# Godot实际使用原生32×32单帧版本，再按地图层相同的2×zoom缩放。
# 最终世界尺寸仍与64px版本一致，但像素密度和建筑完全相同。
$output32Path = [System.IO.Path]::GetFullPath($Output32)
$output32Bitmap = New-Object System.Drawing.Bitmap 128, 128, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
for ($logicalY = 0; $logicalY -lt 128; $logicalY++) {
    for ($logicalX = 0; $logicalX -lt 128; $logicalX++) {
        $output32Bitmap.SetPixel($logicalX, $logicalY, $cleanPixels[$logicalX, $logicalY])
    }
}
$output32Bitmap.Save($output32Path, [System.Drawing.Imaging.ImageFormat]::Png)
$output32Bitmap.Dispose()

Write-Output "Saved crisp sprite sheet: $outputPath"
Write-Output "Saved native-resolution sprite sheet: $output32Path"
