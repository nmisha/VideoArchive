# Metadata

## Что копируется

Через ExifTool:

```text
-TagsFromFile source
-All:All
-Keys:All
-XMP:All
-FileCreateDate
-FileModifyDate
```

## Windows timestamps

После ExifTool PowerShell восстанавливает:

- CreationTime;
- LastWriteTime;
- LastAccessTime.

## Нюансы

Некоторые proprietary metadata могут не переноситься, если контейнер или кодек их не поддерживает.

HDR Vivid / Dolby Vision dynamic metadata не считаются обычными ExifTool metadata и требуют отдельной стратегии.
