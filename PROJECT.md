# VideoArchive Project Specification

## Goal

VideoArchive is a PowerShell utility for video archive compression with strong safety rules.

Primary objective:

- reduce file size;
- preserve HDR/SDR behavior;
- preserve source resolution and FPS;
- preserve metadata and useful file dates;
- make every skip or encode decision explainable.

## Core principles

1. Reliability is more important than raw speed.
2. HDR must not silently become SDR.
3. Resolution and FPS must not change.
4. Metadata preservation is part of the workflow, not an optional extra.
5. Decisions must be transparent in console and logs.
6. The codebase must stay modular.
7. External tools are single-purpose and strictly separated.

## External tools

### `MediaInfo`

Used only for analysis.

### `NVEncC`

Used only for encoding.

### `ExifTool`

Used only for metadata copy and capture-date tag restoration.

## Current behavior

### Encode policy

- HDR -> HEVC Main10 10-bit
- SDR -> HEVC Main 8-bit
- audio -> copy
- no resize
- no FPS conversion

### Output structure

For an input folder `D:\Video`, VideoArchive creates:

```text
D:\Video_HDR_Encoded
D:\Video_SDR_Encoded
```

Subfolder structure is preserved.

### Capture date policy

Capture date is resolved in this order:

```text
metadata -> filename -> filesystem fallback -> none
```

Notes:

- metadata currently has priority over file name;
- this means that if filename and metadata differ, metadata wins;
- in real files this may happen because filename can reflect recording start time while metadata may reflect media creation/finalization time;
- filesystem fallback is opt-in through `dates.fileDateFallbackMode`;
- if no date is found, the value stays empty and warnings are written;
- if `strictDateMode=true`, files without capture date are not processed successfully.

### File timestamp policy

When `metadata.fileTimestampMode = captureDate`, Windows timestamps are derived from the resolved capture date.

Offset behavior:

- metadata-derived capture dates receive `dates.defaultTimezoneOffset` when written to `CreationTime` / `LastWriteTime` / `LastAccessTime`;
- filename-derived capture dates are not shifted again.

This keeps `Media created` metadata and Windows filesystem timestamps aligned with expected local time without double-adjusting file names that already contain local time.

## Validation policy

Encoded outputs are validated for:

- codec;
- resolution;
- FPS;
- rotation;
- HDR preservation;
- bit depth;
- transfer, primaries, and matrix;
- audio codec and channels;
- GPS and date metadata;
- file timestamps;
- capture date consistency.

## Logging policy

Each run produces:

- TXT for human-readable history;
- CSV for spreadsheet analysis;
- JSONL for machine processing and future resume/history features.

Current resume support:

- JSONL-based resume is implemented;
- completed files are not restarted when history, preset, fingerprint, and output existence still match;
- SQLite-backed global history remains a later step.

## Operator feedback

Current CLI feedback includes:

- color-coded action lines for encode, skip, fail, discard, and resume states;
- text progress bar with processed file count and processed source size;
- live per-file encoder telemetry from `NVEncC`;
- estimated total remaining time based on current file remain time plus average completed-file duration;
- final summary with aggregate size and throughput metrics.
