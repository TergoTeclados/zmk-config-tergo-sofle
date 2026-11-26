#!/usr/bin/env bash
# Compila localmente um ou mais alvos definidos em build.yaml no Linux ou macOS.
#
# Exemplos:
#   ./local-build/build-local.sh --list
#   ./local-build/build-local.sh --target sofle_receptor_ABNT2_displayV2
#   ./local-build/build-local.sh --target sofle_receptor_ABNT2_displayV2,sofle_esquerdo --pristine
#   ./local-build/build-local.sh --all --pristine

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PARENT_DIR="$(dirname "$REPO_ROOT")"

WORKSPACE_PATH="$PARENT_DIR/zmk-workspace"
ZMK_PATH="$PARENT_DIR/zmk"
TARGETS_RAW=""
BUILD_ALL=0
LIST_ONLY=0
PRISTINE=0
USB_LOGGING=0

usage() {
    cat <<'EOF'
Uso: ./local-build/build-local.sh [opcoes]

Opcoes:
  -l, --list                 Lista os alvos definidos em build.yaml
  -t, --target <nomes>       Compila um ou mais alvos separados por virgula (pode repetir)
  -a, --all                  Compila todos os 7 alvos de build.yaml
  -p, --pristine             Forca recompilacao limpa (west build -p)
      --usb-logging          Adiciona o snippet zmk-usb-logging (gera *_logging.uf2)
      --workspace-path <dir> Caminho do zmk-workspace (padrao: ../zmk-workspace)
      --zmk-path <dir>       Caminho do repositorio zmk (padrao: ../zmk)
  -h, --help                 Exibe esta ajuda
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -l|--list)        LIST_ONLY=1; shift ;;
        -a|--all)         BUILD_ALL=1; shift ;;
        -p|--pristine)    PRISTINE=1; shift ;;
        --usb-logging)    USB_LOGGING=1; shift ;;
        -t|--target)
            if [[ -n "$TARGETS_RAW" ]]; then
                TARGETS_RAW="${TARGETS_RAW},$2"
            else
                TARGETS_RAW="$2"
            fi
            shift 2
            ;;
        --workspace-path) WORKSPACE_PATH="$2"; shift 2 ;;
        --zmk-path)       ZMK_PATH="$2"; shift 2 ;;
        -h|--help)        usage; exit 0 ;;
        *)                echo "Opcao desconhecida: $1" >&2; usage; exit 1 ;;
    esac
done

VENV_BIN="$WORKSPACE_PATH/.venv/bin"
VENV_PYTHON="$VENV_BIN/python"
SDK_DIR="$WORKSPACE_PATH/tools/zephyr-sdk-0.16.8"
PROTOC_BIN="$WORKSPACE_PATH/tools/protoc/bin/protoc"
BUILD_YAML="$REPO_ROOT/build.yaml"
OUT_DIR="$REPO_ROOT/build-artifacts"

if [[ ! -x "$VENV_PYTHON" || ! -d "$ZMK_PATH" ]]; then
    echo "Erro: toolchain ('$WORKSPACE_PATH') ou repositorio ZMK ('$ZMK_PATH') nao encontrado." >&2
    echo "Execute './local-build/setup-env.sh' primeiro." >&2
    exit 1
fi

export PATH="$VENV_BIN:$(dirname "$PROTOC_BIN"):$PATH"
export ZEPHYR_TOOLCHAIN_VARIANT="zephyr"
export ZEPHYR_SDK_INSTALL_DIR="$SDK_DIR"

mkdir -p "$OUT_DIR"

"$VENV_PYTHON" - "$BUILD_YAML" "$ZMK_PATH" "$REPO_ROOT" "$PROTOC_BIN" "$OUT_DIR" \
    "$LIST_ONLY" "$BUILD_ALL" "$PRISTINE" "$USB_LOGGING" "$TARGETS_RAW" <<'PY'
import os
import shlex
import shutil
import subprocess
import sys
import time
import yaml

(
    build_yaml,
    zmk_dir,
    repo_root,
    protoc_bin,
    out_dir,
    list_only,
    build_all,
    pristine,
    usb_logging,
    targets_raw,
) = sys.argv[1:]

list_only = list_only == "1"
build_all = build_all == "1"
pristine = pristine == "1"
usb_logging = usb_logging == "1"
requested = [t.strip() for t in targets_raw.split(",") if t.strip()]

