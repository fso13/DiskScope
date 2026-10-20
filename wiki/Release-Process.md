# Процесс релиза

## Текущая версия

**DiskScope 1.1.1**

- macOS 14+;
- Apple Silicon + Intel;
- 42 XCTest;
- DMG и ZIP;
- ad-hoc подпись без нотаризации.

## Перед релизом

1. Обновите `CHANGELOG.md` разделом `## [x.y.z]`.
2. Проверьте версию в `Support/Info.plist` и `build.sh`.
3. Запустите тесты:

   ```bash
   swift test
   ```

4. Проверьте сборку:

   ```bash
   VERSION=1.1.1 BUILD_NUMBER=1 UNIVERSAL=1 ./build.sh
   ```

5. Проверьте DMG, подпись и версию.
6. Обновите документацию и wiki при необходимости.

## Тег

```bash
git tag -a v1.1.1 -m "DiskScope 1.1.1"
git push origin v1.1.1
```

Тег запускает `.github/workflows/release.yml`.

## Что делает workflow

1. Клонирует репозиторий с тегами.
2. Печатает версии macOS, Swift и Xcode.
3. Запускает `swift test`.
4. Собирает universal-приложение с версией из тега.
5. Проверяет `codesign`, `lipo`, `Info.plist` и DMG.
6. Достаёт раздел `[x.y.z]` из `CHANGELOG.md`.
7. Добавляет в release notes:
   - блок «Скачать» с прямыми ссылками на DMG и ZIP;
   - страницу релиза;
   - ссылку на CHANGELOG;
   - SHA-256;
   - инструкцию по установке.
8. Загружает артефакты workflow.
9. Создаёт GitHub Release через `gh release create` с DMG, ZIP и `SHA256SUMS.txt`.

## Ассеты релиза

- `DiskScope-macos-universal.dmg` — кастомный установщик;
- `DiskScope-macos-universal.zip` — резервный архив;
- `SHA256SUMS.txt` — контрольные суммы;
- версионированные DMG/ZIP — в артефактах workflow.

## Прямые ссылки

Для тега `v1.1.1`:

- DMG: `https://github.com/fso13/DiskScope/releases/download/v1.1.1/DiskScope-macos-universal.dmg`
- ZIP: `https://github.com/fso13/DiskScope/releases/download/v1.1.1/DiskScope-macos-universal.zip`
- Релиз: `https://github.com/fso13/DiskScope/releases/tag/v1.1.1`

Постоянная ссылка на последний стабильный DMG:

https://github.com/fso13/DiskScope/releases/latest/download/DiskScope-macos-universal.dmg

## Release notes

Тело релиза берётся из раздела CHANGELOG. Если раздела нет, скрипт собирает список коммитов между предыдущим и текущим тегом.

## Проверка после релиза

- скачать DMG;
- открыть образ;
- перетащить приложение в «Программы»;
- запустить и проверить версию в настройках;
- проверить, что проверка обновлений видит релиз;
- проверить ссылки на сайте.

## Документация

После релиза обновите `docs/index.md`, скриншоты и, при необходимости, `wiki/`.

## Ограничения

- Нотаризация не настроена.
- Для Developer ID нужен отдельный сертификат и секреты CI.
- Wiki не публикуется автоматически; см. [Contributing](Contributing).
