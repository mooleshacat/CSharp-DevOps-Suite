# MixerThreholdMod DevOps Tool: Basic Syntax Validator (NON-INTERACTIVE)
# Performs basic syntax validation including bracket matching, semicolon checks, and file integrity
# Identifies potential syntax issues that could cause compilation problems
# Excludes: ForCopilot, Scripts, and Legacy directories

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ((Split-Path $ScriptDir -Leaf) -ieq "Scripts") {
    $ProjectRoot = Split-Path $ScriptDir -Parent
} else {
    $ProjectRoot = $ScriptDir
}

# Check if running interactively or from another script
$IsInteractive = [Environment]::UserInteractive -and $Host.Name -ne "ConsoleHost"
$RunningFromScript = $MyInvocation.InvocationName -notmatch "\.ps1$"

Write-Host "🕐 Syntax validation started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "Validating syntax in: $ProjectRoot" -ForegroundColor DarkCyan
Write-Host "🚀 NON-INTERACTIVE VERSION - Compatible with automation" -ForegroundColor Green
Write-Host "Excluding: ForCopilot, Scripts, and Legacy directories" -ForegroundColor DarkGray

# Function to perform comprehensive syntax validation
function Get-SyntaxValidation {
    param([string]$Path)
    
    try {
        $files = Get-ChildItem -Path $Path -Recurse -Include *.cs -ErrorAction SilentlyContinue | Where-Object {
            $_.PSIsContainer -eq $false -and
            $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy)[\\/]" -and
            $_.FullName -notmatch "[\\/]\.git[\\/]"
        }
        
        $validation = @()
        
        foreach ($file in $files) {
            try {
                # Check file accessibility and basic integrity
                $fileInfo = Get-Item $file.FullName -ErrorAction Stop
                $content = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
                $lines = Get-Content -Path $file.FullName -ErrorAction Stop
                
                if (-not $content) {
                    $validation += [PSCustomObject]@{
                        File = $file.FullName
                        RelativePath = $file.FullName.Replace($Path, "").TrimStart('\', '/')
                        FileName = $file.Name
                        FileSize = $fileInfo.Length
                        LineCount = 0
                        Issues = @("Empty file")
                        Warnings = @()
                        SyntaxScore = 0
                        HasCriticalIssues = $true
                        IsTruncated = $false
                        Encoding = "Unknown"
                    }
                    continue
                }
                
                $relativePath = $file.FullName.Replace($Path, "").TrimStart('\', '/')
                $issues = @()
                $warnings = @()
                
                # Basic file integrity checks
                $isTruncated = $false
                $encoding = "UTF-8"
                
                # Check for file truncation (incomplete syntax at end)
                $lastNonEmptyLine = ""
                for ($i = $lines.Count - 1; $i -ge 0; $i--) {
                    if ($lines[$i].Trim()) {
                        $lastNonEmptyLine = $lines[$i].Trim()
                        break
                    }
                }
                
                if ($lastNonEmptyLine -and -not $lastNonEmptyLine.EndsWith('}') -and -not $lastNonEmptyLine.EndsWith(';') -and -not $lastNonEmptyLine.EndsWith('*/')) {
                    $isTruncated = $true
                    $issues += "File may be truncated (incomplete ending)"
                }
                
                # Bracket and brace matching
                $brackets = @{
                    '(' = 0; ')' = 0
                    '[' = 0; ']' = 0
                    '{' = 0; '}' = 0
                }
                
                $inString = $false
                $inChar = $false
                $inComment = $false
                $inMultiComment = $false
                $escapeNext = $false
                
                # Parse character by character for accurate bracket counting
                for ($i = 0; $i -lt $content.Length; $i++) {
                    $char = $content[$i]
                    $nextChar = if ($i + 1 -lt $content.Length) { $content[$i + 1] } else { $null }
                    
                    # Handle escape sequences
                    if ($escapeNext) {
                        $escapeNext = $false
                        continue
                    }
                    
                    if ($char -eq '\' -and ($inString -or $inChar)) {
                        $escapeNext = $true
                        continue
                    }
                    
                    # Handle comments
                    if (-not $inString -and -not $inChar) {
                        if ($char -eq '/' -and $nextChar -eq '/') {
                            $inComment = $true
                            $i++ # Skip next char
                            continue
                        }
                        elseif ($char -eq '/' -and $nextChar -eq '*') {
                            $inMultiComment = $true
                            $i++ # Skip next char
                            continue
                        }
                        elseif ($char -eq '*' -and $nextChar -eq '/' -and $inMultiComment) {
                            $inMultiComment = $false
                            $i++ # Skip next char
                            continue
                        }
                        elseif ($char -eq "`n" -and $inComment) {
                            $inComment = $false
                            continue
                        }
                    }
                    
                    # Skip if in comment
                    if ($inComment -or $inMultiComment) {
                        continue
                    }
                    
                    # Handle strings and characters
                    if ($char -eq '"' -and -not $inChar) {
                        $inString = -not $inString
                        continue
                    }
                    elseif ($char -eq "'" -and -not $inString) {
                        $inChar = -not $inChar
                        continue
                    }
                    
                    # Count brackets only outside strings/comments
                    if (-not $inString -and -not $inChar) {
                        if ($brackets.ContainsKey($char)) {
                            $brackets[$char]++
                        }
                    }
                }
                
                # Check bracket balance
                if ($brackets['('] -ne $brackets[')']) {
                    $issues += "Unmatched parentheses: $($brackets['(']) open, $($brackets[')']) close"
                }
                if ($brackets['['] -ne $brackets[']']) {
                    $issues += "Unmatched square brackets: $($brackets['[']) open, $($brackets[']']) close"
                }
                if ($brackets['{'] -ne $brackets['}']) {
                    $issues += "Unmatched curly braces: $($brackets['{']) open, $($brackets['}']) close"
                }
                
                # Basic semicolon validation
                $missingSemicolons = @()
                $extraSemicolons = @()
                
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    $line = $lines[$i].Trim()
                    $lineNum = $i + 1
                    
                    # Skip empty lines, comments, and preprocessor directives
                    if (-not $line -or $line.StartsWith('//') -or $line.StartsWith('#') -or $line.StartsWith('/*') -or $line -eq '*/') {
                        continue
                    }
                    
                    # Check for missing semicolons (simplified heuristic)
                    if ($line -match '^\s*(var|int|string|bool|float|double|decimal|long|short|byte|char|object)\s+\w+\s*=\s*.+[^;{}\s]$') {
                        $missingSemicolons += $lineNum
                    }
                    elseif ($line -match '^\s*\w+\s*\([^)]*\)\s*[^;{}\s]$' -and -not $line -match '\s*(if|for|while|using|switch|try|catch|finally|else)\s*\(') {
                        $missingSemicolons += $lineNum
                    }
                    elseif ($line -match '^\s*return\s+.+[^;]$') {
                        $missingSemicolons += $lineNum
                    }
                    
                    # Check for extra semicolons
                    if ($line -match ';;+') {
                        $extraSemicolons += $lineNum
                    }
                }
                
                if ($missingSemicolons.Count -gt 0) {
                    $issues += "Potential missing semicolons on lines: $($missingSemicolons -join ', ')"
                }
                if ($extraSemicolons.Count -gt 0) {
                    $warnings += "Extra semicolons on lines: $($extraSemicolons -join ', ')"
                }
                
                # String literal validation
                $unclosedStrings = @()
                
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    $line = $lines[$i]
                    $lineNum = $i + 1
                    
                    # Simple string validation (not perfect but catches obvious issues)
                    $quoteCount = ($line.ToCharArray() | Where-Object { $_ -eq '"' }).Count
                    $escapedQuoteCount = ([regex]::Matches($line, '\\"')).Count
                    $actualQuoteCount = $quoteCount - $escapedQuoteCount
                    
                    if ($actualQuoteCount % 2 -ne 0) {
                        $unclosedStrings += $lineNum
                    }
                }
                
                if ($unclosedStrings.Count -gt 0) {
                    $issues += "Potential unclosed strings on lines: $($unclosedStrings -join ', ')"
                }
                
                # Namespace and class structure validation
                $hasNamespace = $content -match 'namespace\s+[A-Za-z0-9_.]+\s*{'
                $hasClass = $content -match '(public|internal|private)?\s*(static|abstract|sealed)?\s*class\s+[A-Za-z0-9_<>]+\s*[:{]'
                
                if (-not $hasNamespace) {
                    $warnings += "No namespace declaration found"
                }
                if (-not $hasClass) {
                    $warnings += "No class declaration found"
                }
                
                # Calculate syntax score
                $syntaxScore = 100
                $syntaxScore -= $issues.Count * 20  # Major issues
                $syntaxScore -= $warnings.Count * 10  # Minor issues
                $syntaxScore = [Math]::Max(0, $syntaxScore)
                
                $validation += [PSCustomObject]@{
                    File = $file.FullName
                    RelativePath = $relativePath
                    FileName = $file.Name
                    FileSize = $fileInfo.Length
                    LineCount = $lines.Count
                    Issues = $issues
                    Warnings = $warnings
                    SyntaxScore = $syntaxScore
                    HasCriticalIssues = ($issues.Count -gt 0)
                    IsTruncated = $isTruncated
                    Encoding = $encoding
                    BracketBalance = $brackets
                    HasNamespace = $hasNamespace
                    HasClass = $hasClass
                }
            }
            catch {
                $validation += [PSCustomObject]@{
                    File = $file.FullName
                    RelativePath = $file.FullName.Replace($Path, "").TrimStart('\', '/')
                    FileName = $file.Name
                    FileSize = 0
                    LineCount = 0
                    Issues = @("Error reading file: $($_.Exception.Message)")
                    Warnings = @()
                    SyntaxScore = 0
                    HasCriticalIssues = $true
                    IsTruncated = $false
                    Encoding = "Unknown"
                }
                
                Write-Host "⚠️  Error processing $($file.Name): $_" -ForegroundColor DarkYellow
                continue
            }
        }
        
        return $validation
    }
    catch {
        Write-Host "⚠️  Error scanning for syntax validation: $_" -ForegroundColor DarkYellow
        return @()
    }
}

