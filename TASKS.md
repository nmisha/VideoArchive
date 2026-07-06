# Tasks

## MVP v1.0 [Done]

- [x] Создать структуру проекта.
- [x] Разделить конфигурацию на `config.json`, `presets.json`, `smartskip.json`, `devices.json`.
- [x] Реализовать `Config.psm1`.
- [x] Реализовать `Scanner.psm1`.
- [x] Реализовать `MediaAnalyzer.psm1` через MediaInfo JSON.
- [x] Реализовать определение HDR/SDR.
- [x] Реализовать `DecisionEngine.psm1`.
- [x] Реализовать `Encoder.psm1` для NVEncC HEVC.
- [x] Реализовать `Metadata.psm1` через ExifTool.
- [x] Реализовать `Logger.psm1` для TXT/CSV/JSONL.
- [x] Реализовать `ConsoleUI.psm1`.
- [x] Собрать основной workflow в `VideoArchive.ps1`.
- [x] Добавить `VideoArchive.cmd`.
- [x] Добавить `README.md`.

## v1.1 - Smart Skip [Done]

- [x] Пропуск AV1.
- [x] Пропуск маленьких файлов.
- [x] Пропуск HEVC ниже bitrate threshold.
- [x] Пропуск существующих выходных файлов.
- [x] Флаг `-Force`.
- [x] Флаг `-NoSmartSkip`.
- [x] Флаг `-DryRun`.
- [x] Подробные причины skip.

## v1.2 - Validation [Done]

- [x] `Validator.psm1`.
- [x] Проверка разрешения.
- [x] Проверка FPS.
- [x] Проверка HDR.
- [x] Проверка аудио.
- [x] Проверка метаданных и дат файлов.
- [x] Ошибка, если HDR потерян.

## v1.3 - Resume

- [ ] Resume из JSONL/SQLite.
- [ ] Не начинать заново успешно обработанные файлы.
- [ ] Отдельный статус `Failed` / `Skipped` / `Encoded`.

## v1.4 - Better UI

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
- [ ] Drag and drop.
- [ ] История запусков.
- [ ] Просмотр логов.
- [ ] Настройка пресетов из интерфейса.
