---
hide:
  - navigation
  - toc
---

<section class="hero" aria-label="DiskScope">
<div class="hero-copy">
<p class="hero-role">macOS disk analyzer</p>
<h1 class="hero-name">DiskScope</h1>
<p class="hero-lead">Нативный анализатор диска: тепловая карта, крупнейшие файлы и очистка в Корзину. SwiftUI, APFS, без облака.</p>
<p class="hero-status"><span class="status-dot" aria-hidden="true"></span><span>v1.1.1 · macOS 14+ · universal</span></p>
<div class="hero-actions">
<a class="btn btn-primary" href="https://github.com/fso13/DiskScope/releases/latest/download/DiskScope-macos-universal.dmg">Скачать последний релиз</a>
<a class="btn btn-ghost" href="https://github.com/fso13/DiskScope/releases">Все релизы</a>
</div>
<nav class="hero-nav" aria-label="Разделы">
<a href="#features">Возможности</a>
<a href="#screenshots">Скриншоты</a>
<a href="#install">Установка</a>
<a href="usage.html">Документация</a>
</nav>
<div class="hero-meta" role="list">
<div role="listitem"><span>Архитектуры</span><strong>Apple · Intel</strong></div>
<div role="listitem"><span>Сканер</span><strong>getattrlistbulk</strong></div>
<div role="listitem"><span>Приватность</span><strong>Локально</strong></div>
</div>
</div>
<aside class="hero-panel" aria-hidden="true">
<div class="panel-bar">
<span class="panel-dots"></span>
<span class="panel-file">DiskScope.scan</span>
<span class="panel-lang">APFS</span>
</div>
<pre class="hero-code"><code><span class="c-line"><span class="c-cmt">$ diskscope scan ~/</span></span>
<span class="c-line"><span class="c-green">✓</span> 238 GB <span class="c-muted">·</span> 3.13M files <span class="c-muted">·</span> 554k dirs</span>
<span class="c-line"><span class="c-muted">├─</span> Documents <span class="c-cyan">87.1 GB</span></span>
<span class="c-line"><span class="c-muted">├─</span> Library <span class="c-cyan">83.2 GB</span></span>
<span class="c-line"><span class="c-muted">├─</span> Movies <span class="c-cyan">27.7 GB</span></span>
<span class="c-line"><span class="c-muted">├─</span> .gradle <span class="c-cyan">10.6 GB</span></span>
<span class="c-line"><span class="c-muted">├─</span> .m2 <span class="c-cyan">2.8 GB</span></span>
<span class="c-line"><span class="c-muted">├─</span> .vscode <span class="c-cyan">2.7 GB</span></span>
<span class="c-line"><span class="c-muted">├─</span> .cache <span class="c-cyan">1.8 GB</span></span>
<span class="c-line"><span class="c-muted">└─</span> Downloads <span class="c-cyan">2.6 GB</span></span>
<span class="c-line"> </span>
<span class="c-line"><span class="c-pink">largest</span> Cursor/state.vscdb <span class="c-yellow">16.2 GB</span></span>
<span class="c-line"><span class="c-muted">nodes</span> 1 061 194 <span class="c-muted">·</span> <span class="c-accent">treemap ready</span></span>
<span class="c-line"><span class="c-green">✓</span> scan completed <span class="c-muted">in 3m 56s</span><span class="c-cursor"></span></span></code></pre>
</aside>
</section>

!!! info "Аналог Disk Space Analyzer"
    DiskScope написан на SwiftUI и анализирует диск локально: файлы и
    результаты не отправляются в сеть. Сеть используется только для проверки
    обновлений по кнопке в настройках. Сторонних библиотек и демонов нет.
    Сканирование идёт напрямую через `getattrlistbulk` и `openat`.

<p class="eyebrow">Features</p>
## Возможности {#features}

<div class="grid cards" markdown>

-   **Быстрый скан**

    ---

    Один системный вызов на пачку файлов, обход на файловых дескрипторах,
    прогресс и отмена. На тёплом кэше — до ~170 000 объектов/с.

-   **Drag & drop**

    ---

    Перетащите папку в окно — скан начнётся сразу. Файл открывает свою папку.

-   **Тепловая карта**

    ---

    Два уровня treemap: размер прямоугольника равен месту на диске. Клик
    проваливает в папку, у больших папок видны вложенные элементы.

-   **Крупнейшие файлы**

    ---

    Файлы и приложения, отсортированные по размеру, с путём, долей и быстрыми
    действиями в Finder или Корзину.

