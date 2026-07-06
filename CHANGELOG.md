# Changelog

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
