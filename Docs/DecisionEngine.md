# Decision Engine

Decision Engine решает, что делать с файлом.

Вход:

- VideoInfo;
- SourceFile;
- OutputPath;
- SmartSkip rules;
- Force flag.

Выход:

```powershell
[pscustomobject]@{
    Action = "Encode" # Encode | Skip
    Reason = "..."
    OutputGroup = "HDR" # HDR | SDR
}
```

Decision Engine не должен знать командную строку NVEncC.
