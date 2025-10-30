# =============================================================================
# Agent OS Create Profile Script - PowerShell Version
# Creates a new profile for Agent OS
# =============================================================================

[CmdletBinding()]
param(
    [switch]$ShowHelp
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Get the directory where this script is located
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$BASE_DIR = Join-Path $env:USERPROFILE "agent-os"
$PROFILES_DIR = Join-Path $BASE_DIR "profiles"

# Source common functions
$commonFunctionsPath = Join-Path $SCRIPT_DIR "Common-Functions.ps1"
if (-not (Test-Path $commonFunctionsPath)) {
    Write-Host "Error: Common-Functions.ps1 not found at $commonFunctionsPath" -ForegroundColor Red
    exit 1
}
. $commonFunctionsPath

# Set script variables for common functions
$script:BASE_DIR = $BASE_DIR
$script:DRY_RUN = $false
$script:VERBOSE = $VerbosePreference -eq 'Continue'

# -----------------------------------------------------------------------------
# Default Values
# -----------------------------------------------------------------------------

$PROFILE_NAME = ""
$INHERIT_FROM = ""
$COPY_FROM = ""

# -----------------------------------------------------------------------------
# Validation Functions
# -----------------------------------------------------------------------------

function Test-Installation {
    # Check base installation
    Test-BaseInstallation
    
    if (-not (Test-Path $PROFILES_DIR)) {
        Write-Error "Profiles directory not found at $PROFILES_DIR"
        exit 1
    }
}

# -----------------------------------------------------------------------------
# Profile Functions
# -----------------------------------------------------------------------------

function Get-AvailableProfiles {
    $profiles = @()
    
    # Find all directories in profiles/
    if (Test-Path $PROFILES_DIR) {
        $dirs = Get-ChildItem -Path $PROFILES_DIR -Directory
        foreach ($dir in $dirs) {
            $profiles += $dir.Name
        }
    }
    
    return $profiles
}

# -----------------------------------------------------------------------------
# Profile Name Input
# -----------------------------------------------------------------------------

function Get-ProfileName {
    $valid = $false
    
    while (-not $valid) {
        Write-Host ""
        Write-Host ""
        Write-Host ""
        Write-Status "Enter a name for the new profile:"
        Write-Host "Example names: 'rails', 'python', 'react', 'wordpress'"
        Write-Host ""
        
        $profileInput = Read-Host "Profile name"
        
        # Normalize the name
        $script:PROFILE_NAME = ConvertTo-NormalizedName $profileInput
        
        if ([string]::IsNullOrEmpty($script:PROFILE_NAME)) {
            Write-Error "Profile name cannot be empty"
            continue
        }
        
        # Check if profile already exists
        $profilePath = Join-Path $PROFILES_DIR $script:PROFILE_NAME
        if (Test-Path $profilePath) {
            Write-Error "Profile '$script:PROFILE_NAME' already exists"
            Write-Host "Please choose a different name"
            continue
        }
        
        $valid = $true
        Write-Success "Profile name set to: $script:PROFILE_NAME"
    }
}

# -----------------------------------------------------------------------------
# Inheritance Selection
# -----------------------------------------------------------------------------

function Select-Inheritance {
    $profiles = Get-AvailableProfiles
    
    if ($profiles.Count -eq 0) {
        Write-Warning "No existing profiles found to inherit from"
        $script:INHERIT_FROM = ""
        return
    }
    
    Write-Host ""
    Write-Host ""
    Write-Host ""
    
    if ($profiles.Count -eq 1) {
        # Only one profile exists
        Write-Status "Should this profile inherit from the '$($profiles[0])' profile?"
        Write-Host ""
        
        do {
            $inheritChoice = Read-Host "Inherit from '$($profiles[0])'? (y/n)"
        } while ($inheritChoice -notmatch '^[yn]$')
        
        if ($inheritChoice -eq "y") {
            $script:INHERIT_FROM = $profiles[0]
            Write-Success "Profile will inherit from: $script:INHERIT_FROM"
        } else {
            $script:INHERIT_FROM = ""
            Write-Status "Profile will not inherit from any profile"
        }
    } else {
        # Multiple profiles exist
        Write-Status "Select a profile to inherit from:"
        Write-Host ""
        Write-Host "  1) Don't inherit from any profile"
        
        $index = 2
        foreach ($profile in $profiles) {
            Write-Host "  $index) $profile"
            $index++
        }
        
        Write-Host ""
        do {
            $selection = Read-Host "Enter selection (1-$($profiles.Count + 1))"
        } while ($selection -notmatch '^\d+$' -or [int]$selection -lt 1 -or [int]$selection -gt ($profiles.Count + 1))
        
        $selectionInt = [int]$selection
        if ($selectionInt -eq 1) {
            $script:INHERIT_FROM = ""
            Write-Status "Profile will not inherit from any profile"
        } else {
            $script:INHERIT_FROM = $profiles[$selectionInt - 2]
            Write-Success "Profile will inherit from: $script:INHERIT_FROM"
        }
    }
}

# -----------------------------------------------------------------------------
# Copy Selection
# -----------------------------------------------------------------------------

function Select-CopySource {
    # Only ask about copying if not inheriting
    if (-not [string]::IsNullOrEmpty($script:INHERIT_FROM)) {
        $script:COPY_FROM = ""
        return
    }
    
    $profiles = Get-AvailableProfiles
    
    if ($profiles.Count -eq 0) {
        Write-Warning "No existing profiles found to copy from"
        $script:COPY_FROM = ""
        return
    }
    
    Write-Host ""
    Write-Host ""
    Write-Host ""
    
    if ($profiles.Count -eq 1) {
        # Only one profile exists
        Write-Status "Do you want to copy the contents from the '$($profiles[0])' profile?"
        Write-Host ""
        
        do {
            $copyChoice = Read-Host "Copy from '$($profiles[0])'? (y/n)"
        } while ($copyChoice -notmatch '^[yn]$')
        
        if ($copyChoice -eq "y") {
            $script:COPY_FROM = $profiles[0]
            Write-Success "Will copy contents from: $script:COPY_FROM"
        } else {
            $script:COPY_FROM = ""
            Write-Status "Will create empty profile structure"
        }
    } else {
        # Multiple profiles exist
        Write-Status "Select a profile to copy from:"
        Write-Host ""
        Write-Host "  1) Don't copy from any profile"
        
        $index = 2
        foreach ($profile in $profiles) {
            Write-Host "  $index) $profile"
            $index++
        }
        
        Write-Host ""
        do {
            $selection = Read-Host "Enter selection (1-$($profiles.Count + 1))"
        } while ($selection -notmatch '^\d+$' -or [int]$selection -lt 1 -or [int]$selection -gt ($profiles.Count + 1))
        
        $selectionInt = [int]$selection
        if ($selectionInt -eq 1) {
            $script:COPY_FROM = ""
            Write-Status "Will create empty profile structure"
        } else {
            $script:COPY_FROM = $profiles[$selectionInt - 2]
            Write-Success "Will copy contents from: $script:COPY_FROM"
        }
    }
}

# -----------------------------------------------------------------------------
# Profile Creation
# -----------------------------------------------------------------------------

function New-ProfileStructure {
    $profilePath = Join-Path $PROFILES_DIR $script:PROFILE_NAME
    
    Write-Status "Creating profile structure..."
    
    if (-not [string]::IsNullOrEmpty($script:COPY_FROM)) {
        # Copy from existing profile
        Write-Status "Copying from profile: $script:COPY_FROM"
        $sourcePath = Join-Path $PROFILES_DIR $script:COPY_FROM
        Copy-Item $sourcePath $profilePath -Recurse
        
        # Update profile-config.yml
        $configContent = @"
inherits_from: false

# Profile configuration for $script:PROFILE_NAME
# Copied from: $script:COPY_FROM
"@
        $configPath = Join-Path $profilePath "profile-config.yml"
        $configContent | Out-File -FilePath $configPath -Encoding UTF8
        
        Write-Success "Profile copied and configured"
    } else {
        # Create new structure
        New-Item -ItemType Directory -Path $profilePath -Force | Out-Null
        
        # Create standard directories
        New-Item -ItemType Directory -Path (Join-Path $profilePath "standards") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $profilePath "workflows" "implementation") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $profilePath "workflows" "planning") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $profilePath "workflows" "specification") -Force | Out-Null
        
        # Create profile-config.yml
        $configContent = if (-not [string]::IsNullOrEmpty($script:INHERIT_FROM)) {
            @"
inherits_from: $script:INHERIT_FROM

# Uncomment and modify to exclude specific inherited files:
# exclude_inherited_files:
#   - standards/backend/api/*
#   - standards/backend/database/migrations.md
#   - workflows/implementation/specific-workflow.md
"@
        } else {
            @"
inherits_from: false

# Profile configuration for $script:PROFILE_NAME
"@
        }
        
        $configPath = Join-Path $profilePath "profile-config.yml"
        $configContent | Out-File -FilePath $configPath -Encoding UTF8
        
        Write-Success "Profile structure created"
    }
}

