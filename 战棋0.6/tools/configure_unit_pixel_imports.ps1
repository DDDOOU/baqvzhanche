param([string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot))

$directories=@(
    (Join-Path $ProjectRoot 'assets\units\animated\all_units_v2'),
    (Join-Path $ProjectRoot 'assets\effects\unit_attacks_v2')
)

$updated=0
foreach($directory in $directories){
    foreach($importFile in Get-ChildItem -LiteralPath $directory -Filter '*.png.import' -File -ErrorAction SilentlyContinue){
        $content=Get-Content -LiteralPath $importFile.FullName -Raw
        $newContent=$content -replace 'mipmaps/generate=true','mipmaps/generate=false'
        $newContent=$newContent -replace 'process/fix_alpha_border=true','process/fix_alpha_border=false'
        if($newContent-ne$content){Set-Content -LiteralPath $importFile.FullName -Value $newContent -Encoding UTF8 -NoNewline;$updated++}
    }
}
Write-Output "Updated $updated pixel-art import files."
