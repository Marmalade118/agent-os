# =============================================================================
# Agent OS PowerShell Scripts Usage Examples
# Demonstrates proper usage of all Agent OS PowerShell scripts
# =============================================================================

Write-Host "=== Agent OS PowerShell Scripts Usage Examples ===" -ForegroundColor Cyan
Write-Host ""

# Get the script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "Available PowerShell Scripts:" -ForegroundColor Yellow
Write-Host "1. Base-Install.ps1     - Install Agent OS base system"
Write-Host "2. Project-Install.ps1  - Install Agent OS into a project"
Write-Host "3. Project-Update.ps1   - Update existing Agent OS installation"
Write-Host "4. Create-Profile.ps1   - Create custom Agent OS profiles"
Write-Host "5. Common-Functions.ps1 - Shared utility functions"
Write-Host ""

Write-Host "Basic Usage Examples:" -ForegroundColor Green
Write-Host ""

Write-Host "# Install Agent OS base system:" -ForegroundColor DarkGray
Write-Host ".\Base-Install.ps1"
Write-Host ""

Write-Host "# Install Agent OS into current project (requires base install first):" -ForegroundColor DarkGray
Write-Host "Import-Module .\Common-Functions.ps1 -Force"
Write-Host ".\Project-Install.ps1"
Write-Host ""

Write-Host "# Install with specific options:" -ForegroundColor DarkGray
Write-Host "Import-Module .\Common-Functions.ps1 -Force"
Write-Host ".\Project-Install.ps1 -Profile custom -ClaudeCodeCommands true"
Write-Host ""

Write-Host "# Dry run to see what would be installed:" -ForegroundColor DarkGray
Write-Host "Import-Module .\Common-Functions.ps1 -Force"
Write-Host ".\Project-Install.ps1 -DryRun"
Write-Host ""

Write-Host "# Update existing installation:" -ForegroundColor DarkGray
Write-Host "Import-Module .\Common-Functions.ps1 -Force"
Write-Host ".\Project-Update.ps1 -OverwriteStandards"
Write-Host ""

Write-Host "# Create a new profile:" -ForegroundColor DarkGray
Write-Host "Import-Module .\Common-Functions.ps1 -Force"
Write-Host ".\Create-Profile.ps1"
Write-Host ""

Write-Host "Important Notes:" -ForegroundColor Yellow
Write-Host "- Always import Common-Functions.ps1 before running project scripts"
Write-Host "- Base-Install.ps1 can be run standalone (it imports functions automatically)"
Write-Host "- Use -ShowHelp with any script to see detailed options"
Write-Host "- Scripts support both Windows PowerShell and PowerShell Core"
Write-Host ""

Write-Host "For detailed help on any script, run:" -ForegroundColor Cyan
Write-Host ".\[ScriptName].ps1 -ShowHelp"
Write-Host ""

Write-Host "PowerShell Syntax Checker:" -ForegroundColor Magenta
Write-Host "Use the included Claude skill to validate script syntax:"
Write-Host "powershell -NoProfile -File `".claude\skills\powershell-syntax-checker\scripts\check-syntax.ps1`" -Path `"scripts\powershell`" -Detailed"
Write-Host ""