<#
.SYNOPSIS
    Moves Windows user profile folders (Documents, Pictures, Music, Videos, etc.) to a new location using robocopy.

.DESCRIPTION
    This script uses robocopy to copy user profile folders to a new destination,
    then optionally updates the Windows shell folder registry keys to point to the new location.
    Run as Administrator for best results.

.PARAMETER DestinationRoot
    The root folder where user folders will be moved (e.g., "D:\UserData")

.PARAMETER FoldersToMove
    Array of folder names to move. Default includes all known user shell folders.

.PARAMETER DryRun
    If specified, shows what would be done without making changes.

.EXAMPLE
    .\Move-UserFolders.ps1 -DestinationRoot "D:\UserData"

.EXAMPLE
    .\Move-UserFolders.ps1 -DestinationRoot "E:\Profiles" -FoldersToMove "Documents","Pictures","Music" -DryRun
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$DestinationRoot,

    [string[]]$FoldersToMove = @(
        "Desktop",
        "Documents",
        "Downloads",
        "Music",
        "Pictures",
        "Videos",
        "Favorites",
        "Contacts",
        "Links",
        "SavedGames",
        "Searches"
    ),

    [switch]$DryRun,
    [switch]$UpdateRegistry,
    [switch]$VerifyOnly
)

# Robocopy flags from your specification
$RobocopyFlags = @(
    "/E",        # Copy subdirectories, including empty ones
    "/Z",        # Restartable mode
    "/J",        # Unbuffered I/O (better for large files)
    "/MT:8",     # Multi-threaded copy with 8 threads
    "/R:3",      # Retry 3 times on failed copies
    "/W:5",      # Wait 5 seconds between retries
    "/COPY:DAT", # Copy Data, Attributes, Timestamps
    "/DCOPY:DAT",# Copy Directory Data, Attributes, Timestamps
    "/ETA"       # Show estimated time of arrival
)

# Known shell folder registry mappings
$ShellFolders = @{
    "Desktop"       = "{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}"
    "Documents"     = "{FDD39AD0-238F-46AF-ADB4-6C85480369C7}"
    "Downloads"     = "{374DE290-123F-4565-9164-39C4925E467B}"
    "Music"         = "{4BD8D571-6D19-48D3-BE97-422220080E43}"
    "Pictures"      = "{33E28130-4E1E-4676-835A-98395C3BC3BB}"
    "Videos"        = "{18989B1D-99B5-455B-841C-AB7C74E4DDFC}"
    "Favorites"     = "{1777F761-68AD-4D8A-87BD-30B759FA33DD}"
    "Contacts"      = "{56784854-C6CB-462B-8169-88E350ACB882}"
    "Links"         = "{bfb9d5e0-c6a9-404c-b2b2-ae6db6af4968}"
    "SavedGames"    = "{4C5C32FF-BB9D-43B0-B5B4-2D72E54EAAA4}"
    "Searches"      = "{7d1d3a04-debb-4115-95cf-2f29da2920da}"
    "AppData"       = "{3EB685DB-65F9-4CF6-A03A-E3EF65729F3D}"
    "LocalAppData"  = "{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}"
}

function Get-CurrentUserFolderPath {
    param([string]$FolderName)
    
    $guid = $ShellFolders[$FolderName]
    if (-not $guid) { return $null }
    
    # First, check if there's a custom path in User Shell Folders
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
    $value = Get-ItemProperty -Path $regPath -Name $guid -ErrorAction SilentlyContinue
    
    if ($value -and $value.$guid) {
        $expanded = [Environment]::ExpandEnvironmentVariables($value.$guid)
        if (Test-Path $expanded) {
            return $expanded
        }
    }
    
    # Fall back to default locations under %USERPROFILE%
    $defaultPaths = @{
        "Desktop"       = "$env:USERPROFILE\Desktop"
        "Documents"     = "$env:USERPROFILE\Documents"
        "Downloads"     = "$env:USERPROFILE\Downloads"
        "Music"         = "$env:USERPROFILE\Music"
        "Pictures"      = "$env:USERPROFILE\Pictures"
        "Videos"        = "$env:USERPROFILE\Videos"
        "Favorites"     = "$env:USERPROFILE\Favorites"
        "Contacts"      = "$env:USERPROFILE\Contacts"
        "Links"         = "$env:USERPROFILE\Links"
        "SavedGames"    = "$env:USERPROFILE\Saved Games"
        "Searches"      = "$env:USERPROFILE\Searches"
        "AppData"       = "$env:APPDATA"
        "LocalAppData"  = "$env:LOCALAPPDATA"
    }
    
    if ($defaultPaths.ContainsKey($FolderName)) {
        $defaultPath = $defaultPaths[$FolderName]
        if (Test-Path $defaultPath) {
            return $defaultPath
        }
    }
    
    return $null
}