with open(build_yaml, "r", encoding="utf-8") as f:
    data = yaml.safe_load(f)

entries = []
for item in data.get("include", []):
    board = item.get("board", "")
    shield = item.get("shield", "")
    snippet = item.get("snippet", "")
    artifact = item.get("artifact-name") or (
        f"{shield}-{board}-zmk" if shield else f"{board}-zmk"
    )
    cmake_raw = item.get("cmake-args", "") or ""
    entries.append(
        {
            "artifact": artifact,
            "board": board,
            "shield": shield,
            "snippet": snippet,
            "cmake_args": shlex.split(cmake_raw),
        }
    )

if list_only or (not build_all and not requested):
    print("Alvos disponiveis em build.yaml:\n")
    print(f"{'Target (artifact-name)':<32} {'Board':<14} {'Shield(s)':<48} {'Snippet'}")
    print("-" * 115)
    for e in entries:
        print(f"{e['artifact']:<32} {e['board']:<14} {e['shield']:<48} {e['snippet']}")
    if not list_only:
        print("\nUse --target <nome> ou --all para compilar. Exemplo:")
        print("  ./local-build/build-local.sh --target sofle_receptor_ABNT2_displayV2")
    sys.exit(0)

if build_all:
    selected = entries
else:
    by_name = {e["artifact"]: e for e in entries}
    selected = []
    for name in requested:
        if name not in by_name:
            valid = ", ".join(by_name.keys())
            sys.exit(f"Erro: alvo '{name}' nao encontrado em build.yaml. Alvos validos: {valid}")
        selected.append(by_name[name])

results = []
for entry in selected:
    t0 = time.monotonic()
    build_dir_name = f"{entry['artifact']}_logging" if usb_logging else entry["artifact"]
    build_dir_rel = os.path.join("build", build_dir_name)
    build_dir_abs = os.path.join(zmk_dir, build_dir_rel)
    is_first_build = not os.path.exists(os.path.join(build_dir_abs, "build.ninja"))
    mode = "Pristine / Configuracao completa" if (pristine or is_first_build) else "Incremental (rapido)"

    print("\n================================================================")
    print(f" Compilando: {entry['artifact']}")
    print(f" Board: {entry['board']} | Shield: {entry['shield']}")
    print(f" Modo: {mode}")
    print("================================================================\n", flush=True)

    west_args = ["west", "build", "-s", "app", "-d", build_dir_rel]
    if pristine or is_first_build:
        if pristine:
            west_args.append("-p")
        west_args.extend(["-b", entry["board"]])

        for sn in entry["snippet"].split():
            west_args.extend(["-S", sn])
        if usb_logging:
            west_args.extend(["-S", "zmk-usb-logging"])

        west_args.append("--")
        west_args.append(f"-DZMK_CONFIG={repo_root}/config")
        west_args.append(f"-DZMK_EXTRA_MODULES={repo_root}")
        west_args.append(f"-DPROTOBUF_PROTOC_EXECUTABLE={protoc_bin}")
        if entry["shield"]:
            west_args.append(f"-DSHIELD={entry['shield']}")
        west_args.extend(entry["cmake_args"])

    rc = subprocess.run(west_args, cwd=zmk_dir).returncode
    if rc != 0:
        sys.exit(f"Falha na compilacao do alvo '{entry['artifact']}' (codigo {rc}).")

    uf2_src = os.path.join(build_dir_abs, "zephyr", "zmk.uf2")
    out_name = f"{entry['artifact']}_logging.uf2" if usb_logging else f"{entry['artifact']}.uf2"
    uf2_dst = os.path.join(out_dir, out_name)

    if not os.path.exists(uf2_src):
        sys.exit(f"Arquivo zmk.uf2 nao encontrado em {uf2_src}.")
    shutil.copy2(uf2_src, uf2_dst)

    elapsed = round(time.monotonic() - t0, 1)
    size_kb = round(os.path.getsize(uf2_dst) / 1024.0, 1)
    results.append((entry["artifact"], out_name, size_kb, elapsed))

print(f"\n=== Compilacao concluida! Artefatos salvos em: {out_dir} ===")
print(f"{'Target':<32} {'Arquivo':<38} {'TamanhoKB':>10} {'TempoSeg':>9}")
print("-" * 92)
for target, fname, size_kb, elapsed in results:
    print(f"{target:<32} {fname:<38} {size_kb:>10.1f} {elapsed:>9.1f}")
PY
