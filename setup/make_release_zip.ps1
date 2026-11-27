param(
    [string]$ReleaseDirectory,
    [string]$XxhsumPath
)

# Copyright (c) 2026 VRAMの魔術師 / SPDX-License-Identifier: GPL-3.0-only
# 配布本体と利用者向け資料を専用フォルダーへまとめ、同梱する AUF2 のハッシュをカタログへ記録する。
$ErrorActionPreference = 'Stop'
$packageName = 'SYNC_TravelTrain'
$projectDir = Split-Path -Parent $PSScriptRoot
if (-not $ReleaseDirectory) { $ReleaseDirectory = Join-Path $env:ProgramData "aviutl2\Plugin\$packageName" }
$pluginName = "$packageName.auf2"
$pluginPath = Join-Path $ReleaseDirectory $pluginName
if (-not (Test-Path -LiteralPath $pluginPath -PathType Leaf)) {
    throw "Release plugin not found: $pluginPath"
}

if (-not $XxhsumPath) {
    $XxhsumPath = Join-Path $projectDir 'Win64\Dependencies\xxHash-0.8.4\xxhsum.exe'
    if (-not (Test-Path -LiteralPath $XxhsumPath -PathType Leaf)) {
        $xxhsum = Get-Command xxhsum.exe -CommandType Application -ErrorAction SilentlyContinue
        if (-not $xxhsum) { throw 'xxhsum.exe is required. See setup\README.md.' }
        $XxhsumPath = $xxhsum.Source
    }
}
$XxhsumPath = (Resolve-Path -LiteralPath $XxhsumPath).ProviderPath

$catalogPath = Join-Path $PSScriptRoot "$packageName.catalog.json"
$zipPath = Join-Path $PSScriptRoot "$packageName.zip"
$tempBase = Join-Path $PSScriptRoot ('.release-' + [guid]::NewGuid().ToString('N'))
$tempPlugin = "$tempBase-plugin.tmp"
$tempZip = "$tempBase-zip.tmp"
$tempCatalog = "$tempBase-catalog.tmp"
$catalogBackup = "$tempBase-previous-catalog.tmp"

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$mutex = [Threading.Mutex]::new($false, 'Local\VRAMWIZ.SYNC_TravelTrain.ReleaseZip')
$ownsLock = $false
try {
    try { $ownsLock = $mutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $ownsLock = $true }
    if (-not $ownsLock) { throw 'Another release ZIP is being created.' }

    $catalogSource = [IO.File]::ReadAllText($catalogPath)
    $catalog = [object[]]($catalogSource | ConvertFrom-Json)
    if ($catalogSource -notmatch '^\s*\[' -or $catalog.Count -ne 1 -or
        $catalog[0].id -cne "VRAMWIZ.$packageName" -or ([string]$catalog[0].summary).Length -gt 35) {
        throw 'Invalid TravelTrain catalog entry.'
    }
    $entry = $catalog[0]
    $github = $entry.installer.source.github
    if ($github.owner -cne 'vramwiz' -or $github.repo -cne $packageName -or
        $github.pattern -cne ('^' + [regex]::Escape("$packageName.zip") + '$')) {
        throw 'The catalog GitHub source must match this repository and ZIP name.'
    }

    $install = @($entry.installer.install)
    $uninstall = @($entry.installer.uninstall)
    if ($install.Count -ne 3 -or $install[0].action -cne 'download' -or $install[1].action -cne 'extract' -or
        $install[2].action -cne 'copy' -or $install[2].from -cne "{tmp}/$packageName" -or
        $install[2].to -cne "{pluginsDir}/$packageName" -or $uninstall.Count -ne 1 -or
        $uninstall[0].action -cne 'delete' -or $uninstall[0].path -cne "{pluginsDir}/$packageName/") {
        throw 'The catalog must install and uninstall only the TravelTrain folder.'
    }
    if (@($entry.version).Count -eq 0 -or $entry.version[0].version -cne 'v1.0.0') {
        throw 'The release history must start at v1.0.0.'
    }
    $version = $entry.version[-1]
    $releaseDate = [datetime]::MinValue
    if ($version.version -cnotmatch '^v\d+\.\d+\.\d+$' -or
        @($entry.version | Where-Object version -ceq $version.version).Count -ne 1 -or
        -not [datetime]::TryParseExact($version.release_date, 'yyyy-MM-dd',
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None, [ref]$releaseDate)) {
        throw 'The last catalog version must have a unique tag and a valid release date.'
    }
    $files = @($version.file)
    if ($files.Count -ne 1 -or $files[0].path -cne "{pluginsDir}/$packageName/$pluginName" -or
        -not $files[0].PSObject.Properties['XXH3_128']) {
        throw 'The last catalog version must list the AUF2 and its XXH3_128 field.'
    }

    # ZIP とハッシュは同じコピーを参照し、元の AUF2 が差し替わった場合も内容を揃える。
    Copy-Item -LiteralPath $pluginPath -Destination $tempPlugin
    $hashOutput = & $XxhsumPath -H128 --tag $tempPlugin
    if ($LASTEXITCODE -ne 0 -or ($hashOutput -join "`n") -notmatch ' = ([0-9a-f]{32})\s*\z') {
        throw 'Could not calculate the AUF2 XXH3-128 hash.'
    }
    $hash = $Matches[1].ToLowerInvariant()
    $packageFiles = [ordered]@{
        $pluginName = $tempPlugin
        'README.md' = Join-Path $projectDir 'README.md'
        'LICENSE' = Join-Path $projectDir 'LICENSE'
        'LICENSES.md' = Join-Path $projectDir 'LICENSES.md'
        'docs/preview.png' = Join-Path $projectDir 'docs\preview.png'
    }
    $zip = [IO.Compression.ZipFile]::Open($tempZip, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in $packageFiles.GetEnumerator()) {
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $file.Value, "$packageName/$($file.Key)", [IO.Compression.CompressionLevel]::Optimal
            ) | Out-Null
        }
    }
    finally { $zip.Dispose() }

    if ([IO.File]::ReadAllText($catalogPath) -cne $catalogSource) {
        throw 'Catalog changed during packaging. Run the batch again.'
    }
    if ($files[0].XXH3_128 -cne $hash) {
        $files[0].XXH3_128 = $hash
        $json = ConvertTo-Json -InputObject $catalog -Depth 12
        [IO.File]::WriteAllText($tempCatalog, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
        [IO.File]::Replace($tempCatalog, $catalogPath, $catalogBackup)
    }
    # ZIP の差し替えに失敗した場合は元のカタログに戻す。
    try {
        if ([IO.File]::Exists($zipPath)) { [IO.File]::Replace($tempZip, $zipPath, [NullString]::Value) }
        else { [IO.File]::Move($tempZip, $zipPath) }
    }
    catch {
        if ([IO.File]::Exists($catalogBackup)) {
            [IO.File]::Replace($catalogBackup, $catalogPath, [NullString]::Value)
        }
        throw
    }
    if ([IO.File]::Exists($catalogBackup)) { [IO.File]::Delete($catalogBackup) }
}
finally {
    if ($ownsLock) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
    foreach ($tempPath in @($tempPlugin, $tempZip, $tempCatalog)) { [IO.File]::Delete($tempPath) }
}

Write-Output "Created $zipPath"
Write-Output "Catalog $catalogPath ($($version.version), XXH3_128=$hash)"
