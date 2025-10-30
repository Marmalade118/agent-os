# =============================================================================
# Agent OS Base Installation Script - PowerShell Version
# Installs Agent OS from GitHub repository to ~/agent-os
# =============================================================================

[CmdletBinding()]
param(
    [switch]$ShowHelp
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Repository configuration
$REPO_URL = "https://github.com/marmalade118/agent-os"

# Installation paths
$BASE_DIR = Join-Path $env:USERPROFILE "agent-os"
$TEMP_DIR = [System.IO.Path]::GetTempPath() + [System.IO.Path]::GetRandomFileName()

# -----------------------------------------------------------------------------
# Bootstrap Functions (before common-functions.ps1 is available)
# -----------------------------------------------------------------------------

# Minimal color codes for bootstrap
$BLUE = "`e[0;36m"
$RED = "`e[0;31m"
$YELLOW = "`e[1;33m"
$NC = "`e[0m"

# Bootstrap print functions
function Write-BootstrapStatus {
    param([string]$Message)
    Write-Host "$BLUE$Message$NC"
}

function Write-BootstrapError {
    param([string]$Message)
    Write-Host "$RED✗ $Message$NC"
}

# Download common-functions.ps1 first
function Get-CommonFunctions {
    $functionsUrl = "$REPO_URL/raw/main/scripts/powershell/Common-Functions.ps1"
    $commonFunctionsTemp = Join-Path $TEMP_DIR "Common-Functions.ps1"
    
    try {
        New-Item -ItemType Directory -Path $TEMP_DIR -Force | Out-Null
        Invoke-WebRequest -Uri $functionsUrl -OutFile $commonFunctionsTemp -UseBasicParsing
        
        # Import the common functions
        . $commonFunctionsTemp
        return $true
    }
    catch {
        # If remote download fails, try to find local copy
        $localCommonFunctions = Join-Path $PSScriptRoot "Common-Functions.ps1"
        if (Test-Path $localCommonFunctions) {
            Write-BootstrapStatus "Using local Common-Functions.ps1..."
            . $localCommonFunctions
            return $true
        }
        Write-BootstrapError "Failed to download Common-Functions.ps1 and no local copy found: $_"
        return $false
    }
}

# -----------------------------------------------------------------------------
# Initialize common functions
# -----------------------------------------------------------------------------

Write-BootstrapStatus "Initializing..."
if (-not (Get-CommonFunctions)) {
    exit 1
}

# Set script variables for common functions
$script:BASE_DIR = $BASE_DIR
$script:DRY_RUN = $false
$script:VERBOSE = $VerbosePreference -eq 'Continue'

# Clean up temp directory on exit
$cleanupScript = {
    if (Test-Path $TEMP_DIR) {
        Remove-Item $TEMP_DIR -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action $cleanupScript | Out-Null

# -----------------------------------------------------------------------------
# Version Functions
# -----------------------------------------------------------------------------

function Get-LatestVersion {
    $configUrl = "$REPO_URL/raw/main/config.yml"
    try {
        $response = Invoke-WebRequest -Uri $configUrl -UseBasicParsing
        $content = $response.Content
        if ($content -match "version:\s*(.+)") {
            return $Matches[1].Trim()
        }
    }
    catch {
        Write-Verbose "Failed to get latest version: $_"
    }
    return "2.1.0"  # fallback
}

# -----------------------------------------------------------------------------
# Download Functions
# -----------------------------------------------------------------------------

function Get-FileFromGitHub {
    param(
        [string]$RelativePath,
        [string]$DestPath
    )
    
    $fileUrl = "$REPO_URL/raw/main/$RelativePath"
    $destDir = Split-Path $DestPath -Parent
    
    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }
    
    try {
        Invoke-WebRequest -Uri $fileUrl -OutFile $DestPath -UseBasicParsing
        return $true
    }
    catch {
        Write-Verbose "Failed to download $RelativePath`: $_"
        return $false
    }
}

# Define exclusion patterns
$EXCLUSIONS = @(
    "scripts/base-install.sh",
    "scripts/powershell/Base-Install.ps1",
    "old-versions/*",
    ".git*",
    ".github/*"
)

function Test-ShouldExclude {
    param([string]$FilePath)
    
    foreach ($pattern in $EXCLUSIONS) {
        # Check exact match
        if ($FilePath -eq $pattern) {
            return $true
        }
        # Check wildcard patterns
        if ($pattern -like "*/*") {
            $prefix = $pattern -replace '/\*$', '/'
            if ($FilePath -like "$prefix*") {
                return $true
            }
        }
    }
    return $false
}

function Get-AllRepoFiles {
    # Get the default branch
    $branch = "main"
    
    # Extract owner and repo name from URL
    $repoPath = $REPO_URL -replace '^https://github.com/', ''
    
    Write-Verbose "Repository path: $repoPath"
    
    # Build API URL
    $treeUrl = "https://api.github.com/repos/$repoPath/git/trees/$branch?recursive=true"
    
    Write-Verbose "Fetching from: $treeUrl"
    
    try {
        $response = Invoke-RestMethod -Uri $treeUrl -UseBasicParsing
        
        if ($response.tree) {
            $files = @()
            foreach ($item in $response.tree) {
                if ($item.type -eq "blob" -and -not (Test-ShouldExclude $item.path)) {
                    $files += $item.path
                }
            }
            return $files
        }
    }
    catch {
        Write-Verbose "GitHub API error: $_"
        Write-Verbose "Falling back to essential files list..."
        
        # Fallback list of essential files for a basic installation
        $essentialFiles = @(
            "config.yml",
            "CHANGELOG.md",
            "README.md",
            "LICENSE",
            "profiles/default/claude-code-skill-template.md",
            "profiles/default/agents/implementer.md",
            "profiles/default/agents/spec-writer.md",
            "profiles/default/commands/plan-product/single-agent/plan-product.md",
            "profiles/default/commands/write-spec/single-agent/write-spec.md",
            "profiles/default/standards/global/coding-style.md",
            "profiles/default/standards/global/error-handling.md",
            "profiles/default/workflows/specification/write-spec.md"
        )
        
        return $essentialFiles
    }
    
    return @()
}

function Get-AllFiles {
    param([string]$DestBase)
    
    Write-Verbose "Fetching repository file list..."
    
    $allFiles = Get-AllRepoFiles
    
    if ($allFiles.Count -eq 0) {
        return 0
    }
    
    $fileCount = 0
    foreach ($filePath in $allFiles) {
        if ($filePath) {
            $destFile = Join-Path $DestBase $filePath
            
            if (Get-FileFromGitHub $filePath $destFile) {
                $fileCount++
                Write-Verbose "  Downloaded: $filePath"
            } else {
                Write-Verbose "  Failed to download: $filePath"
            }
        }
    }
    
    return $fileCount
}

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

function Show-Spinner {
    param([string]$Message = "Installing Agent OS files")
    
    $job = Start-Job -ScriptBlock {
        $counter = 0
        while ($true) {
            $dots = "." * ($counter % 4)
            $spaces = " " * (3 - ($counter % 4))
            Write-Host "`r$using:BLUE$using:Message$dots$spaces$using:NC" -NoNewline
            Start-Sleep -Milliseconds 500
            $counter++
        }
    }
    
    return $job
}

# -----------------------------------------------------------------------------
# Installation Functions
# -----------------------------------------------------------------------------

function Install-AllFiles {
    $spinnerJob = $null
    
    if (-not $script:VERBOSE) {
        # Hide cursor and start spinner
        [Console]::CursorVisible = $false
        $spinnerJob = Show-Spinner
    } else {
        Write-Status "Installing Agent OS files..."
    }
    
    try {
        # Download all files
        $fileCount = Get-AllFiles $BASE_DIR
        
        # Stop spinner if running
        if ($spinnerJob) {
            Stop-Job $spinnerJob
            Remove-Job $spinnerJob
            Write-Host "`r" -NoNewline
            [Console]::CursorVisible = $true
        }
        
        if ($fileCount -gt 0) {
            Write-Success "Installed $fileCount files to ~/agent-os"
        } else {
            Write-Error "No files were downloaded"
            return $false
        }
        
        # Make scripts executable (PowerShell scripts don't need chmod)
        $scriptsDir = Join-Path $BASE_DIR "scripts"
        if (Test-Path $scriptsDir) {
            # For PowerShell, we don't need to set execute permissions
            Write-Verbose "Scripts directory found at: $scriptsDir"
        }
        
        return $true
    }
    finally {
        if ($spinnerJob) {
            Stop-Job $spinnerJob -ErrorAction SilentlyContinue
            Remove-Job $spinnerJob -ErrorAction SilentlyContinue
            [Console]::CursorVisible = $true
        }
    }
}

# -----------------------------------------------------------------------------
# Overwrite Functions
# -----------------------------------------------------------------------------

function Show-OverwritePrompt {
    param(
        [string]$CurrentVersion,
        [string]$LatestVersion
    )
    
    Write-Host ""
    Write-ColorOutput $YELLOW "=== ⚠️  Existing Installation Detected ==="
    Write-Host ""
    
    Write-Host "You already have a base installation of Agent OS"
    
    if ($CurrentVersion) {
        Write-Host "  Your installed version: $YELLOW$CurrentVersion$NC"
    } else {
        Write-Host "  Your installed version: (unknown)"
    }
    
    if ($LatestVersion) {
        Write-Host "  Latest available version: $YELLOW$LatestVersion$NC"
    } else {
        Write-Host "  Latest available version: (unable to determine)"
    }
    
    Write-Host ""
    Write-Status "What would you like to do?"
    Write-Host ""
    
    Write-ColorOutput $YELLOW "1) Full update"
    Write-Host ""
    Write-Host "    Updates & overwrites:"
    Write-Host "    - ~/agent-os/profiles/default/*"
    Write-Host "    - ~/agent-os/scripts/*"
    Write-Host "    - ~/agent-os/CHANGELOG.md"
    Write-Host ""
    Write-Host "    Updates your version number in ~/agent-os/config.yml but doesn't change anything else in this file."
    Write-Host ""
    Write-Host "    Everything else in your ~/agent-os folder will remain intact."
    Write-Host ""
    
    Write-ColorOutput $YELLOW "2) Update default profile only"
    Write-Host ""
    Write-Host "    Updates & overwrites:"
    Write-Host "    - ~/agent-os/profiles/default/*"
    Write-Host ""
    Write-Host "    Everything else in your ~/agent-os folder will remain intact."
    Write-Host ""
    
    Write-ColorOutput $YELLOW "3) Update scripts only"
    Write-Host ""
    Write-Host "    Updates & overwrites:"
    Write-Host "    - ~/agent-os/scripts/*"
    Write-Host ""
    Write-Host "    Everything else in your ~/agent-os folder will remain intact."
    Write-Host ""
    
    Write-ColorOutput $YELLOW "4) Update config.yml only"
    Write-Host ""
    Write-Host "    Updates & overwrites:"
    Write-Host "    - ~/agent-os/config.yml"
    Write-Host ""
    Write-Host "    Everything else in your ~/agent-os folder will remain intact."
    Write-Host ""
    
    Write-ColorOutput $YELLOW "5) Delete & reinstall fresh"
    Write-Host ""
    Write-Host "    - Makes a backup of your current ~/agent-os folder at ~/agent-os.backup"
    Write-Host "    - Deletes your current ~/agent-os folder and all of its contents."
    Write-Host "    - Installs a fresh ~/agent-os base installation"
    Write-Host ""
    
    Write-ColorOutput $YELLOW "6) Cancel and abort"
    Write-Host ""
    
    do {
        $choice = Read-Host "Enter your choice (1-6)"
    } while ($choice -notmatch '^[1-6]$')
    
    switch ($choice) {
        "1" {
            Write-Host ""
            Write-Status "Performing full update..."
            Invoke-FullUpdate $LatestVersion
        }
        "2" {
            Write-Host ""
            Write-Status "Updating default profile..."
            New-Backup
            Update-Profile
        }
        "3" {
            Write-Host ""
            Write-Status "Updating scripts..."
            New-Backup
            Update-Scripts
        }
        "4" {
            Write-Host ""
            Write-Status "Updating config.yml..."
            New-Backup
            Update-Config
        }
        "5" {
            Write-Host ""
            Write-Status "Deleting & reinstalling fresh..."
            Invoke-OverwriteAll
        }
        "6" {
            Write-Host ""
            Write-Warning "Installation cancelled"
            exit 0
        }
    }
}

function New-Backup {
    $backupPath = "$BASE_DIR.backup"
    if (Test-Path $backupPath) {
        Remove-Item $backupPath -Recurse -Force
    }
    Copy-Item $BASE_DIR $backupPath -Recurse
    Write-Success "Backed up existing installation to ~/agent-os.backup"
    Write-Host ""
}

function Invoke-FullUpdate {
    param([string]$LatestVersion)
    
    # Create backup first
    New-Backup
    
    # Update default profile
    Write-Status "Updating default profile..."
    $profilePath = Join-Path $BASE_DIR "profiles" "default"
    if (Test-Path $profilePath) {
        Remove-Item $profilePath -Recurse -Force
    }
    
    $fileCount = 0
    $allFiles = Get-AllRepoFiles | Where-Object { $_ -like "profiles/default/*" }
    foreach ($filePath in $allFiles) {
        if ($filePath) {
            $destFile = Join-Path $BASE_DIR $filePath
            if (Get-FileFromGitHub $filePath $destFile) {
                $fileCount++
                Write-Verbose "  Downloaded: $filePath"
            }
        }
    }
    Write-Success "Updated default profile ($fileCount files)"
    Write-Host ""
    
    # Update scripts
    Write-Status "Updating scripts..."
    $scriptsPath = Join-Path $BASE_DIR "scripts"
    if (Test-Path $scriptsPath) {
        Remove-Item $scriptsPath -Recurse -Force
    }
    
    $fileCount = 0
    $allFiles = Get-AllRepoFiles | Where-Object { $_ -like "scripts/*" }
    foreach ($filePath in $allFiles) {
        if ($filePath) {
            $destFile = Join-Path $BASE_DIR $filePath
            if (Get-FileFromGitHub $filePath $destFile) {
                $fileCount++
                Write-Verbose "  Downloaded: $filePath"
            }
        }
    }
    Write-Success "Updated scripts ($fileCount files)"
    Write-Host ""
    
    # Update CHANGELOG.md
    Write-Status "Updating CHANGELOG.md..."
    $changelogPath = Join-Path $BASE_DIR "CHANGELOG.md"
    if (Get-FileFromGitHub "CHANGELOG.md" $changelogPath) {
        Write-Success "Updated CHANGELOG.md"
    }
    Write-Host ""
    
    # Update version number in config.yml
    Write-Status "Updating version number in config.yml..."
    $configPath = Join-Path $BASE_DIR "config.yml"
    if ((Test-Path $configPath) -and $LatestVersion) {
        $content = Get-Content $configPath -Raw
        $content = $content -replace "^version:.*", "version: $LatestVersion"
        $content | Out-File -FilePath $configPath -Encoding UTF8
        Write-Success "Updated version to $LatestVersion in config.yml"
    }
    Write-Host ""
    
    Write-Success "Full update completed!"
}

function Invoke-OverwriteAll {
    # Backup existing installation
    $backupPath = "$BASE_DIR.backup"
    if (Test-Path $backupPath) {
        Remove-Item $backupPath -Recurse -Force
    }
    Move-Item $BASE_DIR $backupPath
    Write-Success "Backed up existing installation to ~/agent-os.backup"
    Write-Host ""
    
    # Perform fresh installation
    Invoke-FreshInstallation
}

function Update-Profile {
    # Remove existing default profile
    $profilePath = Join-Path $BASE_DIR "profiles" "default"
    if (Test-Path $profilePath) {
        Remove-Item $profilePath -Recurse -Force
    }
    
    # Download only profile files
    $fileCount = 0
    $allFiles = Get-AllRepoFiles | Where-Object { $_ -like "profiles/default/*" }
    foreach ($filePath in $allFiles) {
        if ($filePath) {
            $destFile = Join-Path $BASE_DIR $filePath
            if (Get-FileFromGitHub $filePath $destFile) {
                $fileCount++
                Write-Verbose "  Downloaded: $filePath"
            }
        }
    }
    
    Write-Success "Updated default profile ($fileCount files)"
    Write-Host ""
    Write-Success "Default profile has been updated!"
}

function Update-Scripts {
    # Remove existing scripts
    $scriptsPath = Join-Path $BASE_DIR "scripts"
    if (Test-Path $scriptsPath) {
        Remove-Item $scriptsPath -Recurse -Force
    }
    
    # Download only script files
    $fileCount = 0
    $allFiles = Get-AllRepoFiles | Where-Object { $_ -like "scripts/*" }
    foreach ($filePath in $allFiles) {
        if ($filePath) {
            $destFile = Join-Path $BASE_DIR $filePath
            if (Get-FileFromGitHub $filePath $destFile) {
                $fileCount++
                Write-Verbose "  Downloaded: $filePath"
            }
        }
    }
    
    Write-Success "Updated scripts ($fileCount files)"
    Write-Host ""
    Write-Success "Scripts have been updated!"
}

function Update-Config {
    # Download new config.yml
    $configPath = Join-Path $BASE_DIR "config.yml"
    if (Get-FileFromGitHub "config.yml" $configPath) {
        Write-Verbose "  Downloaded: config.yml"
    }
    
    Write-Success "Updated config.yml"
    Write-Host ""
    Write-Success "Config has been updated!"
}

# -----------------------------------------------------------------------------
# Main Installation Functions
# -----------------------------------------------------------------------------

function Invoke-FreshInstallation {
    Write-Host ""
    Write-Status "Configuration:"
    Write-Host "  Repository: $YELLOW$REPO_URL$NC"
    Write-Host "  Target: ${YELLOW}~/agent-os$NC"
    Write-Host ""
    
    # Create base directory
    New-DirectoryIfNotExists $BASE_DIR
    Write-Success "Created base directory: ~/agent-os"
    Write-Host ""
    
    # Install all files from repository
    if (-not (Install-AllFiles)) {
        Write-Error "Installation failed"
        exit 1
    }
    
    Write-Host ""
    Write-Success "Agent OS has been successfully installed!"
    Write-Host ""
    Write-ColorOutput $script:Colors.GREEN "Next steps:"
    Write-Host ""
    Write-ColorOutput $script:Colors.GREEN "1) Customize your profile's standards in ~/agent-os/profiles/default/standards"
    Write-Host ""
    Write-ColorOutput $script:Colors.GREEN "2) Navigate to a project directory"
    Write-Host "   ${YELLOW}cd path\to\project-directory$NC"
    Write-Host ""
    Write-ColorOutput $script:Colors.GREEN "3) Install Agent OS in your project by running:"
    Write-Host "   ${YELLOW}& `"$env:USERPROFILE\agent-os\scripts\powershell\Project-Install.ps1`"$NC"
    Write-Host ""
    Write-ColorOutput $script:Colors.GREEN "Visit the docs for guides on how to use Agent OS: https://buildermethods.com/agent-os"
    Write-Host ""
}

function Test-ExistingInstallation {
    if (Test-Path $BASE_DIR) {
        # Get current version if available
        $currentVersion = ""
        $configPath = Join-Path $BASE_DIR "config.yml"
        if (Test-Path $configPath) {
            $currentVersion = Get-YamlValue $configPath "version" ""
        }
        
        # Get latest version from GitHub
        $latestVersion = Get-LatestVersion
        
        # Prompt for overwrite choice
        Show-OverwritePrompt $currentVersion $latestVersion
    } else {
        # Fresh installation
        Invoke-FreshInstallation
    }
}

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------

function Show-Help {
    Write-Host @"
Usage: .\Base-Install.ps1 [OPTIONS]

Options:
  -Verbose    Show verbose output
  -ShowHelp   Show this help message

Examples:
  .\Base-Install.ps1
  .\Base-Install.ps1 -Verbose
"@
    exit 0
}

function Main {
    if ($ShowHelp) {
        Show-Help
    }
    
    Write-Section "Agent OS Base Installation"
    
    # Check for required tools
    try {
        Invoke-WebRequest -Uri "https://www.google.com" -UseBasicParsing -TimeoutSec 5 | Out-Null
    }
    catch {
        Write-Error "Internet connection or Invoke-WebRequest is required but not working. Please check your connection and try again."
        exit 1
    }
    
    # Check for existing installation or perform fresh install
    Test-ExistingInstallation
}

# Run main function
Main