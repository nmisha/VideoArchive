# Presets

## Overview

Presets tune quality, speed, and output size for the `NVEncC` HEVC workflow.

Current preset families:

- `Archive`
- `Balanced`
- `Fast`
- `Storage`

Common rule:

- HDR and SDR share the same structural preset idea, but use separate `qvbrHdr` and `qvbrSdr` values.

## Archive

Maximum quality for long-term archive.

- `qvbrHdr = 19`
- `qvbrSdr = 19`
- `nvPreset = p7`
- `lookahead = 32`
- `multipass = 2pass-full`

## Balanced

Recommended default balance.

- `qvbrHdr = 19`
- `qvbrSdr = 19`
- `nvPreset = p5`
- `lookahead = 16`
- `multipass = 2pass-quarter`

## Fast

Faster encode with lower analysis cost.

- `qvbrHdr = 20`
- `qvbrSdr = 20`
- `nvPreset = p4`
- `lookahead = 8`
- `multipass = none`

## Storage

Higher compression for smaller files.

- `qvbrHdr = 21`
- `qvbrSdr = 21`
- `nvPreset = p5`
- `lookahead = 16`
- `multipass = 2pass-quarter`

## Notes

- Higher `qvbr` values generally reduce file size and also reduce quality.
- `Archive` is intended for minimum quality loss, not maximum size reduction.
- `Storage` is intended for stronger size reduction, but validation rules still apply.
- Smart Skip and validation are independent from preset descriptions.
