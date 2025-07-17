# MixerThreholdMod DevOps Tool: Conflict Markers Report Generator (NON-INTERACTIVE)
# Scans the project for merge conflict markers (<<<<<<<, =======, >>>>>>>)
# Distinguishes between REAL merge conflicts and false positives
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

Write-Host "🕐 Conflict markers scan started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "Scanning project root for conflict markers: $ProjectRoot" -ForegroundColor DarkCyan
Write-Host "🚀 NON-INTERACTIVE VERSION - Compatible with automation" -ForegroundColor Green
Write-Host "Excluding: ForCopilot, Scripts, and Legacy directories" -ForegroundColor DarkGray

# Find all text/code files with CORRECTED exclusions
$files = Get-ChildItem -Path $ProjectRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Extension -match "^\.(cs|txt|md|json|xml|config|yaml|yml|ini|cpp|h|js|ts|py|java|csproj|sln|ps1|psm1|psd1|bat|cmd|sh)$" -and
    $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy)[\\/]" -and
    $_.FullName -notmatch "[\\/]\.git[\\/]"
}

Write-Host "📊 Files to scan: $($files.Count)" -ForegroundColor Gray

if ($files.Count -eq 0) {
    Write-Host "⚠️  No files found for scanning" -ForegroundColor DarkYellow
    if ($IsInteractive -and -not $RunningFromScript) {
        Write-Host "`nPress ENTER to continue..." -ForegroundColor Gray -NoNewline
        Read-Host
    }
    return
}

# Function to check if a file has a complete merge conflict pattern
function Test-MergeConflictPattern {
    param($lines, $startIndex)
    
    # Look for complete conflict pattern within reasonable distance
    $foundEquals = $false
    $foundEnd = $false
    
    for ($i = $startIndex + 1; $i -lt $lines.Count -and $i -lt ($startIndex + 50); $i++) {
        if ($lines[$i] -match "^=======$") {
            $foundEquals = $true
        }
        elseif ($foundEquals -and $lines[$i] -match "^>>>>>>>\s+") {
            $foundEnd = $true
            return $true
        }
    }
    return $false
}

# Function to analyze conflict context
function Get-ConflictContext {
    param($line)
    
    # Check for common false positive patterns
    $isInString = $line -match '".*(<<<<<<<|=======|>>>>>>>).*"' -or $line -match "'.*(<<<<<<<|=======|>>>>>>>).*'"
    $isInComment = $line -match "//.*(<<<<<<<|=======|>>>>>>>)" -or $line -match "/\*.*(<<<<<<<|=======|>>>>>>>)"
    $isInRegex = $line -match "regex|pattern|match" -and $line -match "(<<<<<<<|=======|>>>>>>>)"
    $isInDocumentation = $line -match "###+|```|---" -and $line -match "(<<<<<<<|=======|>>>>>>>)"
    
    if ($isInString) { return "STRING_LITERAL" }
    if ($isInComment) { return "COMMENT" }
    if ($isInRegex) { return "REGEX_PATTERN" }
    if ($isInDocumentation) { return "DOCUMENTATION" }
    
    return "CODE_CONTEXT"
}

Write-Host "`n📂 Scanning for conflict markers..." -ForegroundColor DarkGray

$realConflicts = @()
$falsePositives = @()
$processedFiles = 0

