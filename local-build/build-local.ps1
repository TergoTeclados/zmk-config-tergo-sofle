<#
.SYNOPSIS
    Compila localmente um ou mais alvos definidos em build.yaml usando o zmk-workspace.

.DESCRIPTION
    Le o arquivo build.yaml da raiz do repositorio zmk-config-tergo-sofle, executa 'west build'
    para cada alvo selecionado e copia os arquivos .uf2 gerados para .\build-artifacts\<artifact-name>.uf2.

.EXAMPLE
    .\local-build\build-local.ps1 -List

.EXAMPLE
    .\local-build\build-local.ps1 -Target sofle_receptor_ABNT2_displayV2

.EXAMPLE
    .\local-build\build-local.ps1 -Target sofle_receptor_ABNT2_displayV2,sofle_esquerdo -Pristine

.EXAMPLE
    .\local-build\build-local.ps1 -All
#>
[CmdletBinding()]
param(
    [string[]]$Target = @(),
    [switch]$All,
    [switch]$List,
    [switch]$Pristine,
    [switch]$UsbLogging,
    [string]$WorkspacePath = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($WorkspacePath)) {
    $WorkspacePath = Join-Path (Split-Path $repoRoot -Parent) "zmk-workspace"
}

$venvScripts = Join-Path $WorkspacePath ".venv\Scripts"
$venvPython  = Join-Path $venvScripts "python.exe"
$sdkDir      = Join-Path $WorkspacePath "tools\zephyr-sdk-0.16.8"
$protocExe   = Join-Path $WorkspacePath "tools\protoc\bin\protoc.exe"
$zmkDir      = Join-Path $WorkspacePath "zmk"
$buildYaml   = Join-Path $repoRoot "build.yaml"
$outDir      = Join-Path $repoRoot "build-artifacts"

if (-not (Test-Path $venvPython) -or -not (Test-Path $zmkDir)) {
    throw "Workspace nao encontrado em '$WorkspacePath'. Execute '.\local-build\setup-env.ps1' primeiro."
}

# Usa Python + PyYAML do venv para ler build.yaml e dividir cmake-args com shlex
$pyParse = @"
import json, shlex, sys, yaml
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)
entries = []
for item in data.get('include', []):
    board = item.get('board', '')
    shield = item.get('shield', '')
    snippet = item.get('snippet', '')
    artifact = item.get('artifact-name') or (f'{shield}-{board}-zmk' if shield else f'{board}-zmk')
    cmake_raw = item.get('cmake-args', '') or ''
    entries.append({
        'artifact': artifact,
        'board': board,
        'shield': shield,
        'snippet': snippet,
        'cmake_args': shlex.split(cmake_raw)
    })
print(json.dumps(entries))
"@

$targetsJson = & $venvPython -c $pyParse $buildYaml
if ($LASTEXITCODE -ne 0) { throw "Falha ao ler $buildYaml." }
$allTargets = $targetsJson | ConvertFrom-Json

