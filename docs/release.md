# CI и релизы

В проекте два GitHub Actions workflow:

| Workflow | Файл | Когда запускается | Что делает |
| --- | --- | --- | --- |
| Release | `.github/workflows/release.yml` | push тега `v*` | тесты, universal-сборка, GitHub Release, артефакт |
| Documentation | `.github/workflows/pages.yml` | push в `main`/`master` (docs) или вручную | сборка MkDocs Material и деплой на GitHub Pages |

## Релиз по тегу

```bash
git tag -a v1.0.0 -m "DiskScope 1.0.0"
git push origin v1.0.0
```

После этого workflow:

1. клонирует репозиторий с полной историей;
2. печатает версии macOS, Swift и Xcode;
3. запускает `swift test`;
4. собирает universal-приложение (`arm64 + x86_64`) с версией из тега:
   `VERSION=1.0.0 BUILD_NUMBER=<run number> UNIVERSAL=1 ./build.sh`;
5. проверяет `codesign`, `lipo` и версию в `Info.plist`;
6. достаёт раздел `[1.0.0]` из `CHANGELOG.md` скриптом
   `scripts/release-notes.sh`; если раздела нет — собирает список коммитов из
   git;
7. добавляет в конец заметок инструкцию по установке и SHA-256 архива;
8. загружает `DiskScope-1.0.0-macos-universal.zip` и `SHA256SUMS.txt` в
   артефакты workflow;
9. создаёт (или обновляет) GitHub Release с этими файлами и описанием.

Тег `v1.0.0-beta.1` автоматически помечается как prerelease, потому что
содержит дефис.

### Что попадает в Release

- `DiskScope-<version>-macos-universal.zip` — приложение, подписанное ad-hoc;
- `SHA256SUMS.txt` — контрольная сумма архива;
- текст из `CHANGELOG.md` + инструкция по установке.

### Changelog

Формат — [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/). Перед
релизом добавьте раздел:

```markdown
## [1.2.0] - 2026-11-01

### Добавлено

- ...
```

Скрипт ищет строку `## [1.2.0]` и выводит всё до следующего заголовка `## [`.
Если раздела нет, release notes будут собраны из коммитов между предыдущим и
текущим тегом.

## Документация на GitHub Pages

### Как устроено

- Исходники сайта — `docs/*.md`, конфигурация — `mkdocs.yml`;
- тема — MkDocs Material, русская локализация, поиск, тёмная тема;
- сборка: `mkdocs build --strict`, артефакт `site/`;
- деплой: `actions/upload-pages-artifact` + `actions/deploy-pages`.

### Первый запуск

1. Создайте репозиторий на GitHub и запушьте код:

   ```bash
   git init
   git add .
   git commit -m "DiskScope 1.0.0"
   git branch -M main
   git remote add origin git@github.com:<owner>/<repo>.git
   git push -u origin main
   ```

2. Откройте **Settings → Pages**. В разделе **Build and deployment**
   выберите **Source: GitHub Actions**. Это нужно сделать один раз вручную:
   встроенный `GITHUB_TOKEN` не может включить Pages — для автоматического
   включения требуется отдельный PAT с правами `administration:write` и
   `pages:write`. Workflow использует `actions/configure-pages` уже после
   включения.
3. Запушьте изменения в `main` или запустите workflow вручную:
   **Actions → Documentation → Run workflow**.
4. Адрес сайта появится в выводе job `deploy` и в настройках Pages. Обычно это
   `https://<owner>.github.io/<repo>/`.

### Адрес сайта

Workflow передаёт `MKDOCS_SITE_URL` и `MKDOCS_REPO_URL` из контекста GitHub,
поэтому `site_url`, ссылки на GitHub и кнопки редактирования подставляются
автоматически. Локально `mkdocs serve` использует `http://localhost:8000/`.

## Права и настройки репозитория

- **Actions → General → Workflow permissions**: достаточно «Read and write»
  для `GITHUB_TOKEN`, если организация не разрешает выдавать права на уровне
  job. В release.yml явно запрошено `contents: write`, в pages.yml —
  `pages: write` и `id-token: write`.
- Секреты не нужны: используется встроенный `GITHUB_TOKEN`.
- Для публикации релиза не требуется отдельный PAT.

## Подпись и нотаризация

Сейчас приложение подписывается ad-hoc. Для публичного распространения
рекомендуется:

1. получить Developer ID Application;
2. подписывать `codesign --deep --force --options runtime --sign "Developer ID Application: ..."`;
3. прогнать `xcrun notarytool submit ... --wait` и `xcrun stapler staple`;
4. хранить сертификат и пароль в GitHub Secrets.

Это отдельный шаг; текущий workflow собирает рабочий артефакт для локальной
установки.

## Ручной запуск

- **Release** создаётся только тегом. Для повторной сборки перезапустите
  workflow из вкладки Actions: он обновит Release для того же тега.
- **Documentation** можно запустить вручную без новых коммитов — удобно после
  изменения настроек Pages.

## Диагностика

| Проблема | Что проверить |
| --- | --- |
| `Resource not accessible by integration` | права `contents: write` / настройки Actions |
| Pages не публикуются | Settings → Pages → Source = GitHub Actions |
| `mkdocs build --strict` падает | битые ссылки или отсутствующие изображения в `docs/` |
| Приложение не открывается | Gatekeeper: «Открыть» через контекстное меню; подпись ad-hoc |
| Пустой Release body | раздел версии в `CHANGELOG.md` не найден — сработал fallback из git log |
