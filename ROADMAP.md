# Roadmap

## v1.0 — Working CLI

Цель: надежный консольный архиватор.

- Модульная PowerShell-архитектура.
- MediaInfo анализ.
- NVEncC HEVC кодирование.
- ExifTool metadata copy.
- HDR/SDR split.
- TXT/CSV/JSONL logs.

## v1.1 — Smart Processing

Цель: не перекодировать лишнее.

- Smart Skip.
- AV1 skip.
- HEVC bitrate thresholds.
- DryRun.
- Force.
- Explainable decisions.

## v1.2 — Safety

Цель: не испортить архив.

- Validator.
- Проверка HDR preservation.
- Проверка resolution/FPS.
- Проверка аудио.
- Проверка метаданных.
- Автоматическое удаление результата при failed validation.

## v1.3 — Resume and History

Цель: надежная обработка больших архивов.

- Resume.
- JSONL state.
- SQLite history.
- Failed jobs retry.

## v2.0 — Multi Encoder

Цель: поддержка разных аппаратных кодировщиков.

- NVENC HEVC.
- NVENC AV1.
- Intel QSV.
- AMD AMF.
- Software x265 fallback.

## v3.0 — GUI

Цель: удобное приложение.

- WPF/WinUI.
- Drag & drop.
- Preset editor.
- Job queue.
- Progress dashboard.
