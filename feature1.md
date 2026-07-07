Прочитай текущий проект VideoArchive и внеси изменения в пресеты, Encoder, MediaAnalyzer и Validator.

Контекст:
Я сравнил оригинальное HDR-видео Honor HDR Vivid / HLG и перекодированный файл. Результат хороший: сохранились HEVC, 10 bit, 3840x2160, rotation 90°, BT.2020, HLG, BT.2020 non-constant, Limited range, AAC 256, GPS и даты. Размер уменьшился примерно с 70.4 MB до 41 MB.

Проблема:
HDR Vivid metadata после перекодирования исчезают. Это ожидаемо: NVEncC не сохраняет CUVA / HDR Vivid metadata. Но базовый HLG HDR должен сохраняться обязательно.

Нужно улучшить проект так, чтобы:
1. Пресеты были более качественными.
2. Encoder явно использовал расширенные параметры NVEncC.
3. Аудио всегда копировалось без перекодирования.
4. MediaAnalyzer различал не просто HDR/SDR, а конкретный тип HDR.
5. Validator после кодирования проверял, что ключевые характеристики не потерялись.

Файлы, которые нужно изменить:
- presets.json
- Modules/Encoder.psm1
- Modules/MediaAnalyzer.psm1
- Modules/Validator.psm1
- Modules/DecisionEngine.psm1, если потребуется
- TASKS.md / CHANGELOG.md, если в проекте они есть

---

## 1. Обновить presets.json

Заменить пресеты на такие:

{
  "Archive": {
    "description": "Maximum quality for long-term archive",
    "qvbrHdr": 18,
    "qvbrSdr": 19,
    "nvPreset": "p7",
    "lookahead": 32,
    "multipass": "2pass-full",
    "aqStrength": 8,
    "bFrames": 4,
    "refFrames": 4,
    "spatialAQ": true,
    "temporalAQ": true,
    "adaptiveI": true,
    "adaptiveB": true,
    "strictGop": false
  },
  "Balanced": {
    "description": "Recommended balance",
    "qvbrHdr": 19,
    "qvbrSdr": 20,
    "nvPreset": "p5",
    "lookahead": 24,
    "multipass": "2pass-quarter",
    "aqStrength": 8,
    "bFrames": 4,
    "refFrames": 4,
    "spatialAQ": true,
    "temporalAQ": true,
    "adaptiveI": true,
    "adaptiveB": true,
    "strictGop": false
  },
  "Fast": {
    "description": "Fast encode",
    "qvbrHdr": 20,
    "qvbrSdr": 21,
    "nvPreset": "p4",
    "lookahead": 8,
    "multipass": "none",
    "aqStrength": 8,
    "bFrames": 3,
    "refFrames": 3,
    "spatialAQ": true,
    "temporalAQ": true,
    "adaptiveI": true,
    "adaptiveB": true,
    "strictGop": false
  },
  "Storage": {
    "description": "Maximum compression",
    "qvbrHdr": 21,
    "qvbrSdr": 22,
    "nvPreset": "p5",
    "lookahead": 24,
    "multipass": "2pass-quarter",
    "aqStrength": 8,
    "bFrames": 4,
    "refFrames": 4,
    "spatialAQ": true,
    "temporalAQ": true,
    "adaptiveI": true,
    "adaptiveB": true,
    "strictGop": false
  }
}

---

## 2. Обновить Encoder.psm1

Encoder должен строить команду NVEncC на основе новых полей пресета.

Для HDR использовать:

- HEVC
- Main10
- 10 bit
- qvbrHdr
- transfer auto
- colorprim auto
- colormatrix auto

Для SDR использовать:

- HEVC
- Main
- 8 bit
- qvbrSdr

Общие параметры:

- --preset из nvPreset
- --multipass, если не "none"
- --lookahead
- --aq, если spatialAQ=true
- --aq-temporal, если temporalAQ=true
- --aq-strength
- --bframes
- --ref
- --gop-len auto
- --audio-copy
- --chapter-copy

Если NVEncC поддерживает эти параметры в установленной версии, добавить:
- --weightp
- --aud
- --repeat-headers

Важно:
Если какой-то параметр NVEncC не поддерживается, код не должен падать в будущем. Лучше вынести optional параметры в конфиг или сделать комментарий/TODO.

Не перекодировать звук. Никаких AAC encode. Только audio copy.

---

## 3. Обновить MediaAnalyzer.psm1

Сейчас проект должен определять не только IsHdr=true/false, а ещё HdrType.

Добавить поля в VideoInfo:

- IsHdr
- HdrType
- Transfer
- Primaries
- Matrix
- HDRFormat
- DolbyVisionProfile, если MediaInfo отдаёт
- BitDepth
- Codec
- Width
- Height
- Fps
- Rotation
- ColorRange
- AudioCodec
- AudioChannels
- AudioSamplingRate

HdrType должен быть одним из:

