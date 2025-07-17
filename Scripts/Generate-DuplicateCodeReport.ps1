# MixerThreholdMod DevOps Tool: Duplicate Code Detector (NON-INTERACTIVE)
# Detects copy-pasted code blocks across C# files
# Helps identify code that should be refactored into shared methods
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

Write-Host "🕐 Duplicate analysis started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "Scanning for duplicate code in: $ProjectRoot" -ForegroundColor DarkCyan
Write-Host "🚀 NON-INTERACTIVE VERSION - Compatible with automation" -ForegroundColor Green
Write-Host "Excluding: ForCopilot, Scripts, and Legacy directories" -ForegroundColor DarkGray

# Find all C# files with CORRECTED exclusions
$files = Get-ChildItem -Path $ProjectRoot -Recurse -Include *.cs -ErrorAction SilentlyContinue | Where-Object {
    $_.PSIsContainer -eq $false -and
    $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy)[\\/]" -and
    $_.FullName -notmatch "[\\/]\.git[\\/]"
}

Write-Host "📊 Files to analyze: $($files.Count)" -ForegroundColor Gray

if ($files.Count -eq 0) {
    Write-Host "❌ No C# files found for analysis!" -ForegroundColor Red
    if ($IsInteractive -and -not $RunningFromScript) {
        Write-Host "`nPress ENTER to continue..." -ForegroundColor Gray -NoNewline
        Read-Host
    }
    return
}

# Function to normalize code for comparison
function Get-NormalizedCode {
    param($code)
    
    # Remove comments and normalize whitespace
    $code = $code -replace '//.*$', '' -replace '/\*[\s\S]*?\*/', ''
    $code = $code -replace '\s+', ' '
    $code = $code.Trim()
    # Use [Environment]::NewLine instead of backtick-n for PowerShell 5.1 compatibility
    $code = ($code -split [Environment]::NewLine | Where-Object { $_.Trim() -ne "" }) -join [Environment]::NewLine
    
    return $code
}

# Function to extract code blocks (optimized for speed)
function Get-CodeBlocks {
    param($filePath)
    
    try {
        $content = Get-Content -Path $filePath -Raw -ErrorAction Stop
        if (-not $content -or $content.Length -lt 300) { return @() }
        
        $blocks = @()
        
        # Extract method bodies with simplified pattern
        $methodPattern = '(public|private|protected|internal)\s+(?:static\s+)?(?:async\s+)?[\w<>\[\]]+\s+(\w+)\s*\([^)]*\)\s*\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}'
        $methodMatches = [regex]::Matches($content, $methodPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        
        foreach ($match in $methodMatches) {
            $methodName = $match.Groups[2].Value
            $methodBody = $match.Groups[3].Value
            
            # Skip very small methods
            if ($methodBody.Length -lt 100) { continue }
            
            $normalizedCode = Get-NormalizedCode -code $methodBody
            $lineNumber = ($content.Substring(0, $match.Index) -split [Environment]::NewLine).Count
            
            # FIXED: Replace Join-String with PowerShell 5.1 compatible approach
            $hashBytes = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($normalizedCode))
            $hash = -join ($hashBytes | ForEach-Object { $_.ToString("x2") })
            
            $blocks += [PSCustomObject]@{
                File = $filePath
                Type = "Method"
                Name = $methodName
                Code = $normalizedCode
                OriginalCode = $methodBody
                LineNumber = $lineNumber
                Length = $methodBody.Length
                Hash = $hash
            }
        }
        
        return $blocks
    }
    catch {
        Write-Host "⚠️  Error processing $(Split-Path $filePath -Leaf): $($_.Exception.Message)" -ForegroundColor DarkYellow
        return @()
    }
}

# Analyze all files with progress
Write-Host "`n🔍 Analyzing code blocks..." -ForegroundColor DarkCyan
$allBlocks = @()
$processedFiles = 0
$totalFiles = $files.Count

foreach ($file in $files) {
    $processedFiles++
    
    # Show progress every 20 files
    if ($processedFiles % 20 -eq 0 -or $processedFiles -eq 1 -or $processedFiles -eq $totalFiles) {
        $percent = [Math]::Round(($processedFiles / $totalFiles) * 100, 1)
        Write-Host "   📈 Progress: $processedFiles/$totalFiles files ($percent%)" -ForegroundColor DarkGray
    }
    
    $blocks = Get-CodeBlocks -filePath $file.FullName
    $allBlocks += $blocks
}

Write-Host "`n=== DUPLICATE CODE ANALYSIS REPORT ===" -ForegroundColor DarkCyan
Write-Host "🕐 Analysis completed: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "📊 Total code blocks analyzed: $($allBlocks.Count)" -ForegroundColor Gray

