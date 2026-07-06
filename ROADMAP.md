# Roadmap

## v1.0 - Working CLI [Done]

Цель: надежный консольный архиватор.

- Модульная PowerShell-архитектура.
- Анализ через MediaInfo.
- Кодирование HEVC через NVEncC.
- Копирование метаданных через ExifTool.
- Разделение HDR и SDR.
- Логи TXT, CSV и JSONL.

## v1.1 - Smart Processing [Done]

Цель: не перекодировать лишнее.

- Smart Skip.
- Пропуск AV1.
- Пороговые bitrate-решения для HEVC.
- DryRun.
- Force.
- Объяснимые решения encode/skip.

## v1.2 - Safety [Done]

Цель: не испортить архив.

- Validator.
- Проверка сохранения HDR.
- Проверка resolution и FPS.
- Проверка аудиодорожек.
- Проверка метаданных и дат файлов.
- Автоматическое удаление результата при failed validation.

## v1.3 - Resume and History

Цель: надежная обработка больших архивов.

- Resume.
- JSONL state.
- SQLite history.
- Retry failed jobs.

## v2.0 - Multi Encoder

Цель: поддержка разных аппаратных кодировщиков.

- NVENC HEVC.
- NVENC AV1.
- Intel QSV.
- AMD AMF.
- Software x265 fallback.

## v3.0 - GUI

Цель: удобное приложение.

- WPF/WinUI.
- Drag and drop.
- Preset editor.
- Job queue.
- Progress dashboard.
