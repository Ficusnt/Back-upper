<#
.SYNOPSIS
    Moves or restores Windows user profile folders (Documents, Pictures, Music, Videos, etc.) to/from a new location using robocopy.

.DESCRIPTION
    This script uses robocopy to copy user profile folders to a new destination,
    then optionally updates the Windows shell folder registry keys to point to the new location.
    Use -Reverse to move folders back from the destination to their original locations.
    Run as Administrator for best results.

.PARAMETER DestinationRoot
    The root folder where user folders will be moved (e.g., "D:\UserData")

.PARAMETER FoldersToMove
    Array of folder names to move. Default includes all known user shell folders.

.PARAMETER DryRun
    If specified, shows what would be done without making changes.

.PARAMETER Reverse
    If specified, performs the inverse operation: moves folders from DestinationRoot back to their original locations.

.PARAMETER MaxParallel
    Maximum number of concurrent robocopy operations (1-8). Default: 3.

.EXAMPLE
    .\Move-UserFolders.ps1 -DestinationRoot "D:\UserData"

.EXAMPLE
    .\Move-UserFolders.ps1 -DestinationRoot "E:\Profiles" -FoldersToMove "Documents","Pictures","Music" -DryRun

.EXAMPLE
    .\Move-UserFolders.ps1 -DestinationRoot "D:\UserData" -Reverse -UpdateRegistry
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
        "Searches",
        "LocalAppData",
        "RoamingAppData",
        "LocalLow"
    ),
    [switch]$DryRun,
    [switch]$UpdateRegistry,
    [switch]$VerifyOnly,
    [switch]$Reverse,

    [ValidateRange(1, 8)]
    [int]$MaxParallel = 3
)

# Elevate if not running as Administrator (unless in dry-run/verify-only mode)
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if (-not $DryRun -and -not $VerifyOnly) {
        Write-Host "Restarting script with elevated privileges..." -ForegroundColor Yellow
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        
        # Build arguments properly to handle arrays
        $boundArgs = @{}
        foreach ($param in $PSBoundParameters.Keys) {
            $val = $PSBoundParameters[$param]
            if ($val -is [Array]) {
                $boundArgs[$param] = $val -join ','
            } else {
                $boundArgs[$param] = $val
            }
        }
        
        $argString = ""
        foreach ($kvp in $boundArgs.GetEnumerator()) {
            if ($kvp.Value -is [Boolean] -and $kvp.Value) {
                $argString += " -$($kvp.Key)"
            } elseif (-not ($kvp.Value -is [Boolean])) {
                $argString += " -$($kvp.Key) $($kvp.Value)"
            }
        }
        
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"$argString"
        $psi.Verb = "runas"
        [Diagnostics.Process]::Start($psi) | Out-Null
        exit
    }
}

# Robocopy flags from your specification
$RobocopyFlags = @(
    "/E",        # Copy subdirectories, including empty ones
    "/Z",        # Restartable mode
    "/J",        # Unbuffered I/O (better for large files)
    "/MT:8",     # Multi-threaded copy with 8 threads
    "/R:3",      # Retry 3 times on failed copies
    "/W:5",      # Wait 5 seconds between retries
    "/COPY:DATOS", # Copy Data, Attributes, Timestamps
    "/DCOPY:DATOS",# Copy Directory Data, Attributes, Timestamps
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
    "LocalLow"      = "{A520A1A4-1780-4FF6-BD18-167343C5AF16}"}

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
        "LocalLow"      = "$env:USERPROFILE\AppData\LocalLow"}

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
Write-Host "Reverse Mode: $Reverse" -ForegroundColor Yellow
Write-Host "Max Parallel: $MaxParallel" -ForegroundColor Yellow
Write-Host ""

$results = @()

# ScriptBlock for parallel robocopy execution
$copyScriptBlock = {
    param(
        [string]$Folder,
        [string]$SrcPath,
        [string]$DstPath,
        [string[]]$RobocopyFlags,
        [bool]$UpdateRegistry,
        [bool]$Reverse,
        [string]$DestinationRoot,
        [string]$UserProfilePath
    )

    $start = [System.Diagnostics.Stopwatch]::StartNew()
    
    if (-not (Test-Path $DstPath)) {
        New-Item -Path $DstPath -ItemType Directory -Force | Out-Null
    }
    
    $robocopyArgs = @($SrcPath, $DstPath) + $RobocopyFlags
    $exitCode = (Start-Process -FilePath "robocopy" -ArgumentList $robocopyArgs -Wait -PassThru).ExitCode
    
    $start.Stop()
    $success = $exitCode -le 3
    
    $result = [PSCustomObject]@{
        Folder     = $Folder
        Source     = $SrcPath
        Destination = $DstPath
        ExitCode   = $exitCode
        Success    = $success
        DurationMs = $start.ElapsedMilliseconds
        Timestamp  = Get-Date
    }
    
    if ($success -and $UpdateRegistry) {
        if ($Reverse) {
            $result | Add-Member -MemberType NoteProperty -Name 'RegistryPath' -Value (Join-Path $UserProfilePath $Folder)
        } else {
            $result | Add-Member -MemberType NoteProperty -Name 'RegistryPath' -Value $DstPath
        }
    }
    
    return $result
}

