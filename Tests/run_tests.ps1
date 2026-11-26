param(
    [string]$PluginPath = 'C:\ProgramData\aviutl2\Plugin\SYNC_TravelTrain\SYNC_TravelTrain.auf2',
    [string]$ImageDirectory
)

$ErrorActionPreference = 'Stop'
$PluginPath = (Resolve-Path -LiteralPath $PluginPath).Path
$output = Join-Path (Split-Path -Parent $PSScriptRoot) 'Win64\Verification'
$dcu = Join-Path $output 'DCU'
$studio = 'C:\Program Files (x86)\Embarcadero\Studio\37.0'
$compiler = Join-Path $studio 'bin\dcc64.exe'
$lib = Join-Path $studio 'lib\Win64\release'
New-Item -ItemType Directory -Path $dcu -Force | Out-Null
$arguments = @($PluginPath)
if ($ImageDirectory) { $arguments += [IO.Path]::GetFullPath($ImageDirectory) }

Push-Location $PSScriptRoot
try {
    $compile = @('--no-config', '-B', '-Q', '-TX.exe', '-$R+', '-$Q+', '-NSSystem;Winapi',
        "-U$lib;$lib\JA", "-E$output", "-NU$dcu", 'TravelTrain_RenderTests.dpr')
    & $compiler @compile
    if ($LASTEXITCODE -ne 0) { throw 'TravelTrain verification build failed.' }
    & (Join-Path $output 'TravelTrain_RenderTests.exe') @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Production AUF2 verification failed.' }
}
finally { Pop-Location }
