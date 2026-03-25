# 🐸 CroakVPN — macOS Client

VPN клиент для macOS на Swift + SwiftUI.  
Бэкенд — **sing-box**, подписки через **Marzban** (VLESS).

## Сборка через GitHub Actions (с Windows)

Вам **не нужен Mac**. Всё собирается в облаке GitHub.

### Быстрый старт (5 минут)

**1. Создайте репозиторий на GitHub**
- Откройте [github.com/new](https://github.com/new)
- Имя: `CroakVPN` (или любое)
- Приватный или публичный — на ваш выбор
- **Не** ставьте галочку «Add README» (мы пушим свой)

**2. Склонируйте и запушьте этот проект**

```bash
# Установите Git для Windows: https://git-scm.com/download/win
# Откройте Git Bash или PowerShell

git init CroakVPN
cd CroakVPN

# Скопируйте ВСЕ файлы из этого архива в папку CroakVPN
# (project.yml, .github/, CroakVPN/, .gitignore, README.md)

git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/CroakVPN.git
git push -u origin main
```

**3. Дождитесь сборки**
- Откройте ваш репозиторий на GitHub
- Перейдите во вкладку **Actions**
- Увидите запущенный workflow «Build CroakVPN macOS»
- Через ~5-10 минут появится зелёная галочка ✅

**4. Скачайте готовое приложение**
- Нажмите на завершённый workflow
- Внизу страницы — раздел **Artifacts**
- Скачайте `CroakVPN-macOS.zip`
- Передайте .zip на Mac, распакуйте, запустите CroakVPN.app

### Создание релиза

Чтобы автоматически создать Release с приложением:

```bash
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions соберёт приложение и прикрепит .zip к Release.

### Обновление sing-box версии

В файле `.github/workflows/build.yml` измените переменную:
```yaml
env:
  SINGBOX_VERSION: "1.11.4"  # ← поменяйте на нужную версию
```

## Структура проекта

```
CroakVPN/
├── .github/workflows/build.yml    # CI/CD — сборка на GitHub
├── .gitignore
├── project.yml                     # XcodeGen — генерирует .xcodeproj
├── README.md
└── CroakVPN/
    ├── CroakVPN.entitlements       # Разрешения приложения
    ├── Sources/                    # Все Swift файлы
    │   ├── CroakVPNApp.swift
    │   ├── ContentView.swift
    │   ├── SubscriptionSetupView.swift
    │   ├── SettingsView.swift
    │   ├── MenuBarView.swift
    │   ├── AppViewModel.swift
    │   ├── SingBoxManager.swift
    │   ├── Models.swift
    │   ├── VLESSParser.swift
    │   ├── ConfigGenerator.swift
    │   ├── SubscriptionRepo.swift
    │   └── PrefsManager.swift
    └── Resources/                  # sing-box скачивается в CI
```

## Фичи

- ✅ Подключение/отключение VPN через sing-box
- ✅ Статистика трафика (скорость, время)
- ✅ Настройки (обновить/удалить подписку)
- ✅ Menubar иконка (tray) со статусом
- ✅ Тёмная тема, дизайн как у Windows клиента
- ✅ VLESS + Reality/TLS, tcp/ws/grpc
- ✅ Auto URL-test при множестве серверов
- ✅ Автосборка через GitHub Actions

## Как это работает

1. Пользователь вводит URL подписки из @croakvpnbot
2. Приложение загружает и декодирует base64 от Marzban
3. Парсит vless:// строки → генерирует конфиг sing-box
4. Запускает sing-box как фоновый процесс
5. Статистика трафика через Clash API (127.0.0.1:9090)

## Примечания

- Сборка бесплатна (GitHub даёт 2000 минут/месяц для приватных репо, безлимит для публичных)
- Приложение **не подписано** — при первом запуске на Mac нужно: ПКМ → Открыть → Открыть
- Для полноценной подписи нужен Apple Developer аккаунт ($99/год)
- sing-box бандлится прямо в .app (скачивается в CI)
