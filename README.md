# JITerm — Linux-терминал для iPhone/iPad на JIT

JITerm — iOS-приложение с настоящим Linux внутри: **Alpine Linux 3.24 (aarch64)**, запущенный в
**QEMU с JIT-трансляцией (TCG)**. Python, vim, git, pip, `apk add` что угодно — как на обычном сервере.

```
root@jiterm:~# python3 -c 'import sys; print(sys.version)'
3.14.8 ...
root@jiterm:~# apk add gcc musl-dev    # любые пакеты Alpine
```

## Возможности

- **Полноценный Linux**: ядро 6.18, OpenRC, `apk`, интернет через NAT, 8 ГБ диска (занимает на
  iPhone только реально использованное место).
- **Предустановлено**: python3 + pip + venv, vim, nano, bash (+completion), git, curl, wget, tmux,
  htop, rsync, openssh-client, jq, tree, zip/unzip, man-страницы.
- **Выбор системы**: встроенный Alpine, а также **Debian 13** и **Arch Linux ARM** — ставятся из
  Alpine командой `jiterm-install debian|arch` (или кнопкой в «Настройки → Система») и загружаются
  вместо Alpine после перезапуска приложения. Alpine при этом остаётся.
- **Рабочий стол (DE/WM)**: `jiterm-desktop xfce|lxqt|openbox|i3` ставит окружение и X-сервер
  (TigerVNC), картинка показывается во вкладке «Экран» — касание = клик, долгое нажатие = правая
  кнопка, ведение = перетаскивание, щипок = масштаб, панель Ctrl/Alt/❖/F-клавиш. Работает в Alpine,
  Debian и Arch.
- **До 4 вкладок** — отдельные консоли Linux (системная `ttyAMA0` + `hvc0..hvc2`).
- **Удобная клавиатура**: панель Esc / Ctrl / Tab / стрелки, вставка (bracketed paste), щипок для
  изменения размера шрифта, автоматический ресайз — vim/htop/tmux сразу видят новый размер окна.
- **Общая папка** `~/shared` ↔ приложение «Файлы» → «На iPhone» → JITerm.
- **Проброс портов**: `python3 -m http.server 8000` → `http://localhost:8000` в Safari;
  опционально — доступ из локальной сети (например, `ssh` с компьютера).
- **Настройки**: 8 тем (Tokyo Night, Dracula, Gruvbox, Nord, Solarized, One Dark, Matrix…), шрифт,
  курсор, Option-как-Meta, память ВМ, ядра CPU, размер JIT-кэша, модель CPU, автовход, параметры ядра,
  сброс системы, журнал QEMU.

## Установка с CachyOS

Готовый неподписанный IPA собирает GitHub Actions (workflow `JITerm iOS (IPA)`) и выкладывает в релиз
**`jiterm-latest`** этого репозитория:
https://github.com/RBXLU/JITerm-ios/releases/download/jiterm-latest/JITerm.ipa

### 1. Подготовка компьютера

```bash
sudo pacman -S --needed usbmuxd libimobiledevice
sudo systemctl enable --now usbmuxd
```

Подключите iPhone по USB и нажмите «Доверять этому компьютеру».
На iPhone включите **Настройки → Конфиденциальность и безопасность → Режим разработчика**
(пункт появляется после первой установки приложения через сайдлоад; требуется перезагрузка).

### 2. Установка IPA (выберите один способ)