Write-Host "`n📂 Performing syntax validation..." -ForegroundColor DarkGray
$validation = Get-SyntaxValidation -Path $ProjectRoot

Write-Host "📊 Validated $($validation.Count) C# files" -ForegroundColor Gray

if ($validation.Count -eq 0) {
    Write-Host "⚠️  No C# files found for syntax validation" -ForegroundColor DarkYellow
    if ($IsInteractive -and -not $RunningFromScript) {
        Write-Host "`nPress ENTER to continue..." -ForegroundColor Gray -NoNewline
        Read-Host
    }
    return
}

# Calculate overall statistics
$filesWithIssues = $validation | Where-Object { $_.HasCriticalIssues }
$filesWithWarnings = $validation | Where-Object { $_.Warnings.Count -gt 0 }
$truncatedFiles = $validation | Where-Object { $_.IsTruncated }
$emptyFiles = $validation | Where-Object { $_.LineCount -eq 0 }

$totalIssues = ($validation | ForEach-Object { $_.Issues.Count } | Measure-Object -Sum).Sum
$totalWarnings = ($validation | ForEach-Object { $_.Warnings.Count } | Measure-Object -Sum).Sum
$averageScore = if ($validation.Count -gt 0) { [Math]::Round(($validation | ForEach-Object { $_.SyntaxScore } | Measure-Object -Average).Average, 1) } else { 0 }

