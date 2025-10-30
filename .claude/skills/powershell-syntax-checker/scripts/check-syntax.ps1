#!/usr/bin/env pwsh
# PowerShell Syntax Checker Utility Script
# Provides comprehensive syntax validation for PowerShell scripts

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,
    
    [switch]$Detailed,
    [switch]$Recursive,
    [switch]$AnalyzeOnly,
    [switch]$Json
)

function Test-PowerShellSyntax {
    param(
        [string]$FilePath,
        [bool]$DetailedOutput = $false
    )
    
    $result = @{
        File = (Split-Path $FilePath -Leaf)
        FullPath = $FilePath
        IsValid = $false
        Errors = @()
        Warnings = @()
        TokenCount = 0
        ParseTime = 0
    }
    
    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        
        # Read the script content
        $content = Get-Content $FilePath -Raw -ErrorAction Stop
        
        # Parse the script
        $errors = $null
        $tokens = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)
        
        $stopwatch.Stop()
        $result.ParseTime = $stopwatch.ElapsedMilliseconds
        $result.TokenCount = $tokens.Count
        
        if ($errors -and $errors.Count -gt 0) {
            $result.IsValid = $false
            $result.Errors = $errors | ForEach-Object {
                @{
                    Line = $_.Token.StartLine
                    Column = $_.Token.StartColumn
                    Message = $_.Message
                    Type = "ParseError"
                }
            }
        } else {
            $result.IsValid = $true
            
            # Additional validation checks
            if ($DetailedOutput) {
                $warnings = @()
                
                # Check for common issues
                if ($content -match '\$Help\b') {
                    $warnings += @{
                        Line = 0
                        Message = "Custom Help parameter may conflict with CmdletBinding"
                        Type = "BestPractice"
                    }
                }
                
                if ($content -match '\$Verbose\b' -and $content -match '\[CmdletBinding\(\)\]') {
                    $warnings += @{
                        Line = 0
                        Message = "Custom Verbose parameter conflicts with CmdletBinding"
                        Type = "BestPractice"
                    }
                }
                
                # Check for module import conflicts
                $hasDotSource = $content -match '\.\s+\$\w+'
                $hasImportModule = $content -match 'Import-Module.*\$\w+'
                if ($hasDotSource -and $hasImportModule) {
                    $warnings += @{
                        Line = 0
                        Message = "Module import conflict: script uses both dot-sourcing and Import-Module patterns"
                        Type = "ModuleConflict"
                    }
                }
                
                # Check for parameter parsing issues with external files
                if ($content -match '\[CmdletBinding\(\)\]' -and $content -match 'Get-Content.*config\.yml') {
                    $warnings += @{
                        Line = 0
                        Message = "Potential parameter parsing conflict with external file operations"
                        Type = "ParameterConflict"
                    }
                }
                
                # Check for both dot-sourcing and Import-Module in dependency chain
                if ($content -match '\.\s+.*Common.*\.ps1' -and $content -match 'Import-Module.*Common.*\.ps1') {
                    $warnings += @{
                        Line = 0
                        Message = "Mixed module loading: both dot-sourcing and Import-Module for Common functions"
                        Type = "ModuleConflict"
                    }
                }
                
                if ($content -match 'Export-ModuleMember\s+[^-]') {
                    $warnings += @{
                        Line = 0
                        Message = "Export-ModuleMember should use -Function parameter"
                        Type = "BestPractice"
                    }
                }
                
                $result.Warnings = $warnings
            }
        }
    }
    catch {
        $result.IsValid = $false
        $result.Errors = @(@{
            Line = 0
            Column = 0
            Message = $_.Exception.Message
            Type = "FileError"
        })
    }
    
    return $result
}

function Get-PowerShellFiles {
    param(
        [string]$SearchPath,
        [bool]$Recursive = $false
    )
    
    if (Test-Path $SearchPath -PathType Leaf) {
        return @($SearchPath)
    }
    
    $searchParams = @{
        Path = $SearchPath
        Filter = "*.ps1"
    }
    
    if ($Recursive) {
        $searchParams.Recurse = $true
    }
    
    return Get-ChildItem @searchParams | Select-Object -ExpandProperty FullName
}

