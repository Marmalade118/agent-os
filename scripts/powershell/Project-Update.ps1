# =============================================================================
# Agent OS Project Update Script - PowerShell Version
# Updates Agent OS installation in a project
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
    [switch]$OverwriteAgents,
    [switch]$OverwriteCommands,
    [switch]$OverwriteStandards,
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
    # If Common-Functions.ps1 is not found locally, assume it's already imported as a module
    # This allows the script to work when Common-Functions is imported externally
    Write-Verbose "Common-Functions.ps1 not found locally, assuming it's imported as a module"
} else {
    # Import as module if found locally
    Import-Module $commonFunctionsPath -Force
}

# Set script variables for common functions
$script:BASE_DIR = $BASE_DIR
$script:PROJECT_DIR = $PROJECT_DIR
$script:DRY_RUN = $DryRun.IsPresent
$script:VERBOSE = $VerbosePreference -eq 'Continue'
$script:SKIPPED_FILES = @()
$script:UPDATED_FILES = @()
$script:NEW_FILES = @()

# -----------------------------------------------------------------------------
# Help Function
# -----------------------------------------------------------------------------

function Show-Help {
    Write-Host @"
Usage: .\Project-Update.ps1 [OPTIONS]

Update Agent OS installation in the current project directory.

Options:
    -Profile PROFILE                        Use specified profile (default: from project config)
    -ClaudeCodeCommands [BOOL]              Install Claude Code commands (true/false)
    -UseClaudeCodeSubagents [BOOL]          Use Claude Code subagents with delegation (true/false)
    -AgentOSCommands [BOOL]                 Install agent-os commands for other tools (true/false)
    -StandardsAsClaudeCodeSkills [BOOL]     Use Claude Code Skills for standards (true/false)
    -ReInstall                              Delete and reinstall Agent OS
    -OverwriteAll                           Overwrite all existing files
    -OverwriteAgents                        Overwrite existing agent files
    -OverwriteCommands                      Overwrite existing command files
    -OverwriteStandards                     Overwrite existing standards files
    -DryRun                                 Show what would be done without doing it
    -Verbose                                Show detailed output
    -Help                                   Show this help message

Examples:
    .\Project-Update.ps1
    .\Project-Update.ps1 -OverwriteAgents
    .\Project-Update.ps1 -ClaudeCodeCommands true -UseClaudeCodeSubagents true
    .\Project-Update.ps1 -DryRun -Verbose
"@
    exit 0
}

# -----------------------------------------------------------------------------
# Validation Functions
# -----------------------------------------------------------------------------

function Test-Installations {
    # Check base installation using common function
    Test-BaseInstallation
    
    # Check project installation
    $projectConfigPath = Join-Path $script:PROJECT_DIR "agent-os" "config.yml"
    if (-not (Test-Path $projectConfigPath)) {
        Write-Error "Agent OS not installed in this project"
        Write-Host ""
        Write-Status "Please run Project-Install.ps1 first"
        exit 1
    }
    
    Write-Verbose "Project installation found at: $script:PROJECT_DIR\agent-os"
}

# -----------------------------------------------------------------------------
# Configuration Functions
# -----------------------------------------------------------------------------