Write-Host "`n=== SYNTAX VALIDATION REPORT ===" -ForegroundColor DarkCyan
Write-Host "🕐 Validation completed: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray

# Overall Health Assessment
Write-Host "`n📊 Overall Syntax Health:" -ForegroundColor DarkCyan
$healthPercent = if ($validation.Count -gt 0) { [Math]::Round((($validation.Count - $filesWithIssues.Count) / $validation.Count) * 100, 1) } else { 0 }
Write-Host "   Files without critical issues: $(($validation.Count - $filesWithIssues.Count))/$($validation.Count) ($healthPercent%)" -ForegroundColor $(if ($healthPercent -gt 90) { "Green" } elseif ($healthPercent -gt 75) { "DarkYellow" } else { "Red" })
Write-Host "   Average syntax score: $averageScore/100" -ForegroundColor $(if ($averageScore -gt 90) { "Green" } elseif ($averageScore -gt 75) { "DarkYellow" } else { "Red" })

# Issue Summary
Write-Host "`n🚨 Issue Summary:" -ForegroundColor DarkCyan
if ($totalIssues -gt 0) {
    Write-Host "   Critical issues: $totalIssues in $($filesWithIssues.Count) files" -ForegroundColor Red
} else {
    Write-Host "   Critical issues: None detected ✅" -ForegroundColor Green
}

