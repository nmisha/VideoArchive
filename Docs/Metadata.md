# Metadata

## Container policy

`output.container` controls the archive container:

```json
"output": {
  "container": "mp4"
}
```

- `mp4` is the default and stores the resolved capture date in embedded QuickTime/XMP tags.
- `mkv` creates a required `<name>.metadata.json` sidecar because ExifTool does not support writing embedded Matroska date tags.
- `source` preserves MP4/MOV/M4V/MKV inputs and falls back to MKV plus sidecar for other source containers.

The MKV sidecar records the source and output paths, resolved capture date, date source and pattern, source fingerprint, warnings, and GPS values. Validation and Resume require this sidecar for MKV results.

## What gets copied

Via ExifTool:

```text
-TagsFromFile source
-All:All
-Keys:All
-XMP:All
-FileCreateDate
-FileModifyDate
```

## Windows timestamps

After ExifTool, PowerShell restores:

- `CreationTime`
- `LastWriteTime`
- `LastAccessTime`

This behavior is controlled by `metadata.fileTimestampMode`:

- `preserve` keeps the original Windows file timestamps from the source file;
- `captureDate` sets Windows file timestamps from the resolved capture date.

## Capture date recovery

VideoArchive resolves capture date in this order:

```text
metadata -> filename -> filesystem fallback -> none
```

Important rules:

- metadata has higher priority than file name;
- filesystem fallback is disabled by default;
- `LastWriteTime`, `CreationTime`, and `FileModifyDate` are never used implicitly as capture date fallback;
- filesystem fallback only happens when `dates.fileDateFallbackMode` explicitly enables `creationTime` or `lastWriteTime`.

Supported filename patterns include:

- `Imou_yyyyMMddHHmmssfff_prefix`
  Example: `20260517112753114_F64ACBFPSFC74F9_L_0_L0120517112753.mp4`
- `Insta360_VID_yyyyMMdd_HHmmss_suffix`
  Example: `VID_20250829_234743_10_133.mp4`
- `VID_yyyyMMdd_HHmmss`
  Example: `VID_20250829_234743.mp4`
- `Generic_yyyyMMddHHmmssfff`
  Example: `some_export_20260517112753114_clip.mp4`

When capture date cannot be resolved, the value stays empty and VideoArchive writes warnings to console and logs. If `strictDateMode=true`, such files are marked as failed.

## Timezone behavior for file timestamps

When `metadata.fileTimestampMode = captureDate`:

- source metadata offsets are preserved;
- offset-less dates use historical rules from `dates.defaultTimezone` when `timezoneMode=sourceOrZone`;
- unresolved zones keep local wall-clock time without inventing an offset;
- known offsets are converted to the corresponding UTC instant for Windows timestamps; unknown offsets keep the unresolved local wall-clock value.

For MP4, QuickTime integer timestamps are UTC. Offset-aware local time is also written to `Keys:CreationDate`. MKV sidecars contain local, offset-aware, and UTC representations when the offset is known.

## Metadata vs filename semantics

Video files may legitimately carry different timestamps:

- the file name may represent recording start time;
- container metadata may represent media creation, track creation, or finalization time.

Current policy:

- if metadata contains a valid date, VideoArchive trusts metadata first;
- the chosen source is written to console and logs as `CaptureDateSource`.

## Notes

Some proprietary metadata may not survive container or codec changes.

HDR Vivid and Dolby Vision dynamic metadata are not treated as ordinary ExifTool metadata and require separate validation logic.
