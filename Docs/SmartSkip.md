# Smart Skip

Smart Skip нужен, чтобы не перекодировать файлы, где экономия будет маленькой или качество может ухудшиться без смысла.

## Правила

### AV1

AV1 обычно эффективнее HEVC.

По умолчанию:

```text
AV1 -> Skip
```

### Small files

Файлы меньше порога не кодируются.

Например:

```text
< 50 MB -> Skip
```

### HEVC bitrate thresholds

Если HEVC уже достаточно сжат:

```text
1080p HEVC < 10 Mbps -> Skip
4K HEVC < 35 Mbps -> Skip
8K HEVC < 80 Mbps -> Skip
```

### Existing output

Если выходной файл уже существует:

```text
Skip
```

## Force

`-Force` отключает Smart Skip.