if ($totalWarnings -gt 0) {
    Write-Host "   Warnings: $totalWarnings in $($filesWithWarnings.Count) files" -ForegroundColor DarkYellow
} else {
    Write-Host "   Warnings: None ✅" -ForegroundColor Green
}

if ($truncatedFiles.Count -gt 0) {
    Write-Host "   Potentially truncated files: $($truncatedFiles.Count)" -ForegroundColor Red
}

if ($emptyFiles.Count -gt 0) {
    Write-Host "   Empty files: $($emptyFiles.Count)" -ForegroundColor DarkYellow
}

# Show critical issues (limited for automation)
if ($filesWithIssues.Count -gt 0) {
    Write-Host "`n🚨 Critical Issues Found:" -ForegroundColor Red
    $topIssues = $filesWithIssues | Sort-Object { $_.Issues.Count } -Descending | Select-Object -First 5
    foreach ($file in $topIssues) {
        Write-Host "   📄 $($file.RelativePath) (Score: $($file.SyntaxScore)/100)" -ForegroundColor Red
        $file.Issues | Select-Object -First 2 | ForEach-Object {
            Write-Host "      • $_" -ForegroundColor DarkRed
        }
        if ($file.Issues.Count -gt 2) {
            Write-Host "      ... and $($file.Issues.Count - 2) more issues" -ForegroundColor DarkGray
        }
    }
    if ($filesWithIssues.Count -gt 5) {
        Write-Host "   ... and $($filesWithIssues.Count - 5) more files with issues" -ForegroundColor DarkGray
    }
}

# Show warnings if any
if ($filesWithWarnings.Count -gt 0 -and $filesWithWarnings.Count -le 3) {
    Write-Host "`n⚠️  Warnings Detected:" -ForegroundColor DarkYellow
    foreach ($file in $filesWithWarnings | Select-Object -First 3) {
        Write-Host "   📄 $($file.RelativePath)" -ForegroundColor DarkYellow
        $file.Warnings | ForEach-Object {
            Write-Host "      • $_" -ForegroundColor Gray
        }
    }
}

# File Statistics
Write-Host "`n📈 File Statistics:" -ForegroundColor DarkCyan
$totalLines = ($validation | ForEach-Object { $_.LineCount } | Measure-Object -Sum).Sum
$totalSize = ($validation | ForEach-Object { $_.FileSize } | Measure-Object -Sum).Sum
$avgLines = if ($validation.Count -gt 0) { [Math]::Round(($totalLines / $validation.Count), 1) } else { 0 }
$avgSize = if ($validation.Count -gt 0) { [Math]::Round(($totalSize / $validation.Count / 1KB), 1) } else { 0 }

Write-Host "   Total lines of code: $totalLines" -ForegroundColor Gray
Write-Host "   Total file size: $([Math]::Round($totalSize / 1KB, 1)) KB" -ForegroundColor Gray
Write-Host "   Average lines per file: $avgLines" -ForegroundColor Gray
Write-Host "   Average file size: $avgSize KB" -ForegroundColor Gray

# Recommendations
Write-Host "`n💡 Recommendations:" -ForegroundColor DarkCyan

if ($filesWithIssues.Count -gt 0) {
    Write-Host "   🚨 CRITICAL: Fix $totalIssues syntax issues in $($filesWithIssues.Count) files" -ForegroundColor Red
    Write-Host "   • Review bracket and brace matching" -ForegroundColor Red
    Write-Host "   • Check for missing semicolons" -ForegroundColor Red
    Write-Host "   • Validate string literal closures" -ForegroundColor Red
}

if ($truncatedFiles.Count -gt 0) {
    Write-Host "   📋 URGENT: Check $($truncatedFiles.Count) potentially truncated files" -ForegroundColor Red
}

if ($totalWarnings -gt 0) {
    Write-Host "   ⚠️  Review $totalWarnings warnings for code quality improvements" -ForegroundColor DarkYellow
}

Write-Host "   • Use IDE syntax highlighting to catch issues early" -ForegroundColor Gray
Write-Host "   • Enable compiler warnings in build configuration" -ForegroundColor Gray
Write-Host "   • Consider automated syntax validation in CI/CD pipeline" -ForegroundColor Gray

