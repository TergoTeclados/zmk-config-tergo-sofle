# Compilação Local do Firmware ZMK (Tergo Sofle)

Scripts auxiliares para preparar o ambiente e compilar localmente no **Windows, Linux ou macOS** o firmware do **Tergo Sofle** sem precisar de Docker, WSL ou permissões de administrador.

Para o guia completo (incluindo compilação na nuvem pelo GitHub Actions, estrutura de pastas e dicas de depuração), consulte a [documentação oficial de modificação do firmware Wireless](https://tergoteclados.github.io/Tergo-Sofle-Documentation/docs/guias/especifico_versao_wireless/COMO_MODIFICAR_CODIGO_FONTE).

## Pré-requisitos

- `git`
- [`uv`](https://docs.astral.sh/uv/)
- `tar` (já vem nativo no Windows 10/11, Linux e macOS)
- `curl` (no Linux e macOS)

## 1. Preparar o ambiente (apenas uma vez)

Execute a partir da raiz do repositório `zmk-config-tergo-sofle`:

**Windows (PowerShell):**
```powershell
.\local-build\setup-env.ps1
```

**Linux / macOS (Bash):**
```bash
./local-build/setup-env.sh
```

## 2. Compilar o firmware

**Windows (PowerShell):**
```powershell
# Listar os 7 alvos do build.yaml
.\local-build\build-local.ps1 -List

# Compilar um alvo específico
.\local-build\build-local.ps1 -Target sofle_receptor_ABNT2_displayV2

# Recompilação limpa após alterar .keymap, .overlay ou .conf
.\local-build\build-local.ps1 -Target sofle_receptor_ABNT2_displayV2 -Pristine

# Compilar todos os 7 alvos
.\local-build\build-local.ps1 -All -Pristine
```

**Linux / macOS (Bash):**
```bash
# Listar os 7 alvos do build.yaml
./local-build/build-local.sh --list

# Compilar um alvo específico
./local-build/build-local.sh --target sofle_receptor_ABNT2_displayV2

# Recompilação limpa após alterar .keymap, .overlay ou .conf
./local-build/build-local.sh --target sofle_receptor_ABNT2_displayV2 --pristine

# Compilar todos os 7 alvos
./local-build/build-local.sh --all --pristine
```

Os arquivos `.uf2` gerados são copiados automaticamente para `build-artifacts/` (pasta ignorada pelo Git).
