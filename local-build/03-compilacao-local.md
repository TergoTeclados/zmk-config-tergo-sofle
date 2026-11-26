# 03 — Compilação Local na Prática

Este guia explica todos os alvos definidos no [`build.yaml`](../build.yaml), como compilar via script ou manualmente com `west build`, e como acelerar seu ciclo de desenvolvimento com builds incrementais.

---

## 1. Mapa dos 7 Alvos do `build.yaml`

| Alvo (`artifact-name`) | Board | Shield(s) | Snippet | `cmake-args` Extras | Papel |
| --- | --- | --- | --- | --- | --- |
| `sofle_receptor_ABNT2_displayV2` | `nice_nano_v2` | `sofle_dongle sofle_dongle_ssd1306 dongle_display` | `studio-rpc-usb-uart` | *(nenhum)* | Dongle central, layout ABNT2, OLED SSD1306 (V2) |
| `sofle_receptor_ABNT2_displayV1` | `nice_nano_v2` | `sofle_dongle sofle_dongle_sh1106 dongle_display` | `studio-rpc-usb-uart` | *(nenhum)* | Dongle central, layout ABNT2, OLED SH1106 (V1) |
| `sofle_receptor_ANSI_displayV2` | `nice_nano_v2` | `sofle_dongle sofle_dongle_ssd1306 dongle_display` | `studio-rpc-usb-uart` | `-DDTS_EXTRA_CPPFLAGS=-DUSE_INTERNATIONAL_LAYOUT` | Dongle central, layout ANSI/Intl, OLED SSD1306 (V2) |
| `sofle_receptor_ANSI_displayV1` | `nice_nano_v2` | `sofle_dongle sofle_dongle_sh1106 dongle_display` | `studio-rpc-usb-uart` | `-DDTS_EXTRA_CPPFLAGS=-DUSE_INTERNATIONAL_LAYOUT` | Dongle central, layout ANSI/Intl, OLED SH1106 (V1) |
| `sofle_esquerdo` | `nice_nano_v2` | `sofle_left` | *(nenhum)* | `-DCONFIG_ZMK_SPLIT=y -DCONFIG_ZMK_SPLIT_ROLE_CENTRAL=n` | Metade esquerda (periférico BLE) |
| `sofle_direito` | `nice_nano_v2` | `sofle_right` | *(nenhum)* | `-DCONFIG_ZMK_SPLIT=y -DCONFIG_ZMK_SPLIT_ROLE_CENTRAL=n` | Metade direita (periférico BLE) |
| `reset-firmware` | `nice_nano_v2` | `settings_reset` | *(nenhum)* | *(nenhum)* | Limpa pareamentos BLE e configurações persistentes |

---

## 2. Compilando com o Script Auxiliar (`build-local.ps1`)

Execute a partir da raiz do repositório `zmk-config-tergo-sofle`:

```powershell
# Ver todos os alvos disponíveis no build.yaml
.\local-build\build-local.ps1 -List

# Compilar apenas o alvo que você está testando (muito mais rápido que compilar todos)
.\local-build\build-local.ps1 -Target sofle_receptor_ABNT2_displayV2

# Compilar vários alvos em sequência
.\local-build\build-local.ps1 -Target sofle_receptor_ABNT2_displayV2,sofle_esquerdo,sofle_direito

# Compilar TODOS os 7 alvos do build.yaml
.\local-build\build-local.ps1 -All

# Forçar build limpo (pristine / -p)
.\local-build\build-local.ps1 -Target sofle_receptor_ABNT2_displayV2 -Pristine

# Compilar com logs via USB habilitados (adiciona snippet zmk-usb-logging)
.\local-build\build-local.ps1 -Target sofle_receptor_ABNT2_displayV2 -UsbLogging
```

Ao final de cada alvo, o script:
1. Compila dentro de `C:\Users\victor\Documents\GitHub\zmk\build\<alvo>\` (cada alvo tem sua própria pasta de build, então alternar entre dongle e metade esquerda **não invalida o cache** do outro!).
2. Copia `zephyr\zmk.uf2` para `zmk-config-tergo-sofle\build-artifacts\<alvo>.uf2`.
3. Exibe uma tabela com tamanho do arquivo e tempo de compilação.

---

## 3. Compilando Manualmente com `west build`

Para entender exatamente o que o script executa (ou para passar flags experimentais manualmente):

```powershell
# 1. Ative o ambiente na sessão do PowerShell
$ws = "C:\Users\victor\Documents\GitHub\zmk-workspace"
$zmk = "C:\Users\victor\Documents\GitHub\zmk"
$cfgRepo = "C:/Users/victor/Documents/GitHub/zmk-config-tergo-sofle"
$env:PATH = "$ws\.venv\Scripts;$ws\tools\protoc\bin;$env:PATH"
$env:ZEPHYR_TOOLCHAIN_VARIANT = "zephyr"
$env:ZEPHYR_SDK_INSTALL_DIR = "$ws\tools\zephyr-sdk-0.16.8"
cd "$zmk"
```

### Exemplo A — Dongle ABNT2 Display V2 (SSD1306)
```powershell
west build -p -s app -d build/sofle_receptor_ABNT2_displayV2 -b nice_nano_v2 -S studio-rpc-usb-uart -- `
    "-DZMK_CONFIG=$cfgRepo/config" `
    "-DZMK_EXTRA_MODULES=$cfgRepo" `
    "-DPROTOBUF_PROTOC_EXECUTABLE=$ws/tools/protoc/bin/protoc.exe" `
    "-DSHIELD=sofle_dongle sofle_dongle_ssd1306 dongle_display"
