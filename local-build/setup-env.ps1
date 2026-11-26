<#
.SYNOPSIS
    Prepara o ambiente local nativo no Windows para compilar o firmware ZMK (v0.3 / Zephyr 3.5).

.DESCRIPTION
    Prepara o ambiente portatil sem necessidade de Docker, WSL ou privilegios de administrador:
      - Toolchain em ..\zmk-workspace (.venv Python 3.12, Zephyr SDK 0.16.8 ARM, protoc 28.3)
      - Repositorio do firmware ZMK (fork TergoTeclados/zmk @ tergo-v0.3) em ..\zmk
      - Workspace West (west init -l app + west update --filter=tree:0) dentro de ..\zmk

.PARAMETER WorkspacePath
    Caminho da pasta onde a toolchain (.venv e tools) sera instalada.
    Padrao: ..\zmk-workspace (ao lado de zmk-config-tergo-sofle).

.PARAMETER ZmkPath
    Caminho da pasta do repositorio Git do ZMK (que tambem atua como workspace West).
    Padrao: ..\zmk (ao lado de zmk-config-tergo-sofle).

.PARAMETER ZmkRepoUrl
    URL do repositorio Git do ZMK a ser clonado. Padrao: https://github.com/TergoTeclados/zmk.git

.PARAMETER ZmkRevision
    Branch ou tag inicial do ZMK. Padrao: tergo-v0.3
#>
[CmdletBinding()]
param(
    [string]$WorkspacePath = "",
    [string]$ZmkPath = "",
    [string]$ZmkRepoUrl = "https://github.com/TergoTeclados/zmk.git",
    [string]$ZmkRevision = "tergo-v0.3"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$parentDir = Split-Path $repoRoot -Parent
if ([string]::IsNullOrWhiteSpace($WorkspacePath)) {
    $WorkspacePath = Join-Path $parentDir "zmk-workspace"
}
if ([string]::IsNullOrWhiteSpace($ZmkPath)) {
    $ZmkPath = Join-Path $parentDir "zmk"
}

$toolsDir  = Join-Path $WorkspacePath "tools"
$venvDir   = Join-Path $WorkspacePath ".venv"
$sdkDir    = Join-Path $toolsDir "zephyr-sdk-0.16.8"
$protocDir = Join-Path $toolsDir "protoc"
$zmkDir    = $ZmkPath

# Verificacao de pre-requisitos
foreach ($cmd in @("git", "uv", "tar")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "Pre-requisito nao encontrado no PATH: '$cmd'. Instale-o antes de continuar."
    }
}

Write-Host "=== Configurando ZMK Workspace em: $WorkspacePath ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null

# 1. Virtualenv Python 3.12
$venvPython = Join-Path $venvDir "Scripts\python.exe"
if (-not (Test-Path $venvPython)) {
    Write-Host "`n[1/6] Criando ambiente virtual Python 3.12 com uv..." -ForegroundColor Yellow
    uv venv --python 3.12 $venvDir
    if ($LASTEXITCODE -ne 0) { throw "Falha ao criar virtualenv Python 3.12." }
} else {
    Write-Host "`n[1/6] Virtualenv Python 3.12 ja existe." -ForegroundColor Green
}

Write-Host "[2/6] Instalando ferramentas base Python (west, cmake<4, ninja, protobuf, setuptools<81)..." -ForegroundColor Yellow
uv pip install --python $venvPython `
    west `
    "cmake<4" `
    ninja `
    "setuptools<81" `
    "protobuf>=4.25,<6" `
    "grpcio-tools<1.72"
if ($LASTEXITCODE -ne 0) { throw "Falha ao instalar pacotes Python base." }

