<p align="center">
  <img src="assets/icon.png" width="112" alt="DiskScope">
</p>

<h1 align="center">DiskScope</h1>

<p align="center">
  <strong>Нативный анализатор диска для macOS.</strong><br>
  Тепловая карта, крупнейшие файлы, типы, медиа-поиск и безопасная очистка.
</p>

<p align="center">
  <a href="https://github.com/fso13/DiskScope/releases/latest/download/DiskScope-macos-universal.dmg">
    <img src="https://img.shields.io/badge/Download-DMG-7c5cff?style=for-the-badge&logo=apple&logoColor=white" alt="Download DMG">
  </a>
  <a href="https://github.com/fso13/DiskScope/releases">
    <img src="https://img.shields.io/badge/Releases-GitHub-24292f?style=for-the-badge&logo=github" alt="Releases">
  </a>
  <a href="https://fso13.github.io/DiskScope/">
    <img src="https://img.shields.io/badge/Docs-Website-2ea44f?style=for-the-badge&logo=readthedocs&logoColor=white" alt="Docs">
  </a>
</p>

<p align="center">
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111827?style=flat-square&logo=apple">
  <img alt="Universal" src="https://img.shields.io/badge/universal-arm64%20%7C%20x86__64-7c5cff?style=flat-square">
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-native-0a84ff?style=flat-square">
  <img alt="Tests" src="https://img.shields.io/badge/tests-42-2ea44f?style=flat-square">
  <img alt="Version" src="https://img.shields.io/badge/version-1.1.1-7c5cff?style=flat-square">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-2ea44f?style=flat-square">
</p>

---

## Что такое DiskScope

DiskScope — нативное приложение для macOS, которое показывает, **что именно занимает место на диске**. Оно сканирует выбранную папку или весь том, строит интерактивную тепловую карту и помогает перейти к крупнейшим объектам.

Приложение не отправляет файлы и результаты сканирования в сеть. Единственный сетевой запрос — проверка обновлений по кнопке в настройках.

![Карта диска](assets/01-map-light.png)

## Что нового в 1.1.1

- **Настройки приложения** (`⌘,`): тема, подтверждение Корзины, сведения и проверка обновлений.
- **Проверка обновлений** через GitHub Releases: только вручную, с прямой ссылкой на DMG.
- **Защита от повторного анализа**: пока идёт сканирование, новый скан не запускается.
- **Кастомный DMG-лаунчер**: фирменный фон, стрелка и аккуратная раскладка иконок.
- **Кастомный title bar** в духе VS Code: нативные traffic lights, бренд, статус и палитра команд.
- 42 XCTest, включая сравнение версий и защиту от повторного скана.

Полная история — в [Changelog](Changelog).

## Возможности

| Возможность | Что делает |
| --- | --- |
| **Быстрый скан** | `getattrlistbulk` + `openat`, прогресс и отмена; миллионы файлов без лишней памяти |
| **Тепловая карта** | Двухуровневая squarified-карта; клик открывает папку, подсказки показывают размер и долю |
| **Крупнейшие объекты** | Файлы и приложения по размеру; `.app` считается одним объектом |
| **Типы файлов** | Видео, изображения, музыка, архивы, документы, код и другое |
| **Медиа-поиск** | Изображения, музыка, видео, документы, DOC/DOCX и PDF по выбранным папкам |
| **Очистка** | Finder и Корзина с подтверждением; дерево и суммы обновляются сразу |
| **Кастомное окно** | Нативные traffic lights, бренд, командная палитра `⌘K` и статус |
| **Настройки** | Тема, подтверждение Корзины, проверка обновлений и сведения |
| **Локальность** | Нет телеметрии; сеть — только для проверки обновлений по кнопке |
| **Universal** | Apple Silicon и Intel, macOS 14+ |

## Скриншоты

### Карта и крупнейшие объекты

![Карта](assets/01-map-light.png)

![Крупнейшие объекты](assets/03-largest.png)

### Медиа-поиск

![Медиа-поиск](assets/10-media-light.png)

### Настройки

![Настройки](assets/12-settings-light.png)

## С чего начать

| Шаг | Страница |
| --- | --- |
| Установить DiskScope | [Установка](Installation) |
| Сделать первый скан | [Быстрый старт](Quick-Start) |
| Разобраться в возможностях | [Возможности](Features) |
| Найти медиа и перенести файлы | [Медиа-поиск](Media-Search) |
| Настроить приложение и обновления | [Настройки и обновления](Settings-and-Updates) |
| Решить проблему | [Решение проблем](Troubleshooting) |

## Требования

- macOS 14 Sonoma или новее;
- Apple Silicon или Intel;
- около 5 МБ для приложения и DMG;
- для защищённых папок — «Полный доступ к диску».

## Приватность

DiskScope читает метаданные файлов локально. Он не отправляет имена, содержимое или результаты сканирования. Сеть используется только для проверки обновлений через GitHub API по явной кнопке. Подробнее — [Приватность и безопасность](Privacy-and-Security).

## Ссылки

- [Сайт документации](https://fso13.github.io/DiskScope/)
- [GitHub](https://github.com/fso13/DiskScope)
- [Релизы](https://github.com/fso13/DiskScope/releases)
- [Issues](https://github.com/fso13/DiskScope/issues)
- [CHANGELOG](https://github.com/fso13/DiskScope/blob/main/CHANGELOG.md)