```

### Exemplo B — Dongle ANSI Display V1 (SH1106)
```powershell
west build -p -s app -d build/sofle_receptor_ANSI_displayV1 -b nice_nano_v2 -S studio-rpc-usb-uart -- `
    "-DZMK_CONFIG=$cfgRepo/config" `
    "-DZMK_EXTRA_MODULES=$cfgRepo" `
    "-DPROTOBUF_PROTOC_EXECUTABLE=$ws/tools/protoc/bin/protoc.exe" `
    "-DSHIELD=sofle_dongle sofle_dongle_sh1106 dongle_display" `
    "-DDTS_EXTRA_CPPFLAGS=-DUSE_INTERNATIONAL_LAYOUT"
```

### Exemplo C — Metade Esquerda (Periférico)
```powershell
west build -p -s app -d build/sofle_esquerdo -b nice_nano_v2 -- `
    "-DZMK_CONFIG=$cfgRepo/config" `
    "-DZMK_EXTRA_MODULES=$cfgRepo" `
    "-DSHIELD=sofle_left" `
    "-DCONFIG_ZMK_SPLIT=y" `
    "-DCONFIG_ZMK_SPLIT_ROLE_CENTRAL=n"
```

### O que significa cada parâmetro?

- `-p` (*pristine*): apaga o diretório de build e refaz toda a configuração CMake/Devicetree/Kconfig do zero.
- `-s app`: aponta para o diretório-fonte da aplicação ZMK (`zmk/app`).
- `-d build/<nome>`: define uma pasta de build dedicada para aquele alvo.
- `-b nice_nano_v2`: define a placa controladora.
- `-S studio-rpc-usb-uart`: ativa um *snippet* do ZMK (pode ser repetido, ex.: `-S studio-rpc-usb-uart -S zmk-usb-logging`).
- `--`: separa opções do `west` das opções repassadas diretamente ao **CMake**.
- `-DZMK_CONFIG=...`: diz ao ZMK onde estão `sofle.keymap` e `sofle.conf`.
- `-DZMK_EXTRA_MODULES=...`: carrega o `zephyr/module.yml` do seu repositório para encontrar os shields customizados (`sofle_dongle`, `dongle_display`, etc.).
- `-DPROTOBUF_PROTOC_EXECUTABLE=...`: garante o uso do `protoc.exe` nativo do Windows para gerar as mensagens do ZMK Studio (`nanopb`).
- **Dica de PowerShell:** use sempre barras normais (`/`) nos caminhos passados em `-D...` e envolva argumentos com espaço ou `=` entre aspas duplas (ex.: `"-DSHIELD=a b c"`).

---

## 4. Build Incremental vs Build Pristine (`-p`)

| O que você alterou | Precisa de `-Pristine` / `-p`? | Tempo típico |
| --- | --- | --- |
| Código C/H no ZMK (`zmk/app/src/*.c`) ou nos widgets (`dongle_display/widgets/*.c`) | **Não** (incremental!) | ~3 a 10 segundos |
| `config/sofle.keymap` ou `.overlay` | **Recomendado `-Pristine`** (às vezes o incremental detecta, mas `-p` garante que o Devicetree foi regenerado) | ~45 a 90 segundos |
| `config/sofle.conf`, `Kconfig*`, `CMakeLists.txt`, troca de shields/snippets | **Sim (`-Pristine`)** | ~45 a 90 segundos |

No modo manual, para rodar um build incremental após editar um `.c`, basta:
```powershell
west build -s app -d build/sofle_receptor_ABNT2_displayV2
```
*(Sem `-p` e sem precisar repetir as flags do CMake, pois elas ficam salvas no `CMakeCache.txt` do diretório de build!)*

---

## 5. Arquivos Úteis Gerados na Pasta `build/<alvo>/zephyr/`

Além do firmware final, o build gera artefatos excelentes para depuração:

- `zmk.uf2`: firmware final para gravar no `nice_nano_v2` (entre no modo bootloader e arraste o `.uf2` para a unidade removível `NICENANO`).
- `zephyr.dts`: o **Devicetree final mesclado** (board + todos os overlays + `sofle.keymap` já expandido após o pré-processador C). Perfeito para conferir se uma macro como `USE_INTERNATIONAL_LAYOUT` ou um pino I2C foi aplicado corretamente!
- `.config`: o **Kconfig final resolvido** com todas as variáveis `CONFIG_*` efetivamente ativas no firmware.
- `zmk.elf` / `zmk.map`: símbolos e mapa de uso de Flash e RAM.
