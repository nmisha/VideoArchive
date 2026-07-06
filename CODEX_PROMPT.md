# Codex Prompt

You are working on the VideoArchive project.

Read these files first:

1. PROJECT.md
2. ARCHITECTURE.md
3. TASKS.md
4. README.md

Implement the project iteratively.

Do not write one giant script.

Start with MVP v1.0:

1. Config loader
2. Scanner
3. MediaInfo analyzer
4. DecisionEngine
5. Encoder wrapper
6. Metadata copier
7. Logger
8. Console UI
9. Main workflow

Follow the architecture strictly.

All decisions must be explainable and logged.

Do not resize video.
Do not change FPS.
Do not convert HDR to SDR.
Preserve metadata after encoding.

Use MediaInfo only for analysis.
Use NVEncC only for encoding.
Use ExifTool only for metadata copy.