function Import-Configurations {
    # Load base and project configurations using common functions
    Import-BaseConfig
    Import-ProjectConfig
    
    # Set effective values
    # For update, base config is the "incoming" config (what we're updating TO)
    # Command line flags override base config
    $script:EFFECTIVE_PROFILE = if ($Profile) { $Profile } else { $script:BASE_PROFILE }
    $script:EFFECTIVE_CLAUDE_CODE_COMMANDS = if ($ClaudeCodeCommands) { $ClaudeCodeCommands -eq "true" } else { $script:BASE_CLAUDE_CODE_COMMANDS }
    $script:EFFECTIVE_USE_CLAUDE_CODE_SUBAGENTS = if ($UseClaudeCodeSubagents) { $UseClaudeCodeSubagents -eq "true" } else { $script:BASE_USE_CLAUDE_CODE_SUBAGENTS }
    $script:EFFECTIVE_AGENT_OS_COMMANDS = if ($AgentOSCommands) { $AgentOSCommands -eq "true" } else { $script:BASE_AGENT_OS_COMMANDS }
    $script:EFFECTIVE_STANDARDS_AS_CLAUDE_CODE_SKILLS = if ($StandardsAsClaudeCodeSkills) { $StandardsAsClaudeCodeSkills -eq "true" } else { $script:BASE_STANDARDS_AS_CLAUDE_CODE_SKILLS }
    $script:EFFECTIVE_VERSION = $script:BASE_VERSION
    
    # Validate config but suppress warnings (will show after user confirms update)
    Test-ConfigurationValid $script:EFFECTIVE_CLAUDE_CODE_COMMANDS $script:EFFECTIVE_USE_CLAUDE_CODE_SUBAGENTS $script:EFFECTIVE_AGENT_OS_COMMANDS $script:EFFECTIVE_STANDARDS_AS_CLAUDE_CODE_SKILLS $script:EFFECTIVE_PROFILE $false
    
    Write-Verbose "Base configuration:"
    Write-Verbose "  Version: $script:BASE_VERSION"
    Write-Verbose "  Profile: $script:BASE_PROFILE"
    Write-Verbose "  Claude Code commands: $script:BASE_CLAUDE_CODE_COMMANDS"
    Write-Verbose "  Use Claude Code subagents: $script:BASE_USE_CLAUDE_CODE_SUBAGENTS"
    Write-Verbose "  Agent OS commands: $script:BASE_AGENT_OS_COMMANDS"
    Write-Verbose "  Standards as Claude Code Skills: $script:BASE_STANDARDS_AS_CLAUDE_CODE_SKILLS"
    
    Write-Verbose "Project configuration:"
    Write-Verbose "  Version: $script:PROJECT_VERSION"
    Write-Verbose "  Profile: $script:PROJECT_PROFILE"
    Write-Verbose "  Claude Code commands: $script:PROJECT_CLAUDE_CODE_COMMANDS"
    Write-Verbose "  Use Claude Code subagents: $script:PROJECT_USE_CLAUDE_CODE_SUBAGENTS"
    Write-Verbose "  Agent OS commands: $script:PROJECT_AGENT_OS_COMMANDS"
    Write-Verbose "  Standards as Claude Code Skills: $script:PROJECT_STANDARDS_AS_CLAUDE_CODE_SKILLS"
    
    Write-Verbose "Effective configuration:"
    Write-Verbose "  Profile: $script:EFFECTIVE_PROFILE"
    Write-Verbose "  Claude Code commands: $script:EFFECTIVE_CLAUDE_CODE_COMMANDS"
    Write-Verbose "  Use Claude Code subagents: $script:EFFECTIVE_USE_CLAUDE_CODE_SUBAGENTS"
    Write-Verbose "  Agent OS commands: $script:EFFECTIVE_AGENT_OS_COMMANDS"
    Write-Verbose "  Standards as Claude Code Skills: $script:EFFECTIVE_STANDARDS_AS_CLAUDE_CODE_SKILLS"
}

# -----------------------------------------------------------------------------
# Update Functions
# -----------------------------------------------------------------------------

function Update-Standards {
    Write-Status "Updating standards"
    
    $standardsUpdated = 0
    $standardsSkipped = 0
    $standardsNew = 0
    
    $files = Get-ProfileFiles $script:PROJECT_PROFILE $script:BASE_DIR "standards"
    foreach ($file in $files) {
        if ($file -like "standards/*") {
            $source = Get-ProfileFile $script:PROJECT_PROFILE $file $script:BASE_DIR
            $dest = Join-Path $script:PROJECT_DIR "agent-os" $file
            
            if (Test-Path $source) {
                if (Test-ShouldSkipFile $dest $OverwriteAll.IsPresent $OverwriteStandards.IsPresent "standard") {
                    $script:SKIPPED_FILES += $dest
                    $standardsSkipped++
                    Write-Verbose "Skipped: $dest"
                } else {
                    if (Test-Path $dest) {
                        $script:UPDATED_FILES += $dest
                        $standardsUpdated++
                        Write-Verbose "Updated: $dest"
                    } else {
                        $script:NEW_FILES += $dest
                        $standardsNew++
                        Write-Verbose "New file: $dest"
                    }
                    if ($script:DRY_RUN -ne $true) {
                        Copy-FileWithDryRun $source $dest | Out-Null
                    }
                }
            }
        }
    }
    
    if ($script:DRY_RUN -ne $true) {
        if ($standardsNew -gt 0) {
            Write-Success "Added $standardsNew standards in agent-os/standards"
        }
        if ($standardsUpdated -gt 0) {
            Write-Success "Updated $standardsUpdated standards in agent-os/standards"
        }
        if ($standardsSkipped -gt 0) {
            Write-ColorOutput $script:Colors.YELLOW "$standardsSkipped files in agent-os/standards were not updated and overwritten. To update and overwrite these, re-run with -OverwriteStandards flag."
        }
    }
}

