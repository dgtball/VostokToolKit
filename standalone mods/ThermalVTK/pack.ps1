param(
    [string]$OutFile = ""
)

$ErrorActionPreference = "Stop"

$src = $PSScriptRoot
if (-not $OutFile) {
    $OutFile = Join-Path $PSScriptRoot "ThermalVTK.vmz"
}

$modTxt = Join-Path $src "mod.txt"
if (Test-Path -LiteralPath $modTxt) {
    $ver = (Select-String -LiteralPath $modTxt -Pattern 'version\s*=\s*"([^"]+)"').Matches.Groups[1].Value
    if ($ver) {
        Write-Host "Version in mod.txt: $ver"
        $verFile = Join-Path $src "mods\ThermalVTK\version.txt"
        [System.IO.File]::WriteAllText($verFile, $ver + "`n", (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "  + mods/ThermalVTK/version.txt ($ver)"
        $readme = Join-Path $PSScriptRoot "README.md"
        if (Test-Path -LiteralPath $readme) {
            $rd = [System.IO.File]::ReadAllText($readme, [System.Text.Encoding]::UTF8)
            $rd2 = [regex]::Replace($rd, '(?m)^(\*\*[^*]+:\*\*\s*)[0-9][0-9a-zA-Z.\-]*', ('${1}' + $ver))
            if ($rd2 -ne $rd) {
                [System.IO.File]::WriteAllText($readme, $rd2, (New-Object System.Text.UTF8Encoding($false)))
                Write-Host "README version synced to $ver"
            }
        }
    }
    else { Write-Warning "mod.txt has no version field" }
} else {
    Write-Warning "mod.txt not found in $src"
}

$entries = @(Get-ChildItem -LiteralPath $src -Recurse -File |
    Where-Object { $_.Name -in @("mod.txt", "version.txt") -or $_.Extension -in @(".gd", ".tres", ".tscn", ".gdshader", ".webp", ".png") } |
    ForEach-Object { $_.FullName.Substring($src.Length).TrimStart([char[]]"\/") -replace "\\", "/" } |
    Sort-Object)

if ($entries.Count -eq 0) {
    throw "Nothing to pack in $src"
}

Add-Type -AssemblyName "System.IO.Compression"
Add-Type -AssemblyName "System.IO.Compression.FileSystem"

$tmpZip = Join-Path ([System.IO.Path]::GetTempPath()) ("thermalvtk_" + [guid]::NewGuid().ToString("N") + ".vmz")
$stream = [System.IO.File]::Create($tmpZip)
$zip = New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($en in $entries) {
        $srcPath = Join-Path $src ($en -replace "/", "\")
        Write-Host "  + $en"
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $srcPath, $en, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
}
finally {
    $zip.Dispose()
    $stream.Dispose()
}

if (Test-Path -LiteralPath $OutFile) {
    Remove-Item -LiteralPath $OutFile -Force
}
Move-Item -LiteralPath $tmpZip -Destination $OutFile -Force

$sizeKb = [math]::Round((Get-Item -LiteralPath $OutFile).Length / 1KB, 1)
Write-Host ""
Write-Host "Pack done: $OutFile ($($entries.Count) entries, $sizeKb KB)"
