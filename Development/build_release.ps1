param([string]$OutputPath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root = Split-Path -Parent $PSScriptRoot
if (-not $OutputPath) { $OutputPath = Join-Path $PSScriptRoot 'release\Gondor_PvP.zip' }
$parent = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$toc = Join-Path $root 'Gondor_PvP.toc'
$files = [System.Collections.Generic.List[string]]::new()
$files.Add($toc)
foreach ($line in Get-Content -LiteralPath $toc) {
    $line = $line.Trim()
    if (-not $line -or $line.StartsWith('#')) { continue }
    $path = Join-Path $root $line
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing TOC file: $line" }
    $files.Add($path)
}
foreach ($name in @('README.md','Libs\Ace-LICENSE.txt','Libs\THIRD_PARTY.md')) {
    $files.Add((Join-Path $root $name))
}
Get-ChildItem -LiteralPath (Join-Path $root 'Media') -Recurse -File | ForEach-Object { $files.Add($_.FullName) }
if ((Get-ChildItem -LiteralPath (Join-Path $root 'Media\Cards') -Filter 'atlas_*.tga' -File).Count -ne 18 -or
    (Get-ChildItem -LiteralPath (Join-Path $root 'Media\Cards') -Filter 'card_*.tga' -File).Count -ne 0) { throw 'Build the 18 card atlases before packaging.' }
$output = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::ReadWrite)
$archive = [System.IO.Compression.ZipArchive]::new($output, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $files | Select-Object -Unique) {
        $relative = $file.Substring($root.Length).TrimStart('\','/').Replace('\','/')
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $file, "Gondor_PvP/$relative", [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally { $archive.Dispose(); $output.Dispose() }
Write-Output "Created $OutputPath with $($files.Count) files."
