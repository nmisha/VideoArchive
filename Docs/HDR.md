# HDR Handling

## Goal

Encoded HDR video must remain HDR after re-encoding.

## Supported HDR Types

- `HLG`
- `PQ`
- `HDR10`
- `HDR10+`
- `HDR Vivid`
- `Dolby Vision`

## Encoder Policy

HDR sources are encoded as:

```text
HEVC Main10
10-bit
--transfer auto
--colorprim auto
--colormatrix auto
```

Audio is always copied with `--audio-copy`.

## Dynamic HDR Metadata

`NVEncC` usually does not preserve dynamic or proprietary HDR metadata such as:

- `HDR Vivid` / `CUVA`
- `Dolby Vision`
- some `HDR10+` signaling details

This is expected behavior for the current HEVC archive workflow.

## Acceptable Outcomes

- `HLG -> HLG` is required.
- `PQ -> PQ` is required.
- `HDR10 -> HDR10/PQ-compatible` is required.
- `HDR Vivid -> HLG` is acceptable when base HDR remains intact.
- `Dolby Vision` may lose dynamic metadata during standard HEVC re-encode.

For Honor HDR Vivid clips, the acceptable archive result is often:

```text
HDR Vivid -> HLG
BT.2020 preserved
10-bit preserved
```

## Validation

After encoding, VideoArchive validates:

- output file exists
- resolution preserved
- FPS preserved within tolerance
- rotation preserved
- HDR not lost
- BT.2020 primaries preserved for HDR
- transfer preserved or accepted as compatible
- audio codec and channels preserved
- GPS and Date Taken preserved

If `HDR Vivid` metadata disappears but the output remains valid `HLG`, validation succeeds with a warning:

```text
HDR Vivid metadata were not preserved; base HLG HDR preserved
```