# Find duplicates by hash
$duplicateGroups = $allBlocks | Group-Object -Property Hash | Where-Object { $_.Count -gt 1 }

Write-Host "🔄 Duplicate code groups found: $($duplicateGroups.Count)" -ForegroundColor $(if ($duplicateGroups.Count -gt 0) { "DarkYellow" } else { "Green" })

if ($duplicateGroups.Count -eq 0) {
    Write-Host "`n✅ No significant duplicate code blocks detected!" -ForegroundColor Green
} else {
    # Calculate statistics using PowerShell 5.1 safe method
    $totalDuplicateLines = 0
    $duplicateGroups | ForEach-Object {
        $lineCount = ($_.Group[0].OriginalCode -split [Environment]::NewLine).Count
        $totalDuplicateLines += $lineCount * ($_.Count - 1)
    }
    
    Write-Host "📏 Estimated duplicate lines: $totalDuplicateLines" -ForegroundColor Red
    
    # Sort by impact (size * occurrences)
    $sortedGroups = $duplicateGroups | ForEach-Object {
        $group = $_
        $impact = $group.Group[0].Length * ($group.Count - 1)
        [PSCustomObject]@{
            Group = $group
            Impact = $impact
            Occurrences = $group.Count
            CodeLength = $group.Group[0].Length
        }
    } | Sort-Object -Property Impact -Descending
    
    # Display top 5 duplicates (reduced for automation)
    Write-Host "`n🔄 Top 5 Duplicate Code Blocks (by impact):" -ForegroundColor DarkCyan
    
    $topDuplicates = $sortedGroups | Select-Object -First 5
    $duplicateNumber = 1
    
    foreach ($duplicate in $topDuplicates) {
        $group = $duplicate.Group
        $firstBlock = $group.Group[0]
        
        Write-Host "`n━━━ Duplicate #$duplicateNumber ━━━" -ForegroundColor DarkYellow
        Write-Host "Type: $($firstBlock.Type), Occurrences: $($duplicate.Occurrences), Size: $($duplicate.CodeLength) chars" -ForegroundColor Gray
        Write-Host "Found in:" -ForegroundColor Gray
        
        foreach ($block in $group.Group | Select-Object -First 3) {  # Limit to first 3
            $fileName = [System.IO.Path]::GetFileName($block.File)
            Write-Host "  • $fileName - $($block.Name) (line $($block.LineNumber))" -ForegroundColor DarkYellow
        }
        
        if ($group.Group.Count -gt 3) {
            Write-Host "  ... ($($group.Group.Count - 3) more occurrences)" -ForegroundColor DarkGray
        }
        
        $duplicateNumber++
    }
    
    if ($sortedGroups.Count -gt 5) {
        $remaining = $sortedGroups.Count - 5
        Write-Host "`n... ($remaining more duplicate groups not shown)" -ForegroundColor DarkGray
    }
    
    # Quick recommendations
    Write-Host "`n💡 Recommendations:" -ForegroundColor DarkCyan
    if ($totalDuplicateLines -gt 500) {
        Write-Host "   🚨 HIGH DUPLICATION: Over $totalDuplicateLines lines of duplicate code!" -ForegroundColor Red
        Write-Host "   • Immediate refactoring recommended" -ForegroundColor Red
    } else {
        Write-Host "   • Extract duplicate methods into shared utility classes" -ForegroundColor Gray
        Write-Host "   • Consider using inheritance or composition patterns" -ForegroundColor Gray
    }
}

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

# Generate detailed duplicate code report using PowerShell 5.1 safe approach
Write-Host "`n📝 Generating detailed duplicate code report..." -ForegroundColor DarkGray

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPath = Join-Path $reportsDir "DUPLICATE-CODE-REPORT_$timestamp.md"

# Build report using separate variables for PowerShell 5.1 compatibility
$reportTitle = "# Duplicate Code Analysis Report"
$reportGenerated = "**Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportFilesAnalyzed = "**Files Analyzed**: $($files.Count)"
$reportBlocksAnalyzed = "**Code Blocks Analyzed**: $($allBlocks.Count)"
$reportDuplicateGroups = "**Duplicate Groups Found**: $($duplicateGroups.Count)"

$reportContent = @()
$reportContent += $reportTitle
$reportContent += ""
$reportContent += $reportGenerated
$reportContent += $reportFilesAnalyzed
$reportContent += $reportBlocksAnalyzed
$reportContent += $reportDuplicateGroups
$reportContent += ""

# Executive Summary
$reportContent += "## Executive Summary"
$reportContent += ""

