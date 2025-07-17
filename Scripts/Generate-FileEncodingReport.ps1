# MixerThreholdMod DevOps Tool: File Encoding Report Generator (NON-INTERACTIVE)
# Detects file encoding issues, BOM problems, and mixed encoding corruption
# Analyzes text files for encoding consistency and potential corruption
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

Write-Host "🕐 File encoding analysis started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "Analyzing file encodings in: $ProjectRoot" -ForegroundColor DarkCyan
Write-Host "🚀 NON-INTERACTIVE VERSION - Compatible with automation" -ForegroundColor Green

# Function to get file encoding
function Get-FileEncoding {
    param([string]$FilePath)
    
    try {
        if (-not (Test-Path $FilePath)) {
            return [PSCustomObject]@{
                Encoding = "UNKNOWN"
                BOM = $false
                Confidence = "LOW"
                Issues = @("File not found")
            }
        }
        
        # Read first few bytes to detect BOM and encoding
        $bytes = [System.IO.File]::ReadAllBytes($FilePath) | Select-Object -First 10
        $issues = @()
        
        # BOM Detection
        $hasBOM = $false
        $encoding = "UNKNOWN"
        $confidence = "LOW"
        
        if ($bytes.Length -ge 3) {
            # UTF-8 BOM: EF BB BF
            if ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
                $encoding = "UTF-8"
                $hasBOM = $true
                $confidence = "HIGH"
            }
            # UTF-16 LE BOM: FF FE
            elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
                $encoding = "UTF-16LE"
                $hasBOM = $true
                $confidence = "HIGH"
            }
            # UTF-16 BE BOM: FE FF
            elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
                $encoding = "UTF-16BE"
                $hasBOM = $true
                $confidence = "HIGH"
            }
            # UTF-32 LE BOM: FF FE 00 00
            elseif ($bytes.Length -ge 4 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE -and $bytes[2] -eq 0x00 -and $bytes[3] -eq 0x00) {
                $encoding = "UTF-32LE"
                $hasBOM = $true
                $confidence = "HIGH"
            }
            # UTF-32 BE BOM: 00 00 FE FF
            elseif ($bytes.Length -ge 4 -and $bytes[0] -eq 0x00 -and $bytes[1] -eq 0x00 -and $bytes[2] -eq 0xFE -and $bytes[3] -eq 0xFF) {
                $encoding = "UTF-32BE"
                $hasBOM = $true
                $confidence = "HIGH"
            }
        }
        
        # If no BOM detected, try to determine encoding heuristically
        if ($encoding -eq "UNKNOWN") {
            $content = $null
            try {
                # Try UTF-8 first
                $content = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)
                
                # Check for UTF-8 validity
                $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
                $reconverted = [System.Text.Encoding]::UTF8.GetString($utf8Bytes)
                
                if ($content -eq $reconverted) {
                    # Check for high-bit characters (suggests UTF-8)
                    $hasHighBit = $false
                    foreach ($byte in $bytes) {
                        if ($byte -gt 127) {
                            $hasHighBit = $true
                            break
                        }
                    }
                    
                    if ($hasHighBit) {
                        $encoding = "UTF-8"
                        $confidence = "MEDIUM"
                    } else {
                        $encoding = "ASCII"
                        $confidence = "HIGH"
                    }
                } else {
                    $issues += "UTF-8 conversion mismatch detected"
                }
            }
            catch {
                try {
                    # Try ANSI/Windows-1252
                    $content = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::GetEncoding(1252))
                    $encoding = "ANSI"
                    $confidence = "LOW"
                    $issues += "Possible ANSI encoding (legacy)"
                }
                catch {
                    $encoding = "BINARY"
                    $confidence = "HIGH"
                    $issues += "Binary file or unknown text encoding"
                }
            }
        }
        
        # Additional corruption checks
        if ($content -and $encoding -ne "BINARY") {
            # Check for null bytes in text files
            if ($content.Contains([char]0)) {
                $issues += "Null bytes found in text file"
            }
            
            # Check for mixed line endings
            $hasLF = $content.Contains("`n")
            $hasCR = $content.Contains("`r")
            $hasCRLF = $content.Contains("`r`n")
            
            $lineEndingCount = 0
            if ($hasLF -and -not $hasCRLF) { $lineEndingCount++ }
            if ($hasCR -and -not $hasCRLF) { $lineEndingCount++ }
            if ($hasCRLF) { $lineEndingCount++ }
            
            if ($lineEndingCount -gt 1) {
                $issues += "Mixed line endings detected"
            }
            
            # Check for suspicious characters
            if ($content -match '[\uFFFD\uFEFF]') {
                $issues += "Replacement characters or BOM in content"
            }
            
            # Check for very long lines (potential corruption)
            $lines = $content -split "`n"
            $maxLineLength = ($lines | Measure-Object -Property Length -Maximum).Maximum
            if ($maxLineLength -gt 10000) {
                $issues += "Extremely long line detected ($maxLineLength chars)"
            }
        }
        
        return [PSCustomObject]@{
            Encoding = $encoding
            BOM = $hasBOM
            Confidence = $confidence
            Issues = $issues
            Size = (Get-Item $FilePath).Length
        }
    }
    catch {
        return [PSCustomObject]@{
            Encoding = "ERROR"
            BOM = $false
            Confidence = "LOW"
            Issues = @("Error analyzing file: $_")
            Size = 0
        }
    }
}