-   **Типы и очистка**

    ---

    Видео, изображения, аудио, архивы, документы, код и приложения. Удаление —
    только по подтверждению, с мгновенным пересчётом дерева.

-   **Очистка по правилам**

    ---

    Кэши Xcode, старые установщики, бэкапы и Docker. Риск, цель по гигабайтам
    и отмена через `⌘Z`.

-   **Экспорт отчёта**

    ---

    CSV или HTML по текущей папке либо всему скану. Учитывает поиск и фильтры;
    HTML — один файл с топ-100.

-   **Коллекция**

    ---

    Кандидаты на удаление из разных папок в одном списке. `⌘`-клик на карте,
    `⌘6` — панель, удаление пачкой с отменой.

-   **Глобальный поиск**

    ---

    `⌘F` по имени или части пути, с фильтрами размера, типа, категории и даты.
    Индекс строится локально и только при первом открытии.

-   **Инспектор и QuickLook**

    ---

    `⌥⌘I` — путь, занятый и логический размер, даты. `Пробел` — быстрый
    просмотр; контекстные меню ведут в Finder, терминал и коллекцию.

-   **Медиа-поиск**

    ---

    Изображения, музыка, видео и документы (DOC/DOCX, PDF) по нескольким
    папкам. Выбор файлов и перенос в выбранную папку.

-   **В «Фото»**

    ---

    Выбранные изображения можно импортировать в медиатеку «Фото»;
    оригиналы перемещаются, а не копируются.

-   **Командная палитра**

    ---

    Все действия — скан, переходы, Finder, Корзина и настройки — через `⌘K`.

-   **Кастомное окно**

    ---

    Title bar с нативными traffic lights, статусом и командной палитрой —
    как в VS Code.

</div>

<p class="eyebrow">Install</p>
## Установка {#install}

[Скачать последний релиз](https://github.com/fso13/DiskScope/releases/latest/download/DiskScope-macos-universal.dmg){ .md-button .md-button--primary }
[Все релизы](https://github.com/fso13/DiskScope/releases){ .md-button }

Universal DMG для Apple Silicon и Intel, macOS 14+. Откройте образ с фирменным
фоном и перетащите `DiskScope.app` в «Программы». Подпись ad-hoc: при первом
запуске может понадобиться «Открыть» через контекстное меню.

1. Скачайте `DiskScope-macos-universal.dmg` и откройте образ.
2. Перетащите `DiskScope.app` в «Программы».
3. Для полного сканирования выдайте приложению «Полный доступ к диску» и
   перезапустите его.

Или соберите сами: `./build.sh` — [Сборка и тесты](build.md).

<p class="eyebrow">Gallery</p>
## Скриншоты {#screenshots}

<div class="screenshot-grid">
<figure>
<img src="assets/screenshots/01-map-light.png" alt="Карта папки в DiskScope">
<figcaption>Тепловая карта</figcaption>
</figure>
<figure>
<img src="assets/screenshots/03-largest.png" alt="Крупнейшие объекты в DiskScope">
<figcaption>Крупнейшие объекты</figcaption>
</figure>
<figure>
<img src="assets/screenshots/04-types.png" alt="Типы файлов в DiskScope">
<figcaption>Типы файлов</figcaption>
</figure>
<figure>
<img src="assets/screenshots/05-map-folder.png" alt="Вложенная карта папки">
<figcaption>Вложенная карта</figcaption>
</figure>
<figure>
<img src="assets/screenshots/14-cleanup-light.png" alt="Мастер очистки в DiskScope">
<figcaption>Очистка по правилам</figcaption>
</figure>
<figure>
<img src="assets/screenshots/16-inspector-light.png" alt="Инспектор файла в DiskScope">
<figcaption>Инспектор и быстрый просмотр</figcaption>
</figure>
</div>

<p class="eyebrow">Releases</p>
## Что нового {#releases}

Текущий релиз — **v1.1.1**. [Все релизы](https://github.com/fso13/DiskScope/releases) ·
[CHANGELOG](https://github.com/fso13/DiskScope/blob/main/CHANGELOG.md).

DiskScope сканирует диск локально, показывает карту и крупнейшие объекты,
считает типы файлов и умеет аккуратно перемещать выбранное в Корзину. Релизы
собираются автоматически по тегам, а этот сайт — из тех же Markdown-файлов.

<p class="eyebrow">License</p>
## Лицензия {#license}

MIT. Исходный код — в репозитории [fso13/DiskScope](https://github.com/fso13/DiskScope).
