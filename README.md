# Backupper

PowerShell script to move Windows user profile folders (Documents, Pictures, Music, Videos, etc.) to a new drive/location using `robocopy`.

## Features

- Uses `robocopy` with restartable, multi-threaded copy (`/Z /MT:8`)
- Auto-detects actual folder locations (handles OneDrive redirection, custom paths)
- Supports all known shell folders: Desktop, Documents, Downloads, Music, Pictures, Videos, Favorites, Contacts, Links, SavedGames, Searches, LocalAppData, RoamingAppData
- Dry-run mode to preview changes
- Optional registry update so Windows uses the new locations
- **Reverse mode** to restore folders from destination back to original locations
- Detailed summary with exit codes

## Usage

```powershell
# Preview what would happen (safe)
.\Move-UserFolders.ps1 -DestinationRoot "D:\UserData" -DryRun

# Move specific folders
.\Move-UserFolders.ps1 -DestinationRoot "D:\UserData" -FoldersToMove "Documents","Pictures","Music"

# Move all folders and update registry (run as Administrator)
.\Move-UserFolders.ps1 -DestinationRoot "D:\UserData" -UpdateRegistry

# Restore folders from destination back to original locations
.\Move-UserFolders.ps1 -DestinationRoot "D:\UserData" -Reverse

# Restore with registry update (run as Administrator)
.\Move-UserFolders.ps1 -DestinationRoot "D:\UserData" -Reverse -UpdateRegistry

# Dry run of restore operation
.\Move-UserFolders.ps1 -DestinationRoot "D:\UserData" -Reverse -DryRun
```

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-DestinationRoot` | Yes | Target root folder (must exist) |
| `-FoldersToMove` | No | Array of folder names (default: all 11 user folders) |
| `-DryRun` | No | Show commands without executing |
| `-UpdateRegistry` | No | Update `HKCU:\...\User Shell Folders` after copy |
| `-VerifyOnly` | No | Alias for `-DryRun` |
| `-Reverse` | No | Perform inverse operation: move from DestinationRoot back to original locations |

## Robocopy Flags Used

```
/E /Z /J /MT:8 /R:3 /W:5 /COPY:DAT /DCOPY:DAT /ETA
```

- `/E` — Include empty subdirectories
- `/Z` — Restartable mode (survives network interruptions)
- `/J` — Unbuffered I/O (better for large files)
- `/MT:8` — 8 parallel threads
- `/R:3 /W:5` — Retry 3 times, wait 5s between retries
- `/COPY:DAT /DCOPY:DAT` — Copy Data, Attributes, Timestamps for files and dirs
- `/ETA` — Show estimated completion time

## Important Notes

- **Run as Administrator** for `-UpdateRegistry` to work
- After registry update, **log off/on** or restart `explorer.exe`
- Moving `AppData`/`LocalAppData` while logged in can break apps — consider doing this from another admin account or WinPE
- Test with `-DryRun` first

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | No files copied, no failure |
| 1 | All files copied successfully |
| 2 | Extra files in destination (not an error) |
| 3 | 1 + 2 |
| ≥8 | Error occurred |

Script treats 0–3 as success.