# Build work items (validate paths first, like before)
$workItems = @()
foreach ($folder in $FoldersToMove) {
    $sourcePath = Get-CurrentUserFolderPath -FolderName $folder
    
    if ($Reverse) {
        $srcPath = Join-Path $DestinationRoot $folder
        $dstPath = $sourcePath
    } else {
        $srcPath = $sourcePath
        $dstPath = Join-Path $DestinationRoot $folder
    }
    
    if (-not $sourcePath) {
        Write-Warning "Could not locate source path for $folder"
        $results += [PSCustomObject]@{
            Folder = $folder; Status = "Not Found"; Source = "N/A"; Destination = "N/A"; ExitCode = $null
        }
        continue
    }
    
    if (-not (Test-Path $srcPath)) {
        Write-Warning "Source path does not exist: $srcPath"
        $results += [PSCustomObject]@{
            Folder = $folder; Status = "Source Missing"; Source = $srcPath; Destination = "N/A"; ExitCode = $null
        }
        continue
    }
    
    if ($Reverse) {
        $srcPath = Join-Path $DestinationRoot $folder
        $dstPath = $sourcePath
    } else {
        $srcPath = $sourcePath
        $dstPath = Join-Path $DestinationRoot $folder
    }
    
    if ($DryRun -or $VerifyOnly) {
        Write-Host "Processing: $folder" -ForegroundColor Cyan
        Write-Host "  Source:      $srcPath" -ForegroundColor Gray
        Write-Host "  Destination: $dstPath" -ForegroundColor Gray
        Write-Host "  [DRY RUN] Would run: robocopy `"$srcPath`" `"$dstPath`" $($RobocopyFlags -join ' ')" -ForegroundColor Yellow
        $results += [PSCustomObject]@{
            Folder = $folder; Status = "Dry Run"; Source = $srcPath; Destination = $dstPath; ExitCode = $null
        }
        Write-Host ""; continue
    }
    
    $workItems += [PSCustomObject]@{
        Folder = $folder; SrcPath = $srcPath; DstPath = $dstPath
    }
}

# Execute in parallel using Runspace Pool
if ($workItems.Count -gt 0) {
    $pool = [RunspaceFactory]::CreateRunspacePool(1, $MaxParallel)
    $pool.Open()
    
    $powershellInstances = @()
    $asyncResults = @()
    
    try {
        foreach ($item in $workItems) {
            $ps = [PowerShell]::Create()
            $ps.RunspacePool = $pool
            [void]$ps.AddScript($copyScriptBlock)
            [void]$ps.AddArgument($item.Folder)
            [void]$ps.AddArgument($item.SrcPath)
            [void]$ps.AddArgument($item.DstPath)
            [void]$ps.AddArgument($RobocopyFlags)
            [void]$ps.AddArgument($UpdateRegistry)
            [void]$ps.AddArgument($Reverse)
            [void]$ps.AddArgument($DestinationRoot)
            [void]$ps.AddArgument($env:USERPROFILE)
            $async = $ps.BeginInvoke()
            $powershellInstances += $ps
            $asyncResults += $async
        }
        
        $completed = 0; $total = $asyncResults.Count
        while ($completed -lt $total) {
            for ($i = 0; $i -lt $total; $i++) {
                $ar = $asyncResults[$i]
                if ($ar -and $ar.IsCompleted -and -not $ar.AsyncWaitHandle.SafeWaitHandle.IsClosed) {
                    try {
                        $result = $powershellInstances[$i].EndInvoke($ar)
                        if ($result.Success) {
                            Write-Host "Processing: $($result.Folder)" -ForegroundColor Cyan
                            Write-Host "  Source:      $($result.Source)" -ForegroundColor Gray
                            Write-Host "  Destination: $($result.Destination)" -ForegroundColor Gray
                            Write-Host "  Copy completed (exit code: $($result.ExitCode), ${result.DurationMs}ms)" -ForegroundColor Green
                            if ($UpdateRegistry -and $result.RegistryPath) {
                                if ($Reverse) { Set-UserFolderPath -FolderName $result.Folder -NewPath (Join-Path $env:USERPROFILE $result.Folder) }
                                else { Set-UserFolderPath -FolderName $result.Folder -NewPath $result.RegistryPath }
                            }
                            $results += [PSCustomObject]@{
                                Folder = $result.Folder; Status = "Success"; Source = $result.Source; Destination = $result.Destination; ExitCode = $result.ExitCode
                            }
                        } else {
                            Write-Host "Processing: $($result.Folder)" -ForegroundColor Cyan
                            Write-Host "  Source:      $($result.Source)" -ForegroundColor Gray
                            Write-Host "  Destination: $($result.Destination)" -ForegroundColor Gray
                            Write-Error "  Copy FAILED (exit code: $($result.ExitCode), ${result.DurationMs}ms)"
                            $results += [PSCustomObject]@{
                                Folder = $result.Folder; Status = "Failed"; Source = $result.Source; Destination = $result.Destination; ExitCode = $result.ExitCode
                            }
                        }
                    }
                    catch {
                        Write-Error "  Exception: $($_.Exception.Message)"
                        $results += [PSCustomObject]@{
                            Folder = $item.Folder; Status = "Failed"; Source = $item.SrcPath; Destination = $item.DstPath; ExitCode = -1
                        }
                    }
                    $asyncResults[$i] = $null; $completed++; Write-Host ""
                }
            }
            if ($completed -lt $total) { Start-Sleep -Milliseconds 200 }
        }
    }
    finally {
        foreach ($ps in $powershellInstances) { $ps.Dispose() }
        $pool.Close(); $pool.Dispose()
    }
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


