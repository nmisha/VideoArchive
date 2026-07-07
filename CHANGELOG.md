# Changelog

## 1.3.0

- Added `DateResolver.psm1` for capture date extraction from metadata or file names.
- Added capture date rules to `config.json`, including `strictDateMode`.
- Added pre-encode capture date resolution and strict/non-strict handling in the main workflow.
- Added capture date restoration to output files when metadata are missing and the date is recovered from the file name.
- Added capture date validation against QuickTime output tags with warning/error behavior.
- Extended CSV/JSONL logs with capture date fields and warnings.
- Added unit tests for filename parsing and capture date resolution priority.
- Improved preset tuning for HDR and SDR archive targets.
- Extended `NVEncC` command construction with preset-driven `bframes`, `ref`, adaptive I/B, temporal AQ, and optional capability-checked switches.
- Kept audio in copy mode only throughout the encode pipeline.
- Expanded `MediaAnalyzer` HDR classification to return concrete `HdrType` values including `HDR Vivid`, `Dolby Vision`, `HDR10+`, `HLG`, `PQ`, and `SDR`.
- Added video analysis fields for `Rotation`, `ColorRange`, `DolbyVisionProfile`, `AudioCodec`, `AudioChannels`, and `AudioSamplingRate`.
- Updated validator to return `Warnings` and `Errors`.
- Added accepted warning flow for `HDR Vivid -> HLG` when base HLG HDR is preserved.
- Relaxed FPS validation tolerance to `0.2 fps`.
- Extended CSV/JSONL logging with source/output HDR and validation detail fields.
- Adjusted Smart Skip so low-bitrate `HDR Vivid`, `Dolby Vision`, and `HDR10+` HEVC files are not skipped by default.
- Added HDR behavior documentation in [Docs/HDR.md](X:\Projects\VideoArchive\Docs\HDR.md).
- Expanded unit tests for `MediaAnalyzer`, `Validator`, and `DecisionEngine`.

## 1.2.0

- Added safety validation for encoded files.
- Validates resolution, FPS, codec, bit depth, HDR preservation, and audio track count.
- Added HDR metadata checks for transfer, primaries, and matrix.
- Added file timestamp preservation validation for `CreationTime`, `LastWriteTime`, and `LastAccessTime`.
- Automatically removes invalid outputs after failed validation.
- Added unit tests for `Validator`.

## 1.1.1

- Added interactive preset selection when `-Preset` is not provided.
- Switched preset descriptions to English to avoid console encoding issues in Windows PowerShell.
- Replaced unreliable `Write-Progress` rendering with plain-text progress output.
- Improved input path normalization for values with trailing spaces, quotes, or trailing backslashes.
- Improved error normalization for cleaner console and log messages.
- Added live encoding telemetry parsing from `NVEncC` output.
- Added per-file live display for current progress, FPS, ETA, and elapsed time.
- Fixed `NVEncC` telemetry parsing for both `46 frames` and `875/2000 frames` formats.

## 1.1.0

- Added Smart Skip decision engine.
- Added AV1 skip support.
- Added skip rules for small files.
- Added HEVC bitrate threshold rules.
- Added skip when output file already exists.
- Added `-DryRun`, `-Force`, and `-NoSmartSkip`.
- Logged explainable encode/skip reasons to console, TXT, CSV, and JSONL logs.
- Added unit tests for `DecisionEngine` and `MediaAnalyzer`.

## 1.0.0

- Implemented modular PowerShell architecture.
- Added configuration loading from JSON files.
- Added recursive video scanning by supported extensions.
- Added MediaInfo-based media analysis.
- Added HDR/SDR detection and output folder split.
- Added NVEncC HEVC encoding pipeline for HDR and SDR sources.
- Added ExifTool metadata copy and Windows timestamp restoration.
- Added TXT, CSV, and JSONL logging.
- Added main `VideoArchive.ps1` workflow and `VideoArchive.cmd` launcher.

## 0.1.0

- Initial project scaffold.
- Added project documentation.
- Added base PowerShell module structure.
- Added configuration JSON files.
