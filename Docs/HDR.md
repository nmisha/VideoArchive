# HDR Handling

## Цель

HDR-видео должно остаться HDR после кодирования.

## Поддерживаемые типы

- HLG
- HDR10
- HDR10+
- HDR Vivid
- Dolby Vision

## Базовое правило

Для HDR использовать:

```text
HEVC Main10
10 bit
--transfer auto
--colorprim auto
--colormatrix auto
```

## HDR Vivid

HDR Vivid часто встречается у Honor/Huawei. Обычно базовая кривая — HLG. Фирменные CUVA metadata могут быть потеряны, но базовый HLG HDR должен сохраниться.

## Dolby Vision

Dolby Vision metadata могут не сохраниться при перекодировании. Нужно классифицировать такие файлы как HDR и в будущем добавить отдельную стратегию.

## Validation

После кодирования проверить через MediaInfo:

- HDR input -> HDR output;
- 10-bit preserved;
- BT.2020/HLG/PQ не потеряны.