# Create Reports directory if it doesn't exist
$reportsDir = Join-Path $ProjectRoot "Reports"
if (-not (Test-Path $reportsDir)) {
    try {
        New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null
        Write-Host "`n📁 Created Reports directory: $reportsDir" -ForegroundColor Green
    }
    catch {
        Write-Host "`n⚠️ Could not create Reports directory, using project root" -ForegroundColor DarkYellow
        $reportsDir = $ProjectRoot
    }
}

# Generate detailed syntax validation report
Write-Host "`n📝 Generating detailed syntax validation report..." -ForegroundColor DarkGray

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPath = Join-Path $reportsDir "SYNTAX-VALIDATION-REPORT_$timestamp.md"

$reportContent = @()
$reportContent += "# Syntax Validation Report"
$reportContent += ""
$reportContent += "**Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportContent += "**Files Validated**: $($validation.Count)"
$reportContent += "**Overall Health**: $healthPercent%"
$reportContent += "**Average Syntax Score**: $averageScore/100"
$reportContent += ""

# Executive Summary
$reportContent += "## Executive Summary"
$reportContent += ""

if ($healthPercent -ge 95 -and $averageScore -ge 90) {
    $reportContent += "🎉 **EXCELLENT SYNTAX QUALITY!** Health: $healthPercent%, Score: $averageScore/100"
    $reportContent += ""
    $reportContent += "Your codebase demonstrates outstanding syntax quality and consistency."
} elseif ($healthPercent -ge 80 -and $averageScore -ge 75) {
    $reportContent += "✅ **GOOD SYNTAX QUALITY!** Health: $healthPercent%, Score: $averageScore/100"
    $reportContent += ""
    $reportContent += "Minor syntax issues exist but overall quality is good."
} elseif ($healthPercent -ge 60 -or $averageScore -ge 50) {
    $reportContent += "⚠️ **SYNTAX ISSUES DETECTED** - Health: $healthPercent%, Score: $averageScore/100"
    $reportContent += ""
    $reportContent += "**Recommendation**: Address syntax issues for better code reliability."
} else {
    $reportContent += "🚨 **CRITICAL SYNTAX PROBLEMS** - Health: $healthPercent%, Score: $averageScore/100"
    $reportContent += ""
    $reportContent += "**Immediate Action Required**: Multiple critical syntax issues need fixing."
}

$reportContent += ""
$reportContent += "| Metric | Value | Status |"
$reportContent += "|--------|-------|--------|"
$reportContent += "| **Files Without Critical Issues** | $(($validation.Count - $filesWithIssues.Count))/$($validation.Count) | $(if ($healthPercent -ge 95) { "✅ Excellent" } elseif ($healthPercent -ge 80) { "⚠️ Good" } else { "🚨 Needs Work" }) |"
$reportContent += "| **Average Syntax Score** | $averageScore/100 | $(if ($averageScore -ge 90) { "✅ Excellent" } elseif ($averageScore -ge 75) { "⚠️ Good" } else { "🚨 Poor" }) |"
$reportContent += "| **Critical Issues** | $totalIssues | $(if ($totalIssues -eq 0) { "✅ None" } elseif ($totalIssues -le 5) { "⚠️ Few" } else { "🚨 Many" }) |"
$reportContent += "| **Warnings** | $totalWarnings | $(if ($totalWarnings -eq 0) { "✅ None" } elseif ($totalWarnings -le 5) { "📝 Few" } else { "⚠️ Several" }) |"
$reportContent += "| **Truncated Files** | $($truncatedFiles.Count) | $(if ($truncatedFiles.Count -eq 0) { "✅ None" } else { "🚨 Found" }) |"
$reportContent += ""

# Critical Issues Analysis
if ($filesWithIssues.Count -gt 0) {
    $reportContent += "## Critical Syntax Issues"
    $reportContent += ""
    $reportContent += "Files with syntax errors requiring immediate attention:"
    $reportContent += ""
    $reportContent += "| File | Score | Issues | Details |"
    $reportContent += "|------|-------|--------|---------|"
    
    foreach ($file in $filesWithIssues | Sort-Object SyntaxScore) {
        $issueList = ($file.Issues | Select-Object -First 2) -join "; "
        if ($file.Issues.Count -gt 2) {
            $issueList += "; ... +$($file.Issues.Count - 2) more"
        }
        $reportContent += "| `$($file.RelativePath)` | $($file.SyntaxScore)/100 | $($file.Issues.Count) | $issueList |"
    }
    $reportContent += ""
}

