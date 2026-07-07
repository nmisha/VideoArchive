# Metadata

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

- metadata-derived capture dates are shifted by `dates.defaultTimezoneOffset` before writing Windows file timestamps;
- filename-derived capture dates are written as-is, without an extra shift.

This is intentional because file names often already contain local time.

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
