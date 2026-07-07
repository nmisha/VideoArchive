# Roadmap

## v1.0 - Working CLI [Done]

Goal: reliable command-line archive workflow.

- Modular PowerShell architecture.
- Media analysis through `MediaInfo`.
- HEVC encoding through `NVEncC`.
- Metadata copy through `ExifTool`.
- HDR and SDR output split.
- TXT, CSV, and JSONL logs.

## v1.1 - Smart Processing [Done]

Goal: avoid unnecessary re-encoding.

- Smart Skip.
- Skip AV1.
- Bitrate-based HEVC skip rules.
- Skip existing outputs.
- `-DryRun`
- `-Force`
- `-NoSmartSkip`
- Explainable encode/skip decisions.

## v1.2 - Safety [Done]

Goal: do not damage the archive.

- Validator.
- Resolution and FPS validation.
- HDR preservation validation.
- Audio validation.
- Metadata and file timestamp validation.
- Remove invalid outputs after failed validation.

## v1.3 - Metadata and Capture Date [Done]

Goal: preserve useful dates and improve archive traceability.

- Explicit HDR type classification.
- Capture date recovery from metadata, file names, and optional filesystem fallback.
- Strict date mode.
- Capture date restoration to output metadata when needed.
- Logging of capture date source, pattern, warnings, and validation state.
- File timestamp policy based on preserved source dates or resolved capture date.
- Timezone-aware Windows file timestamps for metadata-derived capture dates.

## v1.4 - Resume

Goal: robust large-archive processing.

- Resume from JSONL or SQLite.
- Do not restart already successful files.
- Separate resume handling for `Failed`, `Skipped`, and `Encoded`.

## v1.5 - Better UI

Goal: better operator feedback during long runs.

- Improve progress visualization.
- Improve total ETA reporting.
- Show before/after file size during processing.
- Expand final HDR/SDR and date-source summary statistics.

## v2.0 - Multi Encoder

Goal: support more hardware backends.

- NVENC AV1.
- Intel QSV.
- AMD AMF.
- Software x265 fallback.
- Multi-GPU support.

## v3.0 - GUI

Goal: operator-friendly desktop workflow.

- WPF or WinUI UI.
- Drag and drop.
- Preset editor.
- Job queue.
- Progress dashboard.
- Log viewer and history browser.
