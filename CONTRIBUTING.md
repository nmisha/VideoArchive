# Contributing

## Стиль кода

- PowerShell 5.1+ совместимость желательна.
- Предпочитать функции с понятными именами: `Get-VideoInfo`, `Invoke-Encode`, `Copy-Metadata`.
- Не делать один огромный скрипт.
- Не смешивать UI, анализ, кодирование и логирование в одной функции.
- Все внешние параметры должны приходить из JSON или CLI.

## Модули

Каждый модуль отвечает только за одну область.

- Config — загрузка настроек.
- Scanner — поиск файлов.
- MediaAnalyzer — MediaInfo.
- DecisionEngine — решение encode/skip.
- Encoder — NVEncC.
- Metadata — ExifTool.
- Logger — логи.
- ConsoleUI — вывод в консоль.
- Validator — проверка результата.

## Правила изменений

1. Сначала обновить TASKS.md.
2. Потом реализовать код.
3. Добавить или обновить тесты.
4. Обновить CHANGELOG.md.

## Тесты

Использовать Pester.

Минимум:

- MediaAnalyzer tests;
- DecisionEngine tests;
- Logger tests;
- Metadata command generation tests;
- Encoder argument generation tests.
