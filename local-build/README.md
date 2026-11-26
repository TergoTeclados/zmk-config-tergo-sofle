# Compilação Local do Firmware ZMK (Tergo Sofle)

Esta pasta contém a documentação e os scripts auxiliares para compilar localmente no **Windows, Linux ou macOS** o firmware do **Tergo Sofle** (receptor/dongle central, metades esquerda e direita e reset), incluindo suporte completo para editar tanto o `zmk-config-tergo-sofle` quanto o código-fonte do fork `TergoTeclados/zmk`.

---

## Quick Start

### 1. Preparar o ambiente (apenas uma vez)

Pré-requisitos no PATH: `git`, [`uv`](https://docs.astral.sh/uv/) e `tar` (no Linux/macOS, também `curl`). Não exige Docker, WSL nem permissões de administrador.

**Windows (PowerShell):**
```powershell
.\local-build\setup-env.ps1
```

**Linux / macOS (Bash):**
```bash
chmod +x ./local-build/setup-env.sh ./local-build/build-local.sh
./local-build/setup-env.sh
```

### 2. Compilar o firmware

**Windows (PowerShell):**
```powershell
# Listar os 7 alvos do build.yaml
.\local-build\build-local.ps1 -List

# Compilar apenas o receptor ABNT2 (display SSD1306 / V2)
.\local-build\build-local.ps1 -Target sofle_receptor_ABNT2_displayV2

# Recompilação limpa (pristine) após alterar .conf, .overlay ou .keymap
.\local-build\build-local.ps1 -Target sofle_receptor_ABNT2_displayV2 -Pristine

# Compilar todos os 7 alvos
.\local-build\build-local.ps1 -All -Pristine
```

**Linux / macOS (Bash):**
```bash
# Listar os 7 alvos do build.yaml
./local-build/build-local.sh --list

# Compilar apenas o receptor ABNT2 (display SSD1306 / V2)
./local-build/build-local.sh --target sofle_receptor_ABNT2_displayV2

# Recompilação limpa (pristine) após alterar .conf, .overlay ou .keymap
./local-build/build-local.sh --target sofle_receptor_ABNT2_displayV2 --pristine

# Compilar todos os 7 alvos
./local-build/build-local.sh --all --pristine
```

Os arquivos `.uf2` prontos para gravar no teclado são copiados automaticamente para `build-artifacts/<artifact-name>.uf2` (pasta ignorada pelo Git via `.gitignore`).

---

## Como as pastas ficam organizadas

```text
<sua-pasta-de-projetos>/
├── zmk-config-tergo-sofle/     <- Configuração (keymap, conf, shields, behaviors locais, build.yaml)
│   ├── config/                 <- sofle.keymap, sofle.conf, west.yml (aponta para TergoTeclados/zmk)
│   ├── boards/shields/         <- sofle_dongle, OLED SSD1306/SH1106, dongle_display
│   ├── src/behaviors/          <- Behaviors locais (giro dos knobs no Studio, scroll por passo)
│   ├── dts/bindings/           <- Bindings Devicetree dos behaviors locais
│   ├── zephyr/module.yml       <- Registra este repositório como módulo Zephyr
│   ├── build-artifacts/        <- Saída local dos .uf2 (ignorado pelo Git)
│   └── local-build/            <- Esta documentação e scripts auxiliares
│
├── zmk/                        <- Fork TergoTeclados/zmk (branch tergo-v0.3) + workspace West
│   ├── app/                    <- Código-fonte do ZMK
│   ├── zephyr/                 <- RTOS Zephyr v3.5.0+zmk-fixes (gerenciado pelo west)
│   ├── modules/                <- HAL Nordic, LVGL, nanopb, zmk-studio-messages
│   └── build/                  <- Diretórios de compilação intermediários por alvo
│
└── zmk-workspace/              <- Toolchain isolada (.venv Python 3.12, Zephyr SDK 0.16.8 ARM, protoc)
```

---

## Índice da documentação técnica

| Guia | O que você vai aprender |
| --- | --- |
| [01 - Arquitetura do ZMK e deste repositório](./01-arquitetura-zmk.md) | Como Zephyr, ZMK, West, Devicetree, Kconfig, Shields e Dongle funcionam juntos. |
| [02 - Preparação do ambiente (Windows)](./02-setup-ambiente-windows.md) | Passo a passo detalhado do ambiente nativo no Windows e comparativo com WSL 2 e Docker. |
| [03 - Compilação local na prática](./03-compilacao-local.md) | Todos os 7 alvos do `build.yaml`, uso dos scripts, comandos `west build` manuais e build incremental vs pristine. |
| [04 - Modificando o código-fonte do ZMK](./04-modificando-codigo-zmk.md) | Mapa de `zmk/app/src/`, fluxo Git com o fork `TergoTeclados/zmk`, debug via USB logging e GitHub Actions. |
| [05 - Problemas encontrados e ajustes feitos](./05-problemas-encontrados.md) | Incompatibilidades conhecidas (LVGL + macro `C` no Windows, `nanopb`/`setuptools`, `cmake<4`, `zephyr/module.yml`) e como foram resolvidas. |

---

## Scripts disponíveis

- [`setup-env.ps1`](./setup-env.ps1) (Windows) e [`setup-env.sh`](./setup-env.sh) (Linux / macOS): criam ou atualizam o `zmk-workspace` e o workspace West em `../zmk` de forma idempotente.
- [`build-local.ps1`](./build-local.ps1) (Windows) e [`build-local.sh`](./build-local.sh) (Linux / macOS): leem o [`build.yaml`](../build.yaml), executam `west build` (incremental por padrão ou pristine) e entregam os `.uf2` em `build-artifacts/`.