function Format-Results {
    param(
        [array]$Results,
        [bool]$JsonOutput = $false,
        [bool]$DetailedOutput = $false
    )
    
    if ($JsonOutput) {
        return $Results | ConvertTo-Json -Depth 4
    }
    
    $validCount = ($Results | Where-Object { $_.IsValid }).Count
    $totalCount = $Results.Count
    $errorCount = $totalCount - $validCount
    
    Write-Host "`n=== PowerShell Syntax Check Results ===" -ForegroundColor Cyan
    Write-Host "Files checked: $totalCount" -ForegroundColor White
    Write-Host "Valid: $validCount" -ForegroundColor Green
    Write-Host "Errors: $errorCount" -ForegroundColor Red
    
    if ($errorCount -gt 0) {
        Write-Host "`n--- Files with Errors ---" -ForegroundColor Red
        $Results | Where-Object { -not $_.IsValid } | ForEach-Object {
            Write-Host "`n✗ $($_.File)" -ForegroundColor Red
            $_.Errors | ForEach-Object {
                if ($_.Line -gt 0) {
                    Write-Host "  Line $($_.Line), Column $($_.Column): $($_.Message)" -ForegroundColor Yellow
                } else {
                    Write-Host "  $($_.Message)" -ForegroundColor Yellow
                }
            }
        }
    }
    
    if ($DetailedOutput) {
        $warningCount = ($Results | ForEach-Object { $_.Warnings.Count } | Measure-Object -Sum).Sum
        if ($warningCount -gt 0) {
            Write-Host "`n--- Warnings ---" -ForegroundColor Yellow
            $Results | Where-Object { $_.Warnings.Count -gt 0 } | ForEach-Object {
                Write-Host "`n⚠ $($_.File)" -ForegroundColor Yellow
                $_.Warnings | ForEach-Object {
                    Write-Host "  $($_.Message)" -ForegroundColor DarkYellow
                }
            }
        }
        
        Write-Host "`n--- Performance Summary ---" -ForegroundColor Cyan
        $totalTokens = ($Results | ForEach-Object { $_.TokenCount } | Measure-Object -Sum).Sum
        $avgParseTime = ($Results | ForEach-Object { $_.ParseTime } | Measure-Object -Average).Average
        Write-Host "Total tokens parsed: $totalTokens" -ForegroundColor White
        Write-Host "Average parse time: $([math]::Round($avgParseTime, 2))ms" -ForegroundColor White
    }
    
    Write-Host ""
    return $errorCount
}

# Main execution
try {
    $files = Get-PowerShellFiles -SearchPath $Path -Recursive $Recursive.IsPresent
    
    if ($files.Count -eq 0) {
        Write-Warning "No PowerShell files found in path: $Path"
        exit 2
    }
    
    Write-Host "Checking $($files.Count) PowerShell file$(if($files.Count -ne 1){'s'})..." -ForegroundColor Cyan
    
    $results = @()
    foreach ($file in $files) {
        Write-Progress -Activity "Checking PowerShell Syntax" -Status "Processing $file" -PercentComplete (($results.Count / $files.Count) * 100)
        $result = Test-PowerShellSyntax -FilePath $file -DetailedOutput $Detailed.IsPresent
        $results += $result
        
        if (-not $AnalyzeOnly.IsPresent) {
            if ($result.IsValid) {
                Write-Host "✓ $($result.File)" -ForegroundColor Green
            } else {
                Write-Host "✗ $($result.File)" -ForegroundColor Red
            }
        }
    }
    
    Write-Progress -Activity "Checking PowerShell Syntax" -Completed
    
    if ($AnalyzeOnly.IsPresent -or $Json.IsPresent) {
        $errorCount = Format-Results -Results $results -JsonOutput $Json.IsPresent -DetailedOutput $Detailed.IsPresent
        exit $errorCount
    }
    
    # Return appropriate exit code
    $errorCount = ($results | Where-Object { -not $_.IsValid }).Count
    exit $errorCount
}
catch {
    Write-Error "Failed to check PowerShell syntax: $_"
    exit 3
}