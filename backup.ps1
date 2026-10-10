<#
.SYNOPSIS
    Создает резервную копию проекта After Wind в ZIP-архив.

.DESCRIPTION
    Архивирует проект с оптимизированным сжатием, исключая кэши, бинарники и временные файлы.
    Поддерживает PowerShell 5.1+ и PowerShell 7+ (pwsh).

.PARAMETER OutputDir
    Каталог для сохранения бэкапов. По умолчанию: "backups" в корне проекта.

.PARAMETER Tag
    Пользовательская метка для добавления в имя файла (например, "before-refactor").

.PARAMETER IncludeGit
    Включить папку .git в архив (по умолчанию исключена для экономии места).

.PARAMETER IncludeGodot
    Включить кэш Godot (.godot) в архив (по умолчанию исключен).

.PARAMETER IncludeBinaries
    Включить бинарные файлы (*.exe, *.dll и т.д.).

.PARAMETER IncludeZip
    Включить существующие zip-файлы из проекта.

.PARAMETER MaxBackups
    Оставить только последние N бэкапов в папке OutputDir (0 = хранить все).

.PARAMETER OpenFolder
    Открыть папку с бэкапом в Проводнике Windows по завершении.
#>

[CmdletBinding()]
param(
    [string]$OutputDir = "backups",
    [string]$Tag = "",
    [switch]$IncludeGit,
    [switch]$IncludeGodot,
    [switch]$IncludeBinaries,
    [switch]$IncludeZip,
    [int]$MaxBackups = 0,
    [switch]$OpenFolder
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Определение корневой директории проекта
$projectRoot = $PSScriptRoot
if (-not $projectRoot) {
    $projectRoot = (Get-Location).Path
}
$projectRoot = [System.IO.Path]::GetFullPath($projectRoot)
$projectName = (Split-Path $projectRoot -Leaf).Replace(" ", "_")

# Определение директории назначения
if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $targetDir = [System.IO.Path]::GetFullPath($OutputDir)
} else {
    $targetDir = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($projectRoot, $OutputDir))
}

if (-not (Test-Path $targetDir)) {
    [System.IO.Directory]::CreateDirectory($targetDir) | Out-Null
}

# Получение Git commit hash (если репозиторий существует)
$gitHash = ""
try {
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCmd) {
        $hashOutput = & git -C "$projectRoot" rev-parse --short HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $hashOutput) {
            $gitHash = $hashOutput.Trim()
        }
    }
} catch {
    $gitHash = ""
}

# Формирование имени архива
$timestamp = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
$nameParts = @($projectName, "backup", $timestamp)
if ($gitHash) { $nameParts += $gitHash }
if ($Tag) {
    $safeTag = ($Tag -replace '[\\/:*?"<>| ]', '_').Trim('_')
    if ($safeTag) { $nameParts += $safeTag }
}
$zipFileName = ($nameParts -join "_") + ".zip"
$zipFilePath = [System.IO.Path]::Combine($targetDir, $zipFileName)

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "             AFTER WIND - BACKUP TOOL                     " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Проект:       $projectRoot" -ForegroundColor Gray
Write-Host " Назначение:   $zipFilePath" -ForegroundColor Gray
if ($gitHash) {
    Write-Host " Git Commit:   $gitHash" -ForegroundColor Gray
}
Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray

# Сбор папок и файлов для исключения
$excludeDirs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$excludeDirs.Add($targetDir) | Out-Null
$excludeDirs.Add([System.IO.Path]::Combine($projectRoot, ".workbuddy-ai")) | Out-Null
$excludeDirs.Add([System.IO.Path]::Combine($projectRoot, ".agents")) | Out-Null
$excludeDirs.Add([System.IO.Path]::Combine($projectRoot, "outputs")) | Out-Null

if (-not $IncludeGit) {
    $excludeDirs.Add([System.IO.Path]::Combine($projectRoot, ".git")) | Out-Null
}
if (-not $IncludeGodot) {
    $excludeDirs.Add([System.IO.Path]::Combine($projectRoot, ".godot")) | Out-Null
}

$excludeDirNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$excludeDirNames.Add("__pycache__") | Out-Null
$excludeDirNames.Add(".mono") | Out-Null

$excludeExtensions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$excludeExtensions.Add(".tmp") | Out-Null
$excludeExtensions.Add(".blend1") | Out-Null
$excludeExtensions.Add(".pyc") | Out-Null
$excludeExtensions.Add(".pyo") | Out-Null

if (-not $IncludeZip) {
    $excludeExtensions.Add(".zip") | Out-Null
}
if (-not $IncludeBinaries) {
    $excludeExtensions.Add(".exe") | Out-Null
    $excludeExtensions.Add(".dll") | Out-Null
    $excludeExtensions.Add(".so") | Out-Null
    $excludeExtensions.Add(".dylib") | Out-Null
}

$excludeFileNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$excludeFileNames.Add(".DS_Store") | Out-Null
$excludeFileNames.Add("Thumbs.db") | Out-Null
$excludeFileNames.Add("desktop.ini") | Out-Null

Write-Host "[1/3] Сканирование файлов проекта..." -ForegroundColor Yellow

$filesToArchive = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
$totalBytes = [long]0