# -----------------------------------------------------------------------------
# Help Function
# -----------------------------------------------------------------------------

function Show-Help {
    Write-Host @"
Usage: .\Create-Profile.ps1

Creates a new profile for Agent OS.

Options:
  -ShowHelp   Show this help message

Examples:
  .\Create-Profile.ps1
"@
    exit 0
}

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------

function Main {
    if ($ShowHelp) {
        Show-Help
    }
    
    Clear-Host
    Write-Host ""
    Write-ColorOutput $script:Colors.BLUE "=== Agent OS - Create Profile Utility ==="
    Write-Host ""
    
    # Validate installation
    Test-Installation
    
    # Get profile name
    Get-ProfileName
    
    # Select inheritance
    Select-Inheritance
    
    # Select copy source (if not inheriting)
    Select-CopySource
    
    # Create the profile
    New-ProfileStructure
    
    # Success message
    Write-Host ""
    Write-ColorOutput $script:Colors.GREEN "========================================"
    Write-Host ""
    Write-Success "Profile '$script:PROFILE_NAME' has been successfully created!"
    Write-Host ""
    Write-Status "Location: $PROFILES_DIR\$script:PROFILE_NAME"
    
    if (-not [string]::IsNullOrEmpty($script:INHERIT_FROM)) {
        Write-Host ""
        Write-Status "This profile inherits from: $script:INHERIT_FROM"
    } elseif (-not [string]::IsNullOrEmpty($script:COPY_FROM)) {
        Write-Host ""
        Write-Status "This profile was copied from: $script:COPY_FROM"
    }
    
    Write-Host ""
    Write-Status "Next steps:"
    Write-Host "  1. Customize standards, workflows, and configurations in your profile"
    Write-Host "  2. Install Agent OS in a project using this profile with: & `"$env:USERPROFILE\agent-os\scripts\powershell\Project-Install.ps1`" -Profile $script:PROFILE_NAME"
    Write-Host ""
    Write-ColorOutput $script:Colors.GREEN "Visit the docs on customizing your profile: https://buildermethods.com/agent-os/profiles"
    Write-Host ""
    Write-ColorOutput $script:Colors.GREEN "========================================"
    Write-Host ""
}

# Run main function
Main