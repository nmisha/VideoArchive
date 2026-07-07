# Architecture

## Pipeline

```text
Console UI
  -> Config
  -> Scanner
  -> Resume
  -> MediaAnalyzer
  -> DateResolver
  -> DecisionEngine
  -> Encoder
  -> Metadata
  -> Validator
  -> Logger
```

`VideoArchive.ps1` owns the workflow and orchestration. Modules stay focused and do not coordinate each other directly.

## Modules

### `Config.psm1`

Loads and normalizes:

- `config.json`
- `presets.json`
- `smartskip.json`
- `devices.json`

Responsibilities:

- resolve tool paths;
- inject defaults for missing config keys;
- expose one runtime config object.

### `Scanner.psm1`

Finds supported video files from:

- a single file path;
- a folder path.

Returns a list of file records with source path and relative path. It does not analyze media.

### `MediaAnalyzer.psm1`

Uses `MediaInfo` only.

Returns `VideoInfo` with fields such as:

- codec;
- width and height;
- fps;
- bitrate;
- bit depth;
- transfer;
- primaries;
- matrix;
- rotation;
- HDR detection and `HdrType`;
- audio track count and per-track audio info.

### `Resume.psm1`

Uses prior JSONL logs to decide which files should be processed in the current run.

Responsibilities:

- resolve the resume log path;
- read JSONL history;
- build latest-state lookup by `SourcePath`;
- compare preset and source fingerprint;
- skip already completed files safely;
- select retry candidates for `failed`, `unfinished`, or `all` resume modes.

Current completion rule:

- last history action is `Encoded`;
- validation passed;
- current preset matches the history preset when available;
- source fingerprint still matches;
- output file still exists and is non-empty.

### `DateResolver.psm1`

Resolves `CaptureDate` in this order:

```text
metadata -> filename -> filesystem fallback -> none
```

Important behavior:

- metadata has higher priority than file name;
- filename dates are used when metadata are missing or invalid;
- filesystem dates are used only when `dates.fileDateFallbackMode` explicitly enables them;
- `LastWriteTime`, `CreationTime`, and `FileModifyDate` are never used implicitly;
- if `strictDateMode=true` and no date is resolved, the file is skipped/failed by policy.

Current filename coverage includes:

- `VID_yyyyMMdd_HHmmss`
- `Insta360_VID_yyyyMMdd_HHmmss_suffix`
- `Imou_yyyyMMddHHmmssfff_prefix`
- `Generic_yyyyMMddHHmmssfff`
- several Android, DJI, GoPro, WhatsApp, Telegram, and Signal patterns

Architectural note:

- file name may represent recording start time;
- metadata may represent media creation/finalization time;
- the system currently trusts metadata first and logs the chosen source.

### `DecisionEngine.psm1`

Decides whether to encode or skip.

Inputs:

- `VideoInfo`
- Smart Skip rules
- CLI overrides such as `-Force` and `-NoSmartSkip`

Returns:

- `Action`
- `Reason`
- `OutputGroup`

It does not know how `NVEncC` arguments are built.

### `Encoder.psm1`

Provides encoder backend abstraction.

Current backends:

- `nvenc`
- `qsv`
- `amf`
- `software`

Current codecs:

- `hevc`
- `av1` for supported hardware backends

Builds an `EncodeJob` and runs it. Also parses live encoder telemetry for:

- percent;
- frames;
- fps;
- per-file ETA;
- elapsed time.

Rules:

- no resize;
- no FPS conversion;
- HDR defaults to HEVC Main10 10-bit;
- SDR defaults to HEVC Main 8-bit;
- audio stays in copy mode.

Selection policy:

- backend can be explicitly requested;
- otherwise `auto` selects the first available backend from config order;
- codec can be explicitly requested;
- HDR AV1 is disabled by default and falls back to HEVC unless config allows it.

### `Metadata.psm1`

Uses `ExifTool` only.

Responsibilities:

- copy metadata from source to encoded file;
- expose metadata snapshot for validation;
- restore filesystem timestamps according to `metadata.fileTimestampMode`.

Current timestamp behavior:

- `preserve`: copy source `CreationTime`, `LastWriteTime`, `LastAccessTime`;
- `captureDate`: set file timestamps from resolved capture date.

Timezone behavior for file timestamps:

- if capture date source is `Metadata`, apply `dates.defaultTimezoneOffset` to Windows file timestamps;
- if capture date source is `FileName`, do not apply offset again;
- this avoids double-shifting file names that already contain local time.

### `Validator.psm1`

Validates encoded outputs after metadata copy.

Checks:

- output file exists and size is non-zero;
- resolution matches;
- FPS matches within tolerance;
- rotation matches;
- output codec is HEVC;
- HDR is not lost;
- HDR stays 10-bit or better;
- SDR stays 8-bit;
- transfer, primaries, and matrix stay compatible;
- audio codec and channels match per track;
- metadata date and GPS survive;
- file timestamps match the configured policy;
- recovered capture date matches output metadata within tolerance.

Special case:

- `HDR Vivid -> HLG` is allowed as a warning when base HDR is preserved.

### `Logger.psm1`

Writes:

- TXT
- CSV
- JSONL

Logs include:

- encode/skip/fail decision;
- size and savings;
- validation warnings and errors;
- source and output HDR fields;
- capture date, source, pattern, and warnings.

### `ConsoleUI.psm1`

Handles console-only interaction:

- banner;
- preset menu;
- status lines;
- plain-text progress bar;
- dashboard counters for encoded, skipped, failed, dry-run, and resume-skipped files;
- live encoding telemetry;
- per-file result lines with source size, output size, savings, and duration;
- final summary with elapsed time, aggregate sizes, savings, and throughput.

## Data contracts

### `VideoInfo`

Media analysis result from `MediaAnalyzer`.

### `CaptureDateResult`

Date resolution result from `DateResolver`.

Fields:

- `Success`
- `DateTime`
- `Source`
- `Pattern`
- `Warnings`

### `EncodeDecision`

Skip/encode decision with reason.

### `EncodeJob`

Full encoder command description.

### `EncodeResult`

Encoder execution result with exit code, duration, log, and final output path.

### `LogRecord`

Unified record for TXT/CSV/JSONL logging.