function Set-UserFolderPath {
    param([string]$FolderName, [string]$NewPath)
    
    $guid = $ShellFolders[$FolderName]
    if (-not $guid) { return $false }
    
    $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
    
    try {
        Set-ItemProperty -Path $regPath -Name $guid -Value $NewPath -Type ExpandString -Force
        Write-Host "  Updated registry for $FolderName -> $NewPath" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "Failed to update registry for $FolderName"
        return $false
    }
}

# Main execution
Write-Host "=== User Folder Migration Script ===" -ForegroundColor Cyan
Write-Host "Destination Root: $DestinationRoot" -ForegroundColor Yellow
Write-Host "Folders to process: $($FoldersToMove -join ', ')" -ForegroundColor Yellow
Write-Host "Dry Run: $DryRun" -ForegroundColor Yellow
Write-Host "Update Registry: $UpdateRegistry" -ForegroundColor Yellow
Write-Host ""

$results = @()

foreach ($folder in $FoldersToMove) {
    Write-Host "Processing: $folder" -ForegroundColor Cyan
    
    $sourcePath = Get-CurrentUserFolderPath -FolderName $folder
    
    if (-not $sourcePath) {
        Write-Warning "  Could not locate source path for $folder (may not exist or be redirected)"
        $results += [PSCustomObject]@{
            Folder = $folder
            Status = "Not Found"
            Source = "N/A"
            Destination = "N/A"
        }
        continue
    }
    
    if (-not (Test-Path $sourcePath)) {
        Write-Warning "  Source path does not exist: $sourcePath"
        $results += [PSCustomObject]@{
            Folder = $folder
            Status = "Source Missing"
            Source = $sourcePath
            Destination = "N/A"
        }
        continue
    }
    
    $destPath = Join-Path $DestinationRoot $folder
    
    Write-Host "  Source:      $sourcePath" -ForegroundColor Gray
    Write-Host "  Destination: $destPath" -ForegroundColor Gray
    
    if ($DryRun -or $VerifyOnly) {
        Write-Host "  [DRY RUN] Would run: robocopy `"$sourcePath`" `"$destPath`" $($RobocopyFlags -join ' ')" -ForegroundColor Yellow
        $results += [PSCustomObject]@{
            Folder = $folder
            Status = "Dry Run"
            Source = $sourcePath
            Destination = $destPath
        }
        continue
    }
    
    # Ensure destination directory exists
    if (-not (Test-Path $destPath)) {
        New-Item -Path $destPath -ItemType Directory -Force | Out-Null
    }
    
    # Run robocopy
    $robocopyArgs = @($sourcePath, $destPath) + $RobocopyFlags
    Write-Host "  Running robocopy..." -ForegroundColor Gray
    
    $exitCode = (Start-Process -FilePath "robocopy" -ArgumentList $robocopyArgs -Wait -PassThru).ExitCode
    
    # Robocopy exit codes:
    # 0 = No files copied, no failure
    # 1 = All files copied successfully
    # 2 = Extra files/dirs in destination (not an error)
    # 3 = 1 + 2
    # 4 = Mismatched files/dirs
    # 5 = 4 + 1
    # 6 = 4 + 2
    # 7 = 4 + 1 + 2
    # >= 8 = Error
    
    $success = $exitCode -le 3
    
    if ($success) {
        Write-Host "  Copy completed (exit code: $exitCode)" -ForegroundColor Green
        
        if ($UpdateRegistry) {
            Set-UserFolderPath -FolderName $folder -NewPath $destPath
        }
        
        $results += [PSCustomObject]@{
            Folder = $folder
            Status = "Success"
            Source = $sourcePath
            Destination = $destPath
            ExitCode = $exitCode
        }
    }
    else {
        Write-Error "  Copy FAILED (exit code: $exitCode)"
        $results += [PSCustomObject]@{
            Folder = $folder
            Status = "Failed"
            Source = $sourcePath
            Destination = $destPath
            ExitCode = $exitCode
        }
    }
    
    Write-Host ""
}

# Summary
Write-Host "=== Summary ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize

$failed = $results | Where-Object { $_.Status -eq "Failed" }
if ($failed.Count -gt 0) {
    Write-Host "`nWARNING: $($failed.Count) folder(s) failed to copy:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  - $($_.Folder) (exit code: $($_.ExitCode))" -ForegroundColor Red }
    exit 1
}
elseif (-not $DryRun -and -not $VerifyOnly) {
    Write-Host "`nAll folders processed successfully!" -ForegroundColor Green
    if ($UpdateRegistry) {
        Write-Host "Registry updated. You may need to log off/on or restart explorer.exe for changes to take effect." -ForegroundColor Yellow
    }
}