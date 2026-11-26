# 02 — Preparação do Ambiente Local no Windows

## 1. Comparativo das Opções no Windows

Existem três maneiras de compilar o ZMK localmente no Windows:

| Abordagem | Prós | Contras |
| --- | --- | --- |
| **Nativo portável no Windows** *(configurado nesta máquina)* | Não exige Docker, WSL 2 nem permissão de administrador; rápido; ~5,5 GB em disco; fácil de editar `zmk/` direto no Windows/VS Code. | Exige alguns cuidados específicos do Windows (versões de `cmake`/`setuptools`/`protobuf` e ordem de `#include` no LVGL — já resolvidos neste guia e nos scripts). |
| **WSL 2 (Ubuntu)** | Ambiente Linux real; evita peculiaridades de caminhos `C:\` do Windows; ótimo para rodar testes unitários `native_posix`. | Exige instalar WSL 2 (`wsl --install`, privilégio de admin e reinicialização). |
| **Docker Desktop + VS Code Dev Containers** | Ambiente 100% idêntico ao container `zmkfirmware/zmk-build-arm:stable` do GitHub Actions. | Exige WSL 2 + Docker Desktop (mais consumo de RAM/disco e admin para instalar). |

Como esta máquina não possui WSL 2 nem Docker instalados — e já conta com `git`, `uv` e `tar` nativo do Windows — montamos o **ambiente nativo portável**, totalmente isolado em `C:\Users\victor\Documents\GitHub\zmk-workspace`.

---

## 2. O Que Foi Instalado (e Quanto Espaço Usa)

Tudo fica contido em uma única pasta externa ao repositório de configuração:

| Componente | Caminho em `zmk-workspace\` | Versão | Papel |
| --- | --- | --- | --- |
| Python + venv | `.venv\` | Python 3.12.13 | Ambiente isolado (evita quebras do Python 3.13 com Zephyr 3.5) |
| West | `.venv\Scripts\west.exe` | 1.5.0 | Gerenciador de workspace e build do Zephyr |
| CMake | `.venv\Scripts\cmake.exe` | 3.31.x (`<4`) | Gerador de build (CMake 4.x quebra módulos antigos do Zephyr 3.5) |
| Ninja | `.venv\Scripts\ninja.exe` | 1.13.x | Executor paralelo de compilação |
| Protobuf + setuptools | `.venv\` | `protobuf 5.x`, `setuptools <81` | Geração dos arquivos `.pb.c`/`.pb.h` do `nanopb` (ZMK Studio) |
| protoc | `tools\protoc\bin\protoc.exe` | 28.3 | Binário compilador de `.proto` para o `nanopb` |
| Zephyr SDK (minimal + ARM) | `tools\zephyr-sdk-0.16.8\` | 0.16.8 (`gcc 12.2.0`) | Cross-compiler `arm-zephyr-eabi-gcc` para nRF52840 (~67 MB compactado em vez de ~10 GB do SDK completo) |
| ZMK + Zephyr + Módulos | `zmk\` | ZMK `v0.3` / Zephyr `v3.5.0+zmk-fixes` | Código-fonte do firmware e bibliotecas HAL/LVGL/nanopb |

**Consumo total em disco:** ~5,5 GB (usando clones enxutos `--filter=tree:0` e SDK minimal apenas para ARM).

---

## 3. Setup Automatizado (Recomendado)

Para recriar o ambiente do zero em outra máquina Windows (ou atualizar dependências se algo for removido), basta ter `git`, `uv` e Windows 10/11 (`tar` nativo) e executar a partir da raiz do `zmk-config-tergo-sofle`:

```powershell
.\local-build\setup-env.ps1
```

Você também pode apontar para outro diretório ou para o **seu fork do ZMK**:

```powershell
.\local-build\setup-env.ps1 -WorkspacePath "C:\zmk-workspace" -ZmkRepoUrl "https://github.com/SEU-USUARIO/zmk.git" -ZmkRevision "sua-branch"
```

O script é idempotente: se rodar novamente, ele pula o que já está baixado e apenas atualiza o necessário.

---

## 4. Setup Manual Passo a Passo (Para Entender Tudo)

Caso queira saber exatamente o que o `setup-env.ps1` executa por baixo dos panos:

### Passo 1 — Criar o ambiente virtual Python 3.12 e instalar ferramentas base
```powershell
$ws = "C:\Users\victor\Documents\GitHub\zmk-workspace"
New-Item -ItemType Directory -Force -Path "$ws\tools" | Out-Null

