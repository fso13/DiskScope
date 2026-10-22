# CLI

`diskscope-cli` — headless-версия сканера для замеров, smoke-тестов и CI.

## Сборка

```bash
swift build -c release --product diskscope-cli
.build/release/diskscope-cli --help
```

## Примеры

```bash
# Человекочитаемый отчёт
.build/debug/diskscope-cli --limit 20 ~/Library

# JSON для CI
.build/debug/diskscope-cli --json --output size.json ~/Library

# Упасть, если скан больше 50 ГБ (exit 3)
.build/debug/diskscope-cli --json --budget 50GB --output size.json ~/Library

# Только файлы крупнее 1 МБ
.build/debug/diskscope-cli --json --min-size 1048576 ~/Projects
```

`--budget` принимает байты или десятичные единицы: `KB`, `MB`, `GB`, `TB`
(1 KB = 1000 байт). Можно писать `10GB`, `1.5 GB`, `500MB`.

## JSON

```json
{
  "schemaVersion": 1,
  "path": "/Users/me/Library",
  "totalBytes": 123456789,
  "totalHuman": "123,5 МБ",
  "files": 1234,
  "folders": 56,
  "nodes": 1290,
  "durationSeconds": 0.42,
  "scanner": "getattrlistbulk",
  "skippedItems": 0,
  "skippedMounts": 0,
  "hardLinkBytes": 0,
  "budget": {
    "limitBytes": 50000000000,
    "withinBudget": true,
    "exceededBy": 0
  },
  "topLevel": [
    {
      "name": "Caches",
      "path": "/Users/me/Library/Caches",
      "relativePath": "Caches",
      "bytes": 12345678,
      "human": "12,3 МБ",
      "isDirectory": true
    }
  ],
  "largest": []
}
```

- `totalBytes` — занятое место с учётом hard links; `human`/`totalHuman`
  зависят от локали и нужны только для людей.
- `topLevel` — дети корня, `largest` — крупнейшие объекты.
- `budget` отсутствует/`null`, если `--budget` не задан.
- `schemaVersion` увеличивается при несовместимом изменении полей.

## Коды выхода

| Код | Значение |
| --- | --- |
| `0` | Успех, бюджет не превышен |
| `1` | Неверные аргументы |
| `2` | Ошибка сканирования |
| `3` | Бюджет превышен |

В JSON-режиме отчёт всё равно записывается (в stdout или `--output`), а
сообщение о превышении уходит в stderr. Это позволяет CI сохранить артефакт и
затем упасть по коду 3.

## CI

```yaml
- name: Disk budget
  run: |
    .build/release/diskscope-cli \
      --json --budget 80GB --output disk.json "$HOME"
```

Для GitHub Actions артефакт `disk.json` можно сохранить через
`actions/upload-artifact`; бюджет удобно держать в переменной репозитория.

## Ограничения

- CLI не удаляет и не перемещает файлы.
- Для защищённых папок нужен Full Disk Access у терминала/CI-агента.
- `--min-size` меньше 64 КБ увеличивает память и время скана.
