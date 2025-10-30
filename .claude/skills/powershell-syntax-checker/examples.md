# PowerShell Syntax Checker Examples

This document provides practical examples of using the PowerShell Syntax Checker skill.

## Basic Usage Examples

### Check a Single File

**Simple syntax validation:**
```powershell
powershell -NoProfile -Command "[System.Management.Automation.PSParser]::Tokenize((Get-Content 'MyScript.ps1' -Raw), [ref]`$null) | Out-Null; Write-Host 'Syntax OK'"
```

**With error details:**
```powershell
powershell -NoProfile -Command "
`$errors = `$null
`$tokens = [System.Management.Automation.PSParser]::Tokenize((Get-Content 'MyScript.ps1' -Raw), [ref]`$errors)
if (`$errors.Count -gt 0) { 
    'Errors found:'; `$errors | ForEach-Object { 'Line ' + `$_.Token.StartLine + ': ' + `$_.Message }
} else { 
    'Syntax OK'
}"
```

### Check Multiple Files

**All .ps1 files in current directory:**
```powershell
Get-ChildItem *.ps1 | ForEach-Object {
    Write-Host "Checking $($_.Name)..." -NoNewline
    try {
        [System.Management.Automation.PSParser]::Tokenize((Get-Content $_.FullName -Raw), [ref]$null) | Out-Null
        Write-Host " ✓ OK" -ForegroundColor Green
    } catch {
        Write-Host " ✗ Error" -ForegroundColor Red
        Write-Host "  $_" -ForegroundColor Yellow
    }
}
```

**Recursive directory check:**
```powershell
Get-ChildItem -Path . -Filter "*.ps1" -Recurse | ForEach-Object {
    $relativePath = Resolve-Path $_.FullName -Relative
    try {
        [System.Management.Automation.PSParser]::Tokenize((Get-Content $_.FullName -Raw), [ref]$null) | Out-Null
        Write-Host "$relativePath ✓" -ForegroundColor Green
    } catch {
        Write-Host "$relativePath ✗" -ForegroundColor Red
    }
}
```

## Advanced Examples

### Detailed Error Analysis

```powershell
function Test-PowerShellSyntaxDetailed {
    param([string]$FilePath)
    
    try {
        $content = Get-Content $FilePath -Raw
        $errors = $null
        $tokens = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)
        
        $result = @{
            File = Split-Path $FilePath -Leaf
            IsValid = ($errors.Count -eq 0)
            TokenCount = $tokens.Count
            Errors = @()
        }
        
        if ($errors.Count -gt 0) {
            $result.Errors = $errors | ForEach-Object {
                @{
                    Line = $_.Token.StartLine
                    Column = $_.Token.StartColumn
                    Type = $_.Token.Type
                    Message = $_.Message
                }
            }
        }
        
        return $result
    }
    catch {
        return @{
            File = Split-Path $FilePath -Leaf
            IsValid = $false
            TokenCount = 0
            Errors = @(@{ Line = 0; Column = 0; Type = "FileError"; Message = $_.Exception.Message })
        }
    }
}

# Usage
$result = Test-PowerShellSyntaxDetailed "MyScript.ps1"
$result | ConvertTo-Json -Depth 3
```

### Best Practices Checker

```powershell
function Test-PowerShellBestPractices {
    param([string]$FilePath)
    
    $content = Get-Content $FilePath -Raw
    $issues = @()
    
    # Check for common issues
    if ($content -match '\$Verbose\b' -and $content -match '\[CmdletBinding\(\)\]') {
        $issues += "Custom Verbose parameter conflicts with CmdletBinding"
    }
    
    if ($content -match '\$Help\b' -and $content -match '\[CmdletBinding\(\)\]') {
        $issues += "Custom Help parameter may conflict with CmdletBinding"
    }
    
    if ($content -match 'Export-ModuleMember\s+[^-]') {
        $issues += "Export-ModuleMember should use -Function parameter"
    }
    
    if ($content -match '\\' -and $content -notmatch '\\n|\\t|\\r|\\\\') {
        $issues += "Consider using Join-Path for cross-platform compatibility"
    }
    
    return @{
        File = Split-Path $FilePath -Leaf
        Issues = $issues
        HasIssues = $issues.Count -gt 0
    }
}
```

### Batch Processing with Report

```powershell
function New-PowerShellSyntaxReport {
    param(
        [string]$Path = ".",
        [switch]$Recursive,
        [string]$OutputFile
    )
    
    $searchParams = @{
        Path = $Path
        Filter = "*.ps1"
    }
    if ($Recursive) { $searchParams.Recurse = $true }
    
    $files = Get-ChildItem @searchParams
    $results = @()
    
    Write-Progress -Activity "Checking PowerShell Scripts" -Status "Starting..." -PercentComplete 0
    
    for ($i = 0; $i -lt $files.Count; $i++) {
        $file = $files[$i]
        $percentComplete = ($i / $files.Count) * 100
        
        Write-Progress -Activity "Checking PowerShell Scripts" -Status "Processing $($file.Name)" -PercentComplete $percentComplete
        
        try {
            $errors = $null
            $tokens = [System.Management.Automation.PSParser]::Tokenize((Get-Content $file.FullName -Raw), [ref]$errors)
            
            $result = [PSCustomObject]@{
                File = $file.Name
                Path = $file.FullName
                RelativePath = Resolve-Path $file.FullName -Relative
                IsValid = ($errors.Count -eq 0)
                TokenCount = $tokens.Count
                ErrorCount = $errors.Count
                FileSize = $file.Length
                LastModified = $file.LastWriteTime
                Errors = if ($errors.Count -gt 0) { 
                    $errors | ForEach-Object { "Line $($_.Token.StartLine): $($_.Message)" }
                } else { @() }
            }
        }
        catch {
            $result = [PSCustomObject]@{
                File = $file.Name
                Path = $file.FullName
                RelativePath = Resolve-Path $file.FullName -Relative
                IsValid = $false
                TokenCount = 0
                ErrorCount = 1
                FileSize = $file.Length
                LastModified = $file.LastWriteTime
                Errors = @("File Error: $($_.Exception.Message)")
            }
        }
        
        $results += $result
    }
    
    Write-Progress -Activity "Checking PowerShell Scripts" -Completed
    
    # Generate summary
    $summary = @{
        TotalFiles = $results.Count
        ValidFiles = ($results | Where-Object IsValid).Count
        InvalidFiles = ($results | Where-Object { -not $_.IsValid }).Count
        TotalTokens = ($results | Measure-Object TokenCount -Sum).Sum
        TotalErrors = ($results | Measure-Object ErrorCount -Sum).Sum
        ReportGenerated = Get-Date
    }
    
    $report = @{
        Summary = $summary
        Results = $results
    }
    
    if ($OutputFile) {
        $report | ConvertTo-Json -Depth 4 | Out-File $OutputFile -Encoding UTF8
        Write-Host "Report saved to: $OutputFile" -ForegroundColor Green
    }
    
    return $report
}

