# VideoArchive

VideoArchive — универсальная PowerShell-утилита для интеллектуальной архивации видео с использованием NVIDIA NVENC через NVEncC.

Проект изначально появился как архиватор HDR-видео с Honor Magic 8 Pro, но архитектура рассчитана на любые источники: смартфоны, камеры, дроны, экшн-камеры, скачанные видео и домашние архивы.

## Что делает

- Рекурсивно обрабатывает файл или папку.
- Анализирует видео через MediaInfo CLI.
- Автоматически определяет HDR/SDR, HLG, HDR10, HDR10+, HDR Vivid, Dolby Vision.
- HDR кодирует в HEVC Main10 10-bit.
- SDR кодирует в HEVC Main 8-bit.
- Сохраняет исходное разрешение и FPS.
- Копирует аудио без перекодирования.
- Копирует метаданные через ExifTool.
- Восстанавливает даты файла Windows.
- Создает отдельные папки для HDR и SDR.
- Ведет TXT, CSV и JSONL логи.
- Поддерживает Smart Skip: пропуск AV1, маленьких файлов, уже эффективно сжатого HEVC и уже существующих результатов.

## Структура

```text
VideoArchive/
├── VideoArchive.ps1
├── VideoArchive.cmd
├── config.json
├── presets.json
├── smartskip.json
├── devices.json
├── Modules/
├── Tests/
├── Docs/
├── NVEncC/
├── ExifTool/
└── MediaInfo/
```

## Зависимости

Положить рядом с проектом:

```text
NVEncC/NVEncC64.exe
ExifTool/exiftool.exe
MediaInfo/MediaInfo.exe
```

## Запуск

Интерактивно:

```powershell
.\VideoArchive.cmd
```

или:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\VideoArchive.ps1
```

С параметрами:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\VideoArchive.ps1 "D:\PhoneVideo" -Preset Balanced
```

Принудительно перекодировать всё:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\VideoArchive.ps1 "D:\PhoneVideo" -Preset Archive -Force
```

Пробный запуск без кодирования:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\VideoArchive.ps1 "D:\PhoneVideo" -DryRun
```

## Пресеты

- `Archive` — максимальное качество.
- `Balanced` — рекомендуемый баланс качества, скорости и размера.
- `Fast` — быстрое кодирование.
- `Storage` — максимальная экономия места.

## Важное

VideoArchive не меняет разрешение и FPS. Если исходник 3840×2160 59.94 FPS, результат остается 3840×2160 59.94 FPS.
