# Tasks

## MVP v1.0

- [ ] Создать структуру проекта.
- [ ] Разделить конфигурацию на config.json, presets.json, smartskip.json, devices.json.
- [ ] Реализовать Config.psm1.
- [ ] Реализовать Scanner.psm1.
- [ ] Реализовать MediaAnalyzer.psm1 через MediaInfo JSON.
- [ ] Реализовать определение HDR/SDR.
- [ ] Реализовать DecisionEngine.psm1.
- [ ] Реализовать Encoder.psm1 для NVEncC HEVC.
- [ ] Реализовать Metadata.psm1 через ExifTool.
- [ ] Реализовать Logger.psm1 для TXT/CSV/JSONL.
- [ ] Реализовать ConsoleUI.psm1.
- [ ] Собрать основной workflow в VideoArchive.ps1.
- [ ] Добавить VideoArchive.cmd.
- [ ] Добавить README.md.

## v1.1 — Smart Skip

- [ ] Пропуск AV1.
- [ ] Пропуск маленьких файлов.
- [ ] Пропуск HEVC ниже bitrate threshold.
- [ ] Пропуск существующих выходных файлов.
- [ ] Флаг `-Force`.
- [ ] Флаг `-NoSmartSkip`.
- [ ] Флаг `-DryRun`.
- [ ] Подробные причины skip.

## v1.2 — Validation

- [ ] Validator.psm1.
- [ ] Проверка разрешения.
- [ ] Проверка FPS.
- [ ] Проверка HDR.
- [ ] Проверка аудио.
- [ ] Проверка метаданных даты.
- [ ] Ошибка, если HDR потерян.

## v1.3 — Resume

- [ ] Resume из JSONL/SQLite.
- [ ] Не начинать заново успешно обработанные файлы.
- [ ] Отдельный статус Failed/Skipped/Encoded.

## v1.4 — Better UI

- [ ] Прогресс-бар.
- [ ] ETA.
- [ ] Скорость.
- [ ] Размер до/после по каждому файлу.
- [ ] Итоговая статистика по HDR/SDR/кодекам.

## v2.0

- [ ] AV1 NVENC.
- [ ] Intel QSV.
- [ ] AMD AMF.
- [ ] Несколько GPU.
- [ ] Очередь задач.
- [ ] SQLite база.

## v3.0

- [ ] GUI.
- [ ] Drag & drop.
- [ ] История запусков.
- [ ] Просмотр логов.
- [ ] Настройка пресетов из интерфейса.
