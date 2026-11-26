# 04 — Modificando o Código-Fonte Original do ZMK

Este guia mostra onde fica cada funcionalidade dentro do código-fonte do ZMK (`zmk-workspace\zmk\`), como organizar suas modificações com Git, como depurar no hardware real com logs USB e como fazer a pipeline na nuvem (GitHub Actions) usar suas mudanças no futuro.

---

## 1. Antes de Mexer no Core: Você Realmente Precisa Alterar o ZMK?

Muitas customizações no ZMK **não exigem** modificar `zmkfirmware/zmk` — elas podem viver no próprio `zmk-config-tergo-sofle` (ou em um módulo Zephyr externo):

- **Não precisa alterar o core do ZMK:**
  - Keymaps, combos, macros, hold-tap, mod-morph, tap-dance (`config/sofle.keymap`)
  - Parâmetros de sleep, potência TX BLE, mouse, debounce (`config/sofle.conf`)
  - Telas customizadas, ícones e widgets LVGL (`boards/shields/dongle_display/`)
  - Novo *behavior* ou *input processor* próprio (pode ser adicionado como driver/módulo via `zephyr/module.yml`)
- **Precisa alterar o core do ZMK (`zmk-workspace\zmk\app\`):**
  - Mudanças internas no protocolo split BLE (`src/split/`)
  - Alterações na lógica interna de `behaviors` existentes, `hid.c`, `endpoints.c`, `ble.c`, `pm.c` (power management / deep sleep) ou `studio/`
  - Correções de bugs ou backports de versões mais novas do ZMK para a base `v0.3`

---

## 2. Mapa do Código-Fonte do ZMK (`zmk-workspace\zmk\app\`)

```text
zmk-workspace\zmk\app\
├── CMakeLists.txt              ← Lista todos os .c compilados e condições Kconfig
├── Kconfig / Kconfig.defaults  ← Declaração de opções CONFIG_ZMK_*
├── include/zmk/                ← Headers públicos internos (#include <zmk/...>)
├── include/dt-bindings/zmk/    ← Constantes usadas em .keymap (keys.h, bt.h, modifiers.h)
├── boards/
│   ├── arm/nice_nano/          ← Definição da placa nice_nano_v2
│   └── shields/sofle/          ← Shields oficiais sofle_left e sofle_right
├── snippets/                   ← studio-rpc-usb-uart, zmk-usb-logging, etc.
└── src/
    ├── main.c                  ← Ponto de entrada do firmware
    ├── keymap.c                ← Resolução de camadas e bindings
    ├── combo.c                 ← Engine de combos
    ├── hid.c / usb_hid.c / hog.c ← Envio de relatórios HID (USB e BLE HOGP)
    ├── endpoints.c             ← Seleção e troca de saída (USB vs BLE)
    ├── usb.c / ble.c           ← Conectividade USB e Bluetooth (perfis, pareamento)
    ├── activity.c / pm.c       ← Controle de idle, sleep e deep sleep
    ├── event_manager.c         ← Barramento de eventos pub/sub do ZMK
    ├── behaviors/              ← Implementação de &kp, &mt, &lt, &mo, &bt, &bootloader...
    ├── display/                ← Framework de tela e widgets padrão
    ├── events/                 ← Definições de eventos (keycode, layer, battery, wpm...)
    ├── pointing/               ← Movimento/scroll de mouse e input processors
    ├── settings/               ← Persistência em flash (NVS)
    ├── split/                  ← Comunicação Central ↔ Periféricos (bluetooth/central.c, peripheral.c)
    └── studio/                 ← Servidor RPC do ZMK Studio (Protobuf/nanopb)
```

---

## 3. Fluxo de Trabalho Recomendado ao Editar o ZMK

Atualmente, `zmk-workspace\zmk` está no commit da tag `v0.3` (*detached HEAD*). Antes de fazer alterações, crie uma branch própria lá dentro:

```powershell
cd C:\Users\victor\Documents\GitHub\zmk-workspace\zmk
git checkout -b tergo-custom
```

A partir daí, o ciclo de desenvolvimento é super rápido:

1. Edite o(s) arquivo(s) desejado(s) em `C:\Users\victor\Documents\GitHub\zmk-workspace\zmk\app\src\...`
2. Volte para `zmk-config-tergo-sofle` e rode o build incremental (leva poucos segundos!):
   ```powershell
   .\local-build\build-local.ps1 -Target sofle_receptor_ABNT2_displayV2
   ```
   *(Se alterou algo nas metades, compile também `-Target sofle_esquerdo,sofle_direito`.)*
3. Coloque o `nice_nano_v2` em modo bootloader (no dongle, o combo das 2 primeiras + 2 últimas teclas da linha inferior, ou duplo clique no botão reset) e copie o `.uf2` de `build-artifacts\` para o drive removível.
4. Quando gostar do resultado, faça commit normalmente dentro de `zmk-workspace\zmk`:
   ```powershell
   cd C:\Users\victor\Documents\GitHub\zmk-workspace\zmk
   git status
   git diff
   git add -p
   git commit -m "Descreva sua alteracao no ZMK"
   ```

> **Atenção:** `west update` reseta projetos gerenciados pelo manifesto, mas **não** sobrescreve a pasta raiz `zmk/` quando `zmk/app` é o repositório de manifesto (`west init -l app`). Ainda assim, mantenha suas alterações em uma branch com commits!

---

## 4. Depurando no Hardware com Logs USB (`zmk-usb-logging`)

Quando você altera código C no ZMK, `LOG_INF(...)`, `LOG_WRN(...)` e `LOG_DBG(...)` são seus melhores amigos.

1. Compile o alvo com a flag `-UsbLogging`:
   ```powershell
   .\local-build\build-local.ps1 -Target sofle_receptor_ABNT2_displayV2 -UsbLogging
   ```
   *(Isso adiciona `-S zmk-usb-logging` em uma pasta de build separada `*_logging` e gera `build-artifacts\<alvo>_logging.uf2`, sem atrapalhar seu build normal.)*
2. Grave o `*_logging.uf2` no dongle (ou na metade conectada ao PC via USB).
3. Descubra a porta COM no PowerShell:
   ```powershell
   Get-CimInstance Win32_SerialPort | Select-Object DeviceID, Description
   ```
4. Abra o monitor serial usando o próprio Python do `zmk-workspace` (o `pyserial` já está instalado!):
   ```powershell
   C:\Users\victor\Documents\GitHub\zmk-workspace\.venv\Scripts\python.exe -m serial.tools.miniterm COM3 115200
   ```
   *(Substitua `COM3` pela porta detectada; saia com `Ctrl + ]`.)*

> **Nota sobre ZMK Studio + USB Logging:** Ambos usam USB CDC ACM. Se houver conflito de endpoints USB no dongle ao ativar os dois ao mesmo tempo, você pode testar temporariamente sem o snippet `studio-rpc-usb-uart` compilando manualmente com `west build -p -s app -d build/debug -b nice_nano_v2 -S zmk-usb-logging -- ...`.

---

## 5. Como Usar Seu ZMK Modificado na Pipeline da Nuvem (GitHub Actions)

Quando suas mudanças no ZMK estiverem prontas e você quiser que o GitHub Actions do `zmk-config-tergo-sofle` volte a gerar todos os 7 artefatos automaticamente na nuvem:

1. Faça um **Fork** de `https://github.com/zmkfirmware/zmk` na sua conta ou organização do GitHub (ex.: `TergoTeclados/zmk`).
2. Adicione o fork como remote no seu clone local e envie sua branch:
   ```powershell
   cd C:\Users\victor\Documents\GitHub\zmk-workspace\zmk
   git remote add meu-fork https://github.com/SEU-USUARIO/zmk.git
   git push -u meu-fork tergo-custom
   ```
3. Atualize o arquivo [`config/west.yml`](../config/west.yml) no `zmk-config-tergo-sofle` para apontar para o seu fork e branch:
   ```yaml
   manifest:
     remotes:
       - name: zmkfirmware
         url-base: https://github.com/zmkfirmware
       - name: meu-fork
         url-base: https://github.com/SEU-USUARIO
     projects:
       - name: zmk
         remote: meu-fork
         revision: tergo-custom
         import: app/west.yml
     self:
       path: config
   ```
4. Faça push no `zmk-config-tergo-sofle`: o GitHub Actions (`.github/workflows/build.yml`) lerá o novo `config/west.yml`, baixará o seu fork do ZMK na branch `tergo-custom` e compilará todos os `.uf2` na nuvem!