if ($List -or (-not $All -and $Target.Count -eq 0)) {
    Write-Host "Alvos disponiveis em build.yaml:`n" -ForegroundColor Cyan
    $allTargets | Select-Object `
        @{n='Target (artifact-name)'; e={$_.artifact}},
        @{n='Board'; e={$_.board}},
        @{n='Shield(s)'; e={$_.shield}},
        @{n='Snippet'; e={$_.snippet}} | Format-Table -AutoSize
    if (-not $List) {
        Write-Host "Use -Target <nome> ou -All para compilar. Exemplo:" -ForegroundColor Yellow
        Write-Host "  .\local-build\build-local.ps1 -Target sofle_receptor_ABNT2_displayV2"
    }
    exit 0
}

$selected = if ($All) {
    $allTargets
} else {
    $matched = @()
    foreach ($t in $Target) {
        $found = $allTargets | Where-Object { $_.artifact -eq $t }
        if (-not $found) {
            $valid = ($allTargets | ForEach-Object { $_.artifact }) -join ", "
            throw "Alvo '$t' nao encontrado em build.yaml. Alvos validos: $valid"
        }
        $matched += $found
    }
    $matched
}

# Configura ambiente da sessao
$env:PATH = "$venvScripts;$(Split-Path $protocExe -Parent);$env:PATH"
$env:ZEPHYR_TOOLCHAIN_VARIANT = "zephyr"
$env:ZEPHYR_SDK_INSTALL_DIR = $sdkDir

$cfgRepoCmake = $repoRoot -replace '\\', '/'
$protocCmake  = $protocExe -replace '\\', '/'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$results = @()

Push-Location $zmkDir
try {
    foreach ($entry in $selected) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $buildDirName = if ($UsbLogging) { "$($entry.artifact)_logging" } else { $entry.artifact }
        $buildDirRel  = "build/$buildDirName"
        $buildDirAbs  = Join-Path $zmkDir $buildDirRel
        $isFirstBuild = -not (Test-Path (Join-Path $buildDirAbs "build.ninja"))

        Write-Host "`n================================================================" -ForegroundColor Cyan
        Write-Host " Compilando: $($entry.artifact)" -ForegroundColor Cyan
        Write-Host " Board: $($entry.board) | Shield: $($entry.shield)" -ForegroundColor DarkCyan
        Write-Host " Modo: $(if ($Pristine -or $isFirstBuild) { 'Pristine / Configuracao completa' } else { 'Incremental (rapido)' })" -ForegroundColor DarkCyan
        Write-Host "================================================================`n" -ForegroundColor Cyan

        $westArgs = @("build", "-s", "app", "-d", $buildDirRel)

        if ($Pristine -or $isFirstBuild) {
            if ($Pristine) { $westArgs += "-p" }
            $westArgs += @("-b", $entry.board)

            if (-not [string]::IsNullOrWhiteSpace($entry.snippet)) {
                foreach ($sn in ($entry.snippet -split '\s+')) {
                    if ($sn) { $westArgs += @("-S", $sn) }
                }
            }
            if ($UsbLogging) {
                $westArgs += @("-S", "zmk-usb-logging")
            }

            $westArgs += "--"
            $westArgs += "-DZMK_CONFIG=$cfgRepoCmake/config"
            $westArgs += "-DZMK_EXTRA_MODULES=$cfgRepoCmake"
            $westArgs += "-DPROTOBUF_PROTOC_EXECUTABLE=$protocCmake"

            if (-not [string]::IsNullOrWhiteSpace($entry.shield)) {
                $westArgs += "-DSHIELD=$($entry.shield)"
            }
            foreach ($ca in $entry.cmake_args) {
                $westArgs += $ca
            }
        }

        & west @westArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Falha na compilacao do alvo '$($entry.artifact)' (codigo $LASTEXITCODE)."
        }

        $uf2Src = Join-Path $buildDirAbs "zephyr\zmk.uf2"
        $outName = if ($UsbLogging) { "$($entry.artifact)_logging.uf2" } else { "$($entry.artifact).uf2" }
        $uf2Dst = Join-Path $outDir $outName

        if (Test-Path $uf2Src) {
            Copy-Item $uf2Src $uf2Dst -Force
        } else {
            throw "Arquivo zmk.uf2 nao encontrado em $uf2Src."
        }

        $sw.Stop()
        $sizeKB = [math]::Round((Get-Item $uf2Dst).Length / 1KB, 1)
        $results += [PSCustomObject]@{
            Target   = $entry.artifact
            Arquivo  = $outName
            TamanhoKB = $sizeKB
            TempoSeg = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        }
    }
} finally {
    Pop-Location
}

Write-Host "`n=== Compilacao concluida! Artefatos salvos em: $outDir ===" -ForegroundColor Green
$results | Format-Table -AutoSize
