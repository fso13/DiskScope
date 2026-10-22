<p class="eyebrow">Build</p>

# Сборка и тесты

## Требования

- macOS 14 или новее;
- Xcode 15+ (Swift 5.9+) с установленными Command Line Tools;
- Python 3.10+ — только для локальной сборки документации.

## Сборка приложения

```bash
./build.sh
open dist/DiskScope.dmg
```

Скрипт собирает release-версию, создаёт `dist/DiskScope.app`, генерирует иконку
при необходимости, подписывает бандл ad-hoc и упаковывает `dist/DiskScope.dmg`
и `dist/DiskScope.zip`.

DMG — кастомный установщик для macOS: фирменный фон, `DiskScope.app` слева,
ярлык `Applications` справа и стрелка между ними. Откройте образ и перетащите
приложение в «Программы».

### Версия и архитектуры

```bash
VERSION=1.2.0 BUILD_NUMBER=57 UNIVERSAL=1 ./build.sh
```

- `VERSION` — значение `CFBundleShortVersionString` (по умолчанию `1.0`);
- `BUILD_NUMBER` — `CFBundleVersion` (по умолчанию `1`);
- `UNIVERSAL=1` — собрать universal-бинарник для Apple Silicon и Intel.
  Без флага собирается только архитектура текущей машины.

Проверить архитектуры можно так:

```bash
lipo -info dist/DiskScope.app/Contents/MacOS/DiskScope
```

!!! note "Подпись"
    Для локальной сборки используется ad-hoc подпись (`codesign --sign -`).
    Нотаризации нет, поэтому при первом запуске из скачанного архива macOS
    может предложить «Открыть» через контекстное меню. Для распространения
    лучше настроить Developer ID и notarization.

## Разработка

```bash
swift build
swift test
```

В `build.sh` SwiftPM запускается с `--disable-sandbox` и локальным кэшем
модулей — это нужно для ограниченных окружений. На обычной машине можно
использовать обычный `swift build`.

### CLI и PNG-снимки

```bash
.build/debug/diskscope-cli /Applications
.build/debug/diskscope-cli --json --budget 50GB --output size.json ~/Library
.build/debug/diskscope-cli --min-size 0 --limit 20 ~/Library
.build/debug/DiskScopeSnapshots snapshots /Applications
```

`diskscope-cli` печатает итоги скана и крупнейшие объекты, поддерживает
`--json` и `--budget` для CI (см. [CLI](cli.md)). `DiskScopeSnapshots`
рендерит реальные SwiftUI-экраны в PNG без разрешения на запись экрана.

## Документация

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements-docs.txt
.venv/bin/mkdocs serve
```

Сайт откроется на `http://127.0.0.1:8000/`. Проверка строгой сборки, как в CI:

```bash
MKDOCS_SITE_URL=http://localhost:8000/ .venv/bin/mkdocs build --strict
```

### Синхронизация скриншотов

Скриншоты для сайта лежат в `docs/assets/screenshots/` и копируются из
`snapshots/`:

```bash
./scripts/sync-docs-assets.sh
```

## Тесты

108 XCTest-тестов покрывают:

- сканер и точность суммы против `du`;
- агрегацию мелких файлов, пакеты, симлинки, Unicode-имена;
- отказ доступа, отмену, copy-on-write удаление;
- свойства squarified-раскладки и вложенные ячейки карты;
- полный цикл `AppModel`: скан → навигация → фильтры;
- медиа-поиск, переносы в папку и модель медиа-вкладки.

```bash
swift test
```

## Структура проекта

```
Sources/
  DiskScopeKit/
    Core/        сканер, дерево, форматирование, treemap-раскладка
    UI/          SwiftUI-интерфейс
    App/         AppModel
  DiskScope/     точка входа приложения
  DiskScopeCLI/  headless-сканер
  DiskScopeSnapshots/  рендер интерфейса в PNG
Tests/           XCTest
Support/         Info.plist и генератор иконки
docs/            исходники сайта (MkDocs Material)
scripts/         релизные заметки и синхронизация ассетов
build.sh         сборка, подпись, DMG и zip
```
