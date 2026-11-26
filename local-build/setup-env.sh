#!/usr/bin/env bash
# Prepara o ambiente local nativo no Linux ou macOS para compilar o firmware ZMK (v0.3 / Zephyr 3.5).
#
# Instala tudo de forma isolada, sem Docker e sem precisar de sudo:
#   - Toolchain em ../zmk-workspace (.venv Python 3.12, Zephyr SDK 0.16.8 ARM, protoc 28.3)
#   - Repositorio do firmware ZMK (fork TergoTeclados/zmk @ tergo-v0.3) em ../zmk
#   - Workspace West (west init -l app + west update --filter=tree:0) dentro de ../zmk

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PARENT_DIR="$(dirname "$REPO_ROOT")"

WORKSPACE_PATH="$PARENT_DIR/zmk-workspace"
ZMK_PATH="$PARENT_DIR/zmk"
ZMK_REPO_URL="https://github.com/TergoTeclados/zmk.git"
ZMK_REVISION="tergo-v0.3"

usage() {
    cat <<'EOF'
Uso: ./local-build/setup-env.sh [opcoes]

Opcoes:
  --workspace-path <dir>   Pasta da toolchain (padrao: ../zmk-workspace)
  --zmk-path <dir>         Pasta do repositorio ZMK (padrao: ../zmk)
  --zmk-repo-url <url>     URL do repositorio ZMK (padrao: https://github.com/TergoTeclados/zmk.git)
  --zmk-revision <rev>     Branch ou tag do ZMK (padrao: tergo-v0.3)
  -h, --help               Exibe esta ajuda
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace-path) WORKSPACE_PATH="$2"; shift 2 ;;
        --zmk-path)       ZMK_PATH="$2"; shift 2 ;;
        --zmk-repo-url)   ZMK_REPO_URL="$2"; shift 2 ;;
        --zmk-revision)   ZMK_REVISION="$2"; shift 2 ;;
        -h|--help)        usage; exit 0 ;;
        *)                echo "Opcao desconhecida: $1" >&2; usage; exit 1 ;;
    esac
done

for cmd in git uv curl tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Erro: pre-requisito nao encontrado no PATH: '$cmd'. Instale-o antes de continuar." >&2
        exit 1
    fi
done

OS_RAW="$(uname -s)"
ARCH_RAW="$(uname -m)"

case "$OS_RAW" in
    Linux)  SDK_OS="linux" ;;
    Darwin) SDK_OS="macos" ;;
    *)      echo "Sistema operacional nao suportado por este script: $OS_RAW" >&2; exit 1 ;;
esac

case "$ARCH_RAW" in
    x86_64|amd64)  SDK_ARCH="x86_64" ;;
    aarch64|arm64) SDK_ARCH="aarch64" ;;
    *)             echo "Arquitetura nao suportada por este script: $ARCH_RAW" >&2; exit 1 ;;
esac

if [[ "$SDK_OS" == "macos" ]]; then
    PROTOC_ASSET="protoc-28.3-osx-universal_binary.zip"
elif [[ "$SDK_ARCH" == "x86_64" ]]; then
    PROTOC_ASSET="protoc-28.3-linux-x86_64.zip"
else
    PROTOC_ASSET="protoc-28.3-linux-aarch_64.zip"
fi

TOOLS_DIR="$WORKSPACE_PATH/tools"
VENV_DIR="$WORKSPACE_PATH/.venv"
VENV_BIN="$VENV_DIR/bin"
VENV_PYTHON="$VENV_BIN/python"
SDK_DIR="$TOOLS_DIR/zephyr-sdk-0.16.8"
PROTOC_DIR="$TOOLS_DIR/protoc"

echo "=== Configurando ZMK Workspace ($SDK_OS/$SDK_ARCH) em: $WORKSPACE_PATH ==="
mkdir -p "$TOOLS_DIR"

# 1. Virtualenv Python 3.12
if [[ ! -x "$VENV_PYTHON" ]]; then
    echo ""
    echo "[1/6] Criando ambiente virtual Python 3.12 com uv..."
    uv venv --python 3.12 "$VENV_DIR"
else
    echo ""
    echo "[1/6] Virtualenv Python 3.12 ja existe."
fi