function Update-SingleAgentCommands {
    Write-Status "Updating single-agent commands..."
    $commandsUpdated = 0
    $commandsSkipped = 0
    $commandsNew = 0
    
    $files = Get-ProfileFiles $script:PROJECT_PROFILE $script:BASE_DIR "commands"
    foreach ($file in $files) {
        # Process single-agent command files OR orchestrate-tasks special case
        if ($file -like "commands/*/single-agent/*" -or $file -eq "commands/orchestrate-tasks/orchestrate-tasks.md") {
            $source = Get-ProfileFile $script:PROJECT_PROFILE $file $script:BASE_DIR
            if (Test-Path $source) {
                # Handle orchestrate-tasks specially
                if ($file -eq "commands/orchestrate-tasks/orchestrate-tasks.md") {
                    $dest = Join-Path $script:PROJECT_DIR "agent-os" "commands" "orchestrate-tasks" "orchestrate-tasks.md"
                } else {
                    # Strip the single-agent/ subfolder for agent-os/commands structure
                    $destFile = $file -replace '/single-agent', ''
                    $dest = Join-Path $script:PROJECT_DIR "agent-os" $destFile
                }
                
                if (Test-ShouldSkipFile $dest $OverwriteAll.IsPresent $OverwriteCommands.IsPresent "command") {
                    $script:SKIPPED_FILES += $dest
                    $commandsSkipped++
                    Write-Verbose "Skipped: $dest"
                } else {
                    if (Test-Path $dest) {
                        $script:UPDATED_FILES += $dest
                        $commandsUpdated++
                        Write-Verbose "Updated: $dest"
                    } else {
                        $script:NEW_FILES += $dest
                        $commandsNew++
                        Write-Verbose "New file: $dest"
                    }
                    if ($script:DRY_RUN -ne $true) {
                        # Compile with PHASE embedding
                        Invoke-CommandCompilation $source $dest $script:BASE_DIR $script:PROJECT_PROFILE "embed" | Out-Null
                    }
                }
            }
        }
    }
    
    if ($script:DRY_RUN -ne $true) {
        if ($commandsNew -gt 0) {
            Write-Success "Added $commandsNew single-agent commands"
        }
        if ($commandsUpdated -gt 0) {
            Write-Success "Updated $commandsUpdated single-agent commands"
        }
        if ($commandsSkipped -gt 0) {
            Write-ColorOutput $script:Colors.YELLOW "$commandsSkipped commands were not updated and overwritten. To update and overwrite these, re-run with -OverwriteCommands flag."
        }
    }
}

