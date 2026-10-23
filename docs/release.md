<p class="eyebrow">CI / CD</p>

# CI и релизы

В проекте пять GitHub Actions workflow:

| Workflow | Файл | Когда запускается | Что делает |
| --- | --- | --- | --- |
| Release | `.github/workflows/release.yml` | push тега `v*` | тесты, universal-сборка, GitHub Release, артефакт |
| Documentation | `.github/workflows/pages.yml` | push в `main`/`master` (docs) или вручную | сборка MkDocs Material и деплой на GitHub Pages |
| Static Analysis | `.github/workflows/static-analysis.yml` | push/PR в `main`, по расписанию | SwiftLint и проверка компиляции |
| CodeQL | `.github/workflows/codeql.yml` | push/PR в `main`, по расписанию | статический security-анализ Swift |
| CVE Analysis | `.github/workflows/cve-analysis.yml` | push/PR в `main`, по расписанию | OSV-Scanner, Trivy и Dependency Review |

## Статический анализ

`static-analysis.yml` запускается на push/PR и раз в неделю.

- **SwiftLint** проверяет `Sources/` и `Tests/` по `.swiftlint.yml`.
  Предупреждения аннотируются в diff, ошибки валят job. JSON-отчёт
  сохраняется артефактом `swiftlint-report`.
- **Compiler** собирает проект через `swift build`, чтобы поймать ошибки
  компиляции независимо от тестов.
- Текущая конфигурация: 0 serious violations; style-предупреждения
  (`empty_count`, `optional_data_string_conversion`) остаются видимыми, но не
  блокируют merge.

## CodeQL

`codeql.yml` выполняет `security-and-quality` запросы для Swift на macOS.
Результаты публикуются в **Security → Code scanning**. Это отдельный
статический анализ безопасности, не заменяющий SwiftLint.

## CVE и зависимости

`cve-analysis.yml` — отдельный pipeline для CVE:

- **Dependency Review** на pull request — блокирует новые зависимости с
  уязвимостями high/critical;
- **OSV-Scanner** — сканирует зависимости через OSV.dev; на PR проверяет
  только новые уязвимости, на push/schedule делает полный скан и публикует
  SARIF в Code Scanning;
- **Trivy** — filesystem-скан library/OS-пакетов с `exit-code: 1` для
  critical/high;
- **Dependabot** (`.github/dependabot.yml`) следит за GitHub Actions и SwiftPM.

Все три pipeline независимы: падение CVE-скана не блокирует статический
анализ, и наоборот.

## Релиз по тегу

```bash
git tag -a v2.0.0 -m "DiskScope 1.1.1"
git push origin v2.0.0
```

После этого workflow:

1. клонирует репозиторий с полной историей;
2. печатает версии macOS, Swift и Xcode;
3. запускает `swift test`;
4. собирает universal-приложение (`arm64 + x86_64`) с версией из тега:
   `VERSION=2.0.0 BUILD_NUMBER=<run number> UNIVERSAL=1 ./build.sh`;
5. проверяет `codesign`, `lipo` и версию в `Info.plist`;
6. достаёт раздел `[2.0.0]` из `CHANGELOG.md` скриптом
   `scripts/release-notes.sh`; если раздела нет — собирает список коммитов из
   git;
7. добавляет в конец заметок блок «Скачать» с прямыми ссылками на собранные
   DMG/ZIP, страницу релиза, ссылку на CHANGELOG, SHA-256 и инструкцию по
   установке;
8. загружает версионированные DMG/ZIP и `SHA256SUMS.txt` в артефакты
   workflow;
9. явно создаёт (или обновляет) GitHub Release через `gh release create`:
   тело из CHANGELOG, DMG, ZIP и `SHA256SUMS.txt`; прямые ссылки на ассеты
   уже включены в описание.

Тег `v1.0.0-beta.1` автоматически помечается как prerelease, потому что
содержит дефис.

### Что попадает в Release

- `DiskScope-macos-universal.dmg` и версионированный DMG — установщик с
  приложением и ярлыком `Applications`;
- `DiskScope-macos-universal.zip` и версионированный ZIP — резервный архив;
- `appcast.xml` и `diskscope.rb` — при настроенных Sparkle и Homebrew;
- `SHA256SUMS.txt` — контрольные суммы DMG и ZIP;
- текст из `CHANGELOG.md` + инструкция по установке + прямые ссылки.

Версионированные `DiskScope-<version>-macos-universal.dmg` и
`DiskScope-<version>-macos-universal.zip` остаются в артефактах workflow.

### Ссылки в релизе

- **DMG:** `https://github.com/fso13/DiskScope/releases/download/<tag>/DiskScope-macos-universal.dmg`
- **ZIP:** `https://github.com/fso13/DiskScope/releases/download/<tag>/DiskScope-macos-universal.zip`
- **Страница релиза:** `https://github.com/fso13/DiskScope/releases/tag/<tag>`
- **CHANGELOG:** `https://github.com/fso13/DiskScope/blob/<tag>/CHANGELOG.md`

Прямые ссылки ведут на билд конкретного тега, а не на `latest`, поэтому
остаются рабочими для старых релизов.

### Постоянная ссылка

https://github.com/fso13/DiskScope/releases/latest/download/DiskScope-macos-universal.dmg

Она всегда указывает на последний **стабильный** релиз (prerelease-теги с
дефисом в `latest` не попадают). Именно эта ссылка используется на сайте
документации.

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
   git remote add origin git@github.com:fso13/DiskScope.git
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
4. Адрес сайта появится в выводе job `deploy` и в настройках Pages:
   https://fso13.github.io/DiskScope/.

### Адрес сайта

Workflow передаёт `MKDOCS_SITE_URL` и `MKDOCS_REPO_URL` из контекста GitHub,
поэтому `site_url`, ссылки на GitHub и кнопки редактирования подставляются
автоматически. Локально `mkdocs serve` использует `http://localhost:8000/`.

## Права и настройки репозитория

- **Actions → General → Workflow permissions**: достаточно «Read and write»
  для `GITHUB_TOKEN`, если организация не разрешает выдавать права на уровне
  job. В release.yml явно запрошено `contents: write`, в pages.yml —
  `pages: write` и `id-token: write`.
- Для публикации достаточно встроенного `GITHUB_TOKEN`; сертификат и Sparkle-ключи — опциональные секреты для подписи и обновлений.
- Для публикации релиза не требуется отдельный PAT.

## Подпись, нотаризация и Sparkle

Если в репозитории заданы секреты `MACOS_CERTIFICATE`,
`MACOS_CERTIFICATE_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID` и
`APPLE_APP_PASSWORD`, workflow:

1. импортирует Developer ID Application во временную keychain;
2. собирает приложение с `SIGN_IDENTITY` (hardened runtime, timestamp);
3. отправляет DMG в `notarytool`, staple-ит app и DMG, проверяет `spctl`;
4. пересобирает ZIP уже со stapled-приложением.

Без секретов собирается рабочий ad-hoc-артефакт. Для Sparkle добавьте
`SPARKLE_PUBLIC_KEY` и `SPARKLE_PRIVATE_KEY`; workflow сгенерирует
`appcast.xml` и загрузит его в релиз. Полная инструкция —
[Распространение](distribution.md).

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
| Приложение не открывается | Для нотаризованного релиза проверьте staple/`spctl`; локальная ad-hoc-сборка открывается через «Открыть» |
| Пустой Release body | раздел версии в `CHANGELOG.md` не найден — сработал fallback из git log |
