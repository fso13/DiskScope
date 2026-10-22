# Распространение

DiskScope собирается как universal-приложение (arm64 + x86_64) для macOS 14+.
Локальная сборка подписывается ad-hoc; релизная — Developer ID с нотаризацией,
Sparkle-обновлениями и Homebrew cask.

## Локальная сборка

```bash
./build.sh
open dist/DiskScope.dmg
```

`build.sh` создаёт `DiskScope.app`, ZIP и DMG. Без `SIGN_IDENTITY` подпись
ad-hoc: macOS может попросить подтвердить первый запуск.

## Developer ID и нотаризация

Нужны сертификат **Developer ID Application** и пароль приложения Apple ID.

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
APPLE_ID="you@example.com" \
APPLE_TEAM_ID="TEAMID" \
APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
  ./scripts/notarize.sh dist/DiskScope.app dist/DiskScope.dmg
```

Или используйте сохранённый профиль:

```bash
xcrun notarytool store-credentials DiskScope \
  --apple-id you@example.com --team-id TEAMID --password app-password
NOTARY_PROFILE=DiskScope ./scripts/notarize.sh
```

Скрипт отправляет DMG, ждёт результат, staple-ит app и DMG, проверяет
`stapler` и `spctl`. Для ZIP-архива приложение уже должно быть подписано и
нотаризовано до упаковки.

### Секреты GitHub Actions

| Секрет | Назначение |
| --- | --- |
| `MACOS_CERTIFICATE` | base64 от `.p12` с Developer ID Application |
| `MACOS_CERTIFICATE_PASSWORD` | пароль `.p12` |
| `APPLE_ID` | Apple ID для notarytool |
| `APPLE_TEAM_ID` | Team ID |
| `APPLE_APP_PASSWORD` | app-specific password |
| `SPARKLE_PUBLIC_KEY` | публичный EdDSA-ключ Sparkle |
| `SPARKLE_PRIVATE_KEY` | base64 файла приватного ключа Sparkle |

Без сертификата/секретов workflow собирает ad-hoc-артефакт и не запускает
нотаризацию — это удобно для форков и локальных прогонов.

## Sparkle

В приложение встроен `Sparkle.framework`; меню **DiskScope → Проверить
обновления…** открывает стандартный updater. Пока `SUPublicEDKey` равен
плейсхолдеру, Sparkle отключён и не показывает ошибку конфигурации.

### Ключи

На машине релиз-инженера:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys
```

Команда печатает публичный ключ и кладёт приватный в Keychain. Публичный ключ
передайте в `SPARKLE_PUBLIC_KEY` при сборке (или впишите в `Info.plist`),
приватный экспортируйте и положите в секрет:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle_private_key
base64 -i sparkle_private_key | pbcopy
```

`SUFeedURL` указывает на `.../releases/latest/download/appcast.xml`;
workflow загружает appcast в каждый релиз.

### Appcast

```bash
VERSION=1.2.0 ./scripts/generate-appcast.sh dist
```

Скрипт берёт `DiskScope-<version>-macos-universal.zip`, подписывает его ключом
из Keychain и создаёт `dist/appcast.xml`. В CI приватный ключ импортируется из
`SPARKLE_PRIVATE_KEY`; appcast загружается в релиз вместе с ZIP.

## Homebrew

Cask лежит в `Casks/diskscope.rb`:

```bash
brew install --cask ./Casks/diskscope.rb
```

Для установки из tap опубликуйте cask в `fso13/homebrew-diskscope`:

```bash
brew install --cask fso13/diskscope/diskscope
```

После релиза обновите версию и SHA-256:

```bash
VERSION=1.2.0 SHA256=$(awk 'NR==1 {print $1}' dist/SHA256SUMS.txt) \
  ./scripts/update-cask.sh
```

Workflow делает это автоматически и прикладывает обновлённый cask к артефактам.

## Проверка релиза

```bash
codesign --verify --deep --strict dist/DiskScope.app
spctl -a -vv --type execute dist/DiskScope.app
xcrun stapler validate dist/DiskScope.dmg
hdiutil verify dist/DiskScope.dmg
lipo -info dist/DiskScope.app/Contents/MacOS/DiskScope
```

## Ограничения

- Нотаризация требует активного Apple Developer Program.
- DMG создаётся через `hdiutil`; в ограниченной песочнице без доступа к
  дисковым устройствам этот шаг может быть недоступен — CI выполняется без
  такой песочницы.
- Sparkle обновляет только подписанные релизы с совпадающим публичным ключом.
