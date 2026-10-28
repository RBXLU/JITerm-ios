# JITerm — установка на iPhone

Linux-терминал (Alpine Linux + Python, vim, git…) для iPhone/iPad.

---

## Что понадобится

| | Требование |
|---|---|
| 📱 Телефон | iPhone или iPad с **iOS 16 или новее** (проверено в симуляторе iPhone 11) |
| 💻 Компьютер | **Windows 10/11** или **Linux** (например, CachyOS) — нужен один раз для установки |
| 🔌 Кабель | USB-кабель для iPhone |
| 🍏 Apple ID | Любой, можно бесплатный. **Лучше завести отдельный**, не основной |
| 📶 Wi-Fi | На телефоне при включении JIT |
| 💾 Место | ~500 МБ на iPhone (приложение 143 МБ + сам Linux) |

> ⚠️ **iOS 26–27.** На iPhone с чипом A15 и новее (iPhone 13 и новее) JIT на iOS 26+ может не
> включиться. На iPhone 11/12 (A13/A14) шансы хорошие, но гарантии нет — проверяется только на устройстве.

---

## Ссылки для скачивания

| Что | Зачем | Ссылка |
|---|---|---|
| **JITerm.ipa** | само приложение | https://github.com/RBXLU/JITerm-ios/releases/tag/jiterm-latest |
| **iloader** | установщик для ПК (Windows/Linux) — ставит SideStore, StikDebug и pairing-файл | https://github.com/nab138/iloader/releases |
| **SideStore** | ставит IPA и сам продлевает подпись на телефоне | https://sidestore.io |
| **StikDebug** | включает JIT прямо на телефоне | https://github.com/StephenDev0/StikDebug |
| **LocalDevVPN** | нужен StikDebug и SideStore | App Store (поиск «LocalDevVPN») |
| **iTunes** (только Windows) | драйвер, чтобы ПК видел iPhone | https://www.apple.com/itunes/download/win64 — версия **с сайта Apple**, не из Microsoft Store |

Запасные варианты установщика: **Sideloadly** (Windows) — https://sideloadly.io,
**Plume Impactor** (Windows/Linux) — https://github.com/khcrysalis/Impactor/releases.

---

## Установка

### Шаг 1. Подготовка компьютера

**Windows 10/11**
1. Установите **iTunes с сайта Apple** (ссылка выше). Если стоит версия из Microsoft Store — удалите её.
2. Перезагрузите компьютер.

**Linux (CachyOS)**
```bash
sudo pacman -S --needed usbmuxd libimobiledevice
sudo systemctl enable --now usbmuxd
```

### Шаг 2. Подключите iPhone
1. Подключите кабелем, разблокируйте.
2. Нажмите **«Доверять этому компьютеру»** и введите код.

### Шаг 3. Установите SideStore и StikDebug через iloader
1. Скачайте и запустите **iloader**.
2. Войдите своим Apple ID.
3. Установите **SideStore** и **StikDebug**. iloader сам положит на телефон **pairing-файл**.
4. Из App Store установите **LocalDevVPN**.

### Шаг 4. Включите режим разработчика
iPhone: **Настройки → Конфиденциальность и безопасность → Режим разработчика → Вкл.**
Телефон перезагрузится — подтвердите включение.

### Шаг 5. Установите JITerm
1. На iPhone откройте ссылку на **JITerm.ipa** (см. выше) и скачайте файл
   (репозиторий приватный — нужно войти в GitHub).
2. Откройте **SideStore → «My Apps» → «+»** и выберите `JITerm.ipa`.
3. Дождитесь установки.

### Шаг 6. Первый запуск
1. Включите **LocalDevVPN**.
2. Откройте **JITerm** → нажмите **«Включить через StikDebug»** (кнопка сама выбирает нужный
   скрипт **legacy**). Если включаете JIT из StikDebug вручную — назначьте JITerm скрипт **legacy**,
   иначе на iOS 26+ Linux «зависнет» на загрузке.
3. Linux загрузится сам (первый раз ~20–40 с). Готово! 🎉

---

## Каждый следующий запуск (без компьютера)
1. Включить LocalDevVPN.
2. Открыть JITerm → «Включить через StikDebug».

**Каждые 7 дней** (бесплатный Apple ID): откройте SideStore → **Refresh All** — подпись продлится
прямо на телефоне. Компьютер не нужен.

**Компьютер снова понадобится**, только если pairing-файл перестанет работать
(например, после обновления iOS) — тогда повторите шаг 3.

---

## Первые команды
```bash
python3                      # Python
apk add <пакет>              # установить программу (gcc, nodejs, htop…)
pip install <пакет>          # Python-библиотека
vim файл.py                  # редактор
ls ~/shared                  # папка JITerm из приложения «Файлы»
python3 -m http.server 8000  # сайт → Safari: http://localhost:8000
```

---

## Если что-то не работает

| Проблема | Что делать |
|---|---|
| ПК не видит iPhone (Windows) | Поставьте iTunes с сайта Apple, переподключите кабель, нажмите «Доверять» |
| JITerm висит на экране «Включите JIT» | Включите Wi-Fi и LocalDevVPN; в StikDebug выберите JITerm вручную; если не помогло — заново создайте pairing-файл через iloader |
| JITerm вылетает сразу после включения JIT | Пришлите скриншот / «Журнал QEMU» (меню «…» в приложении) |
| Приложение перестало открываться через 7 дней | SideStore → Refresh All |
| iOS закрывает JITerm | В настройках JITerm уменьшите «Память» до 1 ГБ |

---

## Удаление iTunes (Windows), если он больше не нужен
**Пуск → Параметры → Приложения**, удалить по порядку: iTunes → iCloud → Apple Software Update →
Apple Mobile Device Support → Bonjour → Apple Application Support (32-бит) → Apple Application Support (64-бит).
JITerm и SideStore на телефоне продолжат работать. iTunes понадобится снова, только если придётся
пересоздавать pairing-файл.

---

## Безопасность — коротко
- Linux работает в «песочнице» приложения и не видит ваши фото, контакты и другие приложения.
- Используйте **отдельный Apple ID** для сайдлоада.
- Опцию «Доступ из локальной сети» включайте, только задав пароль в Linux командой `passwd`.
