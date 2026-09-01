param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

Add-Type -AssemblyName System.Drawing

$sourcePath = Join-Path $ProjectRoot 'assets\units\animated\wp_light_tank_target_4dir_4f.png'
$attackDir = Join-Path $ProjectRoot 'assets\units\animated'
$effectDir = Join-Path $ProjectRoot 'assets\effects'
$attackPath = Join-Path $attackDir 'wp_light_tank_attack_4dir_4f.png'
$flashPath = Join-Path $effectDir 'tank_muzzle_flash_4f.png'

New-Item -ItemType Directory -Force -Path $attackDir, $effectDir | Out-Null

$source = [System.Drawing.Bitmap]::FromFile($sourcePath)
$attack = New-Object System.Drawing.Bitmap 128, 128, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$attack.SetResolution(96, 96)
$graphics = [System.Drawing.Graphics]::FromImage($attack)
$graphics.Clear([System.Drawing.Color]::Transparent)
$graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half

# 四行依次为右下、左下、左上、右上。四帧：预备、后坐、最大后坐、复位。
$recoil = @(
    @(@(0,0), @(-1,-1), @(-1,-1), @(0,0)),
    @(@(0,0), @(1,-1),  @(1,-1),  @(0,0)),
    @(@(0,0), @(1,1),   @(1,1),   @(0,0)),
    @(@(0,0), @(-1,1),  @(-1,1),  @(0,0))
)

for ($row = 0; $row -lt 4; $row++) {
    $sourceRect = New-Object System.Drawing.Rectangle 0, ($row * 32), 32, 32
    for ($frame = 0; $frame -lt 4; $frame++) {
        $dx = [int]$recoil[$row][$frame][0]
        $dy = [int]$recoil[$row][$frame][1]
        $destRect = New-Object System.Drawing.Rectangle (($frame * 32) + $dx), (($row * 32) + $dy), 32, 32
        $graphics.DrawImage($source, $destRect, $sourceRect, [System.Drawing.GraphicsUnit]::Pixel)
    }
}

$graphics.Dispose()
$source.Dispose()
$attack.Save($attackPath, [System.Drawing.Imaging.ImageFormat]::Png)
$attack.Dispose()

function Set-PixelBlock {
    param($Bitmap, [int]$X, [int]$Y, [int]$W, [int]$H, [System.Drawing.Color]$Color)
    for ($py = $Y; $py -lt ($Y + $H); $py++) {
        for ($px = $X; $px -lt ($X + $W); $px++) {
            if ($px -ge 0 -and $px -lt $Bitmap.Width -and $py -ge 0 -and $py -lt $Bitmap.Height) {
                $Bitmap.SetPixel($px, $py, $Color)
            }
        }
    }
}

$flash = New-Object System.Drawing.Bitmap 128, 32, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$transparent = [System.Drawing.Color]::Transparent
$white = [System.Drawing.Color]::FromArgb(255, 255, 250, 211)
$yellow = [System.Drawing.Color]::FromArgb(255, 255, 220, 67)
$orange = [System.Drawing.Color]::FromArgb(255, 240, 128, 28)
$red = [System.Drawing.Color]::FromArgb(255, 185, 62, 24)
$smoke = [System.Drawing.Color]::FromArgb(210, 105, 105, 92)
$darkSmoke = [System.Drawing.Color]::FromArgb(150, 62, 64, 58)

# 每帧的炮口基准点为(16,16)，特效朝右；运行时按单位朝向旋转。
# 第1帧：点火。
Set-PixelBlock $flash 16 15 4 3 $yellow
Set-PixelBlock $flash 20 16 3 1 $orange
Set-PixelBlock $flash 17 13 1 7 $white

# 第2帧：最大火光。
$o = 32
Set-PixelBlock $flash ($o+14) 14 12 5 $orange
Set-PixelBlock $flash ($o+16) 12 6 9 $yellow
Set-PixelBlock $flash ($o+18) 14 7 5 $white
Set-PixelBlock $flash ($o+25) 15 4 3 $red
Set-PixelBlock $flash ($o+13) 15 2 3 $white

# 第3帧：拉长火焰和烟尘。
$o = 64
Set-PixelBlock $flash ($o+15) 15 8 3 $yellow
Set-PixelBlock $flash ($o+21) 14 7 5 $orange
Set-PixelBlock $flash ($o+27) 15 3 3 $red
Set-PixelBlock $flash ($o+18) 12 3 2 $smoke
Set-PixelBlock $flash ($o+24) 10 4 3 $darkSmoke
Set-PixelBlock $flash ($o+27) 20 3 2 $smoke

# 第4帧：残留火星和消散烟雾。
$o = 96
Set-PixelBlock $flash ($o+17) 15 3 2 $orange
Set-PixelBlock $flash ($o+22) 12 2 2 $yellow
Set-PixelBlock $flash ($o+27) 18 2 2 $red
Set-PixelBlock $flash ($o+19) 10 4 3 $smoke
Set-PixelBlock $flash ($o+25) 8 5 4 $darkSmoke
Set-PixelBlock $flash ($o+29) 13 2 3 $smoke

$flash.Save($flashPath, [System.Drawing.Imaging.ImageFormat]::Png)
$flash.Dispose()

Write-Output "Generated: $attackPath"
Write-Output "Generated: $flashPath"
