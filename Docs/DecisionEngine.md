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
4. Sources listed in `legacySourceExtensions` are always transcoded, regardless of size, and their output is protected from the minimum-savings discard rule.
5. AV1 can be skipped for non-legacy sources.
6. Small modern files are skipped by default, or encoded when `encodeSmallModernFiles=true`; explicitly encoded small outputs are protected from the minimum-savings discard rule.
7. HEVC bitrate thresholds can skip already efficient files.
8. Protected HDR formats such as `HDR Vivid`, `Dolby Vision`, and `HDR10+` are not silently skipped by low-bitrate HEVC rules.
9. Non-HEVC codecs default to encode.

Relevant `smartskip.json` settings:

```json
"skipSmallFilesMb": 50,
"encodeSmallModernFiles": false,
"legacySourceExtensions": [".mts", ".m2ts", ".avi", ".wmv", ".webm"]
```

## Scope boundary

The Decision Engine does not know:

- how `NVEncC` arguments are built;
- how metadata are copied;
- how validation works after encode.

It only decides `Encode` or `Skip` and explains why.
