param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

Add-Type -AssemblyName System.Drawing
$assetDir = Join-Path $ProjectRoot 'assets\units\animated\all_units_v2'

function Test-LightNeutral([Drawing.Color]$color) {
    $max=[Math]::Max($color.R,[Math]::Max($color.G,$color.B))
    $min=[Math]::Min($color.R,[Math]::Min($color.G,$color.B))
    return $color.A -gt 0 -and ($max-$min) -le 20 -and (($color.R+$color.G+$color.B)/3.0) -ge 205
}

foreach($file in Get-ChildItem -LiteralPath $assetDir -Filter '*.png' -File) {
    $source=[Drawing.Bitmap]::FromFile($file.FullName)
    $bitmap=New-Object Drawing.Bitmap $source.Width,$source.Height,([Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics=[Drawing.Graphics]::FromImage($bitmap);$graphics.DrawImageUnscaled($source,0,0);$graphics.Dispose();$source.Dispose()
    for($cellY=0;$cellY -lt 4;$cellY++) {
        for($cellX=0;$cellX -lt 4;$cellX++) {
            $visited=New-Object 'bool[,]' 32,32
            for($startY=0;$startY -lt 32;$startY++) {
                for($startX=0;$startX -lt 32;$startX++) {
                    if($visited[$startX,$startY] -or -not (Test-LightNeutral $bitmap.GetPixel($cellX*32+$startX,$cellY*32+$startY))){continue}
                    $queue=New-Object 'System.Collections.Generic.Queue[int]';$component=New-Object 'System.Collections.Generic.List[int]'
                    $queue.Enqueue($startY*32+$startX);$visited[$startX,$startY]=$true;$touchesBorder=$false
                    while($queue.Count -gt 0){
                        $value=$queue.Dequeue();$x=$value%32;$y=[int][Math]::Floor($value/32);$component.Add($value)
                        if($x-eq 0-or$y-eq 0-or$x-eq 31-or$y-eq 31){$touchesBorder=$true}
                        $neighbors = @(
                            @(($x - 1), $y), @(($x + 1), $y),
                            @($x, ($y - 1)), @($x, ($y + 1))
                        )
                        foreach($pair in $neighbors){
                            $nx=[int]$pair[0];$ny=[int]$pair[1]
                            if($nx-ge 0-and$ny-ge 0-and$nx-lt 32-and$ny-lt 32-and-not $visited[$nx,$ny]-and(Test-LightNeutral $bitmap.GetPixel($cellX*32+$nx,$cellY*32+$ny))){$visited[$nx,$ny]=$true;$queue.Enqueue($ny*32+$nx)}
                        }
                    }
                    if($touchesBorder -or $component.Count -ge 16){foreach($value in $component){$x=$value%32;$y=[int][Math]::Floor($value/32);$bitmap.SetPixel($cellX*32+$x,$cellY*32+$y,[Drawing.Color]::Transparent)}}
                }
            }
        }
    }
    # AH-64母版的背向高光在32px下会形成白块，将大块中性高光压回军用橄榄灰。
    if($file.Name -like 'ah64_helicopter_*') {
        for($y=0;$y -lt $bitmap.Height;$y++){for($x=0;$x -lt $bitmap.Width;$x++){
            $c=$bitmap.GetPixel($x,$y);$max=[Math]::Max($c.R,[Math]::Max($c.G,$c.B));$min=[Math]::Min($c.R,[Math]::Min($c.G,$c.B))
            if($c.A-gt 0-and($max-$min)-le 12-and(($c.R+$c.G+$c.B)/3.0)-ge 120){$level=[Math]::Min(128,[int](($c.R+$c.G+$c.B)/3.0));$bitmap.SetPixel($x,$y,[Drawing.Color]::FromArgb(255,$level,[int]($level*0.92),[int]($level*0.58)))}
        }}
    }
    # 北约前线母版行距较紧，机械化步兵单元格顶部混入了下一行直升机旋翼。
    if($file.Name -like 'mech_infantry_*') {
        for($cellY=0;$cellY -lt 4;$cellY++){for($cellX=0;$cellX -lt 4;$cellX++){
            for($localY=0;$localY -lt 8;$localY++){for($localX=0;$localX -lt 32;$localX++){
                $bitmap.SetPixel($cellX*32+$localX,$cellY*32+$localY,[Drawing.Color]::Transparent)
            }}
        }}
    }
    $bitmap.Save($file.FullName,[Drawing.Imaging.ImageFormat]::Png);$bitmap.Dispose()
}
Write-Output 'Cleaned generated 128x128 unit atlases.'