# Function to find text files for analysis
function Find-TextFiles {
    try {
        # Text file extensions to analyze
        $textExtensions = @(
            '*.cs', '*.txt', '*.md', '*.json', '*.xml', '*.config', 
            '*.yaml', '*.yml', '*.ini', '*.log', '*.sql', '*.css', 
            '*.js', '*.ts', '*.html', '*.htm', '*.py', '*.cpp', 
            '*.h', '*.hpp', '*.java', '*.php', '*.rb', '*.go', 
            '*.rs', '*.swift', '*.kt', '*.scala', '*.ps1', '*.psm1', 
            '*.psd1', '*.bat', '*.cmd', '*.sh', '*.dockerfile'
        )
        
        $allFiles = @()
        
        foreach ($extension in $textExtensions) {
            try {
                $files = Get-ChildItem -Path $ProjectRoot -Recurse -Include $extension -ErrorAction SilentlyContinue | Where-Object {
                    $_.PSIsContainer -eq $false -and
                    $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy)[\\/]" -and
                    $_.FullName -notmatch "[\\/]\.git[\\/]" -and
                    $_.Length -lt 50MB  # Skip very large files
                }
                $allFiles += $files
            }
            catch {
                # Skip extensions that cause errors
                continue
            }
        }
        
        return $allFiles | Sort-Object -Unique
    }
    catch {
        Write-Host "⚠️  Error finding text files: $_" -ForegroundColor DarkYellow
        return @()
    }
}

# Function to categorize encoding issues
function Get-EncodingIssueSeverity {
    param($encodingResult, $fileExtension)
    
    $issues = $encodingResult.Issues
    $encoding = $encodingResult.Encoding
    
    # Critical issues
    if ($issues -match "Null bytes|Replacement characters|UTF-8 conversion mismatch") {
        return "CRITICAL"
    }
    
    # High severity for source code files
    if ($fileExtension -match '\.(cs|cpp|h|hpp|java|py|js|ts)$') {
        if ($encoding -eq "ANSI" -or $issues -match "Mixed line endings") {
            return "HIGH"
        }
        if ($encodingResult.BOM -and $fileExtension -eq '.cs') {
            return "HIGH"  # BOM in C# files can cause issues
        }
    }
    
    # Medium severity
    if ($issues -match "Mixed line endings|Extremely long line") {
        return "MEDIUM"
    }
    
    if ($encoding -eq "ANSI" -or $encoding -eq "UNKNOWN") {
        return "MEDIUM"
    }
    
    # Low severity
    if ($issues.Count -gt 0) {
        return "LOW"
    }
    
    return "NONE"
}

# Main script execution
Write-Host "`n📂 Scanning for text files..." -ForegroundColor DarkGray
$textFiles = Find-TextFiles

if ($textFiles.Count -eq 0) {
    Write-Host "❌ No text files found for analysis!" -ForegroundColor Red
    if ($IsInteractive -and -not $RunningFromScript) {
        Write-Host "`nPress ENTER to continue..." -ForegroundColor Gray -NoNewline
        Read-Host
    }
    return
}

Write-Host "📊 Found $($textFiles.Count) text files to analyze" -ForegroundColor Gray