# Usage
$report = New-PowerShellSyntaxReport -Path "." -Recursive -OutputFile "syntax-report.json"
```

## Integration Examples

### Pre-commit Hook

```bash
#!/bin/bash
# .git/hooks/pre-commit

echo "Checking PowerShell script syntax..."

# Find all staged .ps1 files
staged_ps1_files=$(git diff --cached --name-only --diff-filter=ACM | grep '\.ps1$')

if [ -n "$staged_ps1_files" ]; then
    echo "Found PowerShell files to check:"
    echo "$staged_ps1_files"
    
    # Check each file
    error_found=0
    while IFS= read -r file; do
        if [ -f "$file" ]; then
            echo "Checking $file..."
            if ! powershell -NoProfile -Command "[System.Management.Automation.PSParser]::Tokenize((Get-Content '$file' -Raw), [ref]\$null) | Out-Null" 2>/dev/null; then
                echo "❌ Syntax error in $file"
                error_found=1
            else
                echo "✅ $file is valid"
            fi
        fi
    done <<< "$staged_ps1_files"
    
    if [ $error_found -eq 1 ]; then
        echo "❌ Commit blocked due to PowerShell syntax errors"
        exit 1
    fi
    
    echo "✅ All PowerShell scripts have valid syntax"
fi

exit 0
```

### CI/CD Pipeline (GitHub Actions)

```yaml
name: PowerShell Syntax Check

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  powershell-syntax:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup PowerShell
      uses: actions/setup-powershell@v1
      
    - name: Check PowerShell Syntax
      run: |
        $files = Get-ChildItem -Path . -Filter "*.ps1" -Recurse
        $errorCount = 0
        
        foreach ($file in $files) {
          Write-Host "Checking $($file.FullName)..."
          try {
            [System.Management.Automation.PSParser]::Tokenize((Get-Content $file.FullName -Raw), [ref]$null) | Out-Null
            Write-Host "✅ $($file.Name) - OK" -ForegroundColor Green
          } catch {
            Write-Host "❌ $($file.Name) - Error: $_" -ForegroundColor Red
            $errorCount++
          }
        }
        
        if ($errorCount -gt 0) {
          Write-Host "Found $errorCount PowerShell syntax errors" -ForegroundColor Red
          exit 1
        } else {
          Write-Host "All PowerShell scripts have valid syntax" -ForegroundColor Green
        }
      shell: pwsh
```

## Common Error Patterns

### CmdletBinding Parameter Conflicts

**Problem:**
```powershell
[CmdletBinding()]
param(
    [switch]$Verbose,  # Conflicts with built-in -Verbose
    [switch]$Help      # May conflict with built-in help
)
```

**Solution:**
```powershell
[CmdletBinding()]
param(
    [switch]$ShowHelp  # Renamed to avoid conflict
)
# Use $VerbosePreference -eq 'Continue' instead of custom $Verbose
```

### Export-ModuleMember Syntax

**Problem:**
```powershell
Export-ModuleMember Get-MyFunction, Set-MyFunction  # Missing -Function
```

**Solution:**
```powershell
Export-ModuleMember -Function Get-MyFunction, Set-MyFunction
```

### Quote and Escape Issues

**Problem:**
```powershell
$message = "Error: File "test.txt" not found"  # Unescaped quotes
```

**Solution:**
```powershell
$message = "Error: File `"test.txt`" not found"  # Escaped quotes
# or
$message = 'Error: File "test.txt" not found'    # Single quotes
```

## Performance Tips

1. **Use -NoProfile**: Significantly faster startup for syntax checking
2. **Batch processing**: Check multiple files in a single PowerShell session
3. **Tokenize only**: Use PSParser.Tokenize for syntax-only checks
4. **Parallel processing**: Use PowerShell jobs for large file sets

```powershell
# Parallel syntax checking
$jobs = @()
Get-ChildItem *.ps1 | ForEach-Object {
    $jobs += Start-Job -ScriptBlock {
        param($filePath)
        try {
            [System.Management.Automation.PSParser]::Tokenize((Get-Content $filePath -Raw), [ref]$null) | Out-Null
            return @{ File = $filePath; Status = "OK" }
        } catch {
            return @{ File = $filePath; Status = "Error"; Message = $_.ToString() }
        }
    } -ArgumentList $_.FullName
}

$results = $jobs | Wait-Job | Receive-Job
$jobs | Remove-Job
```