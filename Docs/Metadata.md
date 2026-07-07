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

## Capture date recovery

VideoArchive resolves capture date in this order:

```text
metadata -> filename -> none
```

It does not use `LastWriteTime`, `CreationTime`, or `FileModifyDate` as capture date fallback.

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

## Notes

Some proprietary metadata may not survive container or codec changes.

HDR Vivid and Dolby Vision dynamic metadata are not treated as ordinary ExifTool metadata and require separate validation logic.
