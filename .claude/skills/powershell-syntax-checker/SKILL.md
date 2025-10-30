---
name: powershell-syntax-checker
description: Check PowerShell script syntax for errors and validation. Use when validating PowerShell scripts, checking .ps1 files for syntax errors, or ensuring PowerShell code quality before execution.
allowed-tools: run_in_terminal, read_file, file_search, grep_search
---

# PowerShell Syntax Checker

This skill provides comprehensive PowerShell script syntax validation using PowerShell's built-in parser and analysis tools.

## When to use this skill

- Validating PowerShell script syntax before execution
- Checking .ps1 files for parse errors
- Ensuring PowerShell code quality and best practices
- Debugging PowerShell syntax issues
- Batch validation of multiple PowerShell scripts

## Instructions

### Single Script Validation

1. **Basic Syntax Check**: Use PowerShell's PSParser to validate syntax
   ```powershell
   powershell -NoProfile -Command "[System.Management.Automation.PSParser]::Tokenize((Get-Content 'script.ps1' -Raw), [ref]`$null) | Out-Null; Write-Host 'Syntax OK'"
   ```

2. **Advanced Analysis**: Use PSScriptAnalyzer for detailed code analysis
   ```powershell
   powershell -NoProfile -Command "if (Get-Module -ListAvailable PSScriptAnalyzer) { Invoke-ScriptAnalyzer 'script.ps1' } else { 'PSScriptAnalyzer not available' }"
   ```

### Multiple Scripts Validation

1. **Batch Check**: Validate all .ps1 files in a directory
   ```powershell
   Get-ChildItem *.ps1 | ForEach-Object { 
       try { 
           [System.Management.Automation.PSParser]::Tokenize((Get-Content $_.FullName -Raw), [ref]$null) | Out-Null
           Write-Host "$($_.Name): ✓ OK" -ForegroundColor Green
       } catch { 
           Write-Host "$($_.Name): ✗ Error - $_" -ForegroundColor Red
       }
   }
   ```

### Syntax Error Analysis

When syntax errors are found:

1. **Parse Error Details**: Extract specific error information
2. **Line Number Identification**: Show where errors occur
3. **Common Issues**: Check for:
   - Missing closing braces `}`
   - Unmatched quotes
   - Invalid parameter syntax
   - Incorrect cmdlet binding
   - Module export issues

### Best Practices Validation

Check for PowerShell best practices:

1. **Parameter Binding**: Ensure proper `[CmdletBinding()]` usage
2. **Error Handling**: Verify `$ErrorActionPreference` and try/catch blocks
3. **Variable Scope**: Check script-level variables with `$script:`
4. **Function Exports**: Validate `Export-ModuleMember` syntax
5. **Help Documentation**: Ensure proper comment-based help

## Common PowerShell Syntax Issues

### CmdletBinding Conflicts
- **Issue**: Custom parameters conflicting with built-in CmdletBinding parameters
- **Check**: Look for `-Verbose`, `-Debug`, `-ErrorAction` parameter conflicts
- **Solution**: Use built-in parameters or rename custom ones

### Quote and Escape Issues
- **Issue**: Unescaped quotes or incorrect string interpolation
- **Check**: Validate quote matching and escape sequences
- **Solution**: Use proper PowerShell string escaping

### Module Export Problems
- **Issue**: Incorrect `Export-ModuleMember` syntax
- **Check**: Ensure functions are properly exported
- **Solution**: Use correct function name lists or wildcards

### Path Separator Issues
- **Issue**: Hardcoded Windows-style paths
- **Check**: Look for backslashes in paths
- **Solution**: Use `Join-Path` for cross-platform compatibility

## Advanced Features

### Script Analysis Report
Generate comprehensive analysis reports including:
- Syntax validation status
- Best practice compliance
- Security considerations
- Performance recommendations
- Cross-platform compatibility

### Integration with Development Workflow
- Pre-commit syntax validation
- CI/CD pipeline integration
- IDE syntax checking
- Automated code review

## Examples

### Quick Single File Check
```powershell
# Basic syntax validation
powershell -NoProfile -Command "try { [System.Management.Automation.PSParser]::Tokenize((Get-Content 'MyScript.ps1' -Raw), [ref]`$null) | Out-Null; 'Syntax OK' } catch { 'Syntax Error: ' + `$_ }"
```

### Detailed Analysis with Error Reporting
```powershell
# Comprehensive check with error details
powershell -NoProfile -Command "
try { 
    `$tokens = [System.Management.Automation.PSParser]::Tokenize((Get-Content 'MyScript.ps1' -Raw), [ref]`$errors)
    if (`$errors.Count -gt 0) { 
        'Syntax Errors Found:'; `$errors | ForEach-Object { '  Line ' + `$_.Token.StartLine + ': ' + `$_.Message }
    } else { 
        'Syntax OK - ' + `$tokens.Count + ' tokens parsed successfully'
    }
} catch { 
    'Parse Error: ' + `$_ 
}"
```

### Batch Validation with Summary
```powershell
# Check all PowerShell scripts in current directory
$results = @()
Get-ChildItem *.ps1 | ForEach-Object {
    try {
        [System.Management.Automation.PSParser]::Tokenize((Get-Content $_.FullName -Raw), [ref]$null) | Out-Null
        $results += [PSCustomObject]@{ File = $_.Name; Status = "✓ OK"; Error = "" }
    } catch {
        $results += [PSCustomObject]@{ File = $_.Name; Status = "✗ Error"; Error = $_.ToString() }
    }
}
$results | Format-Table -AutoSize
```

## Requirements

- PowerShell 5.1 or later
- Windows PowerShell or PowerShell Core
- Optional: PSScriptAnalyzer module for advanced analysis

## Error Codes

- **0**: All scripts passed syntax validation
- **1**: One or more scripts have syntax errors
- **2**: Unable to access or read script files
- **3**: PowerShell parser not available

## Tips

1. **Always validate before execution**: Catch syntax errors early
2. **Use verbose output**: Get detailed information about parsing process
3. **Check module dependencies**: Ensure required modules are available
4. **Test cross-platform**: Validate scripts work on different PowerShell versions
5. **Automate validation**: Integrate into build and deployment processes