echo "[2/6] Instalando ferramentas base Python (west, cmake<4, ninja, protobuf, setuptools<81)..."
uv pip install --python "$VENV_PYTHON" \
    west \
    "cmake<4" \
    ninja \
    "setuptools<81" \
    "protobuf>=4.25,<6" \
    "grpcio-tools<1.72"

# 2. Zephyr SDK 0.16.8 minimal + arm-zephyr-eabi
ARM_GCC="$SDK_DIR/arm-zephyr-eabi/bin/arm-zephyr-eabi-gcc"
if [[ ! -x "$ARM_GCC" ]]; then
    echo ""
    echo "[3/6] Baixando Zephyr SDK 0.16.8 (minimal + arm-zephyr-eabi)..."
    SDK_ARCHIVE="$TOOLS_DIR/zephyr-sdk-minimal.tar.xz"
    ARM_ARCHIVE="$TOOLS_DIR/arm-zephyr-eabi.tar.xz"

    curl -fsSL "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.16.8/zephyr-sdk-0.16.8_${SDK_OS}-${SDK_ARCH}_minimal.tar.xz" -o "$SDK_ARCHIVE"
    curl -fsSL "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.16.8/toolchain_${SDK_OS}-${SDK_ARCH}_arm-zephyr-eabi.tar.xz" -o "$ARM_ARCHIVE"

    tar -xf "$SDK_ARCHIVE" -C "$TOOLS_DIR"
    tar -xf "$ARM_ARCHIVE" -C "$SDK_DIR"
    rm -f "$SDK_ARCHIVE" "$ARM_ARCHIVE"
else
    echo ""
    echo "[3/6] Zephyr SDK 0.16.8 (arm-zephyr-eabi) ja instalado."
fi

# 3. protoc 28.3
PROTOC_BIN="$PROTOC_DIR/bin/protoc"
if [[ ! -x "$PROTOC_BIN" ]]; then
    echo ""
    echo "[4/6] Baixando protoc 28.3 (necessario para ZMK Studio / nanopb)..."
    PROTOC_ARCHIVE="$TOOLS_DIR/protoc.zip"
    curl -fsSL "https://github.com/protocolbuffers/protobuf/releases/download/v28.3/${PROTOC_ASSET}" -o "$PROTOC_ARCHIVE"
    mkdir -p "$PROTOC_DIR"
    "$VENV_PYTHON" -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" "$PROTOC_ARCHIVE" "$PROTOC_DIR"
    chmod +x "$PROTOC_BIN"
    rm -f "$PROTOC_ARCHIVE"
else
    echo ""
    echo "[4/6] protoc 28.3 ja instalado."
fi

export PATH="$VENV_BIN:$PROTOC_DIR/bin:$PATH"

# 4. Clonar ZMK e inicializar workspace West
if [[ ! -d "$ZMK_PATH/.git" ]]; then
    echo ""
    echo "[5/6] Clonando ZMK ($ZMK_REPO_URL @ $ZMK_REVISION)..."
    git clone --branch "$ZMK_REVISION" "$ZMK_REPO_URL" "$ZMK_PATH"
else
    echo ""
    echo "[5/6] Repositorio ZMK ja clonado em $ZMK_PATH."
fi

pushd "$ZMK_PATH" >/dev/null
if [[ ! -d "$ZMK_PATH/.west" ]]; then
    echo "      Executando 'west init -l app'..."
    west init -l app
fi

echo "      Executando 'west update --fetch-opt=--filter=tree:0'..."
west update --fetch-opt=--filter=tree:0

echo ""
echo "[6/6] Exportando pacotes CMake e instalando dependencias Python do Zephyr..."
west zephyr-export
uv pip install --python "$VENV_PYTHON" -r "$ZMK_PATH/zephyr/scripts/requirements-base.txt"
cmake -P "$SDK_DIR/cmake/zephyr_sdk_export.cmake"
popd >/dev/null

echo ""
echo "=== Ambiente ZMK pronto! ==="
echo "Para listar os alvos do build.yaml:"
echo "  ./local-build/build-local.sh --list"
echo "Para compilar um alvo:"
echo "  ./local-build/build-local.sh --target sofle_receptor_ABNT2_displayV2"
