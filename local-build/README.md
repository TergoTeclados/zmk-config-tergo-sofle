# Compilação Local do Firmware ZMK — Tergo Sofle

Esta pasta contém toda a documentação e os scripts de automação para compilar localmente no **Windows** o firmware do **Tergo Sofle** (dongle central + metades esquerda e direita + reset), incluindo suporte completo para **editar o código-fonte original do ZMK** (`zmkfirmware/zmk`).

---

## Quick Start (Compilar Agora)

Se o ambiente já foi preparado em `C:\Users\victor\Documents\GitHub\zmk-workspace` (ou após rodar `setup-env.ps1`), abra o PowerShell na raiz do `zmk-config-tergo-sofle` e use o script auxiliar:

```powershell
# 1. Listar todos os alvos definidos no build.yaml
.\local-build\build-local.ps1 -List

# 2. Compilar apenas o dongle ABNT2 (display SSD1306 / V2)
.\local-build\build-local.ps1 -Target sofle_receptor_ABNT2_displayV2

# 3. Compilar mais de um alvo (ex.: dongle + metade esquerda)
.\local-build\build-local.ps1 -Target sofle_receptor_ABNT2_displayV2,sofle_esquerdo

# 4. Forçar recompilação limpa (pristine) após alterar .conf, .overlay ou .keymap
.\local-build\build-local.ps1 -Target sofle_receptor_ABNT2_displayV2 -Pristine

# 5. Compilar TODOS os 7 alvos do build.yaml
.\local-build\build-local.ps1 -All
```

Os arquivos `.uf2` prontos para gravar no teclado são copiados automaticamente para:

```text
zmk-config-tergo-sofle\build-artifacts\<artifact-name>.uf2
```

*(A pasta `build-artifacts/` é ignorada pelo Git via `.gitignore`.)*

---

## Como as Pastas Estão Organizadas

```text
C:\Users\victor\Documents\GitHub\
├── zmk-config-tergo-sofle\          ← SUA configuração (shields, keymap, conf, build.yaml)
│   ├── config\                      ← sofle.keymap, sofle.conf, west.yml
│   ├── boards\shields\              ← sofle_dongle, oled SSD1306/SH1106, dongle_display
│   ├── zephyr\module.yml            ← Registra este repo como módulo Zephyr
│   ├── build-artifacts\             ← Saída local dos .uf2 (ignorado pelo Git)
│   └── local-build\                 ← Esta documentação e scripts PowerShell
│
└── zmk-workspace\                   ← Ambiente de build local (fora deste repo)
    ├── .venv\                       ← Python 3.12 isolado (west, cmake, ninja, deps Zephyr)
    ├── tools\
    │   ├── zephyr-sdk-0.16.8\       ← Compilador ARM (arm-zephyr-eabi-gcc)
    │   └── protoc\                  ← Compilador Protobuf (usado pelo ZMK Studio / nanopb)
    └── zmk\                         ← Clone do repositório zmkfirmware/zmk (v0.3) + workspace West
        ├── app\                     ← Código-fonte do ZMK (onde você faz alterações no core!)
        ├── zephyr\                  ← RTOS Zephyr v3.5.0+zmk-fixes (baixado pelo west)
        ├── modules\                 ← HAL Nordic, LVGL, nanopb, zmk-studio-messages, etc.
        └── build\                   ← Diretórios de compilação intermediários por alvo
```

---

## Índice da Documentação

| Guia | O que você vai aprender |
| --- | --- |
| [01 — Arquitetura do ZMK e deste repositório](./01-arquitetura-zmk.md) | Como Zephyr, ZMK, West, Devicetree, Kconfig, Shields e Dongle funcionam juntos, e o que a pipeline na nuvem faz por baixo dos panos. |
| [02 — Preparação do Ambiente no Windows](./02-setup-ambiente-windows.md) | Passo a passo completo (automatizado e manual) para montar a toolchain nativa no Windows, além do comparativo com WSL 2 e Docker. |
| [03 — Compilação Local na Prática](./03-compilacao-local.md) | Todos os 7 alvos do `build.yaml`, uso do `build-local.ps1`, comandos `west build` manuais, build incremental vs pristine e arquivos de diagnóstico. |
| [04 — Modificando o Código-Fonte do ZMK](./04-modificando-codigo-zmk.md) | Mapa de `zmk/app/src/`, fluxo Git com branch/fork, debug via USB logging e como apontar o `config/west.yml` para seu fork no GitHub Actions. |
| [05 — Problemas Encontrados e Ajustes Feitos](./05-problemas-encontrados.md) | Registro técnico das incompatibilidades encontradas no Windows (LVGL + macro `C`, `nanopb`/`setuptools`, `cmake<4`, `zephyr/module.yml`) e como foram resolvidas. |

---

## Scripts Disponíveis

- [`setup-env.ps1`](./setup-env.ps1): Recria ou atualiza o `zmk-workspace` do zero em qualquer máquina Windows (requer apenas `git`, `uv` e `tar` nativo do Windows — sem precisar de Docker, WSL ou permissões de administrador).
- [`build-local.ps1`](./build-local.ps1): Lê automaticamente o [`build.yaml`](../build.yaml), executa `west build` (incremental por padrão ou `-Pristine`) e entrega os `.uf2` nomeados em `build-artifacts/`.
