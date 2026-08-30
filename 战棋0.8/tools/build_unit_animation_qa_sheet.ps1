param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Add-Type -AssemblyName System.Drawing
$config=Get-Content -LiteralPath (Join-Path $ProjectRoot 'data\units\unit_animation_config.json') -Raw | ConvertFrom-Json
$output=Join-Path $ProjectRoot 'art\qa\unit_animation_four_direction_qa.png'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $output) | Out-Null
$sheet=New-Object Drawing.Bitmap 1000,750,([Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g=[Drawing.Graphics]::FromImage($sheet);$g.Clear([Drawing.Color]::FromArgb(255,42,44,46));$g.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::NearestNeighbor;$g.PixelOffsetMode=[Drawing.Drawing2D.PixelOffsetMode]::Half
$font=[Drawing.Font]::new('Consolas',[single]10,[Drawing.FontStyle]::Regular,[Drawing.GraphicsUnit]::Point)
$brush=New-Object Drawing.SolidBrush ([Drawing.Color]::White)
$pen=New-Object Drawing.Pen ([Drawing.Color]::FromArgb(255,88,92,96)),1
$index=0
foreach($property in $config.units.psobject.Properties){
    $col=$index%5;$row=[int][Math]::Floor($index/5);$left=$col*200;$top=$row*150
    $g.DrawRectangle($pen,$left,$top,199,149);$g.DrawString($property.Name,$font,$brush,$left+5,$top+5)
    $path=Join-Path $ProjectRoot ($property.Value.move_path -replace '^res://','' -replace '/','\')
    $bitmap=[Drawing.Bitmap]::FromFile($path)
    for($direction=0;$direction-lt4;$direction++){
        $source=New-Object Drawing.Rectangle 0,($direction*32),32,32
        $dx=$left+8+($direction%2)*84;$dy=$top+25+[int][Math]::Floor($direction/2)*58
        $dest=New-Object Drawing.Rectangle $dx,$dy,64,64
        $g.DrawImage($bitmap,$dest,$source,[Drawing.GraphicsUnit]::Pixel)
    }
    $bitmap.Dispose();$index++
}
$g.Dispose();$font.Dispose();$brush.Dispose();$pen.Dispose();$sheet.Save($output,[Drawing.Imaging.ImageFormat]::Png);$sheet.Dispose()
Write-Output $output
