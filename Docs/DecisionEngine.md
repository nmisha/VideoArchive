# Decision Engine

The Decision Engine decides whether a file should be encoded or skipped.

## Inputs

- `VideoInfo`
- `OutputFile`
- Smart Skip rules
- `PresetName`
- `-Force`
- `-NoSmartSkip`

## Output

```powershell
[pscustomobject]@{
    Action = 'Encode'    # Encode | Skip
    Reason = '...'
    OutputGroup = 'HDR'  # HDR | SDR
    SmartSkipApplied = $true
}
```

## Current rules

Decision order:

1. `-Force` always encodes.
2. `-NoSmartSkip` or disabled Smart Skip encodes.
3. Existing output can be skipped when `skipIfOutputExists=true`.
4. AV1 can be skipped.
5. Small files can be skipped.
6. HEVC bitrate thresholds can skip already efficient files.
7. Protected HDR formats such as `HDR Vivid`, `Dolby Vision`, and `HDR10+` are not silently skipped by low-bitrate HEVC rules.
8. Non-HEVC codecs default to encode.

## Scope boundary

The Decision Engine does not know:

- how `NVEncC` arguments are built;
- how metadata are copied;
- how validation works after encode.

It only decides `Encode` or `Skip` and explains why.
