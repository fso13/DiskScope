# Сборка из исходников

## Требования

| Компонент | Версия |
| --- | --- |
| macOS | 14+ |
| Xcode | 16.4+ |
| Swift | 5.9+ (Swift 6 toolchain поддерживается) |
| Python | 3.10+ только для документации |

## Клонирование

```bash
git clone https://github.com/fso13/DiskScope.git
cd DiskScope
```

## Сборка

```bash
swift build
swift run DiskScope
```

Для релизной universal-сборки:

```bash
VERSION=1.1.1 BUILD_NUMBER=1 UNIVERSAL=1 ./build.sh
```

`build.sh` создаёт:

- `dist/DiskScope.app`;
- `dist/DiskScope.zip`;
- `dist/DiskScope.dmg` — кастомный DMG-установщик.

DMG использует фон и Finder layout из `Support/dmg/`; сторонние инструменты не нужны.

## Тесты

```bash
swift test
```

Сейчас **42 XCTest**: сканер, агрегация, пакеты, Unicode, отказ доступа, отмена, удаление, раскладка карты, медиа-поиск, переносы, модель, защита от повторного скана и сравнение версий.

## Скриншоты

```bash
swift run DiskScopeSnapshots snapshots /Applications
```

Рендерятся:

- карта в светлой и тёмной теме;
- крупнейшие и типы;
- вложенная папка;
- welcome и scanning;
- медиа;
- настройки.

## Структура проекта

```text
Sources/
  DiskScope/            приложение
  DiskScopeKit/         ядро и UI
  DiskScopeCLI/         CLI для замеров
  DiskScopeSnapshots/   рендер PNG
Tests/
  DiskScopeKitTests/    XCTest
Support/                Info.plist, иконки, DMG-ассеты
docs/                   MkDocs
wiki/                   исходники этой wiki
build.sh                сборка app/zip/dmg
```

## CI

GitHub Actions на тег `v*`:

1. `swift test`;
2. universal-сборка;
3. проверка `codesign`, `lipo` и версии;
4. проверка DMG;
5. создание GitHub Release с описанием и ссылками.

Подробнее — [Процесс релиза](Release-Process).

## Нотаризация

Сейчас используется ad-hoc подпись. Для распространения нужен Apple Developer ID и notarization; в текущем workflow этого нет.

## Документация

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements-docs.txt
.venv/bin/mkdocs serve
```

## Wiki

Исходники wiki лежат в `wiki/`. Публикация:

```bash
./scripts/publish-wiki.sh
```

Скрипт требует, чтобы GitHub wiki была инициализирована первой страницей.