**Способ А — iloader + SideStore (рекомендуется).**
[iloader](https://github.com/nab138/iloader) — кроссплатформенный установщик (есть AppImage для Linux).
Войдите Apple ID, установите **SideStore** и **StikDebug**; iloader также кладёт на телефон
pairing-файл, нужный для включения JIT. Затем на iPhone: SideStore → «+» → выберите `JITerm.ipa`.
SideStore сам продлевает подпись каждые 7 дней (для бесплатного Apple ID).

**Способ Б — Plume Impactor.**
[Impactor](https://github.com/khcrysalis/Impactor) (AppImage/Flatpak) — войдите Apple ID, перетащите
`JITerm.ipa`, нажмите «Install». Продлевать подпись придётся вручную раз в 7 дней.

> Бесплатный Apple ID: до 3 приложений одновременно, подпись на 7 дней.

### 3. Включение JIT

iOS не даёт приложениям генерировать исполняемый код, поэтому при **каждом запуске** JITerm к нему
нужно подключить отладчик:

1. Откройте JITerm — появится экран «Включите JIT».
2. Нажмите **«Включить через StikDebug»** (или откройте StikDebug и выберите JITerm со скриптом
   **legacy** — он обрабатывает `brk #0x69` из QEMU и подготавливает JIT-память на iOS 26+).
   StikDebug нужен pairing-файл и LocalDevVPN — их проще всего получить через iloader.
3. Как только JIT включён, Linux загрузится сам (первая загрузка ~10–30 с).

Альтернативы: SideJITServer / JitStreamer с компьютера, запуск из Xcode на macOS.

> **iOS 26:** на устройствах с TXM (новые iPhone на iOS 26) классический способ JIT изменился.
> JITerm использует ту же сборку QEMU, что и UTM 5.0.7, и требует те же условия, что UTM. Если на
> вашем устройстве UTM с JIT не работает, JITerm тоже не запустится. Гарантированно работает на iOS 16–18.

## Использование

| Что | Как |
|---|---|
| Новая вкладка | «+» в верхней панели |
| Рабочий стол | вкладка «Экран» → XFCE / LXQt / Openbox / i3 (или `jiterm-desktop i3 1280x720`; `jiterm-desktop stop`) |
| Debian / Arch | «Настройки → Система → Установить…» (или `jiterm-install debian`), затем выбрать систему в «Загружать» и перезапустить приложение. `jiterm-install list` / `remove debian` |
| Вставить / Ctrl-C / Ctrl-D | меню «…» или панель над клавиатурой |
| Размер шрифта | щипок двумя пальцами или меню «…» |
| Перезагрузка / выключение | меню «…» → Система (или `reboot` / `poweroff`) |
| Файлы с iPhone | «Файлы» → «На iPhone» → JITerm ↔ `~/shared` |
| Веб-сервер | `python3 -m http.server 8000` → Safari: `http://localhost:8000` |
| SSH с компьютера | `apk add openssh && rc-service sshd start`, в настройках: проброс `2222:22` + «Доступ из локальной сети», затем `ssh -p 2222 root@<ip-iphone>` (сначала задайте `passwd`) |

`pip install` работает без venv (в образе разрешён `break-system-packages`), но venv тоже есть:
`python3 -m venv .venv && . .venv/bin/activate`.

После выключения Linux (`poweroff`) QEMU нельзя перезапустить в том же процессе — закройте приложение
из переключателя и откройте снова. Перезагрузка (`reboot`) работает без перезапуска приложения.

Когда приложение уходит в фон, iOS приостанавливает его — Linux «замирает» и продолжает работу при
возврате (часы гостя синхронизируются автоматически). Долгие задачи держите на экране (опция
«Не гасить экран» включена по умолчанию).

## Как это устроено

```
┌─────────────── JITerm.app (SwiftUI) ────────────────┐
│  SwiftTerm (вкладки 1–4) ──TCP 127.0.0.1──┐          │
│  канал управления (ресайз, часы) ─────────┤          │
│                                           ▼          │
│  qemu-aarch64-softmmu.framework (в потоке приложения)│
│   machine virt · cortex-a76 · TCG JIT (split-wx)    │
│   virtio-blk (rootfs.qcow2) · virtio-net (slirp)    │
│   virtio-9p (~/shared) · virtio-serial (hvc0..2)    │
└──────────────────────────────────────────────────────┘
                 Alpine Linux 3.24 aarch64
```

- **QEMU** берётся из официального `UTM.ipa` (v5.0.7, проверяется SHA-256): там он уже собран под iOS
  как динамическая библиотека с JIT. Скрипт `scripts/fetch-qemu.sh` вытаскивает
  `qemu-aarch64-softmmu.framework` и 24 зависимости (~54 МБ).
- Приложение загружает QEMU через `dlopen` и вызывает `qemu_init` / `qemu_main_loop` в отдельном потоке
  (`ios/Sources/Bridge/QemuBridge.c`), перехватывая `exit()` QEMU, чтобы не падало всё приложение.
- **Гостевая система** собирается скриптом `guest/build-guest.sh`: `apk.static` + qemu-user ставят
  пакеты в rootfs, затем `mkfs.ext4 -d` и сжатый qcow2. Ядро `linux-virt` грузится напрямую
  (`-kernel`/`-initrd`), его версия закреплена в `/etc/apk/world`, чтобы `apk upgrade` не ломал модули.
- **Агент** `jiterm-agent` в госте слушает virtio-порт `jiterm.control`: принимает размеры окон
  (`stty rows/cols` → SIGWINCH), время, `sync`/`reboot`/`poweroff` и сообщает `ready` после загрузки.

## Сборка

Всё собирается в GitHub Actions (`.github/workflows/build.yml`) при пуше в ветку `main`
или вручную (Run workflow):

1. **ubuntu-24.04**: `guest/build-guest.sh` → `vmlinuz-virt`, `initramfs-virt`, `rootfs.qcow2`, `guest.json`.
2. **macos-15**: `fetch-qemu.sh` → XcodeGen → `xcodebuild` (без подписи) → `package-ipa.sh`
   (фреймворки QEMU + фейковая подпись `ldid` с entitlements) → артефакт и релиз `jiterm-latest`.

Локально на CachyOS можно собрать и проверить гостевую систему:

```bash
sudo pacman -S --needed qemu-user-static qemu-user-static-binfmt qemu-img qemu-system-aarch64 e2fsprogs
sudo guest/build-guest.sh /tmp/jiterm-guest
qemu-system-aarch64 -machine virt -cpu cortex-a76 -m 1024 -nographic \
  -kernel /tmp/jiterm-guest/vmlinuz-virt -initrd /tmp/jiterm-guest/initramfs-virt \
  -append "root=/dev/vda rootfstype=ext4 modules=ext4 console=ttyAMA0" \
  -drive file=/tmp/jiterm-guest/rootfs.qcow2,if=virtio,format=qcow2 -nic user,model=virtio
```

Сам IPA требует macOS + Xcode (через Actions это не нужно).

## Структура

```
JITerm-ios/
├── guest/
│   ├── build-guest.sh          сборка Alpine-образа
│   └── overlay/                файлы, копируемые в rootfs (inittab, агент, профиль, motd…)
├── ios/
│   ├── project.yml             проект XcodeGen (SwiftTerm 1.10 через SPM)
│   ├── JITerm.entitlements     get-task-allow, increased-memory-limit
│   ├── Resources/              иконка, (Guest/ — кладёт CI)
│   └── Sources/
│       ├── App/                точка входа
│       ├── Bridge/             C-мост к QEMU, проверка JIT (CS_DEBUGGED)
│       ├── Core/               ВМ, аргументы QEMU, файлы, сеть, настройки, темы, системы
│       ├── Desktop/            VNC-клиент (RFB 3.8) и вкладка «Экран»
│       ├── Terminal/           вкладки на SwiftTerm, внешний вид
│       └── UI/                 экраны SwiftUI
└── scripts/
    ├── fetch-qemu.sh           QEMU-фреймворки из UTM.ipa
    └── package-ipa.sh          упаковка IPA
```

## Ограничения

- JIT нужно включать при каждом запуске приложения (ограничение iOS для сайдлоада).
- Эмуляция: скорость ниже нативной (порядка нескольких раз), но для Python, скриптов, git и
  редактирования кода — комфортно.
- Рабочий стол работает под эмуляцией без GPU — заметно медленнее нативного; лучше всего Openbox
  или i3, XFCE/LXQt — терпимо. GNOME/KDE формально можно поставить, но пользоваться ими нереально;
  Wayland-композиторы (Hyprland и т. п.) не работают — нет GPU/DRM. Нет звука и USB.
- Debian/Arch хранятся в Documents/.jiterm (диск разреженный, до 16 ГБ, исключён из бэкапа iCloud).
- Без entitlement'а увеличенной памяти iOS может закрыть приложение при большом объёме RAM ВМ —
  оставьте 1 ГБ, если такое происходит.

## Лицензии

QEMU — GPL v2 (исходники: https://github.com/utmapp/qemu), сборка QEMU для iOS — UTM (Apache 2.0),
SwiftTerm — MIT, Alpine Linux — свободные лицензии пакетов. Код JITerm — MIT (см. LICENSE).
