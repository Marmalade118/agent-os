# =============================================================================
# Agent OS Project Installation Script - PowerShell Version
# Installs Agent OS into a project's codebase
# =============================================================================

[CmdletBinding()]
param(
    [string]$Profile,
    [string]$ClaudeCodeCommands,
    [string]$UseClaudeCodeSubagents,
    [string]$AgentOSCommands,
    [string]$StandardsAsClaudeCodeSkills,
    [switch]$ReInstall,
    [switch]$OverwriteAll,
    [switch]$OverwriteStandards,
    [switch]$OverwriteCommands,
    [switch]$OverwriteAgents,
    [switch]$DryRun,
    [switch]$ShowHelp
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Get the directory where this script is located
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$BASE_DIR = Join-Path $env:USERPROFILE "agent-os"
$PROJECT_DIR = Get-Location

# Source common functions
$commonFunctionsPath = Join-Path $SCRIPT_DIR "Common-Functions.ps1"
if (-not (Test-Path $commonFunctionsPath)) {
    Write-Host "Error: Common-Functions.ps1 not found at $commonFunctionsPath" -ForegroundColor Red
    exit 1
}
. $commonFunctionsPath

# Set script variables for common functions
$script:BASE_DIR = $BASE_DIR
$script:PROJECT_DIR = $PROJECT_DIR
$script:DRY_RUN = $DryRun.IsPresent
$script:VERBOSE = $VerbosePreference -eq 'Continue'
$script:INSTALLED_FILES = @()

# -----------------------------------------------------------------------------
# Help Function
# -----------------------------------------------------------------------------

function Show-Help {
    Write-Host @"
Usage: .\Project-Install.ps1 [OPTIONS]

Install Agent OS into the current project directory.

Options:
    -Profile PROFILE                        Use specified profile (default: from config.yml)
    -ClaudeCodeCommands [BOOL]              Install Claude Code commands (default: from config.yml)
    -UseClaudeCodeSubagents [BOOL]          Use Claude Code subagents (default: from config.yml)
    -AgentOSCommands [BOOL]                 Install agent-os commands (default: from config.yml)
    -StandardsAsClaudeCodeSkills [BOOL]     Use Claude Code Skills for standards (default: from config.yml)
    -ReInstall                              Delete and reinstall Agent OS
    -OverwriteAll                           Overwrite all existing files during update
    -OverwriteStandards                     Overwrite existing standards during update
    -OverwriteCommands                      Overwrite existing commands during update
    -OverwriteAgents                        Overwrite existing agents during update
    -DryRun                                 Show what would be done without doing it
    -Verbose                                Show detailed output
    -ShowHelp                               Show this help message

Examples:
    .\Project-Install.ps1
    .\Project-Install.ps1 -Profile rails
    .\Project-Install.ps1 -ClaudeCodeCommands true -UseClaudeCodeSubagents true
    .\Project-Install.ps1 -AgentOSCommands true -DryRun
"@
    exit 0
}

# -----------------------------------------------------------------------------
# Configuration Functions
# -----------------------------------------------------------------------------

function Import-Configuration {
    # Load base configuration using common function
    Import-BaseConfig
    
    # Set effective values (command line overrides base config)
    $script:EFFECTIVE_PROFILE = if ($Profile) { $Profile } else { $script:BASE_PROFILE }
    $script:EFFECTIVE_CLAUDE_CODE_COMMANDS = if ($ClaudeCodeCommands) { $ClaudeCodeCommands -eq "true" } else { $script:BASE_CLAUDE_CODE_COMMANDS }
    $script:EFFECTIVE_USE_CLAUDE_CODE_SUBAGENTS = if ($UseClaudeCodeSubagents) { $UseClaudeCodeSubagents -eq "true" } else { $script:BASE_USE_CLAUDE_CODE_SUBAGENTS }
    $script:EFFECTIVE_AGENT_OS_COMMANDS = if ($AgentOSCommands) { $AgentOSCommands -eq "true" } else { $script:BASE_AGENT_OS_COMMANDS }
    $script:EFFECTIVE_STANDARDS_AS_CLAUDE_CODE_SKILLS = if ($StandardsAsClaudeCodeSkills) { $StandardsAsClaudeCodeSkills -eq "true" } else { $script:BASE_STANDARDS_AS_CLAUDE_CODE_SKILLS }
    $script:EFFECTIVE_VERSION = $script:BASE_VERSION
    
    # Validate configuration
    Test-ConfigurationValid $script:EFFECTIVE_CLAUDE_CODE_COMMANDS $script:EFFECTIVE_USE_CLAUDE_CODE_SUBAGENTS $script:EFFECTIVE_AGENT_OS_COMMANDS $script:EFFECTIVE_STANDARDS_AS_CLAUDE_CODE_SKILLS $script:EFFECTIVE_PROFILE
    
    Write-Verbose "Configuration loaded:"
    Write-Verbose "  Profile: $script:EFFECTIVE_PROFILE"
    Write-Verbose "  Claude Code commands: $script:EFFECTIVE_CLAUDE_CODE_COMMANDS"
    Write-Verbose "  Use Claude Code subagents: $script:EFFECTIVE_USE_CLAUDE_CODE_SUBAGENTS"
    Write-Verbose "  Agent OS commands: $script:EFFECTIVE_AGENT_OS_COMMANDS"
    Write-Verbose "  Standards as Claude Code Skills: $script:EFFECTIVE_STANDARDS_AS_CLAUDE_CODE_SKILLS"
}

# -----------------------------------------------------------------------------
# Installation Functions
# -----------------------------------------------------------------------------

function Install-Standards {
    if ($script:DRY_RUN -ne $true) {
        Write-Status "Installing standards"
    }
    
    $standardsCount = 0
    
    $files = Get-ProfileFiles $script:EFFECTIVE_PROFILE $script:BASE_DIR "standards"
    foreach ($file in $files) {
        if ($file -like "standards/*") {
            $source = Get-ProfileFile $script:EFFECTIVE_PROFILE $file $script:BASE_DIR
            $dest = Join-Path $script:PROJECT_DIR "agent-os" $file
            
            if (Test-Path $source) {
                $installedFile = Copy-FileWithDryRun $source $dest
                if ($installedFile) {
                    $script:INSTALLED_FILES += $installedFile
                    $standardsCount++
                }
            }
        }
    }
    
    if ($script:DRY_RUN -ne $true) {
        if ($standardsCount -gt 0) {
            Write-Success "Installed $standardsCount standards in agent-os/standards"
        }
    }
}

function Install-ClaudeCodeCommandsWithDelegation {
    if ($script:DRY_RUN -ne $true) {
        Write-Status "Installing Claude Code commands (with delegation to subagents)..."
    }
    
    $commandsCount = 0
    $targetDir = Join-Path $script:PROJECT_DIR ".claude" "commands" "agent-os"
    New-DirectoryIfNotExists $targetDir
    
    $files = Get-ProfileFiles $script:EFFECTIVE_PROFILE $script:BASE_DIR "commands"
    foreach ($file in $files) {
        # Process multi-agent command files OR orchestrate-tasks special case
        if ($file -like "commands/*/multi-agent/*" -or $file -eq "commands/orchestrate-tasks/orchestrate-tasks.md") {
            $source = Get-ProfileFile $script:EFFECTIVE_PROFILE $file $script:BASE_DIR
            if (Test-Path $source) {
                # Extract command name from path
                $cmdName = ($file -split '/')[1]
                $dest = Join-Path $targetDir "$cmdName.md"
                
                # Compile with workflow and standards injection
                $compiled = Invoke-CommandCompilation $source $dest $script:BASE_DIR $script:EFFECTIVE_PROFILE
                if ($script:DRY_RUN -eq $true) {
                    $script:INSTALLED_FILES += $dest
                }
                $commandsCount++
            }
        }
    }
    
    if ($script:DRY_RUN -ne $true) {
        if ($commandsCount -gt 0) {
            Write-Success "Installed $commandsCount Claude Code commands (with delegation)"
        }
    }
}

function Install-ClaudeCodeCommandsWithoutDelegation {
    if ($script:DRY_RUN -ne $true) {
        Write-Status "Installing Claude Code commands (without delegation)..."
    }
    
    $commandsCount = 0
    
    $files = Get-ProfileFiles $script:EFFECTIVE_PROFILE $script:BASE_DIR "commands"
    foreach ($file in $files) {
        # Process single-agent command files OR orchestrate-tasks special case
        if ($file -like "commands/*/single-agent/*" -or $file -eq "commands/orchestrate-tasks/orchestrate-tasks.md") {
            $source = Get-ProfileFile $script:EFFECTIVE_PROFILE $file $script:BASE_DIR
            if (Test-Path $source) {
                # Handle orchestrate-tasks specially
                if ($file -eq "commands/orchestrate-tasks/orchestrate-tasks.md") {
                    $dest = Join-Path $script:PROJECT_DIR ".claude" "commands" "agent-os" "orchestrate-tasks.md"
                    # Compile without PHASE embedding for orchestrate-tasks
                    $compiled = Invoke-CommandCompilation $source $dest $script:BASE_DIR $script:EFFECTIVE_PROFILE ""
                    if ($script:DRY_RUN -eq $true) {
                        $script:INSTALLED_FILES += $dest
                    }
                    $commandsCount++
                } else {
                    # Only install non-numbered files
                    $filename = Split-Path $file -Leaf
                    if ($filename -notmatch '^[0-9]+-.*\.md$') {
                        # Extract command name
                        $cmdName = ($file -split '/')[1]
                        $dest = Join-Path $script:PROJECT_DIR ".claude" "commands" "agent-os" "$cmdName.md"
                        
                        # Compile with PHASE embedding
                        $compiled = Invoke-CommandCompilation $source $dest $script:BASE_DIR $script:EFFECTIVE_PROFILE "embed"
                        if ($script:DRY_RUN -eq $true) {
                            $script:INSTALLED_FILES += $dest
                        }
                        $commandsCount++
                    }
                }
            }
        }
    }
    
    if ($script:DRY_RUN -ne $true) {
        if ($commandsCount -gt 0) {
            Write-Success "Installed $commandsCount Claude Code commands (without delegation)"
        }
    }
}

function Install-ClaudeCodeAgents {
    if ($script:DRY_RUN -ne $true) {
        Write-Status "Installing Claude Code agents..."
    }
    
    $agentsCount = 0
    $targetDir = Join-Path $script:PROJECT_DIR ".claude" "agents" "agent-os"
    New-DirectoryIfNotExists $targetDir
    
    $files = Get-ProfileFiles $script:EFFECTIVE_PROFILE $script:BASE_DIR "agents"
    foreach ($file in $files) {
        # Include all agent files (flatten structure)
        if ($file -like "agents/*.md" -and $file -notlike "agents/templates/*") {
            $source = Get-ProfileFile $script:EFFECTIVE_PROFILE $file $script:BASE_DIR
            if (Test-Path $source) {
                # Get just the filename (flatten directory structure)
                $filename = Split-Path $file -Leaf
                $dest = Join-Path $targetDir $filename
                
                # Compile with workflow and standards injection
                $compiled = Invoke-AgentCompilation $source $dest $script:BASE_DIR $script:EFFECTIVE_PROFILE ""
                if ($script:DRY_RUN -eq $true) {
                    $script:INSTALLED_FILES += $dest
                }
                $agentsCount++
            }
        }
    }
    
    if ($script:DRY_RUN -ne $true) {
        if ($agentsCount -gt 0) {
            Write-Success "Installed $agentsCount Claude Code agents"
        }
    }
}

function Install-AgentOSCommands {
    if ($script:DRY_RUN -ne $true) {
        Write-Status "Installing agent-os commands..."
    }
    
    $commandsCount = 0
    
    $files = Get-ProfileFiles $script:EFFECTIVE_PROFILE $script:BASE_DIR "commands"
    foreach ($file in $files) {
        # Process single-agent command files OR orchestrate-tasks special case
        if ($file -like "commands/*/single-agent/*" -or $file -eq "commands/orchestrate-tasks/orchestrate-tasks.md") {
            $source = Get-ProfileFile $script:EFFECTIVE_PROFILE $file $script:BASE_DIR
            if (Test-Path $source) {
                # Handle orchestrate-tasks specially
                if ($file -eq "commands/orchestrate-tasks/orchestrate-tasks.md") {
                    $dest = Join-Path $script:PROJECT_DIR "agent-os" "commands" "orchestrate-tasks" "orchestrate-tasks.md"
                } else {
                    # Extract command name and preserve numbering
                    $cmdPath = $file -replace "commands/([^/]*)/single-agent/(.*)", '$1/$2'
                    $dest = Join-Path $script:PROJECT_DIR "agent-os" "commands" $cmdPath
                }
                
                # Compile with workflow and standards injection and PHASE embedding
                $compiled = Invoke-CommandCompilation $source $dest $script:BASE_DIR $script:EFFECTIVE_PROFILE "embed"
                if ($script:DRY_RUN -eq $true) {
                    $script:INSTALLED_FILES += $dest
                }
                $commandsCount++
            }
        }
    }
    
    if ($script:DRY_RUN -ne $true) {
        if ($commandsCount -gt 0) {
            Write-Success "Installed $commandsCount agent-os commands"
        }
    }
}

function New-AgentOSFolder {
    if ($script:DRY_RUN -ne $true) {
        Write-Status "Installing agent-os folder"
    }
    
    # Create the main agent-os folder
    $agentOSPath = Join-Path $script:PROJECT_DIR "agent-os"
    New-DirectoryIfNotExists $agentOSPath
    
    # Create the configuration file
    $configFile = Set-ProjectConfig $script:EFFECTIVE_VERSION $script:EFFECTIVE_PROFILE $script:EFFECTIVE_CLAUDE_CODE_COMMANDS $script:EFFECTIVE_USE_CLAUDE_CODE_SUBAGENTS $script:EFFECTIVE_AGENT_OS_COMMANDS $script:EFFECTIVE_STANDARDS_AS_CLAUDE_CODE_SKILLS
    if ($script:DRY_RUN -eq $true -and $configFile) {
        $script:INSTALLED_FILES += $configFile
    }
    
    if ($script:DRY_RUN -ne $true) {
        Write-Success "Created agent-os folder"
        Write-Success "Created agent-os project configuration"
    }
}

function Invoke-Installation {
    # Show dry run warning at the top if applicable
    if ($script:DRY_RUN -eq $true) {
        Write-Warning "DRY RUN - No files will be actually created"
        Write-Host ""
    }
    
    # Display configuration at the top
    Write-Host ""
    Write-Status "Configuration:"
    Write-Host "  Profile: $($script:Colors.YELLOW)$script:EFFECTIVE_PROFILE$($script:Colors.NC)"
    Write-Host "  Claude Code commands: $($script:Colors.YELLOW)$script:EFFECTIVE_CLAUDE_CODE_COMMANDS$($script:Colors.NC)"
    Write-Host "  Use Claude Code subagents: $($script:Colors.YELLOW)$script:EFFECTIVE_USE_CLAUDE_CODE_SUBAGENTS$($script:Colors.NC)"
    Write-Host "  Standards as Claude Code Skills: $($script:Colors.YELLOW)$script:EFFECTIVE_STANDARDS_AS_CLAUDE_CODE_SKILLS$($script:Colors.NC)"
    Write-Host "  Agent OS commands: $($script:Colors.YELLOW)$script:EFFECTIVE_AGENT_OS_COMMANDS$($script:Colors.NC)"
    Write-Host ""
    
    # In dry run mode, just collect files silently
    if ($script:DRY_RUN -eq $true) {
        # Collect files without output
        New-AgentOSFolder
        Install-Standards
        
        # Install Claude Code files if enabled
        if ($script:EFFECTIVE_CLAUDE_CODE_COMMANDS -eq $true) {
            if ($script:EFFECTIVE_USE_CLAUDE_CODE_SUBAGENTS -eq $true) {
                Install-ClaudeCodeCommandsWithDelegation
                Install-ClaudeCodeAgents
            } else {
                Install-ClaudeCodeCommandsWithoutDelegation
            }
            Install-ClaudeCodeSkills
            Install-ImproveSkillsCommand
        }
        
        # Install agent-os commands if enabled
        if ($script:EFFECTIVE_AGENT_OS_COMMANDS -eq $true) {
            Install-AgentOSCommands
        }
        
        Write-Host ""
        Write-Status "The following files would be created:"
        foreach ($file in $script:INSTALLED_FILES) {
            # Make paths relative to project root
            $relativePath = $file.Replace("$script:PROJECT_DIR\", "")
            Write-Host "  - $relativePath"
        }
    } else {
        # Normal installation with output
        New-AgentOSFolder
        Write-Host ""
        
        Install-Standards
        Write-Host ""
        
        # Install Claude Code files if enabled
        if ($script:EFFECTIVE_CLAUDE_CODE_COMMANDS -eq $true) {
            if ($script:EFFECTIVE_USE_CLAUDE_CODE_SUBAGENTS -eq $true) {
                Install-ClaudeCodeCommandsWithDelegation
                Write-Host ""
                Install-ClaudeCodeAgents
                Write-Host ""
            } else {
                Install-ClaudeCodeCommandsWithoutDelegation
                Write-Host ""
            }
            Install-ClaudeCodeSkills
            Install-ImproveSkillsCommand
            Write-Host ""
        }
        
        # Install agent-os commands if enabled
        if ($script:EFFECTIVE_AGENT_OS_COMMANDS -eq $true) {
            Install-AgentOSCommands
            Write-Host ""
        }
    }
    
    if ($script:DRY_RUN -eq $true) {
        Write-Host ""
        do {
            $proceed = Read-Host "Proceed with actual installation? (y/n)"
        } while ($proceed -notmatch '^[yn]$')
        
        if ($proceed -eq "y") {
            $script:DRY_RUN = $false
            $script:INSTALLED_FILES = @()
            Invoke-Installation
        }
    } else {
        Write-Success "Agent OS has been successfully installed in your project!"
        Write-Host ""
        Write-ColorOutput $script:Colors.GREEN "Visit the docs for guides on how to use Agent OS: https://buildermethods.com/agent-os"
        Write-Host ""
    }
}

function Invoke-Reinstallation {
    Write-Section "Re-installation"
    
    Write-Warning "This will DELETE your current agent-os/ folder and reinstall from scratch."
    Write-Host ""
    
    # Check for Claude Code files
    $claudeAgentsPath = Join-Path $script:PROJECT_DIR ".claude" "agents" "agent-os"
    $claudeCommandsPath = Join-Path $script:PROJECT_DIR ".claude" "commands" "agent-os"
    
    if ((Test-Path $claudeAgentsPath) -or (Test-Path $claudeCommandsPath)) {
        Write-Warning "This will also DELETE:"
        if (Test-Path $claudeAgentsPath) { Write-Host "  - .claude/agents/agent-os/" }
        if (Test-Path $claudeCommandsPath) { Write-Host "  - .claude/commands/agent-os/" }
        Write-Host ""
    }
    
    do {
        $proceed = Read-Host "Are you sure you want to proceed? (y/n)"
    } while ($proceed -notmatch '^[yn]$')
    
    if ($proceed -ne "y") {
        Write-Status "Re-installation cancelled"
        exit 0
    }
    
    if ($script:DRY_RUN -ne $true) {
        Write-Status "Removing existing installation..."
        $agentOSPath = Join-Path $script:PROJECT_DIR "agent-os"
        if (Test-Path $agentOSPath) { Remove-Item $agentOSPath -Recurse -Force }
        if (Test-Path $claudeAgentsPath) { Remove-Item $claudeAgentsPath -Recurse -Force }
        if (Test-Path $claudeCommandsPath) { Remove-Item $claudeCommandsPath -Recurse -Force }
        Write-Success "Existing installation removed"
        Write-Host ""
    }
    
    Invoke-Installation
}

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------

function Main {
    if ($ShowHelp) {
        Show-Help
    }
    
    Write-Section "Agent OS Project Installation"
    
    # Check if we're trying to install in the base installation directory
    Test-NotBaseInstallation
    
    # Validate base installation
    Test-BaseInstallation
    
    # Load configuration
    Import-Configuration
    
    # Check if Agent OS is already installed
    if (Test-AgentOSInstalled $script:PROJECT_DIR) {
        if ($ReInstall) {
            Invoke-Reinstallation
        } else {
            # Delegate to update script
            Write-Status "Agent OS is already installed. Running update..."
            $updateScript = Join-Path $SCRIPT_DIR "Project-Update.ps1"
            
            # Build arguments for update script
            $updateArgs = @()
            if ($Profile) { $updateArgs += "-Profile", $Profile }
            if ($ClaudeCodeCommands) { $updateArgs += "-ClaudeCodeCommands", $ClaudeCodeCommands }
            if ($UseClaudeCodeSubagents) { $updateArgs += "-UseClaudeCodeSubagents", $UseClaudeCodeSubagents }
            if ($AgentOSCommands) { $updateArgs += "-AgentOSCommands", $AgentOSCommands }
            if ($StandardsAsClaudeCodeSkills) { $updateArgs += "-StandardsAsClaudeCodeSkills", $StandardsAsClaudeCodeSkills }
            if ($OverwriteAll) { $updateArgs += "-OverwriteAll" }
            if ($OverwriteStandards) { $updateArgs += "-OverwriteStandards" }
            if ($OverwriteCommands) { $updateArgs += "-OverwriteCommands" }
            if ($OverwriteAgents) { $updateArgs += "-OverwriteAgents" }
            if ($DryRun) { $updateArgs += "-DryRun" }
            if ($VerbosePreference -eq 'Continue') { $updateArgs += "-Verbose" }
            
            & $updateScript @updateArgs
        }
    } else {
        # Fresh installation
        Invoke-Installation
    }
}

# Run main function
Main