if ($duplicateGroups.Count -eq 0) {
    $reportContent += "🎉 **EXCELLENT!** No significant duplicate code blocks detected."
    $reportContent += ""
    $reportContent += "Your codebase demonstrates:"
    $reportContent += "- Well-structured code with minimal duplication"
    $reportContent += "- Good use of shared utilities and common patterns"
    $reportContent += "- Effective code reuse strategies"
} else {
    $reportContent += "**Duplication Analysis**: $($duplicateGroups.Count) duplicate code groups found"
    $reportContent += "**Estimated Duplicate Lines**: $totalDuplicateLines"
    $reportContent += ""
    
    # Impact assessment
    if ($totalDuplicateLines -gt 1000) {
        $reportContent += "🚨 **HIGH IMPACT**: Over $totalDuplicateLines lines of duplicate code detected."
        $reportContent += "**Recommendation**: Immediate refactoring recommended to improve maintainability."
    } elseif ($totalDuplicateLines -gt 500) {
        $reportContent += "⚠️ **MEDIUM IMPACT**: $totalDuplicateLines lines of duplicate code detected."
        $reportContent += "**Recommendation**: Consider refactoring the most impactful duplicates."
    } else {
        $reportContent += "✅ **LOW IMPACT**: $totalDuplicateLines lines of duplicate code detected."
        $reportContent += "**Recommendation**: Address duplicates during regular refactoring cycles."
    }
    
    $reportContent += ""
    $reportContent += "| Metric | Value |"
    $reportContent += "|--------|-------|"
    $reportContent += "| Total Duplicate Groups | $($duplicateGroups.Count) |"
    $reportContent += "| Estimated Duplicate Lines | $totalDuplicateLines |"
    $reportContent += "| Average Group Size | $([Math]::Round(($duplicateGroups | ForEach-Object { $_.Count } | Measure-Object -Average).Average, 1)) occurrences |"
    $reportContent += "| Largest Duplicate | $($sortedGroups[0].CodeLength) characters |"
}

$reportContent += ""

# BULLETPROOF: Detailed Duplicate Analysis with DOUBLE backticks (FIXED)
if ($duplicateGroups.Count -gt 0) {
    $reportContent += "## Duplicate Code Groups"
    $reportContent += ""
    
    $groupNumber = 1
    foreach ($sortedGroup in $sortedGroups | Select-Object -First 10) {
        $group = $sortedGroup.Group
        $firstBlock = $group.Group[0]
        
        $reportContent += "### Duplicate Group #$groupNumber"
        $reportContent += ""
        $reportContent += "**Impact Score**: $($sortedGroup.Impact) (size × duplicates)"
        $reportContent += "**Code Size**: $($sortedGroup.CodeLength) characters"
        $reportContent += "**Occurrences**: $($sortedGroup.Occurrences)"
        $reportContent += "**Type**: $($firstBlock.Type)"
        $reportContent += ""
        
        $reportContent += "#### Locations"
        $reportContent += ""
        $reportContent += "| File | Method | Line |"
        $reportContent += "|------|--------|------|"
        
        # SAFE: Basic string concatenation only
        foreach ($block in $group.Group) {
            $fileName = [System.IO.Path]::GetFileName($block.File)
            $tableRow = "| " + $fileName + " | " + $block.Name + " | " + $block.LineNumber + " |"
            $reportContent += $tableRow
        }
        
        $reportContent += ""
        
        # FIXED: Use DOUBLE backticks instead of TRIPLE for PowerShell 5.1 compatibility
        $reportContent += "#### Code Sample"
        $reportContent += ""
        
        # SAFE: Use double backticks which are PowerShell 5.1 safe
        $codeBlockStart = "``"
        $reportContent += $codeBlockStart
        
        # Safe line splitting using [Environment]::NewLine
        $originalLines = $firstBlock.OriginalCode -split [Environment]::NewLine
        $maxLinesToShow = [Math]::Min(10, $originalLines.Length)
        
        for ($i = 0; $i -lt $maxLinesToShow; $i++) {
            if ($originalLines[$i] -ne $null) {
                $reportContent += $originalLines[$i].TrimEnd()
            }
        }
        
        # SAFE: Use double backticks which are PowerShell 5.1 safe
        $codeBlockEnd = "``"
        $reportContent += $codeBlockEnd
        $reportContent += ""
        
        $groupNumber++
    }
}

# Refactoring Recommendations
$reportContent += "## Refactoring Recommendations"
$reportContent += ""

