# VideoArchive

VideoArchive is a PowerShell-based video archiving utility that uses NVIDIA NVENC through `NVEncC`.

The project started as an HDR video archiver, but the current architecture is generic enough for phones, cameras, drones, action cameras, exports, and mixed home archives.

## What it does

- Recursively processes a file or folder.
- Uses `MediaInfo` for video analysis only.
- Uses `NVEncC` for encoding only.
- Uses `ExifTool` for metadata copy and capture-date restoration only.
- Detects `HDR Vivid`, `Dolby Vision`, `HDR10+`, `HLG`, `PQ`, and `SDR`.
- Encodes HDR to HEVC Main10 10-bit.
- Encodes SDR to HEVC Main 8-bit.
- Preserves source resolution and FPS.
- Copies audio without re-encoding.
- Splits outputs into `_HDR_Encoded` and `_SDR_Encoded`.
- Writes TXT, CSV, and JSONL logs.
- Supports Smart Skip, `-DryRun`, `-Force`, and `-NoSmartSkip`.
- Validates encoded files before accepting them.

## Capture date behavior

VideoArchive resolves capture date in this order:

```text
metadata -> filename -> filesystem fallback -> none
```

Important details:

- metadata currently has priority over file name;
- this means a file name like `20260411_235932.mp4` can lose to metadata if the metadata date is considered valid;
- this is intentional because many containers carry a real media timestamp, while file names can be export-generated;
- in some devices the opposite is also possible: filename can represent recording start time while metadata may represent recording end or finalization time.

If no date is resolved:

- the capture date stays empty;
- a warning is written to console and logs;
- if `strictDateMode=true`, the file is treated as a strict-date failure.

## File timestamp behavior

When `metadata.fileTimestampMode = "captureDate"`:

- `CreationTime`
- `LastWriteTime`
- `LastAccessTime`

are set from the resolved capture date.

Timezone offset behavior:

- metadata-derived dates are shifted by `dates.defaultTimezoneOffset` before writing Windows file timestamps;
- filename-derived dates are not shifted again.

This is done to avoid double-adjusting file names that already contain local time.

## Project structure

```text
VideoArchive/
|-- VideoArchive.ps1
|-- VideoArchive.cmd
|-- config.json
|-- presets.json
|-- smartskip.json
|-- devices.json
|-- Modules/
|-- Tests/
|-- Docs/
|-- NVEncC/
|-- ExifTool/
`-- MediaInfo/
```

## Requirements

Place these tools in the project directory:

```text
NVEncC/NVEncC64.exe
ExifTool/exiftool.exe
MediaInfo/MediaInfo.exe
```

## Run

Interactive:

```powershell
.\VideoArchive.cmd
```

Direct PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\VideoArchive.ps1
```

With explicit input and preset:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\VideoArchive.ps1 -InputPath "D:\PhoneVideo" -Preset Balanced
```

Force re-encode:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\VideoArchive.ps1 -InputPath "D:\PhoneVideo" -Preset Archive -Force
```

Dry run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\VideoArchive.ps1 -InputPath "D:\PhoneVideo" -DryRun
```

## Presets

- `Archive` - Maximum quality for long-term archive
- `Balanced` - Recommended balance
- `Fast` - Fast encode
- `Storage` - Maximum compression

## Notes

- VideoArchive does not resize video.
- VideoArchive does not change FPS.
- Audio stays in copy mode.
- Validation happens after encode and metadata copy.
- `HDR Vivid -> HLG` is treated as a warning when base HDR is preserved.