# 2. Zephyr SDK 0.16.8 minimal + arm-zephyr-eabi
$armGcc = Join-Path $sdkDir "arm-zephyr-eabi\bin\arm-zephyr-eabi-gcc.exe"
if (-not (Test-Path $armGcc)) {
    Write-Host "`n[3/6] Baixando Zephyr SDK 0.16.8 (minimal + arm-zephyr-eabi)..." -ForegroundColor Yellow
    $sdkArchive = Join-Path $toolsDir "zephyr-sdk-minimal.7z"
    $armArchive = Join-Path $toolsDir "arm-zephyr-eabi.7z"

    Invoke-WebRequest -Uri "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.16.8/zephyr-sdk-0.16.8_windows-x86_64_minimal.7z" -OutFile $sdkArchive
    Invoke-WebRequest -Uri "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.16.8/toolchain_windows-x86_64_arm-zephyr-eabi.7z" -OutFile $armArchive

    tar -xf $sdkArchive -C $toolsDir
    tar -xf $armArchive -C $sdkDir
    Remove-Item $sdkArchive, $armArchive -Force
} else {
    Write-Host "`n[3/6] Zephyr SDK 0.16.8 (arm-zephyr-eabi) ja instalado." -ForegroundColor Green
}

# 3. protoc 28.3
$protocExe = Join-Path $protocDir "bin\protoc.exe"
if (-not (Test-Path $protocExe)) {
    Write-Host "`n[4/6] Baixando protoc 28.3 (necessario para ZMK Studio / nanopb)..." -ForegroundColor Yellow
    $protocArchive = Join-Path $toolsDir "protoc.zip"
    Invoke-WebRequest -Uri "https://github.com/protocolbuffers/protobuf/releases/download/v28.3/protoc-28.3-win64.zip" -OutFile $protocArchive
    New-Item -ItemType Directory -Force -Path $protocDir | Out-Null
    tar -xf $protocArchive -C $protocDir
    Remove-Item $protocArchive -Force
} else {
    Write-Host "`n[4/6] protoc 28.3 ja instalado." -ForegroundColor Green
}

# Adiciona ferramentas ao PATH da sessao atual
$env:PATH = "$(Join-Path $venvDir 'Scripts');$(Join-Path $protocDir 'bin');$env:PATH"

# 4. Clonar ZMK e inicializar workspace West
if (-not (Test-Path (Join-Path $zmkDir ".git"))) {
    Write-Host "`n[5/6] Clonando ZMK ($ZmkRepoUrl @ $ZmkRevision)..." -ForegroundColor Yellow
    git clone --branch $ZmkRevision $ZmkRepoUrl $zmkDir
    if ($LASTEXITCODE -ne 0) { throw "Falha ao clonar repositorio ZMK." }
} else {
    Write-Host "`n[5/6] Repositorio ZMK ja clonado em $zmkDir." -ForegroundColor Green
}

Push-Location $zmkDir
try {
    if (-not (Test-Path (Join-Path $zmkDir ".west"))) {
        Write-Host "      Executando 'west init -l app'..." -ForegroundColor Yellow
        west init -l app
        if ($LASTEXITCODE -ne 0) { throw "Falha no west init." }
    }

    Write-Host "      Executando 'west update --fetch-opt=--filter=tree:0'..." -ForegroundColor Yellow
    west update --fetch-opt=--filter=tree:0
    if ($LASTEXITCODE -ne 0) { throw "Falha no west update." }

    Write-Host "`n[6/6] Exportando pacotes CMake e instalando dependencias Python do Zephyr..." -ForegroundColor Yellow
    west zephyr-export
    if ($LASTEXITCODE -ne 0) { throw "Falha no west zephyr-export." }

    uv pip install --python $venvPython -r (Join-Path $zmkDir "zephyr\scripts\requirements-base.txt")
    if ($LASTEXITCODE -ne 0) { throw "Falha ao instalar requirements-base.txt do Zephyr." }

    # Registra Zephyr SDK no registro de pacotes CMake do usuario (sem depender de wget/setup.cmd)
    cmake -P (Join-Path $sdkDir "cmake\zephyr_sdk_export.cmake")
    if ($LASTEXITCODE -ne 0) { throw "Falha ao registrar Zephyr SDK no CMake." }
} finally {
    Pop-Location
}

Write-Host "`n=== Ambiente ZMK pronto! ===" -ForegroundColor Green
Write-Host "Para listar os alvos do build.yaml:"
Write-Host "  .\local-build\build-local.ps1 -List" -ForegroundColor Cyan
Write-Host "Para compilar um alvo:"
Write-Host "  .\local-build\build-local.ps1 -Target sofle_receptor_ABNT2_displayV2" -ForegroundColor Cyan