if ($duplicateGroups.Count -eq 0) {
    $reportContent += "### ✅ Excellent Code Structure"
    $reportContent += ""
    $reportContent += "No significant code duplication detected. Continue following these best practices:"
    $reportContent += ""
    $reportContent += "- Keep methods focused and single-purpose"
    $reportContent += "- Use shared utility classes for common operations"
    $reportContent += "- Apply DRY (Don't Repeat Yourself) principles consistently"
    $reportContent += "- Consider composition over inheritance for code reuse"
} else {
    $reportContent += "### Priority Actions"
    $reportContent += ""
    
    # High impact duplicates
    $highImpactGroups = $sortedGroups | Where-Object { $_.Impact -gt 1000 }
    if ($highImpactGroups.Count -gt 0) {
        $reportContent += "#### 🚨 High Impact Duplicates (Immediate Action)"
        $reportContent += ""
        foreach ($group in $highImpactGroups | Select-Object -First 5) {
            $firstBlock = $group.Group.Group[0]
            $reportContent += "- **Extract $($firstBlock.Name) pattern** ($($group.Occurrences) occurrences, $($group.CodeLength) chars)"
            $reportContent += "  - Create shared utility method or base class"
            $reportContent += "  - Impact reduction: $($group.Impact) points"
        }
        $reportContent += ""
    }
    
    # Medium impact duplicates
    $mediumImpactGroups = $sortedGroups | Where-Object { $_.Impact -gt 300 -and $_.Impact -le 1000 }
    if ($mediumImpactGroups.Count -gt 0) {
        $reportContent += "#### ⚠️ Medium Impact Duplicates"
        $reportContent += ""
        foreach ($group in $mediumImpactGroups | Select-Object -First 5) {
            $firstBlock = $group.Group.Group[0]
            $reportContent += "- **Refactor $($firstBlock.Name) pattern** ($($group.Occurrences) occurrences)"
        }
        $reportContent += ""
    }
    
    $reportContent += "### Refactoring Strategies"
    $reportContent += ""
    $reportContent += "1. **Extract Utility Methods**: Move common code patterns to shared utility classes"
    $reportContent += "2. **Create Base Classes**: Use inheritance for classes with similar behavior"
    $reportContent += "3. **Use Composition**: Prefer composition over inheritance for flexible code reuse"
    $reportContent += "4. **Parameter Extraction**: Convert similar methods to use configurable parameters"
    $reportContent += "5. **Template Methods**: Use template method pattern for algorithms with variations"
}

$reportContent += ""

# Technical Details
$reportContent += "## Technical Analysis Details"
$reportContent += ""
$reportContent += "### Analysis Configuration"
$reportContent += ""
$reportContent += "- **Minimum Method Size**: 100 characters (to avoid flagging trivial similarities)"
$reportContent += "- **Hash Algorithm**: SHA256 for reliable duplicate detection"
$reportContent += "- **Normalization**: Removed comments and normalized whitespace"
$reportContent += "- **Code Block Types**: Method bodies (public, private, protected, internal)"
$reportContent += ""

if ($duplicateGroups.Count -gt 0) {
    $reportContent += "### Impact Calculation"
    $reportContent += ""
    $reportContent += "Impact Score = Code Size (characters) × (Occurrences - 1)"
    $reportContent += ""
    $reportContent += "This metric prioritizes:"
    $reportContent += "- Larger code blocks (more maintenance overhead)"
    $reportContent += "- Higher frequency duplicates (more refactoring benefit)"
}

# Footer
$reportContent += ""
$reportContent += "---"
$reportContent += ""
$reportContent += "**Analysis Coverage**: $($files.Count) C# files, $($allBlocks.Count) code blocks"
$reportContent += ""
$footerText = "Generated by MixerThreholdMod DevOps Suite - Duplicate Code Detector"
$reportContent += $footerText

try {
    $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
    $saveSuccess = $true
}
catch {
    Write-Host "⚠️ Error saving detailed report: $_" -ForegroundColor DarkYellow
    $saveSuccess = $false
}

Write-Host "`n🚀 Duplicate code analysis complete!" -ForegroundColor Green

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
        Write-Host "   R - Re-run duplicate code analysis" -ForegroundColor DarkYellow
        Write-Host "   X - Exit to DevOps menu" -ForegroundColor Gray
        
        $choice = Read-Host "`nEnter choice (D/R/X)"
        $choice = $choice.ToUpper()
        
        switch ($choice) {
            'D' {
                if ($saveSuccess) {
                    Write-Host "`n📋 DISPLAYING DUPLICATE CODE REPORT:" -ForegroundColor DarkCyan
                    Write-Host "====================================" -ForegroundColor DarkCyan
                    try {
                        $reportDisplay = Get-Content -Path $reportPath -Raw
                        Write-Host $reportDisplay -ForegroundColor White
                        Write-Host "`n====================================" -ForegroundColor DarkCyan
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
                Write-Host "`n🔄 RE-RUNNING DUPLICATE CODE ANALYSIS..." -ForegroundColor DarkYellow
                Write-Host "=======================================" -ForegroundColor DarkYellow
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
    } while ($choice -notin @("X"))
} else {
    Write-Host "📄 Script completed - returning to caller" -ForegroundColor DarkGray
}