function Collect-Files {
    param([string]$dirPath)

    # Проверка исключенных каталогов по полному пути
    foreach ($exDir in $excludeDirs) {
        if ($dirPath.Equals($exDir, [System.StringComparison]::OrdinalIgnoreCase) -or
            $dirPath.StartsWith($exDir + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            return
        }
    }

    # Проверка каталогов по имени
    $dirName = [System.IO.Path]::GetFileName($dirPath)
    if ($excludeDirNames.Contains($dirName)) {
        return
    }

    # Сбор файлов в каталоге
    $dirInfo = [System.IO.DirectoryInfo]::new($dirPath)
    try {
        $files = $dirInfo.GetFiles()
    } catch {
        Write-Warning "Не удалось прочитать файлы в: $dirPath ($($_.Exception.Message))"
        return
    }

    foreach ($file in $files) {
        $ext = $file.Extension
        $name = $file.Name

        if ($excludeFileNames.Contains($name)) { continue }
        if ($excludeExtensions.Contains($ext)) { continue }

        $filesToArchive.Add($file)
        $script:totalBytes += $file.Length
    }

    # Рекурсивный обход подпапок
    try {
        $subDirs = $dirInfo.GetDirectories()
    } catch {
        Write-Warning "Не удалось прочитать подпапки в: $dirPath ($($_.Exception.Message))"
        return
    }

    foreach ($sub in $subDirs) {
        Collect-Files -dirPath $sub.FullName
    }
}

Collect-Files -dirPath $projectRoot

$totalMB = [math]::Round($totalBytes / 1MB, 2)
Write-Host " Найдено файлов: $($filesToArchive.Count) (всего ~$totalMB МБ)" -ForegroundColor Green

Write-Host "[2/3] Создание ZIP-архива..." -ForegroundColor Yellow

# Создание архива
$zipStream = [System.IO.File]::Open($zipFilePath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
$archive = [System.IO.Compression.ZipArchive]::new($zipStream, [System.IO.Compression.ZipArchiveMode]::Create)

$rootPrefixLen = $projectRoot.Length
if (-not $projectRoot.EndsWith([System.IO.Path]::DirectorySeparatorChar.ToString())) {
    $rootPrefixLen++
}

$processedCount = 0
$step = [math]::Max(1, [math]::Floor($filesToArchive.Count / 20))

try {
    foreach ($file in $filesToArchive) {
        $relPath = $file.FullName.Substring($rootPrefixLen).Replace('\', '/')
        $entry = $archive.CreateEntry($relPath, [System.IO.Compression.CompressionLevel]::Optimal)
        $entry.LastWriteTime = $file.LastWriteTime

        $entryStream = $entry.Open()
        $sourceStream = [System.IO.File]::OpenRead($file.FullName)
        try {
            $sourceStream.CopyTo($entryStream)
        } finally {
            $sourceStream.Dispose()
            $entryStream.Dispose()
        }

        $processedCount++
        if ($processedCount % $step -eq 0 -or $processedCount -eq $filesToArchive.Count) {
            $percent = [math]::Round(($processedCount / $filesToArchive.Count) * 100)
            Write-Progress -Activity "Архивация проекта" -Status "$percent% ($processedCount / $($filesToArchive.Count))" -PercentComplete $percent
        }
    }
} finally {
    Write-Progress -Activity "Архивация проекта" -Completed
    $archive.Dispose()
    $zipStream.Dispose()
}

$stopwatch.Stop()
$elapsedSec = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)

$zipInfo = [System.IO.FileInfo]::new($zipFilePath)
$zipSizeMB = [math]::Round($zipInfo.Length / 1MB, 2)
$ratio = if ($totalBytes -gt 0) { [math]::Round((1 - ($zipInfo.Length / $totalBytes)) * 100, 1) } else { 0 }

Write-Host "[3/3] Готово!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " Архив создан успешно!" -ForegroundColor Green
Write-Host " Файл:             $($zipInfo.Name)" -ForegroundColor White
Write-Host " Полный путь:      $($zipInfo.FullName)" -ForegroundColor Gray
Write-Host " Размер архива:    $zipSizeMB МБ (исходный: $totalMB МБ, сжатие: $ratio%)" -ForegroundColor White
Write-Host " Файлов добавлено: $($filesToArchive.Count)" -ForegroundColor White
Write-Host " Время упаковки:   $elapsedSec сек." -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Cyan

# Ротация старых бэкапов (если задан MaxBackups)
if ($MaxBackups -gt 0) {
    Write-Host "Проверка ротации бэкапов (максимум: $MaxBackups)..." -ForegroundColor Yellow
    $existingBackups = Get-ChildItem -Path $targetDir -Filter "${projectName}_backup_*.zip" -File |
        Sort-Object CreationTime -Descending

    if ($existingBackups.Count -gt $MaxBackups) {
        $toRemove = $existingBackups | Select-Object -Skip $MaxBackups
        foreach ($old in $toRemove) {
            Write-Host " Удаление старого бэкапа: $($old.Name)" -ForegroundColor DarkGray
            Remove-Item -Path $old.FullName -Force
        }
    }
}

if ($OpenFolder) {
    Start-Process "explorer.exe" -ArgumentList "/select,`"$($zipInfo.FullName)`""
}
