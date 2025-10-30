# =============================================================================
# Agent OS Common Functions - PowerShell Version
# Shared utilities for Agent OS scripts
# =============================================================================

# Colors for output (using ANSI escape codes for cross-platform compatibility)
$script:Colors = @{
    RED    = "`e[38;2;255;32;86m"
    GREEN  = "`e[38;2;0;234;179m"
    YELLOW = "`e[38;2;255;185;0m"
    BLUE   = "`e[38;2;0;208;255m"
    PURPLE = "`e[38;2;142;81;255m"
    NC     = "`e[0m"  # No Color
}

# -----------------------------------------------------------------------------
# Global Variables (set by scripts that use this module)
# -----------------------------------------------------------------------------
# These should be set by the calling script:
# $script:BASE_DIR, $script:PROJECT_DIR, $script:DRY_RUN, $script:VERBOSE

# -----------------------------------------------------------------------------
# Output Functions
# -----------------------------------------------------------------------------

function Write-ColorOutput {
    param(
        [string]$Color,
        [string]$Message
    )
    Write-Host "$Color$Message$($script:Colors.NC)"
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-ColorOutput $script:Colors.BLUE "=== $Title ==="
    Write-Host ""
}

function Write-Status {
    param([string]$Message)
    Write-ColorOutput $script:Colors.BLUE $Message
}

function Write-Success {
    param([string]$Message)
    Write-ColorOutput $script:Colors.GREEN "✓ $Message"
}

function Write-Warning {
    param([string]$Message)
    Write-ColorOutput $script:Colors.YELLOW "⚠️  $Message"
}

function Write-Error {
    param([string]$Message)
    Write-ColorOutput $script:Colors.RED "✗ $Message"
}

function Write-Verbose {
    param([string]$Message)
    if ($script:VERBOSE -eq $true) {
        Write-Host "[VERBOSE] $Message" -ForegroundColor Gray
    }
}

# -----------------------------------------------------------------------------
# String Normalization Functions
# -----------------------------------------------------------------------------

function ConvertTo-NormalizedName {
    param([string]$InputString)
    
    return $InputString.ToLower() -replace '[ _]', '-' -replace '[^a-z0-9-]', ''
}

# -----------------------------------------------------------------------------
# YAML Parsing Functions
# -----------------------------------------------------------------------------

function Get-YamlValue {
    param(
        [string]$FilePath,
        [string]$Key,
        [string]$DefaultValue = ""
    )
    
    if (-not (Test-Path $FilePath)) {
        return $DefaultValue
    }
    
    $content = Get-Content $FilePath -Raw
    $pattern = "^$Key\s*:\s*(.*)$"
    
    if ($content -match $pattern) {
        $value = $Matches[1].Trim()
        # Remove quotes if present
        $value = $value -replace '^["`'']|["`'']$', ''
        if ($value) {
            return $value
        }
    }
    
    return $DefaultValue
}

function Get-YamlArray {
    param(
        [string]$FilePath,
        [string]$Key
    )
    
    if (-not (Test-Path $FilePath)) {
        return @()
    }
    
    $content = Get-Content $FilePath
    $found = $false
    $keyIndent = -1
    $arrayIndent = -1
    $result = @()
    
    foreach ($line in $content) {
        $originalLine = $line
        $trimmedLine = $line.Trim()
        
        # Calculate indentation
        $indent = $line.Length - $line.TrimStart().Length
        
        # Look for the key
        if (-not $found -and $trimmedLine -match "^$Key\s*:") {
            $found = $true
            $keyIndent = $indent
            continue
        }
        
        # Process array items under the key
        if ($found) {
            # If we hit a line with same or less indentation as key, stop
            if ($indent -le $keyIndent -and $trimmedLine -ne "" -and $trimmedLine -notmatch '^\s*$') {
                break
            }
            
            # Look for array items (- item)
            if ($trimmedLine -match '^-\s+(.*)') {
                # Set array indent from first item
                if ($arrayIndent -eq -1) {
                    $arrayIndent = $indent
                }
                
                # Only process items at the expected indentation
                if ($indent -eq $arrayIndent) {
                    $value = $Matches[1].Trim()
                    # Remove quotes if present
                    $value = $value -replace '^["`'']|["`'']$', ''
                    $result += $value
                }
            }
        }
    }
    
    return $result
}

# -----------------------------------------------------------------------------
# File Operations Functions
# -----------------------------------------------------------------------------

function New-DirectoryIfNotExists {
    param([string]$Path)
    
    if ($script:DRY_RUN -eq $true) {
        if (-not (Test-Path $Path)) {
            Write-Verbose "Would create directory: $Path"
        }
    } else {
        if (-not (Test-Path $Path)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            Write-Verbose "Created directory: $Path"
        }
    }
}

function Copy-FileWithDryRun {
    param(
        [string]$Source,
        [string]$Destination
    )
    
    if ($script:DRY_RUN -eq $true) {
        return $Destination
    } else {
        $destDir = Split-Path $Destination -Parent
        New-DirectoryIfNotExists $destDir
        Copy-Item $Source $Destination -Force
        Write-Verbose "Copied: $Source -> $Destination"
        return $Destination
    }
}