uv venv --python 3.12 "$ws\.venv"
uv pip install --python "$ws\.venv\Scripts\python.exe" `
    west "cmake<4" ninja "setuptools<81" "protobuf>=4.25,<6" "grpcio-tools<1.72"
```

### Passo 2 — Baixar e extrair Zephyr SDK 0.16.8 (somente ARM) e `protoc`
```powershell
$tools = "$ws\tools"
Invoke-WebRequest "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.16.8/zephyr-sdk-0.16.8_windows-x86_64_minimal.7z" -OutFile "$tools\sdk.7z"
Invoke-WebRequest "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v0.16.8/toolchain_windows-x86_64_arm-zephyr-eabi.7z" -OutFile "$tools\arm.7z"
Invoke-WebRequest "https://github.com/protocolbuffers/protobuf/releases/download/v28.3/protoc-28.3-win64.zip" -OutFile "$tools\protoc.zip"

tar -xf "$tools\sdk.7z" -C "$tools"
tar -xf "$tools\arm.7z" -C "$tools\zephyr-sdk-0.16.8"
New-Item -ItemType Directory -Force -Path "$tools\protoc" | Out-Null
tar -xf "$tools\protoc.zip" -C "$tools\protoc"
Remove-Item "$tools\sdk.7z", "$tools\arm.7z", "$tools\protoc.zip"
```
*(O `tar.exe` embutido no Windows usa `libarchive` e extrai arquivos `.7z` e `.zip` nativamente, sem precisar instalar 7-Zip.)*

### Passo 3 — Clonar o ZMK `v0.3` e inicializar o workspace West
```powershell
$env:PATH = "$ws\.venv\Scripts;$ws\tools\protoc\bin;$env:PATH"

git clone --branch v0.3 https://github.com/zmkfirmware/zmk.git "$ws\zmk"
cd "$ws\zmk"

# Cria .west/ dentro de zmk/ apontando para o manifesto zmk/app/west.yml
west init -l app

# Baixa Zephyr v3.5.0+zmk-fixes, hal_nordic, lvgl, nanopb, zmk-studio-messages...
# --filter=tree:0 economiza tempo e vários GB de histórico Git
west update --fetch-opt=--filter=tree:0
```

> **Por que `west init -l app` dentro de `zmk/`?**
> O próprio `.gitignore` do repositório oficial do ZMK já ignora `/.west`, `/zephyr`, `/modules`, `/tools`, `/bootloader` e `/build`. Assim, `git status` dentro de `zmk\` continua 100% limpo mesmo com todo o ecossistema Zephyr dentro dele!

### Passo 4 — Registrar pacotes CMake e instalar dependências Python do Zephyr
```powershell
# Registra o Zephyr no registro de pacotes CMake do usuário (HKCU)
west zephyr-export

# Instala pyelftools, intelhex, anytree, pyserial, etc.
uv pip install --python "$ws\.venv\Scripts\python.exe" -r "$ws\zmk\zephyr\scripts\requirements-base.txt"

# Registra o Zephyr SDK no CMake do usuário (sem precisar do setup.cmd que exige wget)
cmake -P "$ws\tools\zephyr-sdk-0.16.8\cmake\zephyr_sdk_export.cmake"
```

---

## 5. Como Ativar o Ambiente Manualmente em um Terminal

Se quiser rodar comandos `west` manualmente (em vez de usar o `build-local.ps1`), basta executar estas 4 linhas na sua janela do PowerShell:

```powershell
$ws = "C:\Users\victor\Documents\GitHub\zmk-workspace"
$env:PATH = "$ws\.venv\Scripts;$ws\tools\protoc\bin;$env:PATH"
$env:ZEPHYR_TOOLCHAIN_VARIANT = "zephyr"
$env:ZEPHYR_SDK_INSTALL_DIR = "$ws\tools\zephyr-sdk-0.16.8"
cd "$ws\zmk"
```
