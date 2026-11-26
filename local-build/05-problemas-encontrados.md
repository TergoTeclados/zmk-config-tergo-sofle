# 05 — Problemas Encontrados e Ajustes Necessários no Windows

Durante a investigação e a validação real da compilação nativa no Windows, encontramos algumas particularidades importantes que **não aparecem** na pipeline Linux do GitHub Actions. Todas foram resolvidas e estão documentadas abaixo para referência futura.

---

## 1. Colisão da Pasta `zephyr/` (`zephyr/module.yml`)

- **Causa:** O repositório `zmk-config-tergo-sofle` contém `zephyr/module.yml` para registrar os shields locais (`boards/shields/`). Se você rodar `west init` diretamente na raiz do `zmk-config-tergo-sofle`, o `west update` tentará clonar o Zephyr RTOS em `zmk-config-tergo-sofle/zephyr/`, colidindo com a pasta versionada no Git.
- **Como o CI resolve:** O workflow `build-user-config.yml@v0.3` detecta `zephyr/module.yml`, cria um workspace temporário separado e passa `-DZMK_EXTRA_MODULES=<repo>`.
- **Solução adotada localmente:** O workspace West fica fora deste repositório (`..\zmk-workspace\zmk`), e o `build-local.ps1` passa sempre `-DZMK_CONFIG=<repo>/config` e `-DZMK_EXTRA_MODULES=<repo>`.

---

## 2. Colisão da Macro `#define C` com o Caminho `C:/...` no LVGL (Ajuste no Código)

Este foi o problema mais curioso — e exclusivo do Windows!

- **Sintoma:** Ao compilar os widgets do `dongle_display`, o GCC falhava com:
  ```text
  lv_conf_internal.h:35:42: fatal error: ...\((((0x07) << 16) | (0x06))):/Users/.../lv_conf.h: Invalid argument
    35 |         #include __LV_TO_STR(LV_CONF_PATH)
  ```
- **Causa raiz:**
  1. O Zephyr 3.5 passa `-DLV_CONF_PATH=C:/Users/.../lv_conf.h` **sem aspas**, deixando para a macro `__LV_TO_STR(LV_CONF_PATH)` transformar o caminho em string.
  2. Os arquivos de widget em `boards/shields/dongle_display/widgets/*.c` incluíam cabeçalhos do ZMK (`<zmk/hid.h>`, `<zmk/usb.h>`, `<zmk/ble.h>`) **antes** do próprio cabeçalho do widget (que inclui `<lvgl.h>`).
  3. Esses cabeçalhos do ZMK incluem transitivamente `<dt-bindings/zmk/keys.h>`, que define `#define C ((((0x07) << 16) | (0x06)))` (o código HID da tecla **C**!).
  4. Como no Windows o caminho absoluto começa com a letra do disco **`C:`**, o pré-processador expandia o token `C` antes de stringificar `LV_CONF_PATH`! No Linux isso nunca ocorre porque caminhos começam com `/`.
- **Solução aplicada nesta branch:** Reordenamos os `#include` nos 5 arquivos de widget em `boards/shields/dongle_display/widgets/` (`modifiers.c`, `battery_status.c`, `output_status.c`, `bongo_cat.c` e `hid_indicators.c`) para incluir o próprio header do widget (e portanto `<lvgl.h>`) **antes** dos headers `<zmk/...>`.
  - É uma mudança mínima, idiomática em C (incluir o próprio `.h` antes dos demais) e **100% compatível** com o build Linux no GitHub Actions.

---

## 3. `nanopb` (ZMK Studio) e `ModuleNotFoundError: No module named 'pkg_resources'`

- **Causa:** O alvo do dongle ativa `CONFIG_ZMK_STUDIO=y` e `-S studio-rpc-usb-uart`, que compilam arquivos `.proto` usando o módulo `nanopb` (revisão de 2024 do ZMK `v0.3`). Versões recentes do `setuptools` (>= 82) removeram o pacote `pkg_resources` importado pelo gerador do `nanopb`, e o `protobuf 7.x` tem incompatibilidades com o gerador mais antigo.
- **Solução aplicada:**
  1. Pinamos no virtualenv Python 3.12: `setuptools<81`, `protobuf>=4.25,<6` e `grpcio-tools<1.72`.
  2. Baixamos o binário nativo `protoc 28.3` para Windows (`zmk-workspace\tools\protoc\bin\protoc.exe`) e passamos `-DPROTOBUF_PROTOC_EXECUTABLE=...` no `west build`.

---

## 4. Compatibilidade do CMake 4.x com Zephyr 3.5

- **Causa:** O pacote `cmake` mais recente no PyPI já está na versão `4.x`, que removeu suporte a `cmake_minimum_required(VERSION < 3.5)` presente em módulos legados do Zephyr 3.5.
- **Solução aplicada:** Pinamos `"cmake<4"` (instalando a série `3.31.x`) no virtualenv.

---

## 5. `setup.cmd` do Zephyr SDK Exige `wget` no Windows

- **Causa:** Ao rodar `zephyr-sdk-0.16.8\setup.cmd -c`, o script aborta se `wget` não estiver no PATH — mesmo quando já baixamos os arquivos manualmente.
- **Solução aplicada:** Chamamos diretamente o script CMake que o `setup.cmd` usaria internamente:
  ```powershell
  cmake -P "$ws\tools\zephyr-sdk-0.16.8\cmake\zephyr_sdk_export.cmake"
  ```
  Isso registra o SDK no registro CMake do usuário sem depender de `wget` ou privilégios de administrador.

---

## 6. Avisos Esperados e Inofensivos Durante o Build

Ao compilar localmente, você verá alguns avisos no terminal que **são normais** e não indicam erro:

- **`Could NOT find Dtc (missing: DTC)`**: No Zephyr 3.5, o parsing de Devicetree é feito inteiramente em Python pela biblioteca `edtlib`. O binário `dtc` só é usado como verificação opcional.
- **`warning: EC11 ... was assigned the value 'y' but got the value 'n'`**: Aparece nos alvos de **dongle** porque `config/sofle.conf` habilita `CONFIG_EC11=y` globalmente (para as metades com encoders), enquanto `sofle_dongle.overlay` mantém `left_encoder` e `right_encoder` com `status = "disabled"`. O mesmo aviso também aparece nos logs do GitHub Actions.
- **`warning: Deprecated symbol NRF_STORE_REBOOT_TYPE_GPREGRET is enabled`**: Aviso padrão do board `nice_nano_v2` no Zephyr 3.5.