- "SDR"
- "HLG"
- "PQ"
- "HDR10"
- "HDR10+"
- "HDR Vivid"
- "Dolby Vision"
- "Unknown HDR"

Правила:
- Если HDR_Format содержит "HDR Vivid" или "CUVA" -> HdrType = "HDR Vivid", IsHdr=true.
- Если HDR_Format содержит "Dolby Vision" -> HdrType = "Dolby Vision", IsHdr=true.
- Если HDR_Format содержит "HDR10+" или "SMPTE ST 2094" -> HdrType = "HDR10+", IsHdr=true.
- Если HDR_Format содержит "HDR10" -> HdrType = "HDR10", IsHdr=true.
- Если Transfer содержит "HLG" или "ARIB STD B67" -> HdrType = "HLG", IsHdr=true.
- Если Transfer содержит "PQ" или "SMPTE ST 2084" -> HdrType = "PQ", IsHdr=true.
- Если Primaries содержит BT.2020 and BitDepth >= 10 -> HdrType = "Unknown HDR", IsHdr=true.
- Иначе SDR.

Важно:
Honor HDR Vivid обычно имеет:
- HDR format: HDR Vivid
- Transfer: HLG
- Primaries: BT.2020
- Matrix: BT.2020 non-constant

После перекодирования HDR Vivid metadata исчезнут, но HLG должен остаться. Validator должен считать это допустимым downgrade: HDR Vivid -> HLG.

---

## 4. Добавить / обновить Validator.psm1

После каждого успешного кодирования нужно анализировать оригинал и результат через MediaInfo и проверять:

Обязательные проверки:
- output file exists
- output size > 0
- width совпадает
- height совпадает
- FPS примерно совпадает, допуск 0.2 fps
- rotation совпадает, если есть
- audio codec присутствует
- audio channels совпадают, если определены
- если исходник HDR:
  - результат тоже HDR
  - bit depth результата >= 10
  - primaries BT.2020 должны сохраниться, если были BT.2020
  - transfer HLG/PQ должен сохраниться или быть совместимым
- если исходник HDR Vivid:
  - допустимо, что результат станет HLG
  - это не ошибка, а warning: "HDR Vivid metadata were not preserved; base HLG HDR preserved"
- если исходник SDR:
  - результат не должен стать HDR неожиданно

Validator должен возвращать объект:

{
  Success: true/false,
  Warnings: [],
  Errors: []
}

Если Success=false:
- логировать ошибку;
- не считать файл успешно обработанным;
- желательно оставить файл для анализа, но пометить как failed в логах.

---

## 5. Обновить логирование

В CSV/JSONL добавить поля:

- HdrTypeSource
- HdrTypeOutput
- ValidationSuccess
- ValidationWarnings
- ValidationErrors
- SourceWidth
- SourceHeight
- OutputWidth
- OutputHeight
- SourceTransfer
- OutputTransfer
- SourcePrimaries
- OutputPrimaries
- SourceBitDepth
- OutputBitDepth

---

## 6. Обновить Smart Skip

Smart Skip не должен пропускать HDR-видео только потому, что оно HEVC с битрейтом ниже порога, если пользователь выбрал Archive и файл содержит HDR Vivid / Dolby Vision / HDR10+.

Для таких файлов лучше:
- либо кодировать;
- либо выводить предупреждение, что dynamic/proprietary HDR metadata могут быть потеряны.

Правило:
- AV1 можно пропускать по умолчанию.
- HEVC SDR ниже порога можно пропускать.
- HEVC HDR ниже порога можно пропускать только если HdrType = HLG или HDR10 и пользователь не указал Force.
- HDR Vivid / Dolby Vision / HDR10+ не пропускать без явного согласия или отдельной настройки.

---

## 7. Обновить документацию

В README или Docs/HDR.md добавить:

- HDR Vivid metadata обычно не сохраняются после NVEncC.
- Это ожидаемо.
- Главное, чтобы сохранились BT.2020, HLG/PQ и 10 bit.
- Для Honor HDR Vivid допустимый результат: HDR Vivid -> HLG.
- Dolby Vision metadata также могут быть потеряны при обычном HEVC перекодировании.

---

## 8. Тесты

Добавить Pester-тесты:

MediaAnalyzer:
- HDR Vivid + HLG -> HdrType HDR Vivid
- BT.2020 + HLG -> HdrType HLG
- SMPTE ST 2084 -> HdrType PQ/HDR10
- SDR BT.709 -> SDR

Validator:
- HDR Vivid source + HLG output -> Success=true, Warning present
- HDR source + SDR output -> Success=false
- resolution mismatch -> Success=false
- fps difference > 0.2 -> Success=false

DecisionEngine:
- AV1 -> Skip
- HEVC SDR low bitrate -> Skip
- HEVC HDR Vivid low bitrate -> Do not skip by default

---

После выполнения:
1. Покажи список изменённых файлов.
2. Покажи новый пример команды NVEncC для HDR.
3. Покажи пример результата Validator для случая HDR Vivid -> HLG.