function Set-FileContentWithDryRun {
    param(
        [string]$Content,
        [string]$Destination
    )
    
    if ($script:DRY_RUN -eq $true) {
        return $Destination
    } else {
        $destDir = Split-Path $Destination -Parent
        New-DirectoryIfNotExists $destDir
        $Content | Out-File -FilePath $Destination -Encoding UTF8
        Write-Verbose "Wrote file: $Destination"
        return $Destination
    }
}

function Test-ShouldSkipFile {
    param(
        [string]$FilePath,
        [bool]$OverwriteAll,
        [bool]$OverwriteType,
        [string]$FileType
    )
    
    if ($OverwriteAll -eq $true) {
        return $false  # Don't skip
    }
    
    if (-not (Test-Path $FilePath)) {
        return $false  # Don't skip - file doesn't exist
    }
    
    # Check specific overwrite flags
    switch ($FileType) {
        "agent" { if ($OverwriteType -eq $true) { return $false } }
        "command" { if ($OverwriteType -eq $true) { return $false } }
        "standard" { if ($OverwriteType -eq $true) { return $false } }
    }
    
    return $true  # Skip file
}

# -----------------------------------------------------------------------------
# Profile Functions
# -----------------------------------------------------------------------------

function Get-ProfileFile {
    param(
        [string]$Profile,
        [string]$FilePath,
        [string]$BaseDir
    )
    
    $currentProfile = $Profile
    $visitedProfiles = @()
    
    while ($true) {
        # Check for circular inheritance
        if ($visitedProfiles -contains $currentProfile) {
            Write-Verbose "Circular inheritance detected at profile: $currentProfile"
            return ""
        }
        $visitedProfiles += $currentProfile
        
        $profileDir = Join-Path $BaseDir "profiles" $currentProfile
        $fullPath = Join-Path $profileDir $FilePath
        
        # Check for profile config first
        $profileConfig = Join-Path $profileDir "profile-config.yml"
        
        # Check if file exists in current profile
        if (Test-Path $fullPath) {
            # Check if this file is excluded
            if (Test-Path $profileConfig) {
                $excludedPatterns = Get-YamlArray $profileConfig "exclude_inherited_files"
                $excluded = $false
                foreach ($pattern in $excludedPatterns) {
                    if ($pattern -and (Test-PatternMatch $FilePath $pattern)) {
                        $excluded = $true
                        break
                    }
                }
                if ($excluded) {
                    return ""
                }
            }
            return $fullPath
        }
        
        # Check for inheritance
        if (-not (Test-Path $profileConfig)) {
            return ""
        }
        
        $inheritsFrom = Get-YamlValue $profileConfig "inherits_from" "default"
        
        if ($inheritsFrom -eq "false" -or [string]::IsNullOrEmpty($inheritsFrom)) {
            return ""
        }
        
        # Check if file is excluded during inheritance
        $excludedPatterns = Get-YamlArray $profileConfig "exclude_inherited_files"
        $excluded = $false
        foreach ($pattern in $excludedPatterns) {
            if ($pattern -and (Test-PatternMatch $FilePath $pattern)) {
                $excluded = $true
                break
            }
        }
        if ($excluded) {
            return ""
        }
        
        $currentProfile = $inheritsFrom
    }
}