function Update-ClaudeCodeFiles {
    Write-Status "Updating Claude Code tools"
    
    $commandsUpdated = 0
    $commandsSkipped = 0
    $commandsNew = 0
    $agentsUpdated = 0
    $agentsSkipped = 0
    $agentsNew = 0
    
    # Update commands in .claude/commands/agent-os/
    # Determine which command mode to use based on subagents setting
    if ($script:PROJECT_USE_CLAUDE_CODE_SUBAGENTS -eq $true) {
        # Process multi-agent command files
        $files = Get-ProfileFiles $script:PROJECT_PROFILE $script:BASE_DIR "commands"
        foreach ($file in $files) {
            if ($file -like "commands/*/multi-agent/*" -or $file -eq "commands/orchestrate-tasks/orchestrate-tasks.md") {
                $source = Get-ProfileFile $script:PROJECT_PROFILE $file $script:BASE_DIR
                if (Test-Path $source) {
                    # Extract command name
                    if ($file -eq "commands/orchestrate-tasks/orchestrate-tasks.md") {
                        $commandName = "orchestrate-tasks"
                    } else {
                        $commandName = ($file -split '/')[1]
                    }
                    $dest = Join-Path $script:PROJECT_DIR ".claude" "commands" "agent-os" "$commandName.md"
                    
                    if (Test-ShouldSkipFile $dest $OverwriteAll.IsPresent $OverwriteCommands.IsPresent "command") {
                        $script:SKIPPED_FILES += $dest
                        $commandsSkipped++
                        Write-Verbose "Skipped: $dest"
                    } else {
                        if (Test-Path $dest) {
                            $script:UPDATED_FILES += $dest
                            $commandsUpdated++
                            Write-Verbose "Updated: $dest"
                        } else {
                            $script:NEW_FILES += $dest
                            $commandsNew++
                            Write-Verbose "New file: $dest"
                        }
                        if ($script:DRY_RUN -ne $true) {
                            # Compile with workflow and standards injection
                            Invoke-CommandCompilation $source $dest $script:BASE_DIR $script:PROJECT_PROFILE "" | Out-Null
                        }
                    }
                }
            }
        }
    } else {
        # Process single-agent command files (only non-numbered files, with PHASE embedding)
        $files = Get-ProfileFiles $script:PROJECT_PROFILE $script:BASE_DIR "commands"
        foreach ($file in $files) {
            if ($file -like "commands/*/single-agent/*" -or $file -eq "commands/orchestrate-tasks/orchestrate-tasks.md") {
                $source = Get-ProfileFile $script:PROJECT_PROFILE $file $script:BASE_DIR
                if (Test-Path $source) {
                    # Handle orchestrate-tasks specially
                    if ($file -eq "commands/orchestrate-tasks/orchestrate-tasks.md") {
                        $dest = Join-Path $script:PROJECT_DIR ".claude" "commands" "agent-os" "orchestrate-tasks.md"
                        
                        if (Test-ShouldSkipFile $dest $OverwriteAll.IsPresent $OverwriteCommands.IsPresent "command") {
                            $script:SKIPPED_FILES += $dest
                            $commandsSkipped++
                            Write-Verbose "Skipped: $dest"
                        } else {
                            if (Test-Path $dest) {
                                $script:UPDATED_FILES += $dest
                                $commandsUpdated++
                                Write-Verbose "Updated: $dest"
                            } else {
                                $script:NEW_FILES += $dest
                                $commandsNew++
                                Write-Verbose "New file: $dest"
                            }
                            if ($script:DRY_RUN -ne $true) {
                                Invoke-CommandCompilation $source $dest $script:BASE_DIR $script:PROJECT_PROFILE "" | Out-Null
                            }
                        }
                    } else {
                        # Only process non-numbered files
                        $filename = Split-Path $file -Leaf
                        if ($filename -notmatch '^[0-9]+-.*\.md$') {
                            $cmdName = ($file -split '/')[1]
                            $dest = Join-Path $script:PROJECT_DIR ".claude" "commands" "agent-os" "$cmdName.md"
                            
                            if (Test-ShouldSkipFile $dest $OverwriteAll.IsPresent $OverwriteCommands.IsPresent "command") {
                                $script:SKIPPED_FILES += $dest
                                $commandsSkipped++
                                Write-Verbose "Skipped: $dest"
                            } else {
                                if (Test-Path $dest) {
                                    $script:UPDATED_FILES += $dest
                                    $commandsUpdated++
                                    Write-Verbose "Updated: $dest"
                                } else {
                                    $script:NEW_FILES += $dest
                                    $commandsNew++
                                    Write-Verbose "New file: $dest"
                                }
                                if ($script:DRY_RUN -ne $true) {
                                    # Compile with PHASE embedding
                                    Invoke-CommandCompilation $source $dest $script:BASE_DIR $script:PROJECT_PROFILE "embed" | Out-Null
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    # Update static agents
    $files = Get-ProfileFiles $script:PROJECT_PROFILE $script:BASE_DIR "agents"
    foreach ($file in $files) {
        if ($file -like "agents/*.md" -and $file -notlike "agents/templates/*") {
            $source = Get-ProfileFile $script:PROJECT_PROFILE $file $script:BASE_DIR
            if (Test-Path $source) {
                $agentName = [System.IO.Path]::GetFileNameWithoutExtension((Split-Path $file -Leaf))
                $dest = Join-Path $script:PROJECT_DIR ".claude" "agents" "agent-os" "$agentName.md"
                
                if (Test-ShouldSkipFile $dest $OverwriteAll.IsPresent $OverwriteAgents.IsPresent "agent") {
                    $script:SKIPPED_FILES += $dest
                    Write-Verbose "Skipped: $dest"
                } else {
                    if (Test-Path $dest) {
                        $script:UPDATED_FILES += $dest
                        Write-Verbose "Updated: $dest"
                    } else {
                        $script:NEW_FILES += $dest
                        Write-Verbose "New file: $dest"
                    }
                    if ($script:DRY_RUN -ne $true) {
                        Invoke-AgentCompilation $source $dest $script:BASE_DIR $script:PROJECT_PROFILE "" | Out-Null
                    }
                }
            }
        }
    }
    
    if ($script:DRY_RUN -ne $true) {
        # Count commands separately
        $commandPattern = ".claude\commands\agent-os"
        $commandsActualUpdated = ($script:UPDATED_FILES | Where-Object { $_ -like "*$commandPattern*" }).Count
        $commandsActualSkipped = ($script:SKIPPED_FILES | Where-Object { $_ -like "*$commandPattern*" }).Count
        $commandsActualNew = ($script:NEW_FILES | Where-Object { $_ -like "*$commandPattern*" }).Count
        
        if ($commandsActualNew -gt 0) {
            Write-Success "Added $commandsActualNew Claude Code commands"
        }
        if ($commandsActualUpdated -gt 0) {
            Write-Success "Updated $commandsActualUpdated Claude Code commands"
        }
        if ($commandsActualSkipped -gt 0) {
            Write-ColorOutput $script:Colors.YELLOW "$commandsActualSkipped commands were not updated and overwritten. To update and overwrite these, re-run with -OverwriteCommands flag."
        }
        
        # Count agent files
        $agentPattern = ".claude\agents\agent-os"
        $agentsUpdated = ($script:UPDATED_FILES | Where-Object { $_ -like "*$agentPattern*" }).Count
        $agentsSkipped = ($script:SKIPPED_FILES | Where-Object { $_ -like "*$agentPattern*" }).Count
        $agentsNew = ($script:NEW_FILES | Where-Object { $_ -like "*$agentPattern*" }).Count
        
        if ($agentsNew -gt 0) {
            Write-Success "Added $agentsNew Claude Code agents"
        }
        if ($agentsUpdated -gt 0) {
            Write-Success "Updated $agentsUpdated Claude Code agents"
        }
        if ($agentsSkipped -gt 0) {
            Write-ColorOutput $script:Colors.YELLOW "$agentsSkipped agents were not updated and overwritten. To update and overwrite these, re-run with -OverwriteAgents flag."
        }
    }
}

function Update-AgentOSFolder {
    Write-Status "Updating agent-os folder"
    
    # Update the configuration file
    Set-ProjectConfig $script:EFFECTIVE_VERSION $script:PROJECT_PROFILE $script:PROJECT_CLAUDE_CODE_COMMANDS $script:PROJECT_USE_CLAUDE_CODE_SUBAGENTS $script:PROJECT_AGENT_OS_COMMANDS $script:PROJECT_STANDARDS_AS_CLAUDE_CODE_SKILLS | Out-Null
    
    if ($script:DRY_RUN -ne $true) {
        Write-Success "Updated agent-os folder"
        Write-Success "Updated agent-os project configuration"
    }
}

function Invoke-Update {
    # Display configuration at the top
    Write-Host ""
    Write-Status "Configuration:"
    Write-Host "  Profile: $($script:Colors.YELLOW)$script:PROJECT_PROFILE$($script:Colors.NC)"
    Write-Host "  Claude Code commands: $($script:Colors.YELLOW)$script:PROJECT_CLAUDE_CODE_COMMANDS$($script:Colors.NC)"
    Write-Host "  Use Claude Code subagents: $($script:Colors.YELLOW)$script:PROJECT_USE_CLAUDE_CODE_SUBAGENTS$($script:Colors.NC)"
    Write-Host "  Standards as Claude Code Skills: $($script:Colors.YELLOW)$script:PROJECT_STANDARDS_AS_CLAUDE_CODE_SKILLS$($script:Colors.NC)"
    Write-Host "  Agent OS commands: $($script:Colors.YELLOW)$script:PROJECT_AGENT_OS_COMMANDS$($script:Colors.NC)"
    Write-Host ""
    
    # Update agent-os folder and configuration
    Update-AgentOSFolder
    Write-Host ""
    
    # Update components based on enabled flags
    Update-Standards
    Write-Host ""
    
    # Update Claude Code files if enabled
    if ($script:PROJECT_CLAUDE_CODE_COMMANDS -eq $true) {
        Update-ClaudeCodeFiles
        Write-Host ""
        
        # Install/update Claude Code Skills (uses install function since directory was cleaned)
        Install-ClaudeCodeSkills
        Install-ImproveSkillsCommand
        Write-Host ""
    }
    
    # Update agent-os commands if enabled
    if ($script:PROJECT_AGENT_OS_COMMANDS -eq $true) {
        Update-SingleAgentCommands
        Write-Host ""
    }
    
    if ($script:DRY_RUN -eq $true) {
        Write-Warning "DRY RUN - No files were actually modified"
        Write-Host ""
        
        if ($script:NEW_FILES.Count -gt 0) {
            Write-Status "New files that would be added:"
            foreach ($file in $script:NEW_FILES) {
                Write-Host "  + $file"
            }
            Write-Host ""
        }
        
        if ($script:UPDATED_FILES.Count -gt 0) {
            Write-Status "Files that would be updated:"
            foreach ($file in $script:UPDATED_FILES) {
                Write-Host "  ~ $file"
            }
            Write-Host ""
        }
        
        if ($script:SKIPPED_FILES.Count -gt 0) {
            Write-Status "Files that would be skipped:"
            foreach ($file in $script:SKIPPED_FILES) {
                Write-Host "  - $file"
            }
            Write-Host ""
        }
        
        do {
            $proceed = Read-Host "Proceed with actual update? (y/n)"
        } while ($proceed -notmatch '^[yn]$')
        
        if ($proceed -eq "y") {
            $script:DRY_RUN = $false
            $script:SKIPPED_FILES = @()
            $script:UPDATED_FILES = @()
            $script:NEW_FILES = @()
            Invoke-Update
        }
    } else {
        Write-Success "Agent OS has been successfully updated!"
        Write-Host ""
        Write-ColorOutput $script:Colors.GREEN "Visit the docs for guides on how to use Agent OS: https://buildermethods.com/agent-os"
        Write-Host ""
    }
}

# -----------------------------------------------------------------------------
# Migration Functions for v2.1.0
# -----------------------------------------------------------------------------

function Show-UpdateConfirmation {
    param(
        [string]$CurrentVersion,
        [bool]$HasVersionDiff,
        [bool]$HasConfigDiff
    )
    
    $targetVersion = $script:BASE_VERSION
    
    # Determine if there are differences
    if ($HasVersionDiff -or $HasConfigDiff) {
        Write-Host ""
        Write-ColorOutput $script:Colors.PURPLE "=== Version/Configuration Update Required ==="
        Write-Host ""
        if ($script:DRY_RUN -eq $true) {
            Write-Warning "Dry run simulation"
        }
        Write-Host ""
        Write-Status "Your project's Agent OS version and/or configuration is different than the version you're trying to install."
    } else {
        Write-Host ""
        Write-ColorOutput $script:Colors.PURPLE "=== Confirm Update ==="
        Write-Host ""
        if ($script:DRY_RUN -eq $true) {
            Write-Warning "Dry run simulation"
        }
        Write-Host ""
        if ($script:DRY_RUN -eq $true) {
            Write-Status "Confirm you'd like to proceed with a DRY RUN update simulation."
        } else {
            Write-Status "Confirm you'd like to proceed with an update."
        }
    }
    Write-Host ""
    
    # Display current project config
    Write-Status "Current project's Agent OS:"
    if ($CurrentVersion) {
        Write-Host "  Version: $CurrentVersion"
    } else {
        Write-Host "  Version: (not specified)"
    }
    
    # Show old config values if they exist
    if ($script:MULTI_AGENT_MODE -or $script:SINGLE_AGENT_MODE -or $script:MULTI_AGENT_TOOL) {
        Write-Host "  Config format: Legacy (multi_agent_mode, single_agent_mode, multi_agent_tool)"
    } elseif ($script:PROJECT_CLAUDE_CODE_COMMANDS -ne $null) {
        Write-Host "  Profile: $($script:PROJECT_PROFILE)"
        Write-Host "  Claude Code commands: $script:PROJECT_CLAUDE_CODE_COMMANDS"
        Write-Host "  Use Claude Code subagents: $script:PROJECT_USE_CLAUDE_CODE_SUBAGENTS"
        Write-Host "  Agent OS commands: $script:PROJECT_AGENT_OS_COMMANDS"
        Write-Host "  Standards as Claude Code Skills: $script:PROJECT_STANDARDS_AS_CLAUDE_CODE_SKILLS"
    } else {
        Write-Host "  Config: Unable to read current configuration"
    }
    Write-Host ""
    
    # Display incoming config
    Write-Status "Incoming Agent OS:"
    Write-Host "  Version: $targetVersion"
    Write-Host "  Profile: $script:EFFECTIVE_PROFILE"
    Write-Host "  Claude Code commands: $script:EFFECTIVE_CLAUDE_CODE_COMMANDS"
    Write-Host "  Use Claude Code subagents: $script:EFFECTIVE_USE_CLAUDE_CODE_SUBAGENTS"
    Write-Host "  Agent OS commands: $script:EFFECTIVE_AGENT_OS_COMMANDS"
    Write-Host "  Standards as Claude Code Skills: $script:EFFECTIVE_STANDARDS_AS_CLAUDE_CODE_SKILLS"
    Write-Host ""
    
    # Show what will happen
    if ($script:DRY_RUN -eq $true) {
        Write-Status "Here's what WOULD happen if this were a real update (but it's a DRY RUN):"
    } else {
        Write-Status "Here's what will happen if you proceed:"
    }
    Write-Host ""
    Write-ColorOutput $script:Colors.GREEN "✔ These will remain intact:"
    Write-Host ""
    Write-Host "  - agent-os/specs/*"
    Write-Host "  - agent-os/product/*"
    Write-Host ""
    if ($script:DRY_RUN -eq $true) {
        Write-ColorOutput $script:Colors.YELLOW "⚠️  These WOULD BE deleted and re-installed to match the new version and configurations if this were a real update (but it's a DRY RUN):"
    } else {
        Write-ColorOutput $script:Colors.YELLOW "⚠️  These will be deleted and re-installed to match the new version and configurations:"
    }
    Write-Host ""
    Write-Host "  - agent-os/config.yml"
    Write-Host "  - agent-os/standards/"
    if ($script:EFFECTIVE_AGENT_OS_COMMANDS -eq $true -or (Test-Path (Join-Path $script:PROJECT_DIR "agent-os" "commands"))) {
        Write-Host "  - agent-os/commands/"
    }
    if ($script:EFFECTIVE_USE_CLAUDE_CODE_SUBAGENTS -eq $true -or (Test-Path (Join-Path $script:PROJECT_DIR ".claude" "agents" "agent-os"))) {
        Write-Host "  - .claude/agents/agent-os/"
    }
    if ($script:EFFECTIVE_CLAUDE_CODE_COMMANDS -eq $true -or (Test-Path (Join-Path $script:PROJECT_DIR ".claude" "commands" "agent-os"))) {
        Write-Host "  - .claude/commands/agent-os/"
    }
    if ($script:EFFECTIVE_STANDARDS_AS_CLAUDE_CODE_SKILLS -eq $true -or (Test-Path (Join-Path $script:PROJECT_DIR ".claude" "skills"))) {
        Write-Host "  - .claude/skills/ (Agent OS skills)"
    }
    Write-Host ""
    
    do {
        $proceed = Read-Host "Do you want to proceed? (y/n)"
    } while ($proceed -notmatch '^[yn]$')
    
    return $proceed -eq "y"
}

function Invoke-UpdateCleanup {
    if ($script:DRY_RUN -eq $true) {
        Write-Warning "Dry run: Would prepare for update..."
        Write-Host ""
    } else {
        Write-Status "Preparing for update..."
        Write-Host ""
    }
    
    # Delete agent-os/standards/ (will be reinstalled)
    $standardsPath = Join-Path $script:PROJECT_DIR "agent-os" "standards"
    if (Test-Path $standardsPath) {
        Write-Status "Removing agent-os/standards/"
        if ($script:DRY_RUN -ne $true) {
            Remove-Item $standardsPath -Recurse -Force
        }
    }
    
    # Delete agent-os/commands/ if exists
    $commandsPath = Join-Path $script:PROJECT_DIR "agent-os" "commands"
    if (Test-Path $commandsPath) {
        Write-Status "Removing agent-os/commands/"
        if ($script:DRY_RUN -ne $true) {
            Remove-Item $commandsPath -Recurse -Force
        }
    }
    
    # Delete .claude/agents/agent-os/ if exists
    $claudeAgentsPath = Join-Path $script:PROJECT_DIR ".claude" "agents" "agent-os"
    if (Test-Path $claudeAgentsPath) {
        Write-Status "Removing .claude/agents/agent-os/"
        if ($script:DRY_RUN -ne $true) {
            Remove-Item $claudeAgentsPath -Recurse -Force
        }
    }
    
    # Delete .claude/commands/agent-os/ if exists
    $claudeCommandsPath = Join-Path $script:PROJECT_DIR ".claude" "commands" "agent-os"
    if (Test-Path $claudeCommandsPath) {
        Write-Status "Removing .claude/commands/agent-os/"
        if ($script:DRY_RUN -ne $true) {
            Remove-Item $claudeCommandsPath -Recurse -Force
        }
    }
    
    # Delete old .claude/skills/agent-os/ if exists (legacy location)
    $legacySkillsPath = Join-Path $script:PROJECT_DIR ".claude" "skills" "agent-os"
    if (Test-Path $legacySkillsPath) {
        Write-Status "Removing legacy .claude/skills/agent-os/"
        if ($script:DRY_RUN -ne $true) {
            Remove-Item $legacySkillsPath -Recurse -Force
        }
    }
    
    # Delete individual Agent OS skills
    $skillsPath = Join-Path $script:PROJECT_DIR ".claude" "skills"
    if (Test-Path $skillsPath) {
        $files = Get-ProfileFiles $script:PROJECT_PROFILE $script:BASE_DIR "standards"
        foreach ($file in $files) {
            if ($file -like "standards/*" -and $file -like "*.md") {
                $skillName = $file -replace '^standards/', '' -replace '\.md$', '' -replace '/', '-'
                $skillDir = Join-Path $skillsPath $skillName
                if (Test-Path $skillDir) {
                    Write-Status "Removing .claude/skills/$skillName/"
                    if ($script:DRY_RUN -ne $true) {
                        Remove-Item $skillDir -Recurse -Force
                    }
                }
            }
        }
    }
    
    # Delete agent-os/roles/ if exists (legacy)
    $rolesPath = Join-Path $script:PROJECT_DIR "agent-os" "roles"
    if (Test-Path $rolesPath) {
        Write-Status "Removing legacy agent-os/roles/"
        if ($script:DRY_RUN -ne $true) {
            Remove-Item $rolesPath -Recurse -Force
        }
    }
    
    Write-Host ""
    if ($script:DRY_RUN -eq $true) {
        Write-Success "Dry run: Cleanup would be complete!"
    } else {
        Write-Success "Cleanup complete!"
    }
    Write-Host ""
    Write-Status "Proceeding with update..."
    Write-Host ""
}

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------

function Main {
    if ($ShowHelp) {
        Show-Help
    }
    
    # Check if we're trying to update in the base installation directory
    Test-NotBaseInstallation
    
    # Validate installations
    Test-Installations
    
    # Load configurations
    Import-Configurations
    
    # Check for version differences
    $hasVersionDiff = $false
    if ($script:PROJECT_VERSION -ne $script:BASE_VERSION -or (Test-NeedsMigration $script:PROJECT_VERSION)) {
        $hasVersionDiff = $true
    }
    
    # Check for config differences
    $hasConfigDiff = $false
    if ($script:PROJECT_PROFILE -ne $script:EFFECTIVE_PROFILE -or
        $script:PROJECT_CLAUDE_CODE_COMMANDS -ne $script:EFFECTIVE_CLAUDE_CODE_COMMANDS -or
        $script:PROJECT_USE_CLAUDE_CODE_SUBAGENTS -ne $script:EFFECTIVE_USE_CLAUDE_CODE_SUBAGENTS -or
        $script:PROJECT_AGENT_OS_COMMANDS -ne $script:EFFECTIVE_AGENT_OS_COMMANDS -or
        $script:PROJECT_STANDARDS_AS_CLAUDE_CODE_SKILLS -ne $script:EFFECTIVE_STANDARDS_AS_CLAUDE_CODE_SKILLS) {
        $hasConfigDiff = $true
    }
    
    # Always prompt for confirmation
    if (Show-UpdateConfirmation $script:PROJECT_VERSION $hasVersionDiff $hasConfigDiff) {
        # User confirmed - show any config validation warnings
        Write-Host ""
        Test-ConfigurationValid $script:EFFECTIVE_CLAUDE_CODE_COMMANDS $script:EFFECTIVE_USE_CLAUDE_CODE_SUBAGENTS $script:EFFECTIVE_AGENT_OS_COMMANDS $script:EFFECTIVE_STANDARDS_AS_CLAUDE_CODE_SKILLS $script:EFFECTIVE_PROFILE $true
        Write-Host ""
        
        # Perform cleanup and update
        Invoke-UpdateCleanup
        
        # Set PROJECT_* variables to match EFFECTIVE_* for Invoke-Update to use
        $script:PROJECT_PROFILE = $script:EFFECTIVE_PROFILE
        $script:PROJECT_CLAUDE_CODE_COMMANDS = $script:EFFECTIVE_CLAUDE_CODE_COMMANDS
        $script:PROJECT_USE_CLAUDE_CODE_SUBAGENTS = $script:EFFECTIVE_USE_CLAUDE_CODE_SUBAGENTS
        $script:PROJECT_AGENT_OS_COMMANDS = $script:EFFECTIVE_AGENT_OS_COMMANDS
        $script:PROJECT_STANDARDS_AS_CLAUDE_CODE_SKILLS = $script:EFFECTIVE_STANDARDS_AS_CLAUDE_CODE_SKILLS
        
        # Proceed with update
        Invoke-Update
        exit 0
    } else {
        Write-Status "Update cancelled by user"
        exit 0
    }
}

# Run main function
Main