# Analyze file encodings
Write-Host "`n🔍 Analyzing file encodings..." -ForegroundColor DarkCyan
$encodingResults = @()
$processedFiles = 0

foreach ($file in $textFiles) {
    $processedFiles++
    
    # Show progress every 25 files
    if ($processedFiles % 25 -eq 0) {
        $percent = [Math]::Round(($processedFiles / $textFiles.Count) * 100, 1)
        Write-Host "   📈 Progress: $processedFiles/$($textFiles.Count) files ($percent%)" -ForegroundColor DarkGray
    }
    
    $encodingResult = Get-FileEncoding -FilePath $file.FullName
    $severity = Get-EncodingIssueSeverity -encodingResult $encodingResult -fileExtension $file.Extension
    
    $analysis = [PSCustomObject]@{
        File = $file.FullName
        RelativePath = $file.FullName.Replace($ProjectRoot, "").TrimStart('\', '/')
        FileName = $file.Name
        Extension = $file.Extension
        Encoding = $encodingResult.Encoding
        BOM = $encodingResult.BOM
        Confidence = $encodingResult.Confidence
        Issues = $encodingResult.Issues
        Severity = $severity
        Size = $encodingResult.Size
    }
    
    $encodingResults += $analysis
}

Write-Host "✅ Analyzed $($encodingResults.Count) files" -ForegroundColor Gray

# Categorize results
$criticalIssues = $encodingResults | Where-Object { $_.Severity -eq "CRITICAL" }
$highIssues = $encodingResults | Where-Object { $_.Severity -eq "HIGH" }
$mediumIssues = $encodingResults | Where-Object { $_.Severity -eq "MEDIUM" }
$lowIssues = $encodingResults | Where-Object { $_.Severity -eq "LOW" }
$cleanFiles = $encodingResults | Where-Object { $_.Severity -eq "NONE" }

# Encoding distribution
$encodingDistribution = $encodingResults | Group-Object Encoding | Sort-Object Count -Descending
$bomFiles = $encodingResults | Where-Object { $_.BOM }
$mixedLineEndingFiles = $encodingResults | Where-Object { $_.Issues -match "Mixed line endings" }

Write-Host "`n=== FILE ENCODING ANALYSIS REPORT ===" -ForegroundColor DarkCyan
Write-Host "🕐 Analysis completed: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray

# Overall status
Write-Host "📊 Encoding Summary:" -ForegroundColor DarkCyan
Write-Host "   Files analyzed: $($encodingResults.Count)" -ForegroundColor Gray
Write-Host "   Critical issues: $($criticalIssues.Count)" -ForegroundColor $(if ($criticalIssues.Count -eq 0) { "Green" } else { "Red" })
Write-Host "   High priority: $($highIssues.Count)" -ForegroundColor $(if ($highIssues.Count -eq 0) { "Green" } else { "Red" })
Write-Host "   Medium priority: $($mediumIssues.Count)" -ForegroundColor $(if ($mediumIssues.Count -eq 0) { "Green" } else { "DarkYellow" })
Write-Host "   Low priority: $($lowIssues.Count)" -ForegroundColor $(if ($lowIssues.Count -eq 0) { "Green" } else { "DarkYellow" })
Write-Host "   Clean files: $($cleanFiles.Count)" -ForegroundColor Green

# Display encoding distribution
Write-Host "`n📋 Encoding Distribution:" -ForegroundColor DarkCyan
foreach ($encoding in $encodingDistribution | Select-Object -First 8) {
    $color = switch ($encoding.Name) {
        "UTF-8" { "Green" }
        "ASCII" { "Green" }
        "ANSI" { "DarkYellow" }
        "UNKNOWN" { "Red" }
        "ERROR" { "Red" }
        default { "Gray" }
    }
    Write-Host "   $($encoding.Name): $($encoding.Count) files" -ForegroundColor $color
}

if ($encodingDistribution.Count -gt 8) {
    Write-Host "   ... and $($encodingDistribution.Count - 8) more encoding types" -ForegroundColor DarkGray
}

# Display critical issues
if ($criticalIssues.Count -gt 0) {
    Write-Host "`n🚨 CRITICAL ENCODING ISSUES:" -ForegroundColor Red
    foreach ($issue in $criticalIssues | Select-Object -First 5) {
        Write-Host "   • $($issue.FileName) - $($issue.Encoding)" -ForegroundColor Red
        foreach ($problemDesc in $issue.Issues) {
            Write-Host "     └─ $problemDesc" -ForegroundColor DarkGray
        }
    }
    if ($criticalIssues.Count -gt 5) {
        Write-Host "   ... and $($criticalIssues.Count - 5) more critical issues" -ForegroundColor DarkGray
    }
}

# Display high priority issues - FIXED LINE 366
if ($highIssues.Count -gt 0) {
    Write-Host "`n⚠️  HIGH PRIORITY ISSUES:" -ForegroundColor DarkYellow
    foreach ($issue in $highIssues | Select-Object -First 5) {
        $bomText = if ($issue.BOM) { " (BOM)" } else { "" }
        Write-Host "   • $($issue.FileName) - $($issue.Encoding)$bomText" -ForegroundColor DarkYellow
        if ($issue.Issues.Count -gt 0) {
            Write-Host "     └─ $($issue.Issues -join ', ')" -ForegroundColor DarkGray
        }
    }
    if ($highIssues.Count -gt 5) {
        Write-Host "   ... and $($highIssues.Count - 5) more high priority issues" -ForegroundColor DarkGray
    }
}

# Special cases
if ($bomFiles.Count -gt 0) {
    Write-Host "`n📄 Files with BOM:" -ForegroundColor DarkCyan
    Write-Host "   $($bomFiles.Count) files have Byte Order Mark" -ForegroundColor Gray
    
    $bomByExtension = $bomFiles | Group-Object Extension
    foreach ($bomGroup in $bomByExtension | Select-Object -First 5) {
        Write-Host "   • $($bomGroup.Name): $($bomGroup.Count) files" -ForegroundColor Gray
    }
}

if ($mixedLineEndingFiles.Count -gt 0) {
    Write-Host "`n🔄 Mixed Line Endings:" -ForegroundColor DarkYellow
    Write-Host "   $($mixedLineEndingFiles.Count) files have inconsistent line endings" -ForegroundColor DarkYellow
}

# Quick recommendations
Write-Host "`n💡 Recommendations:" -ForegroundColor DarkCyan

if ($criticalIssues.Count -gt 0) {
    Write-Host "   🚨 IMMEDIATE: Fix $($criticalIssues.Count) critical encoding corruption" -ForegroundColor Red
    Write-Host "   • Check for file corruption or encoding conversion errors" -ForegroundColor Red
}

if ($highIssues.Count -gt 0) {
    Write-Host "   ⚠️  REVIEW: Address $($highIssues.Count) high priority encoding issues" -ForegroundColor DarkYellow
    Write-Host "   • Consider standardizing source code file encodings" -ForegroundColor DarkYellow
}

$ansiFiles = $encodingResults | Where-Object { $_.Encoding -eq "ANSI" }
if ($ansiFiles.Count -gt 0) {
    Write-Host "   📝 CONSIDER: Convert $($ansiFiles.Count) ANSI files to UTF-8" -ForegroundColor Gray
}

if ($bomFiles.Count -gt 0) {
    $csBomFiles = $bomFiles | Where-Object { $_.Extension -eq ".cs" }
    if ($csBomFiles.Count -gt 0) {
        Write-Host "   🔧 REVIEW: $($csBomFiles.Count) C# files have BOM (may cause compiler issues)" -ForegroundColor DarkYellow
    }
}

Write-Host "   • Use consistent UTF-8 encoding for source files" -ForegroundColor Gray
Write-Host "   • Standardize line endings (preferably LF or CRLF)" -ForegroundColor Gray

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

# Generate detailed file encoding report
Write-Host "`n📝 Generating detailed file encoding report..." -ForegroundColor DarkGray

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPath = Join-Path $reportsDir "FILE-ENCODING-REPORT_$timestamp.md"

$reportContent = @()
$reportContent += "# File Encoding Analysis Report"
$reportContent += ""
$reportContent += "**Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportContent += "**Files Analyzed**: $($encodingResults.Count)"
$reportContent += "**Critical Issues**: $($criticalIssues.Count)"
$reportContent += "**High Priority Issues**: $($highIssues.Count)"
$reportContent += "**Medium Priority Issues**: $($mediumIssues.Count)"
$reportContent += ""

# Executive Summary
$reportContent += "## Executive Summary"
$reportContent += ""

if ($criticalIssues.Count -eq 0 -and $highIssues.Count -eq 0) {
    $reportContent += "✅ **ENCODING HEALTH GOOD** - No critical encoding corruption detected."
    $reportContent += ""
    if ($mediumIssues.Count -eq 0) {
        $reportContent += "Perfect encoding consistency across all analyzed files."
    } else {
        $reportContent += "Minor encoding inconsistencies detected that may benefit from standardization."
    }
} else {
    $reportContent += "⚠️ **ENCODING ISSUES DETECTED** - Review and fix required."
    $reportContent += ""
    $reportContent += "File encoding inconsistencies and potential corruption found that may cause issues."
}

$reportContent += ""
$reportContent += "| Metric | Count | Status |"
$reportContent += "|--------|-------|--------|"
$reportContent += "| **Files Analyzed** | $($encodingResults.Count) | - |"
$reportContent += "| **Critical Issues** | $($criticalIssues.Count) | $(if ($criticalIssues.Count -eq 0) { "✅ None" } else { "🚨 Action Required" }) |"
$reportContent += "| **High Priority** | $($highIssues.Count) | $(if ($highIssues.Count -eq 0) { "✅ None" } else { "⚠️ Review Needed" }) |"
$reportContent += "| **Medium Priority** | $($mediumIssues.Count) | $(if ($mediumIssues.Count -eq 0) { "✅ None" } else { "📝 Consider Fixing" }) |"
$reportContent += "| **Clean Files** | $($cleanFiles.Count) | $(if ($cleanFiles.Count -eq $encodingResults.Count) { "🎉 All Clean" } else { "📊 Partial" }) |"
$reportContent += "| **Files with BOM** | $($bomFiles.Count) | $(if ($bomFiles.Count -eq 0) { "✅ None" } else { "📝 Review BOM Usage" }) |"
$reportContent += ""

# Encoding Distribution
$reportContent += "## Encoding Distribution"
$reportContent += ""
$reportContent += "| Encoding | Files | Percentage | Recommendation |"
$reportContent += "|----------|-------|------------|----------------|"

foreach ($encoding in $encodingDistribution) {
    $percentage = [Math]::Round(($encoding.Count / $encodingResults.Count) * 100, 1)
    $recommendation = switch ($encoding.Name) {
        "UTF-8" { "✅ Preferred" }
        "ASCII" { "✅ Compatible" }
        "ANSI" { "⚠️ Consider UTF-8" }
        "UNKNOWN" { "🚨 Investigate" }
        "ERROR" { "🚨 Fix Required" }
        "BINARY" { "📝 Skip Analysis" }
        default { "📝 Review" }
    }
    $reportContent += "| $($encoding.Name) | $($encoding.Count) | $percentage% | $recommendation |"
}

$reportContent += ""

# Detailed Issue Analysis
if ($criticalIssues.Count -gt 0 -or $highIssues.Count -gt 0) {
    $reportContent += "## Issues Requiring Attention"
    $reportContent += ""
    
    if ($criticalIssues.Count -gt 0) {
        $reportContent += "### 🚨 Critical Issues ($($criticalIssues.Count) files)"
        $reportContent += ""
        $reportContent += "These files have severe encoding corruption that must be fixed:"
        $reportContent += ""
        $reportContent += "| File | Encoding | Issues |"
        $reportContent += "|------|----------|--------|"
        
        foreach ($issue in $criticalIssues) {
            $issueText = $issue.Issues -join "; "
            $reportContent += "| `$($issue.RelativePath)` | $($issue.Encoding) | $issueText |"
        }
        $reportContent += ""
    }
    
    if ($highIssues.Count -gt 0) {
        $reportContent += "### ⚠️ High Priority Issues ($($highIssues.Count) files)"
        $reportContent += ""
        $reportContent += "These files have encoding issues that should be addressed:"
        $reportContent += ""
        $reportContent += "| File | Encoding | BOM | Issues |"
        $reportContent += "|------|----------|-----|--------|"
        
        foreach ($issue in $highIssues | Select-Object -First 20) {
            $issueText = if ($issue.Issues.Count -gt 0) { $issue.Issues -join "; " } else { "BOM or encoding inconsistency" }
            $bomIcon = if ($issue.BOM) { "✅" } else { "❌" }
            $reportContent += "| `$($issue.RelativePath)` | $($issue.Encoding) | $bomIcon | $issueText |"
        }
        
        if ($highIssues.Count -gt 20) {
            $reportContent += ""
            $reportContent += "*... and $($highIssues.Count - 20) more high priority issues*"
        }
        $reportContent += ""
    }
}

# File Type Analysis
$reportContent += "## File Type Analysis"
$reportContent += ""

$extensionStats = $encodingResults | Group-Object Extension | Sort-Object Count -Descending
$reportContent += "| Extension | Files | Most Common Encoding | Issues |"
$reportContent += "|-----------|-------|---------------------|--------|"

foreach ($extGroup in $extensionStats | Select-Object -First 15) {
    $mostCommonEncoding = ($extGroup.Group | Group-Object Encoding | Sort-Object Count -Descending | Select-Object -First 1).Name
    $issueCount = ($extGroup.Group | Where-Object { $_.Severity -ne "NONE" }).Count
    $issueStatus = if ($issueCount -eq 0) { "✅ None" } else { "$issueCount issues" }
    $reportContent += "| `$($extGroup.Name)` | $($extGroup.Count) | $mostCommonEncoding | $issueStatus |"
}

if ($extensionStats.Count -gt 15) {
    $reportContent += ""
    $reportContent += "*... and $($extensionStats.Count - 15) more file types*"
}

$reportContent += ""

# BOM Analysis
if ($bomFiles.Count -gt 0) {
    $reportContent += "## Byte Order Mark (BOM) Analysis"
    $reportContent += ""
    $reportContent += "Files containing BOM may cause issues in certain environments:"
    $reportContent += ""
    
    $bomByType = $bomFiles | Group-Object Extension | Sort-Object Count -Descending
    $reportContent += "| File Type | Count | Recommendation |"
    $reportContent += "|-----------|-------|----------------|"
    
    foreach ($bomGroup in $bomByType) {
        $recommendation = switch ($bomGroup.Name) {
            ".cs" { "⚠️ Remove BOM (may cause compiler issues)" }
            ".js" { "⚠️ Remove BOM (may cause runtime errors)" }
            ".css" { "⚠️ Remove BOM (may cause display issues)" }
            ".html" { "⚠️ Remove BOM (may cause rendering issues)" }
            ".xml" { "📝 BOM acceptable but not required" }
            ".txt" { "📝 BOM acceptable" }
            default { "📝 Review necessity" }
        }
        $reportContent += "| `$($bomGroup.Name)` | $($bomGroup.Count) | $recommendation |"
    }
    $reportContent += ""
}

# Recommendations
$reportContent += "## 🎯 Action Plan"
$reportContent += ""

if ($criticalIssues.Count -gt 0) {
    $reportContent += "### 🚨 IMMEDIATE ACTION REQUIRED"
    $reportContent += ""
    $reportContent += "**$($criticalIssues.Count) files with critical encoding corruption:**"
    $reportContent += ""
    $reportContent += "1. **Backup Files**: Create backups before making changes"
    $reportContent += "2. **Investigate Corruption**: Determine cause of encoding issues"
    $reportContent += "3. **Re-encode Files**: Convert to proper UTF-8 encoding"
    $reportContent += "4. **Validate Content**: Ensure file content is intact after conversion"
    $reportContent += ""
} elseif ($highIssues.Count -gt 0) {
    $reportContent += "### ⚠️ HIGH PRIORITY FIXES"
    $reportContent += ""
    $reportContent += "**$($highIssues.Count) files with significant encoding issues:**"
    $reportContent += ""
    $reportContent += "1. **Standardize Encoding**: Convert source files to UTF-8 without BOM"
    $reportContent += "2. **Fix Line Endings**: Standardize to LF (Unix) or CRLF (Windows)"
    $reportContent += "3. **Remove Problematic BOMs**: Especially from .cs, .js, .css files"
    $reportContent += "4. **Test After Changes**: Verify functionality after encoding fixes"
    $reportContent += ""
} else {
    $reportContent += "### ✅ MAINTENANCE MODE"
    $reportContent += ""
    $reportContent += "Excellent encoding health! Consider these optimizations:"
    $reportContent += ""
    $reportContent += "1. **Maintain Standards**: Keep using UTF-8 for new files"
    $reportContent += "2. **Editor Configuration**: Set UTF-8 as default in IDEs"
    $reportContent += "3. **Git Configuration**: Set consistent line ending handling"
    $reportContent += "4. **Regular Audits**: Run this analysis periodically"
}

# Best Practices
$reportContent += ""
$reportContent += "### 📋 Best Practices"
$reportContent += ""
$reportContent += "1. **UTF-8 Without BOM**: Use for most source code files"
$reportContent += "2. **Consistent Line Endings**: Choose LF or CRLF and stick to it"
$reportContent += "3. **Editor Settings**: Configure your IDE to:"
$reportContent += "   - Default to UTF-8 encoding"
$reportContent += "   - Show line ending types"
$reportContent += "   - Highlight encoding issues"
$reportContent += ""
$reportContent += "4. **Git Configuration**: Set up .gitattributes for line ending handling"
$reportContent += "   ```"
$reportContent += "   # text=auto"  # FIXED LINE 638 - Changed * to # to avoid multiplication operator
$reportContent += "   *.cs text eol=crlf"
$reportContent += "   *.md text eol=lf"
$reportContent += "   ```"

# Technical Details
$reportContent += ""
$reportContent += "## Technical Analysis Details"
$reportContent += ""
$reportContent += "### Detection Methods"
$reportContent += ""
$reportContent += "- **BOM Detection**: Analyzes file headers for byte order marks"
$reportContent += "- **Heuristic Analysis**: Tests UTF-8 validity and character patterns"
$reportContent += "- **Content Validation**: Checks for null bytes and suspicious characters"
$reportContent += "- **Line Ending Analysis**: Detects CR, LF, and CRLF patterns"
$reportContent += ""
$reportContent += "### File Coverage"
$reportContent += ""
$reportContent += "- **Text Files**: Source code, documentation, configuration"
$reportContent += "- **Size Limit**: Files under 50MB (prevents memory issues)"
$reportContent += "- **Exclusions**: ForCopilot/, Scripts/, Legacy/, .git/"
$reportContent += "- **Binary Files**: Detected and skipped from text analysis"

# Footer
$reportContent += ""
$reportContent += "---"
$reportContent += ""
$reportContent += "**File Encoding Standards**: UTF-8 preferred for cross-platform compatibility"
$reportContent += ""
$reportContent += "*Generated by MixerThreholdMod DevOps Suite - File Encoding Report Generator*"

try {
    $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
    $saveSuccess = $true
}
catch {
    Write-Host "⚠️ Error saving detailed report: $_" -ForegroundColor DarkYellow
    $saveSuccess = $false
}

Write-Host "`n🚀 File encoding analysis complete!" -ForegroundColor Green

# OUTPUT PATH AT THE END for easy finding
if ($saveSuccess) {
    Write-Host "`n📄 DETAILED REPORT SAVED:" -ForegroundColor Green
    Write-Host "   Location: $reportPath" -ForegroundColor Cyan
    Write-Host "   Size: $([Math]::Round((Get-Item $reportPath).Length / 1KB, 1)) KB" -ForegroundColor Gray
} else {
    Write-Host "`n⚠️ No detailed report generated" -ForegroundColor DarkYellow
}

# INTERACTIVE WORKFLOW LOOP (only when running standalone)
if ($IsInteractive -and -not $RunningFromScript) {
    do {
        Write-Host "`n🎯 What would you like to do next?" -ForegroundColor DarkCyan
        Write-Host "   D - Display report in console" -ForegroundColor Green
        Write-Host "   R - Re-run file encoding analysis" -ForegroundColor DarkYellow
        Write-Host "   X - Exit to DevOps menu" -ForegroundColor Gray
        
        $choice = Read-Host "`nEnter choice (D/R/X)"
        $choice = $choice.ToUpper()
        
        switch ($choice) {
            'D' {
                if ($saveSuccess) {
                    Write-Host "`n📋 DISPLAYING FILE ENCODING REPORT:" -ForegroundColor DarkCyan
                    Write-Host "===================================" -ForegroundColor DarkCyan
                    try {
                        $reportDisplay = Get-Content -Path $reportPath -Raw
                        Write-Host $reportDisplay -ForegroundColor White
                        Write-Host "`n===================================" -ForegroundColor DarkCyan
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
                Write-Host "`n🔄 RE-RUNNING FILE ENCODING ANALYSIS..." -ForegroundColor DarkYellow
                Write-Host "======================================" -ForegroundColor DarkYellow
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