# Tasks

## MVP v1.0 [Done]

- [x] Create modular project structure.
- [x] Split configuration into `config.json`, `presets.json`, `smartskip.json`, and `devices.json`.
- [x] Implement `Config.psm1`.
- [x] Implement `Scanner.psm1`.
- [x] Implement `MediaAnalyzer.psm1` with MediaInfo JSON parsing.
- [x] Implement HDR/SDR detection.
- [x] Implement `DecisionEngine.psm1`.
- [x] Implement `Encoder.psm1` for NVEncC HEVC encoding.
- [x] Implement `Metadata.psm1` with ExifTool metadata copy.
- [x] Implement `Logger.psm1` for TXT/CSV/JSONL logs.
- [x] Implement `ConsoleUI.psm1`.
- [x] Assemble the main workflow in `VideoArchive.ps1`.
- [x] Add `VideoArchive.cmd`.
- [x] Add project README and docs.

## v1.1 - Smart Skip [Done]

- [x] Skip AV1.
- [x] Skip small files.
- [x] Skip low-bitrate HEVC sources.
- [x] Skip existing outputs.
- [x] Add `-Force`.
- [x] Add `-NoSmartSkip`.
- [x] Add `-DryRun`.
- [x] Log explicit skip reasons.

## v1.2 - Validation [Done]

- [x] Add `Validator.psm1`.
- [x] Validate resolution.
- [x] Validate FPS.
- [x] Validate HDR preservation.
- [x] Validate audio track preservation.
- [x] Validate metadata and file timestamps.
- [x] Fail when HDR is lost.

## v1.3 - HDR Metadata Policy [Done]

- [x] Add explicit HDR type classification.
- [x] Detect `HDR Vivid`, `Dolby Vision`, `HDR10+`, `HLG`, `PQ`, and `SDR`.
- [x] Accept `HDR Vivid -> HLG` as a warning instead of a hard failure.
- [x] Extend logs with source/output validation details.
- [x] Prevent Smart Skip from silently skipping low-bitrate proprietary HDR formats.
- [x] Document HDR metadata behavior in `Docs/HDR.md`.

## v1.3.1 - Capture Date Recovery [Done]

- [x] Add `DateResolver.psm1`.
- [x] Resolve capture dates from metadata first and file names second.
- [x] Keep filesystem date fallback disabled by default.
- [x] Add opt-in `fileDateFallbackMode` for `creationTime` and `lastWriteTime`.
- [x] Add `strictDateMode`.
- [x] Restore output capture date tags when recovered from the file name.
- [x] Log capture date source, pattern, warnings, and validation state.
- [x] Validate recovered capture dates in output metadata.
- [x] Add extended filename patterns including Imou, Insta360, and generic 17-digit timestamps.

## v1.3.2 - Timestamp Policy and Date Semantics [Done]

- [x] Add `metadata.fileTimestampMode` with `preserve` and `captureDate`.
- [x] Default file timestamps to capture date.
- [x] Apply timezone offset to Windows file timestamps for metadata-derived capture dates.
- [x] Do not re-apply timezone offset for filename-derived capture dates.
- [x] Validate file timestamps against the same policy used during metadata copy.
- [x] Document that metadata and file name dates may legitimately differ.
- [x] Keep `Media created` and Windows file timestamps as separate but related concepts.

## v1.4 - Resume

- [ ] Resume from JSONL or SQLite.
- [ ] Do not restart already successful files.
- [ ] Separate resume handling for `Failed`, `Skipped`, and `Encoded`.

## v1.5 - Better UI

- [ ] Improve progress visualization.
- [ ] Improve ETA reporting.
- [ ] Show per-file before/after size.
- [ ] Expand final HDR/SDR summary statistics.

## v2.0

- [ ] AV1 NVENC.
- [ ] Intel QSV.
- [ ] AMD AMF.
- [ ] Multi-GPU support.
- [ ] Queue manager.
- [ ] SQLite history.

## v3.0

- [ ] GUI.
- [ ] Drag and drop.
- [ ] Run history browser.
- [ ] Log viewer.
- [ ] Preset editing from UI.
