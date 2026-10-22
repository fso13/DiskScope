# Автоматизация

DiskScope отдаёт три точки входа: **App Intents** для Shortcuts, **Finder
Quick Action** через Services и CLI. Всё выполняется локально.

## Shortcuts

В приложении зарегистрированы интенты:

| Интент | Что делает |
| --- | --- |
| **Scan folder with DiskScope** | Сканирует папку и возвращает размер, число файлов, папок, hard links и длительность |
| **Check folder budget** | Сканирует папку и сравнивает размер с бюджетом в байтах |

Порядок:

1. Откройте **Shortcuts** на Mac.
2. Создайте шорткат, добавьте действие **DiskScope → Scan folder with DiskScope**.
3. Выберите папку; при необходимости задайте **Budget (bytes)**.
4. Результат — `FolderScanEntity`: `summary.path`, `totalBytes`, `totalHuman`,
   `files`, `folders`, `hardLinkBytes`, `withinBudget`, `exceededBy`.

Пример: если `withinBudget` равно `false`, отправьте уведомление или запустите
очистку. Shortcuts не запускает приложение: интент работает в фоне.

## Finder Quick Action

В `Info.plist` объявлен сервис `Scan with DiskScope` для `public.folder`.
Чтобы включить его в Finder:

1. **Системные настройки → Клавиатура → Сочетания клавиш → Службы →
   Файлы и папки**.
2. Включите **Scan with DiskScope**.
3. В Finder нажмите на папку правой кнопкой → **Быстрые действия** (или
   **Службы**) → **Scan with DiskScope**.

Сервис активирует DiskScope, подставляет путь и запускает обычный скан.
Это не Finder Sync extension: отдельного расширения и дополнительных
разрешений не требуется.

## App Intents metadata

Интенты объявлены в `Sources/DiskScope/ScanIntents.swift`; `AppShortcutsProvider`
добавляет фразы:

- «Scan a folder with DiskScope»;
- «Scan <folder> with DiskScope»;
- «Check a folder budget with DiskScope».

Чтобы Shortcuts увидел новые интенты после обновления, перезапустите приложение
и, при необходимости, **Shortcuts → Обновить**.

## Ограничения

- Скан в Shortcuts использует `.balanced` (файлы меньше 64 КБ агрегируются).
- Для защищённых папок нужно выдать **Full Disk Access** самому DiskScope.
- Интенты не удаляют файлы и не меняют настройки.