function Get-ProfileFiles {
    param(
        [string]$Profile,
        [string]$BaseDir,
        [string]$SubDir = ""
    )
    
    $currentProfile = $Profile
    $visitedProfiles = @()
    $excludedPatterns = @()
    $profilesToProcess = @()
    
    # First, collect exclusion patterns
    while ($true) {
        if ($visitedProfiles -contains $currentProfile) {
            break
        }
        $visitedProfiles += $currentProfile
        
        $profileDir = Join-Path $BaseDir "profiles" $currentProfile
        $profileConfig = Join-Path $profileDir "profile-config.yml"
        
        # Add exclusion patterns from this profile
        if (Test-Path $profileConfig) {
            $patterns = Get-YamlArray $profileConfig "exclude_inherited_files"
            $excludedPatterns += $patterns
            
            $inheritsFrom = Get-YamlValue $profileConfig "inherits_from" "default"
            if ($inheritsFrom -eq "false" -or [string]::IsNullOrEmpty($inheritsFrom)) {
                break
            }
            $currentProfile = $inheritsFrom
        } else {
            break
        }
    }
    
    # Now collect files starting from the base profile
    $currentProfile = $Profile
    $visitedProfiles = @()
    
    while ($true) {
        if ($visitedProfiles -contains $currentProfile) {
            break
        }
        $visitedProfiles += $currentProfile
        $profilesToProcess = @($currentProfile) + $profilesToProcess
        
        $profileDir = Join-Path $BaseDir "profiles" $currentProfile
        $profileConfig = Join-Path $profileDir "profile-config.yml"
        
        if (Test-Path $profileConfig) {
            $inheritsFrom = Get-YamlValue $profileConfig "inherits_from" "default"
            if ($inheritsFrom -eq "false" -or [string]::IsNullOrEmpty($inheritsFrom)) {
                break
            }
            $currentProfile = $inheritsFrom
        } else {
            break
        }
    }
    
    # Process profiles from base to specific
    $allFiles = @()
    foreach ($procProfile in $profilesToProcess) {
        $profileDir = Join-Path $BaseDir "profiles" $procProfile
        $searchDir = $profileDir
        
        if ($SubDir) {
            $searchDir = Join-Path $profileDir $SubDir
        }
        
        if (Test-Path $searchDir) {
            $files = Get-ChildItem -Path $searchDir -Recurse -File | Where-Object { $_.Extension -match '\.(md|yml|yaml)$' }
            foreach ($file in $files) {
                $relativePath = $file.FullName.Substring($profileDir.Length + 1).Replace('\', '/')
                
                # Check if excluded
                $excluded = $false
                foreach ($pattern in $excludedPatterns) {
                    if ($pattern -and (Test-PatternMatch $relativePath $pattern)) {
                        $excluded = $true
                        break
                    }
                }
                
                if (-not $excluded -and $allFiles -notcontains $relativePath) {
                    $allFiles += $relativePath
                }
            }
        }
    }
    
    return $allFiles | Sort-Object
}

function Test-PatternMatch {
    param(
        [string]$Path,
        [string]$Pattern
    )
    
    # Convert pattern to regex
    $regex = $Pattern -replace '\*', '[^/]*' -replace '\*\*', '.*'
    
    return $Path -match "^$regex$"
}

# -----------------------------------------------------------------------------
# Template Processing Functions
# -----------------------------------------------------------------------------

function Expand-PlaywrightTools {
    param([string]$Tools)
    
    $playwrightTools = "mcp__playwright__browser_close, mcp__playwright__browser_console_messages, mcp__playwright__browser_handle_dialog, mcp__playwright__browser_evaluate, mcp__playwright__browser_file_upload, mcp__playwright__browser_fill_form, mcp__playwright__browser_install, mcp__playwright__browser_press_key, mcp__playwright__browser_type, mcp__playwright__browser_navigate, mcp__playwright__browser_navigate_back, mcp__playwright__browser_network_requests, mcp__playwright__browser_take_screenshot, mcp__playwright__browser_snapshot, mcp__playwright__browser_click, mcp__playwright__browser_drag, mcp__playwright__browser_hover, mcp__playwright__browser_select_option, mcp__playwright__browser_tabs, mcp__playwright__browser_wait_for, mcp__ide__getDiagnostics, mcp__ide__executeCode, mcp__playwright__browser_resize"
    
    return $Tools -replace "Playwright", $playwrightTools
}

function Invoke-ConditionalProcessing {
    param(
        [string]$Content,
        [bool]$UseClaudeCodeSubagents = $true,
        [bool]$StandardsAsClaudeCodeSkills = $true,
        [bool]$CompiledSingleCommand = $false
    )
    
    $lines = $Content -split "`r?`n"
    $result = @()
    $nestingLevel = 0
    $shouldInclude = $true
    $stackShouldInclude = @()
    
    foreach ($line in $lines) {
        # Check for IF tags
        if ($line -match '\{\{IF\s+([a-z_]+)\}\}') {
            $flagName = $Matches[1]
            
            # Evaluate condition
            $conditionMet = $false
            switch ($flagName) {
                "use_claude_code_subagents" {
                    $conditionMet = $UseClaudeCodeSubagents
                }
                "standards_as_claude_code_skills" {
                    $conditionMet = $StandardsAsClaudeCodeSkills
                }
                "compiled_single_command" {
                    $conditionMet = $CompiledSingleCommand
                }
                default {
                    Write-Warning "Unknown conditional flag: $flagName"
                }
            }
            
            # Push current should_include onto stack
            $stackShouldInclude += $shouldInclude
            
            # Update should_include based on parent's state AND current condition
            $shouldInclude = $shouldInclude -and $conditionMet
            $nestingLevel++
            continue
        }
        
        # Check for UNLESS tags
        if ($line -match '\{\{UNLESS\s+([a-z_]+)\}\}') {
            $flagName = $Matches[1]
            
            # Evaluate condition (opposite of IF)
            $conditionMet = $false
            switch ($flagName) {
                "use_claude_code_subagents" {
                    $conditionMet = -not $UseClaudeCodeSubagents
                }
                "standards_as_claude_code_skills" {
                    $conditionMet = -not $StandardsAsClaudeCodeSkills
                }
                "compiled_single_command" {
                    $conditionMet = -not $CompiledSingleCommand
                }
                default {
                    Write-Warning "Unknown conditional flag: $flagName"
                }
            }
            
            # Push current should_include onto stack
            $stackShouldInclude += $shouldInclude
            
            # Update should_include based on parent's state AND current condition
            $shouldInclude = $shouldInclude -and $conditionMet
            $nestingLevel++
            continue
        }
        
        # Check for ENDIF tags
        if ($line -match '\{\{ENDIF\s+([a-z_]+)\}\}') {
            $nestingLevel--
            
            # Pop should_include from stack
            if ($stackShouldInclude.Count -gt 0) {
                $shouldInclude = $stackShouldInclude[-1]
                $stackShouldInclude = $stackShouldInclude[0..($stackShouldInclude.Count - 2)]
            } else {
                $shouldInclude = $true
            }
            continue
        }
        
        # Check for ENDUNLESS tags
        if ($line -match '\{\{ENDUNLESS\s+([a-z_]+)\}\}') {
            $nestingLevel--
            
            # Pop should_include from stack
            if ($stackShouldInclude.Count -gt 0) {
                $shouldInclude = $stackShouldInclude[-1]
                $stackShouldInclude = $stackShouldInclude[0..($stackShouldInclude.Count - 2)]
            } else {
                $shouldInclude = $true
            }
            continue
        }
        
        # Include line if should_include is true
        if ($shouldInclude) {
            $result += $line
        }
    }
    
    # Check for unclosed conditionals
    if ($nestingLevel -ne 0) {
        Write-Warning "Unclosed conditional block detected (nesting level: $nestingLevel)"
    }
    
    return $result -join "`n"
}

function Invoke-WorkflowProcessing {
    param(
        [string]$Content,
        [string]$BaseDir,
        [string]$Profile,
        [string]$ProcessedFiles = ""
    )
    
    # Process each workflow reference
    $workflowRefs = [regex]::Matches($Content, '\{\{workflows/[^}]*\}\}') | ForEach-Object { $_.Value } | Sort-Object -Unique
    
    foreach ($workflowRef in $workflowRefs) {
        if ([string]::IsNullOrEmpty($workflowRef)) {
            continue
        }
        
        $workflowPath = $workflowRef -replace '\{\{workflows/', '' -replace '\}\}', ''
        
        # Avoid infinite recursion
        if ($ProcessedFiles -like "*$workflowPath*") {
            Write-Warning "Circular workflow reference detected: $workflowPath"
            continue
        }
        
        # Get workflow file
        $workflowFile = Get-ProfileFile $Profile "workflows/$workflowPath.md" $BaseDir
        
        if (Test-Path $workflowFile) {
            $workflowContent = Get-Content $workflowFile -Raw
            
            # Recursively process nested workflows
            $workflowContent = Invoke-WorkflowProcessing $workflowContent $BaseDir $Profile "$ProcessedFiles $workflowPath"
            
            # Replace the workflow reference
            $Content = $Content -replace [regex]::Escape($workflowRef), $workflowContent
        } else {
            # Insert warning message
            $warningMsg = "⚠️ This workflow file was not found in your Agent OS base installation at ~/agent-os/profiles/$Profile/workflows/$workflowPath.md"
            $Content = $Content -replace [regex]::Escape($workflowRef), "$workflowRef`n$warningMsg"
        }
    }
    
    return $Content
}

function Invoke-StandardsProcessing {
    param(
        [string]$Content,
        [string]$BaseDir,
        [string]$Profile,
        [string[]]$StandardsPatterns
    )
    
    $standardsList = @()
    
    foreach ($pattern in $StandardsPatterns) {
        if ([string]::IsNullOrEmpty($pattern)) {
            continue
        }
        
        $basePath = $pattern -replace '\*', ''
        
        if ($pattern -like '*\**') {
            # Wildcard pattern - find all files
            $searchDir = "standards/$basePath"
            $files = Get-ProfileFiles $Profile $BaseDir $searchDir
            foreach ($file in $files) {
                if ($file -like "standards/*" -and $file -like "*.md") {
                    $standardsList += "@agent-os/$file"
                }
            }
        } else {
            # Specific file
            $filePath = "standards/$pattern.md"
            $fullFile = Get-ProfileFile $Profile $filePath $BaseDir
            if (Test-Path $fullFile) {
                $standardsList += "@agent-os/$filePath"
            }
        }
    }
    
    return $standardsList | Sort-Object -Unique
}

function Invoke-PhaseTagProcessing {
    param(
        [string]$Content,
        [string]$BaseDir,
        [string]$Profile,
        [string]$Mode = ""
    )
    
    # If no mode specified, return content unchanged
    if ([string]::IsNullOrEmpty($Mode)) {
        return $Content
    }
    
    # Find all PHASE tags
    $phaseRefs = [regex]::Matches($Content, '\{\{PHASE [^}]*\}\}') | ForEach-Object { $_.Value } | Sort-Object -Unique
    
    if ($phaseRefs.Count -eq 0) {
        return $Content
    }
    
    foreach ($phaseRef in $phaseRefs) {
        if ([string]::IsNullOrEmpty($phaseRef)) {
            continue
        }
        
        if ($Mode -eq "embed") {
            # Extract phase label and file reference
            if ($phaseRef -match '\{\{PHASE ([^:]+): @agent-os/commands/(.+)\}\}') {
                $phaseLabel = $Matches[1].Trim()
                $fileRef = $Matches[2].Trim()
                $fileName = [System.IO.Path]::GetFileNameWithoutExtension($fileRef)
                
                # Convert "1-product-concept" to "Product Concept"
                $title = $fileName -replace '^[0-9]+-', '' -replace '-', ' '
                $title = (Get-Culture).TextInfo.ToTitleCase($title)
                
                # Get the actual file path in the profile
                $cmdName = Split-Path $fileRef -Parent
                $filename = Split-Path $fileRef -Leaf
                $sourceFile = Get-ProfileFile $Profile "commands/$cmdName/single-agent/$filename" $BaseDir
                
                if (Test-Path $sourceFile) {
                    # Read and process the file content
                    $fileContent = Get-Content $sourceFile -Raw
                    
                    # Process through compilation pipeline
                    $fileContent = Invoke-ConditionalProcessing $fileContent $script:EFFECTIVE_USE_CLAUDE_CODE_SUBAGENTS $script:EFFECTIVE_STANDARDS_AS_CLAUDE_CODE_SKILLS $true
                    $fileContent = Invoke-WorkflowProcessing $fileContent $BaseDir $Profile ""
                    
                    # Process standards replacements
                    $standardsRefs = [regex]::Matches($fileContent, '\{\{standards/[^}]*\}\}') | ForEach-Object { $_.Value } | Sort-Object -Unique
                    foreach ($standardsRef in $standardsRefs) {
                        if ([string]::IsNullOrEmpty($standardsRef)) {
                            continue
                        }
                        
                        $standardsPattern = $standardsRef -replace '\{\{standards/', '' -replace '\}\}', ''
                        $standardsList = Invoke-StandardsProcessing $fileContent $BaseDir $Profile @($standardsPattern)
                        $standardsText = $standardsList -join "`n"
                        
                        $fileContent = $fileContent -replace [regex]::Escape($standardsRef), $standardsText
                    }
                    
                    # Create replacement text with H1 header
                    $replacement = "# $phaseLabel`: $title`n`n$fileContent"
                    
                    # Replace the tag with the embedded content
                    $Content = $Content -replace [regex]::Escape($phaseRef), $replacement
                } else {
                    Write-Verbose "Warning: File not found for PHASE tag: $fileRef"
                }
            }
        }
    }
    
    return $Content
}

# -----------------------------------------------------------------------------
# Compilation Functions
# -----------------------------------------------------------------------------

function Invoke-AgentCompilation {
    param(
        [string]$SourceFile,
        [string]$DestFile,
        [string]$BaseDir,
        [string]$Profile,
        [string]$RoleData = "",
        [string]$PhaseMode = ""
    )
    
    $content = Get-Content $SourceFile -Raw
    
    # Process role replacements if provided
    if (-not [string]::IsNullOrEmpty($RoleData)) {
        $roleLines = $RoleData -split "`r?`n"
        $i = 0
        while ($i -lt $roleLines.Count) {
            $line = $roleLines[$i]
            if ($line -match '^<<<(.+)>>>$') {
                $key = $Matches[1]
                $value = ""
                $i++
                
                # Read until we hit <<<END>>>
                while ($i -lt $roleLines.Count -and $roleLines[$i] -ne "<<<END>>>") {
                    if ($value) {
                        $value += "`n" + $roleLines[$i]
                    } else {
                        $value = $roleLines[$i]
                    }
                    $i++
                }
                
                if (-not [string]::IsNullOrEmpty($key)) {
                    $content = $content -replace [regex]::Escape("{{$key}}"), $value
                }
            }
            $i++
        }
    }
    
    # Process conditional compilation tags
    $content = Invoke-ConditionalProcessing $content $script:EFFECTIVE_USE_CLAUDE_CODE_SUBAGENTS $script:EFFECTIVE_STANDARDS_AS_CLAUDE_CODE_SKILLS $false
    
    # Process workflow replacements
    $content = Invoke-WorkflowProcessing $content $BaseDir $Profile ""
    
    # Process standards replacements
    $standardsRefs = [regex]::Matches($content, '\{\{standards/[^}]*\}\}') | ForEach-Object { $_.Value } | Sort-Object -Unique
    foreach ($standardsRef in $standardsRefs) {
        if ([string]::IsNullOrEmpty($standardsRef)) {
            continue
        }
        
        $standardsPattern = $standardsRef -replace '\{\{standards/', '' -replace '\}\}', ''
        $standardsList = Invoke-StandardsProcessing $content $BaseDir $Profile @($standardsPattern)
        $standardsText = $standardsList -join "`n"
        
        $content = $content -replace [regex]::Escape($standardsRef), $standardsText
    }
    
    # Process PHASE tag replacements
    $content = Invoke-PhaseTagProcessing $content $BaseDir $Profile $PhaseMode
    
    # Replace Playwright in tools
    if ($content -match "^tools:.*Playwright") {
        $toolsLine = ($content -split "`n" | Where-Object { $_ -match "^tools:" })[0]
        $newToolsLine = Expand-PlaywrightTools $toolsLine
        $content = $content -replace [regex]::Escape($toolsLine), $newToolsLine
    }
    
    if ($script:DRY_RUN -eq $true) {
        return $DestFile
    } else {
        $destDir = Split-Path $DestFile -Parent
        New-DirectoryIfNotExists $destDir
        $content | Out-File -FilePath $DestFile -Encoding UTF8
        Write-Verbose "Compiled agent: $DestFile"
        return $DestFile
    }
}

function Invoke-CommandCompilation {
    param(
        [string]$SourceFile,
        [string]$DestFile,
        [string]$BaseDir,
        [string]$Profile,
        [string]$PhaseMode = ""
    )
    
    return Invoke-AgentCompilation $SourceFile $DestFile $BaseDir $Profile "" $PhaseMode
}

# -----------------------------------------------------------------------------
# Version Functions
# -----------------------------------------------------------------------------

function Test-VersionCompatibility {
    param(
        [string]$BaseVersion,
        [string]$ProjectVersion
    )
    
    # Extract major version
    $baseMajor = ($BaseVersion -split '\.')[0]
    $projectMajor = ($ProjectVersion -split '\.')[0]
    
    return $baseMajor -eq $projectMajor
}

function Test-NeedsMigration {
    param([string]$ProjectVersion)
    
    # Empty or missing version needs migration
    if ([string]::IsNullOrEmpty($ProjectVersion)) {
        return $true
    }
    
    # Parse version components
    $versionParts = $ProjectVersion -split '\.'
    $major = [int]$versionParts[0]
    $minor = if ($versionParts.Count -gt 1) { [int]$versionParts[1] } else { 0 }
    
    # Check if < 2.1.0
    if ($major -lt 2) {
        return $true
    } elseif ($major -eq 2 -and $minor -lt 1) {
        return $true
    }
    
    return $false
}

# -----------------------------------------------------------------------------
# Installation Check Functions
# -----------------------------------------------------------------------------

function Test-AgentOSInstalled {
    param([string]$ProjectDir)
    
    return Test-Path (Join-Path $ProjectDir "agent-os" "config.yml")
}

function Get-ProjectConfig {
    param(
        [string]$ProjectDir,
        [string]$Key
    )
    
    $configPath = Join-Path $ProjectDir "agent-os" "config.yml"
    return Get-YamlValue $configPath $Key ""
}

# -----------------------------------------------------------------------------
# Validation Functions
# -----------------------------------------------------------------------------

function Test-BaseInstallation {
    if (-not (Test-Path $script:BASE_DIR)) {
        Write-Error "Agent OS base installation not found at ~/agent-os/"
        Write-Host ""
        Write-Status "Please run the base installation first:"
        Write-Host "  Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/buildermethods/agent-os/main/scripts/powershell/Base-Install.ps1' -OutFile 'Base-Install.ps1'; .\Base-Install.ps1"
        Write-Host ""
        exit 1
    }
    
    $configPath = Join-Path $script:BASE_DIR "config.yml"
    if (-not (Test-Path $configPath)) {
        Write-Error "Base installation config.yml not found"
        exit 1
    }
    
    Write-Verbose "Base installation found at: $script:BASE_DIR"
}

function Test-NotBaseInstallation {
    $projectConfigPath = Join-Path $script:PROJECT_DIR "agent-os" "config.yml"
    if (Test-Path $projectConfigPath) {
        $baseInstall = Get-YamlValue $projectConfigPath "base_install" ""
        if ($baseInstall -eq "true") {
            Write-Host ""
            Write-Error "Cannot install Agent OS in base installation directory"
            Write-Host ""
            Write-Host "It appears you are in the location of your Agent OS base installation (your home directory)."
            Write-Host "To install Agent OS in a project, move to your project's root folder:"
            Write-Host ""
            Write-Host "  cd path\to\project"
            Write-Host ""
            Write-Host "And then run:"
            Write-Host ""
            Write-Host "  & `"$env:USERPROFILE\agent-os\scripts\powershell\Project-Install.ps1`""
            Write-Host ""
            exit 1
        }
    }
}

# -----------------------------------------------------------------------------
# Argument Parsing Helpers
# -----------------------------------------------------------------------------

function ConvertTo-BooleanFlag {
    param(
        [string]$CurrentValue,
        [string]$NextValue
    )
    
    if ($NextValue -eq "true" -or $NextValue -eq "false") {
        return @{ Value = ($NextValue -eq "true"); ShiftCount = 2 }
    } else {
        return @{ Value = $true; ShiftCount = 1 }
    }
}

# -----------------------------------------------------------------------------
# Configuration Loading Helpers
# -----------------------------------------------------------------------------

function Import-BaseConfig {
    $configPath = Join-Path $script:BASE_DIR "config.yml"
    
    $script:BASE_VERSION = Get-YamlValue $configPath "version" "2.1.0"
    $script:BASE_PROFILE = Get-YamlValue $configPath "profile" "default"
    $script:BASE_CLAUDE_CODE_COMMANDS = (Get-YamlValue $configPath "claude_code_commands" "true") -eq "true"
    $script:BASE_USE_CLAUDE_CODE_SUBAGENTS = (Get-YamlValue $configPath "use_claude_code_subagents" "true") -eq "true"
    $script:BASE_AGENT_OS_COMMANDS = (Get-YamlValue $configPath "agent_os_commands" "false") -eq "true"
    $script:BASE_STANDARDS_AS_CLAUDE_CODE_SKILLS = (Get-YamlValue $configPath "standards_as_claude_code_skills" "true") -eq "true"
    
    # Check for old config flags
    $script:MULTI_AGENT_MODE = Get-YamlValue $configPath "multi_agent_mode" ""
    $script:SINGLE_AGENT_MODE = Get-YamlValue $configPath "single_agent_mode" ""
    $script:MULTI_AGENT_TOOL = Get-YamlValue $configPath "multi_agent_tool" ""
}

function Import-ProjectConfig {
    $script:PROJECT_VERSION = Get-ProjectConfig $script:PROJECT_DIR "version"
    $script:PROJECT_PROFILE = Get-ProjectConfig $script:PROJECT_DIR "profile"
    $script:PROJECT_CLAUDE_CODE_COMMANDS = (Get-ProjectConfig $script:PROJECT_DIR "claude_code_commands") -eq "true"
    $script:PROJECT_USE_CLAUDE_CODE_SUBAGENTS = (Get-ProjectConfig $script:PROJECT_DIR "use_claude_code_subagents") -eq "true"
    $script:PROJECT_AGENT_OS_COMMANDS = (Get-ProjectConfig $script:PROJECT_DIR "agent_os_commands") -eq "true"
    $script:PROJECT_STANDARDS_AS_CLAUDE_CODE_SKILLS = (Get-ProjectConfig $script:PROJECT_DIR "standards_as_claude_code_skills") -eq "true"
    
    # Check for old config flags
    $script:MULTI_AGENT_MODE = Get-ProjectConfig $script:PROJECT_DIR "multi_agent_mode"
    $script:SINGLE_AGENT_MODE = Get-ProjectConfig $script:PROJECT_DIR "single_agent_mode"
    $script:MULTI_AGENT_TOOL = Get-ProjectConfig $script:PROJECT_DIR "multi_agent_tool"
}

function Test-ConfigurationValid {
    param(
        [bool]$ClaudeCodeCommands,
        [bool]$UseClaudeCodeSubagents,
        [bool]$AgentOSCommands,
        [bool]$StandardsAsClaudeCodeSkills,
        [string]$Profile,
        [bool]$PrintWarnings = $true
    )
    
    # Validate at least one output is enabled
    if (-not $ClaudeCodeCommands -and -not $AgentOSCommands) {
        Write-Error "At least one of 'claude_code_commands' or 'agent_os_commands' must be true"
        exit 1
    }
    
    # Validate subagents require Claude Code
    if ($UseClaudeCodeSubagents -and -not $ClaudeCodeCommands) {
        if ($PrintWarnings) {
            Write-Warning "use_claude_code_subagents requires claude_code_commands to be true"
            Write-Warning "Ignoring subagent setting"
        }
    }
    
    # Validate standards as skills require Claude Code
    if ($StandardsAsClaudeCodeSkills -and -not $ClaudeCodeCommands) {
        if ($PrintWarnings) {
            Write-Warning "standards_as_claude_code_skills requires claude_code_commands to be true"
            Write-Warning "Treating standards_as_claude_code_skills as false"
        }
        # Set global variable to override the effective value
        $script:EFFECTIVE_STANDARDS_AS_CLAUDE_CODE_SKILLS = $false
    }
    
    # Validate profile exists
    $profilePath = Join-Path $script:BASE_DIR "profiles" $Profile
    if (-not (Test-Path $profilePath)) {
        Write-Error "Profile not found: $Profile"
        exit 1
    }
}

function Set-ProjectConfig {
    param(
        [string]$Version,
        [string]$Profile,
        [bool]$ClaudeCodeCommands,
        [bool]$UseClaudeCodeSubagents,
        [bool]$AgentOSCommands,
        [bool]$StandardsAsClaudeCodeSkills
    )
    
    $dest = Join-Path $script:PROJECT_DIR "agent-os" "config.yml"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    $configContent = @"
version: $Version
last_compiled: $timestamp

# ================================================
# Compiled with the following settings:
#
# To change these settings, run ~/agent-os/scripts/powershell/Project-Update.ps1 to re-compile your project with the new settings.
# ================================================
profile: $Profile
claude_code_commands: $($ClaudeCodeCommands.ToString().ToLower())
use_claude_code_subagents: $($UseClaudeCodeSubagents.ToString().ToLower())
agent_os_commands: $($AgentOSCommands.ToString().ToLower())
standards_as_claude_code_skills: $($StandardsAsClaudeCodeSkills.ToString().ToLower())
"@
    
    $result = Set-FileContentWithDryRun $configContent $dest
    if ($script:DRY_RUN -eq $true) {
        return $dest
    }
    return $null
}

# -----------------------------------------------------------------------------
# Claude Code Skills Functions
# -----------------------------------------------------------------------------

function ConvertTo-HumanName {
    param([string]$Filename)
    
    # List of common acronyms to preserve in uppercase
    $acronyms = @("API", "CSS", "HTML", "SQL", "REST", "JSON", "XML", "HTTP", "HTTPS", "URL", "URI", "CLI", "GUI", "IDE", "SDK", "JWT")
    
    # Remove .md extension
    $name = $Filename -replace '\.md$', ''
    
    # Replace hyphens, underscores, and slashes with spaces
    $name = $name -replace '[-_/]', ' '
    
    # Convert to lowercase first
    $name = $name.ToLower()
    
    # Replace known acronyms with uppercase version
    foreach ($acronym in $acronyms) {
        $lowercase = $acronym.ToLower()
        $capitalized = (Get-Culture).TextInfo.ToTitleCase($lowercase)
        
        $name = $name -replace "\b$lowercase\b", $acronym
        $name = $name -replace "\b$capitalized\b", $acronym
    }
    
    return $name
}

function ConvertTo-HumanNameCapitalized {
    param([string]$Filename)
    
    # List of common acronyms to preserve in uppercase
    $acronyms = @("API", "CSS", "HTML", "SQL", "REST", "JSON", "XML", "HTTP", "HTTPS", "URL", "URI", "CLI", "GUI", "IDE", "SDK", "JWT")
    
    # Remove .md extension
    $name = $Filename -replace '\.md$', ''
    
    # Replace hyphens, underscores, and slashes with spaces
    $name = $name -replace '[-_/]', ' '
    
    # Capitalize first letter of each word
    $name = (Get-Culture).TextInfo.ToTitleCase($name)
    
    # Replace known acronyms with uppercase version
    foreach ($acronym in $acronyms) {
        $lowercase = $acronym.ToLower()
        $capitalized = (Get-Culture).TextInfo.ToTitleCase($lowercase)
        
        $name = $name -replace "\b$lowercase\b", $acronym
        $name = $name -replace "\b$capitalized\b", $acronym
    }
    
    return $name
}

function New-StandardSkill {
    param(
        [string]$StandardsFile,
        [string]$DestBase,
        [string]$BaseDir,
        [string]$Profile
    )
    
    # Remove "standards/" prefix and ".md" extension for skill directory name
    $skillName = $StandardsFile -replace '^standards/', '' -replace '\.md$', '' -replace '/', '-'
    
    # Get human-readable name from the full path
    $pathWithoutStandards = $StandardsFile -replace '^standards/', ''
    $humanName = ConvertTo-HumanName $pathWithoutStandards
    $humanNameCapitalized = ConvertTo-HumanNameCapitalized $pathWithoutStandards
    
    # Create skill directory
    $skillDir = Join-Path $DestBase ".claude" "skills" $skillName
    New-DirectoryIfNotExists $skillDir
    
    # Get the skill template from the profile
    $templateFile = Get-ProfileFile $Profile "claude-code-skill-template.md" $BaseDir
    if (-not (Test-Path $templateFile)) {
        Write-Error "Skill template not found: $templateFile"
        return $false
    }
    
    # Prepend agent-os/ to the standards file path
    $standardFilePathWithPrefix = "agent-os/$StandardsFile"
    
    # Read template and replace placeholders
    $skillContent = Get-Content $templateFile -Raw
    $skillContent = $skillContent -replace '\{\{standard_name_humanized\}\}', $humanName
    $skillContent = $skillContent -replace '\{\{standard_name_humanized_capitalized\}\}', $humanNameCapitalized
    $skillContent = $skillContent -replace '\{\{standard_file_path\}\}', $standardFilePathWithPrefix
    
    # Write SKILL.md
    $skillFile = Join-Path $skillDir "SKILL.md"
    if ($script:DRY_RUN -eq $true) {
        return $skillFile
    } else {
        $skillContent | Out-File -FilePath $skillFile -Encoding UTF8
        Write-Verbose "Created skill: $skillFile"
        return $skillFile
    }
}

function Install-ClaudeCodeSkills {
    # Only install skills if both flags are enabled
    if (-not $script:EFFECTIVE_STANDARDS_AS_CLAUDE_CODE_SKILLS -or -not $script:EFFECTIVE_CLAUDE_CODE_COMMANDS) {
        return
    }
    
    if ($script:DRY_RUN -ne $true) {
        Write-Status "Installing Claude Code Skills..."
    }
    
    $skillsCount = 0
    
    # Get all standards files for the current profile
    $files = Get-ProfileFiles $script:EFFECTIVE_PROFILE $script:BASE_DIR "standards"
    foreach ($file in $files) {
        if ($file -like "standards/*" -and $file -like "*.md") {
            # Create skill from this standards file
            $skillFile = New-StandardSkill $file $script:PROJECT_DIR $script:BASE_DIR $script:EFFECTIVE_PROFILE
            
            if ($script:DRY_RUN -eq $true -and $skillFile) {
                $script:INSTALLED_FILES += $skillFile
            }
            $skillsCount++
        }
    }
    
    if ($script:DRY_RUN -ne $true) {
        if ($skillsCount -gt 0) {
            Write-Success "Installed $skillsCount Claude Code Skills"
            Write-ColorOutput $script:Colors.YELLOW "  👉 Be sure to run the /improve-skills command next using Claude Code"
        }
    }
}

function Install-ImproveSkillsCommand {
    # Only install if both Claude Code commands AND Skills are enabled
    if (-not $script:EFFECTIVE_STANDARDS_AS_CLAUDE_CODE_SKILLS -or -not $script:EFFECTIVE_CLAUDE_CODE_COMMANDS) {
        return
    }
    
    $targetDir = Join-Path $script:PROJECT_DIR ".claude" "commands" "agent-os"
    New-DirectoryIfNotExists $targetDir
    
    # Find the improve-skills command file
    $sourceFile = Get-ProfileFile $script:EFFECTIVE_PROFILE "commands/improve-skills/improve-skills.md" $script:BASE_DIR
    
    if (Test-Path $sourceFile) {
        $dest = Join-Path $targetDir "improve-skills.md"
        
        # Compile the command
        $compiled = Invoke-CommandCompilation $sourceFile $dest $script:BASE_DIR $script:EFFECTIVE_PROFILE
        
        if ($script:DRY_RUN -eq $true) {
            $script:INSTALLED_FILES += $dest
        }
    }
}

# All functions are now available for use by scripts that dot-source this file