# Truncated Files
if ($truncatedFiles.Count -gt 0) {
    $reportContent += "## 🚨 Potentially Truncated Files"
    $reportContent += ""
    $reportContent += "Files that may be incomplete or corrupted:"
    $reportContent += ""
    $reportContent += "| File | Size | Lines | Last Content |"
    $reportContent += "|------|------|-------|--------------|"
    
    foreach ($file in $truncatedFiles) {
        $reportContent += "| `$($file.RelativePath)` | $([Math]::Round($file.FileSize / 1KB, 1)) KB | $($file.LineCount) | Incomplete ending detected |"
    }
    $reportContent += ""
}

# Warnings Analysis
if ($filesWithWarnings.Count -gt 0) {
    $reportContent += "## Code Quality Warnings"
    $reportContent += ""
    $reportContent += "Files with non-critical quality issues:"
    $reportContent += ""
    $reportContent += "| File | Warnings | Details |"
    $reportContent += "|------|----------|---------|"
    
    foreach ($file in $filesWithWarnings | Sort-Object { $_.Warnings.Count } -Descending) {
        $warningList = ($file.Warnings | Select-Object -First 3) -join "; "
        if ($file.Warnings.Count -gt 3) {
            $warningList += "; ... +$($file.Warnings.Count - 3) more"
        }
        $reportContent += "| `$($file.RelativePath)` | $($file.Warnings.Count) | $warningList |"
    }
    $reportContent += ""
}

# File Statistics
$reportContent += "## File Statistics"
$reportContent += ""
$reportContent += "| Metric | Value |"
$reportContent += "|--------|-------|"
$reportContent += "| **Total Files** | $($validation.Count) |"
$reportContent += "| **Total Lines of Code** | $totalLines |"
$reportContent += "| **Total Size** | $([Math]::Round($totalSize / 1KB, 1)) KB |"
$reportContent += "| **Average Lines per File** | $avgLines |"
$reportContent += "| **Average File Size** | $avgSize KB |"
$reportContent += "| **Empty Files** | $($emptyFiles.Count) |"
$reportContent += ""

# Action Plan
$reportContent += "## 🎯 Action Plan"
$reportContent += ""

if ($filesWithIssues.Count -gt 0) {
    $reportContent += "### 🚨 CRITICAL: Fix Syntax Errors"
    $reportContent += ""
    $reportContent += "**$totalIssues critical syntax issues** require immediate attention:"
    $reportContent += ""
    $reportContent += "1. **Bracket Matching**: Fix unmatched brackets and braces"
    $reportContent += "2. **Semicolon Issues**: Add missing semicolons, remove duplicates"
    $reportContent += "3. **String Literals**: Close unclosed string literals"
    $reportContent += "4. **File Integrity**: Restore truncated or corrupted files"
    $reportContent += ""
}

if ($truncatedFiles.Count -gt 0) {
    $reportContent += "### 📋 URGENT: Restore Truncated Files"
    $reportContent += ""
    $reportContent += "**$($truncatedFiles.Count) files** appear to be incomplete:"
    $reportContent += ""
    $reportContent += "1. **Check Version Control**: Restore from git history"
    $reportContent += "2. **Backup Recovery**: Use backup copies if available"
    $reportContent += "3. **Manual Restoration**: Complete incomplete syntax manually"
    $reportContent += ""
}

if ($totalWarnings -gt 0) {
    $reportContent += "### ⚠️ Address Quality Warnings"
    $reportContent += ""
    $reportContent += "**$totalWarnings warnings** for code quality improvements:"
    $reportContent += ""
    $reportContent += "1. **Missing Namespaces**: Add namespace declarations"
    $reportContent += "2. **Missing Classes**: Ensure files contain class definitions"
    $reportContent += "3. **Code Organization**: Improve file structure"
    $reportContent += ""
}

# Best Practices
$reportContent += "### Best Practices for .NET 4.8.1"
$reportContent += ""
$reportContent += "1. **IDE Integration**: Use syntax highlighting and error detection"
$reportContent += "2. **Build Validation**: Enable all compiler warnings"
$reportContent += "3. **Code Reviews**: Manual syntax review during PRs"
$reportContent += "4. **Automated Checks**: Include syntax validation in CI/CD"
$reportContent += "5. **File Backup**: Regular backups to prevent data loss"

