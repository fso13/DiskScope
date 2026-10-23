# APFS-клоны: исследование

Дата: 2026-10. Проверено на macOS 27.0.1 (APFS, `clonefile`).

## Проблема

Клон APFS делит блоки с оригиналом. DiskScope, как и `du`, учитывает каждый
файл отдельно, поэтому две полные копии по 10 ГБ могут давать «20 ГБ», хотя
физически занято около 10 ГБ. Удаление одной копии освобождает 0 байт.

## Публичный API

В `sys/attr.h` есть расширенные атрибуты (`FSOPT_ATTR_CMN_EXTENDED`):

| Атрибут | Тип | Смысл |
| --- | --- | --- |
| `ATTR_CMNEXT_CLONEID` | `u_int64_t` | Идентификатор data stream; у полных клонов совпадает |
| `ATTR_CMNEXT_CLONE_REFCNT` | `u_int32_t` | Число полных клонов |
| `ATTR_CMNEXT_PRIVATESIZE` | `off_t` | Байты, освобождаемые при удалении файла (не входят в клоны/снимки) |
| `ATTR_CMNEXT_EXT_FLAGS` | `u_int64_t` | `EF_MAY_SHARE_BLOCKS` (0x1), `EF_SHARES_ALL_BLOCKS` (0x40) |

Поддержка тома — `VOL_CAP_FMT_CLONE_MAPPING` (0x04000000).

`getattrlist`/`getattrlistbulk` возвращают длину, затем `attribute_set_t`;
fork-атрибуты идут после common/file в порядке битов. `ATTR_CMN_RETURNED_ATTRS`
позволяет не парсить отсутствующие поля.

## Прототип

```bash
cp -c source.bin clone.bin   # clonefile
du -k source.bin clone.bin
swift scripts/clone-probe.swift
```

| Файл | cloneID | refcnt | private size | flags | du |
| --- | --- | --- | --- | --- | --- |
| обычный | уникальный | 1 | ≈ размер | 0 | 9,7 МБ |
| source (полный клон) | X | 2 | 0 | 0x41 | 9,7 МБ |
| clone (полный клон) | X | 2 | 0 | 0x41 | 9,7 МБ |
| source после append в clone | X | 1 | 8 КБ | 0x1 | 9,7 МБ |
| clone после append | Y | 1 | ≈1 МБ | 0x1 | 10,7 МБ |

Выводы:

- Полные клоны надёжно группируются по `CLONEID` + `REFCNT > 1`.
- `PRIVATESIZE` точно отвечает на вопрос «сколько освободится при удалении
  этого файла».
- После частичного изменения `CLONEID` расходится, `REFCNT` становится 1,
  остаётся только `EF_MAY_SHARE_BLOCKS`. Публичного API с картой частичных
  extents нет.
- Сумма `PRIVATESIZE` не равна физическому уникальному объёму: общие 10 ГБ
  не входят ни в один private size, пока живы оба файла.

## Решение

**Полный учёт клонов отложен.** Реализовывать приблизительный учёт опасно:
он покажет неверное «освободится» и может подтолкнуть удалить клон, который
ничего не освободит.

Сделано:

- в «Диске» добавлено предупреждение, что клоны считаются отдельными файлами;
- ограничение описано в [limitations](limitations.md);
- API зафиксировано здесь для будущей реализации.

## Что нужно для полного учёта

1. `cloneID`/`refcnt`/`privateSize` в `ScanNode` через расширенный
   `getattrlistbulk` (нужен отдельный парсер fork-атрибутов).
2. Группировка полных клонов и вычитание дублей из «занято», но с сохранением
   `PRIVATESIZE` для сценария удаления.
3. Для частичных extents — приватный `F_LOG2PHYS_EXT`/extent map или
   `fs_snapshot`-метаданные; публичного стабильного API не найдено.
4. Проверка на macOS 14/15/26 и на томах без `VOL_CAP_FMT_CLONE_MAPPING`.
5. Тесты: `cp -c`, частичная модификация, удаление одного клона, `du`.

## Ссылки

- `sys/attr.h`: `ATTR_CMNEXT_CLONEID`, `ATTR_CMNEXT_CLONE_REFCNT`,
  `ATTR_CMNEXT_PRIVATESIZE`, `VOL_CAP_FMT_CLONE_MAPPING`.
- `sys/stat.h`: `EF_MAY_SHARE_BLOCKS`, `EF_SHARES_ALL_BLOCKS`.