foreach ($file in $files) {
    $processedFiles++
    
    # Show progress every 50 files
    if ($processedFiles % 50 -eq 0) {
        $percent = [Math]::Round(($processedFiles / $files.Count) * 100, 1)
        Write-Host "   📈 Progress: $processedFiles/$($files.Count) files ($percent%)" -ForegroundColor DarkGray
    }
    
    try {
        $lines = Get-Content -Path $file.FullName -ErrorAction SilentlyContinue
        if (-not $lines) { continue }
        
        for ($lineNum = 0; $lineNum -lt $lines.Count; $lineNum++) {
            $line = $lines[$lineNum]
            
            # Check for conflict start marker
            if ($line -match "^<<<<<<<\s+") {
                if (Test-MergeConflictPattern -lines $lines -startIndex $lineNum) {
                    $realConflicts += [PSCustomObject]@{
                        File = $file.FullName
                        RelativePath = $file.FullName.Replace($ProjectRoot, "").TrimStart('\', '/')
                        FileName = $file.Name
                        LineNumber = $lineNum + 1
                        MarkerType = "CONFLICT_START"
                        Line = $line.Substring(0, [Math]::Min($line.Length, 100))
                        Severity = "CRITICAL"
                    }
                }
            }
            # Check for standalone markers (potential false positives or orphaned markers)
            elseif ($line -match "(=======|<<<<<<<|>>>>>>>)") {
                $context = Get-ConflictContext -line $line
                
                $severity = switch ($context) {
                    "STRING_LITERAL" { "FALSE_POSITIVE" }
                    "COMMENT" { "FALSE_POSITIVE" }
                    "REGEX_PATTERN" { "FALSE_POSITIVE" }
                    "DOCUMENTATION" { "FALSE_POSITIVE" }
                    default { "SUSPICIOUS" }
                }
                
                $falsePositives += [PSCustomObject]@{
                    File = $file.FullName
                    RelativePath = $file.FullName.Replace($ProjectRoot, "").TrimStart('\', '/')
                    FileName = $file.Name
                    LineNumber = $lineNum + 1
                    MarkerType = if ($line -match "<<<<<<<") { "STANDALONE_START" } 
                                elseif ($line -match "=======") { "STANDALONE_SEPARATOR" }
                                else { "STANDALONE_END" }
                    Context = $context
                    Line = $line.Substring(0, [Math]::Min($line.Length, 100))
                    Severity = $severity
                }
            }
        }
    }
    catch {
        Write-Host "   ⚠️  Error processing $($file.Name): $_" -ForegroundColor DarkYellow
        continue
    }
}

Write-Host "`n=== CONFLICT MARKERS ANALYSIS REPORT ===" -ForegroundColor DarkCyan
Write-Host "🕐 Analysis completed: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "📊 Files scanned: $($files.Count)" -ForegroundColor Gray
Write-Host "🚨 Real conflicts found: $($realConflicts.Count)" -ForegroundColor $(if ($realConflicts.Count -eq 0) { "Green" } else { "Red" })
Write-Host "⚠️  Suspicious markers found: $($falsePositives.Count)" -ForegroundColor $(if ($falsePositives.Count -eq 0) { "Green" } else { "DarkYellow" })

if ($realConflicts.Count -eq 0 -and $falsePositives.Count -eq 0) {
    Write-Host "`n✅ EXCELLENT! No conflict markers found in project." -ForegroundColor Green
} else {
    if ($realConflicts.Count -gt 0) {
        Write-Host "`n🚨 REAL MERGE CONFLICTS DETECTED:" -ForegroundColor Red
        Write-Host "   These require immediate attention!" -ForegroundColor Red
        
        # Show top conflicts (limited for automation)
        $topConflicts = $realConflicts | Select-Object -First 10
        foreach ($conflict in $topConflicts) {
            Write-Host "   • $($conflict.FileName) (line $($conflict.LineNumber))" -ForegroundColor Red
            Write-Host "     $($conflict.Line)" -ForegroundColor DarkGray
        }
        
        if ($realConflicts.Count -gt 10) {
            Write-Host "   ... and $($realConflicts.Count - 10) more conflicts" -ForegroundColor DarkGray
        }
        
        # Show affected files
        $conflictFiles = $realConflicts | Select-Object -ExpandProperty FileName -Unique
        Write-Host "`n📁 Files with real conflicts:" -ForegroundColor Red
        $conflictFiles | Select-Object -First 5 | ForEach-Object { 
            Write-Host "   • $_" -ForegroundColor Red 
        }
        if ($conflictFiles.Count -gt 5) {
            Write-Host "   ... and $($conflictFiles.Count - 5) more files" -ForegroundColor DarkGray
        }
    }
    
    if ($falsePositives.Count -gt 0) {
        Write-Host "`n⚠️  SUSPICIOUS MARKERS:" -ForegroundColor DarkYellow
        
        $suspiciousMarkers = $falsePositives | Where-Object { $_.Severity -eq "SUSPICIOUS" }
        $knownFalsePositives = $falsePositives | Where-Object { $_.Severity -eq "FALSE_POSITIVE" }
        
        if ($suspiciousMarkers.Count -gt 0) {
            Write-Host "   🔍 Require manual review ($($suspiciousMarkers.Count) items):" -ForegroundColor DarkYellow
            $suspiciousMarkers | Select-Object -First 5 | ForEach-Object {
                Write-Host "   • $($_.FileName) (line $($_.LineNumber)) - $($_.MarkerType)" -ForegroundColor DarkYellow
            }
            if ($suspiciousMarkers.Count -gt 5) {
                Write-Host "   ... and $($suspiciousMarkers.Count - 5) more suspicious markers" -ForegroundColor DarkGray
            }
        }
        
        if ($knownFalsePositives.Count -gt 0) {
            Write-Host "   ✅ Known false positives ($($knownFalsePositives.Count) items):" -ForegroundColor Green
            Write-Host "      These appear to be separators or content, not merge conflicts" -ForegroundColor DarkGray
        }
    }
}

# Quick recommendations
Write-Host "`n💡 Recommendations:" -ForegroundColor DarkCyan

if ($realConflicts.Count -gt 0) {
    Write-Host "   🚨 IMMEDIATE ACTION: $($realConflicts.Count) real merge conflicts found!" -ForegroundColor Red
    Write-Host "   • Run 'git status' to see conflicted files" -ForegroundColor Red
    Write-Host "   • Resolve conflicts manually and commit changes" -ForegroundColor Red
    Write-Host "   • Use git mergetool for complex conflicts" -ForegroundColor Red
} else {
    Write-Host "   ✅ No real merge conflicts detected" -ForegroundColor Green
}

if ($falsePositives.Count -gt 0) {
    $suspiciousCount = ($falsePositives | Where-Object { $_.Severity -eq "SUSPICIOUS" }).Count
    if ($suspiciousCount -gt 0) {
        Write-Host "   ⚠️  Review $suspiciousCount suspicious markers manually" -ForegroundColor DarkYellow
    }
}

Write-Host "   • Run this scan after git merges and pulls" -ForegroundColor Gray
Write-Host "   • Configure git merge tools for easier conflict resolution" -ForegroundColor Gray

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

# Generate detailed conflict markers report
Write-Host "`n📝 Generating detailed conflict markers report..." -ForegroundColor DarkGray

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPath = Join-Path $reportsDir "CONFLICT-MARKERS-REPORT_$timestamp.md"

$reportContent = @()
$reportContent += "# Conflict Markers Analysis Report"
$reportContent += ""
$reportContent += "**Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportContent += "**Files Scanned**: $($files.Count)"
$reportContent += "**Real Conflicts**: $($realConflicts.Count)"
$reportContent += "**Suspicious Markers**: $($falsePositives.Count)"
$reportContent += ""

# Executive Summary
$reportContent += "## Executive Summary"
$reportContent += ""

if ($realConflicts.Count -eq 0 -and $falsePositives.Count -eq 0) {
    $reportContent += "🎉 **EXCELLENT!** No conflict markers detected in the codebase."
    $reportContent += ""
    $reportContent += "Your repository is free of merge conflicts and suspicious markers."
} elseif ($realConflicts.Count -eq 0) {
    $reportContent += "✅ **CLEAN REPOSITORY** - No real merge conflicts detected."
    $reportContent += ""
    $reportContent += "Some suspicious markers were found but they appear to be false positives."
} else {
    $reportContent += "🚨 **MERGE CONFLICTS DETECTED** - Immediate action required."
    $reportContent += ""
    $reportContent += "**Critical**: $($realConflicts.Count) real merge conflicts must be resolved before continuing development."
}

$reportContent += ""
$reportContent += "| Metric | Count | Status |"
$reportContent += "|--------|-------|--------|"
$reportContent += "| **Files Scanned** | $($files.Count) | - |"
$reportContent += "| **Real Conflicts** | $($realConflicts.Count) | $(if ($realConflicts.Count -eq 0) { "✅ None" } else { "🚨 Found" }) |"
$reportContent += "| **Suspicious Markers** | $($falsePositives.Count) | $(if ($falsePositives.Count -eq 0) { "✅ None" } else { "⚠️ Found" }) |"

$suspiciousCount = ($falsePositives | Where-Object { $_.Severity -eq "SUSPICIOUS" }).Count
$falsePositiveCount = ($falsePositives | Where-Object { $_.Severity -eq "FALSE_POSITIVE" }).Count

$reportContent += "| **Require Review** | $suspiciousCount | $(if ($suspiciousCount -eq 0) { "✅ None" } else { "⚠️ Review Needed" }) |"
$reportContent += "| **False Positives** | $falsePositiveCount | $(if ($falsePositiveCount -eq 0) { "✅ None" } else { "📝 Identified" }) |"
$reportContent += ""

# Real Conflicts Analysis
if ($realConflicts.Count -gt 0) {
    $reportContent += "## 🚨 Real Merge Conflicts"
    $reportContent += ""
    $reportContent += "The following files contain actual merge conflict markers that must be resolved:"
    $reportContent += ""
    
    # Group by file
    $conflictsByFile = $realConflicts | Group-Object RelativePath | Sort-Object Name
    
    foreach ($fileGroup in $conflictsByFile) {
        $reportContent += "### $($fileGroup.Name)"
        $reportContent += ""
        $reportContent += "**Conflicts**: $($fileGroup.Count)"
        $reportContent += ""
        $reportContent += "| Line | Type | Content |"
        $reportContent += "|------|------|---------|"
        
        foreach ($conflict in $fileGroup.Group | Sort-Object LineNumber) {
            $reportContent += "| $($conflict.LineNumber) | $($conflict.MarkerType) | ``$($conflict.Line)`` |"
        }
        $reportContent += ""
    }
    
    $reportContent += "### Resolution Steps"
    $reportContent += ""
    $reportContent += "1. **Check Git Status**: Run git status to see all conflicted files"
    $reportContent += "2. **Open Each File**: Review conflict markers and choose correct content"
    $reportContent += "3. **Remove Markers**: Delete conflict markers and resolve differences"
    $reportContent += "4. **Test Changes**: Ensure code compiles and works correctly"
    $reportContent += "5. **Stage Files**: Add resolved files to git staging area"
    $reportContent += "6. **Commit Resolution**: Commit the merge conflict resolution"
    $reportContent += ""
}

# Suspicious Markers Analysis
if ($falsePositives.Count -gt 0) {
    $reportContent += "## ⚠️ Suspicious Markers Analysis"
    $reportContent += ""
    
    $suspiciousMarkers = $falsePositives | Where-Object { $_.Severity -eq "SUSPICIOUS" }
    $knownFalsePositives = $falsePositives | Where-Object { $_.Severity -eq "FALSE_POSITIVE" }
    
    if ($suspiciousMarkers.Count -gt 0) {
        $reportContent += "### Markers Requiring Manual Review"
        $reportContent += ""
        $reportContent += "These markers were found outside of typical false positive contexts:"
        $reportContent += ""
        $reportContent += "| File | Line | Type | Content |"
        $reportContent += "|------|------|------|---------|"
        
        foreach ($marker in $suspiciousMarkers | Sort-Object RelativePath, LineNumber) {
            $reportContent += "| ``$($marker.RelativePath)`` | $($marker.LineNumber) | $($marker.MarkerType) | ``$($marker.Line)`` |"
        }
        $reportContent += ""
        
        $reportContent += "**Action Required**: Manually verify these are not orphaned conflict markers."
        $reportContent += ""
    }
    
    if ($knownFalsePositives.Count -gt 0) {
        $reportContent += "### Identified False Positives"
        $reportContent += ""
        $reportContent += "These markers are likely intentional content (strings, comments, documentation):"
        $reportContent += ""
        
        # Group by context type
        $contextGroups = $knownFalsePositives | Group-Object Context
        
        foreach ($contextGroup in $contextGroups) {
            $reportContent += "#### $($contextGroup.Name) ($($contextGroup.Count) items)"
            $reportContent += ""
            
            foreach ($marker in $contextGroup.Group | Select-Object -First 10) {
                $reportContent += "- **$($marker.FileName)** (Line $($marker.LineNumber)): ``$($marker.Line)``"
            }
            
            if ($contextGroup.Group.Count -gt 10) {
                $reportContent += "- ... and $($contextGroup.Group.Count - 10) more items"
            }
            $reportContent += ""
        }
    }
}

# Scan Coverage
$reportContent += "## Scan Coverage Details"
$reportContent += ""
$reportContent += "### File Types Scanned"
$reportContent += ""

$filesByExtension = $files | Group-Object Extension | Sort-Object Count -Descending
$reportContent += "| Extension | Count | Description |"
$reportContent += "|-----------|-------|-------------|"

foreach ($extGroup in $filesByExtension) {
    $description = switch ($extGroup.Name) {
        ".cs" { "C# source files" }
        ".md" { "Markdown documentation" }
        ".json" { "JSON configuration files" }
        ".xml" { "XML configuration files" }
        ".ps1" { "PowerShell scripts" }
        ".txt" { "Text files" }
        ".config" { "Configuration files" }
        default { "Other files" }
    }
    $reportContent += "| ``$($extGroup.Name)`` | $($extGroup.Count) | $description |"
}

$reportContent += ""
$reportContent += "### Directory Exclusions"
$reportContent += ""
$reportContent += "The following directories were excluded from scanning:"
$reportContent += "- ForCopilot - GitHub Copilot instruction files"
$reportContent += "- Scripts - DevOps and build scripts"
$reportContent += "- Legacy - Deprecated code"
$reportContent += "- .git - Git repository metadata"

# Best Practices
$reportContent += ""
$reportContent += "## 🎯 Best Practices"
$reportContent += ""
$reportContent += "### Preventing Merge Conflicts"
$reportContent += ""
$reportContent += "1. **Frequent Pulls**: Pull from main branch regularly"
$reportContent += "2. **Small Commits**: Make focused, atomic commits"
$reportContent += "3. **Communication**: Coordinate changes to shared files"
$reportContent += "4. **Feature Branches**: Use separate branches for different features"
$reportContent += ""
$reportContent += "### Conflict Resolution Tools"
$reportContent += ""
$reportContent += "1. **Git Mergetool**: Configure a visual merge tool"
$reportContent += "2. **IDE Integration**: Use Visual Studio merge conflict resolution"
$reportContent += "3. **Manual Resolution**: For simple conflicts, edit files directly"
$reportContent += ""
$reportContent += "### Regular Scanning"
$reportContent += ""
$reportContent += "Run this analysis:"
$reportContent += "- After every merge or pull operation"
$reportContent += "- Before pushing changes to shared branches"
$reportContent += "- As part of CI/CD pipeline validation"

# Technical Details
$reportContent += ""
$reportContent += "## Technical Analysis Details"
$reportContent += ""
$reportContent += "### Detection Patterns"
$reportContent += ""
$reportContent += "This analysis uses the following detection patterns:"
$reportContent += ""
$reportContent += "- **Real Conflicts**: Complete merge conflict pattern sequence"
$reportContent += "- **Orphaned Markers**: Standalone markers not in complete pattern"
$reportContent += "- **Context Analysis**: Identifies markers in strings, comments, etc."
$reportContent += ""
$reportContent += "### Classification Logic"
$reportContent += ""
$reportContent += "- **CRITICAL**: Complete merge conflict patterns"
$reportContent += "- **SUSPICIOUS**: Standalone markers in code context"
$reportContent += "- **FALSE_POSITIVE**: Markers in strings, comments, or documentation"

# Footer
$reportContent += ""
$reportContent += "---"
$reportContent += ""
$reportContent += "**Git Commands**: git status, git mergetool, git add, git commit"
$reportContent += ""
$reportContent += "*Generated by MixerThreholdMod DevOps Suite - Conflict Markers Scanner*"

try {
    $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
    $saveSuccess = $true
}
catch {
    Write-Host "⚠️ Error saving detailed report: $_" -ForegroundColor DarkYellow
    $saveSuccess = $false
}

Write-Host "`n🚀 Conflict markers analysis complete!" -ForegroundColor Green

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
        Write-Host "   R - Re-run conflict markers analysis" -ForegroundColor DarkYellow
        Write-Host "   X - Exit to DevOps menu" -ForegroundColor Gray
        
        $choice = Read-Host "`nEnter choice (D/R/X)"
        $choice = $choice.ToUpper()
        
        switch ($choice) {
            'D' {
                if ($saveSuccess) {
                    Write-Host "`n📋 DISPLAYING CONFLICT MARKERS REPORT:" -ForegroundColor DarkCyan
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
                Write-Host "`n🔄 RE-RUNNING CONFLICT MARKERS ANALYSIS..." -ForegroundColor DarkYellow
                Write-Host "=========================================" -ForegroundColor DarkYellow
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