# Technical Details
$reportContent += ""
$reportContent += "## Technical Analysis Details"
$reportContent += ""
$reportContent += "### Validation Checks Performed"
$reportContent += ""
$reportContent += "- **Bracket Matching**: Parentheses, square brackets, curly braces"
$reportContent += "- **String Literals**: Quote matching and escape sequence validation"
$reportContent += "- **Semicolon Analysis**: Missing and duplicate semicolons"
$reportContent += "- **File Integrity**: Truncation and corruption detection"
$reportContent += "- **Structure Validation**: Namespace and class presence"
$reportContent += ""
$reportContent += "### Scoring Methodology"
$reportContent += ""
$reportContent += "- **Base Score**: 100 points"
$reportContent += "- **Critical Issues**: -20 points each"
$reportContent += "- **Warnings**: -10 points each"
$reportContent += "- **Minimum Score**: 0 points"

# Footer
$reportContent += ""
$reportContent += "---"
$reportContent += ""
$reportContent += "**Target Health**: 95%+ files without critical issues"
$reportContent += ""
$reportContent += "*Generated by MixerThreholdMod DevOps Suite - Syntax Validation Tool*"

try {
    $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
    $saveSuccess = $true
}
catch {
    Write-Host "⚠️ Error saving detailed report: $_" -ForegroundColor DarkYellow
    $saveSuccess = $false
}

Write-Host "`n🚀 Syntax validation complete!" -ForegroundColor Green

# OUTPUT PATH AT THE END for easy finding
if ($saveSuccess) {
    Write-Host "`n📄 DETAILED REPORT SAVED:" -ForegroundColor Green
    Write-Host "   Location: $reportPath" -ForegroundColor Cyan
    Write-Host "   Size: $([Math]::Round((Get-Item $reportPath).Length / 1KB, 1)) KB" -ForegroundColor Gray
    Write-Host "   Health Score: $healthPercent%" -ForegroundColor $(if ($healthPercent -ge 95) { "Green" } elseif ($healthPercent -ge 80) { "DarkYellow" } else { "Red" })
} else {
    Write-Host "`n⚠️ No detailed report generated" -ForegroundColor DarkYellow
}

# INTERACTIVE WORKFLOW LOOP (only when running standalone)
if ($IsInteractive -and -not $RunningFromScript) {
    do {
        Write-Host "`n🎯 What would you like to do next?" -ForegroundColor DarkCyan
        Write-Host "   D - Display report in console" -ForegroundColor Green
        Write-Host "   R - Re-run syntax validation analysis" -ForegroundColor DarkYellow
        Write-Host "   X - Exit to DevOps menu" -ForegroundColor Gray
        
        $choice = Read-Host "`nEnter choice (D/R/X)"
        $choice = $choice.ToUpper()
        
        switch ($choice) {
            'D' {
                if ($saveSuccess) {
                    Write-Host "`n📋 DISPLAYING SYNTAX VALIDATION REPORT:" -ForegroundColor DarkCyan
                    Write-Host "=====================================" -ForegroundColor DarkCyan
                    try {
                        $reportDisplay = Get-Content -Path $reportPath -Raw
                        Write-Host $reportDisplay -ForegroundColor White
                        Write-Host "`n=====================================" -ForegroundColor DarkCyan
                        Write-Host "📋 END OF REPORT" -ForegroundColor DarkCyan
                    }
                    catch {
                        Write-Host "❌ Could not display report: $_" -ForegroundColor Red
                    }
                } else {
                    Write-Host "❌ No report available to display" -ForegroundColor Red
                }
            }
            'R' {
                Write-Host "`n🔄 RE-RUNNING SYNTAX VALIDATION..." -ForegroundColor DarkYellow
                Write-Host "=================================" -ForegroundColor DarkYellow
                & $MyInvocation.MyCommand.Path
                return
            }
            'X' {
                Write-Host "`n👋 Returning to DevOps menu..." -ForegroundColor Gray
                return
            }
            default {
                Write-Host "❌ Invalid choice. Please enter D, R, or X." -ForegroundColor Red
            }
        }
    } while ($choice -notin @('X'))
} else {
    Write-Host "📄 Script completed - returning to caller" -ForegroundColor DarkGray
}