# Architecture

## Общий пайплайн

```text
Console UI
   ↓
Config Loader
   ↓
Scanner
   ↓
Media Analyzer
   ↓
Decision Engine
   ↓
Encoder
   ↓
Metadata Copier
   ↓
Validator
   ↓
Logger
```

## Модули

### Config.psm1

Отвечает за загрузку:

- config.json;
- presets.json;
- smartskip.json;
- devices.json.

Не должен содержать бизнес-логику кодирования.

### Scanner.psm1

Отвечает за поиск файлов.

Вход:

- файл;
- папка.

Выход:

- список `VideoFile`.

Не анализирует HDR/SDR.

### MediaAnalyzer.psm1

Использует MediaInfo CLI.

Возвращает объект `VideoInfo`.

Пример:

```powershell
[pscustomobject]@{
    Path        = "D:\Video\VID.mp4"
    Codec       = "HEVC"
    Width       = 3840
    Height      = 2160
    Fps         = 59.94
    BitDepth    = 10
    BitrateMbps = 77.2
    Transfer    = "HLG"
    Primaries   = "BT.2020"
    Matrix      = "BT.2020 non-constant"
    HDRFormat   = "HDR Vivid"
    IsHdr       = $true
    HdrType     = "HLG"
}
```

### DecisionEngine.psm1

Принимает `VideoInfo` и правила Smart Skip.

Возвращает `Decision`.

```powershell
[pscustomobject]@{
    Action = "Encode" # Encode | Skip
    Reason = "HEVC 77 Mbps > 35 Mbps threshold"
    OutputGroup = "HDR"
}
```

DecisionEngine ничего не знает о параметрах NVEncC.

### Encoder.psm1

Принимает `EncodeJob`.

Возвращает `EncodeResult`.

```powershell
[pscustomobject]@{
    Success = $true
    ExitCode = 0
    OutputFile = "..."
    Duration = "00:01:33"
}
```

### Metadata.psm1

Копирует метаданные через ExifTool.

Не должен знать, HDR это или SDR.

### Validator.psm1

Проверяет результат после кодирования:

- файл существует;
- размер > 0;
- разрешение совпадает;
- FPS совпадает;
- HDR не потерян;
- битность для HDR = 10;
- аудио дорожки сохранены.

### Logger.psm1

Пишет:

- TXT;
- CSV;
- JSONL.

### ConsoleUI.psm1

Только интерфейс:

- меню;
- прогресс;
- ETA;
- итоговая сводка.

## Правила зависимости

Модули не должны импортировать друг друга хаотично.

Главный скрипт `VideoArchive.ps1` orchestrates modules.

Предпочтительный поток данных:

```text
VideoArchive.ps1 owns the workflow
Modules are pure helpers where possible
```

## Объекты данных

### VideoInfo

Результат анализа.

### EncodeDecision

Решение: кодировать или пропустить.

### EncodeJob

Полный набор параметров для кодирования.

### EncodeResult

Итог кодирования.

### LogRecord

Единая структура для CSV/JSONL.
