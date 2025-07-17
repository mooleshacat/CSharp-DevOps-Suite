# MixerThreholdMod DevOps Tool: Method Complexity Analyzer (NON-INTERACTIVE)
# Analyzes C# methods for complexity and identifies refactoring candidates
# Calculates cyclomatic complexity, parameter count, and line count metrics
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

Write-Host "🕐 Method complexity analysis started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "Analyzing method complexity in: $ProjectRoot" -ForegroundColor DarkCyan
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

# Function to calculate cyclomatic complexity (simplified)
function Get-CyclomaticComplexity {
    param($methodContent)
    
    $complexity = 1  # Base complexity
    
    # Count decision points
    $decisionPatterns = @(
        'if\s*\(',
        'else\s+if\s*\(',
        'while\s*\(',
        'for\s*\(',
        'foreach\s*\(',
        'case\s+',
        'catch\s*\(',
        '\?\s*.*\s*:',  # Ternary operator
        '&&',
        '\|\|'
    )
    
    foreach ($pattern in $decisionPatterns) {
        $matches = [regex]::Matches($methodContent, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        $complexity += $matches.Count
    }
    
    return $complexity
}

# Function to analyze a single method
function Get-MethodAnalysis {
    param($methodMatch, $fileName, $fileContent)
    
    try {
        $methodName = $methodMatch.Groups[2].Value
        $methodContent = $methodMatch.Groups[3].Value
        $methodSignature = $methodMatch.Groups[0].Value
        
        # Calculate metrics
        $lineCount = ($methodContent -split "`n").Count
        $cyclomaticComplexity = Get-CyclomaticComplexity -methodContent $methodContent
        
        # Count parameters
        $parameterCount = 0
        if ($methodSignature -match '\(([^)]*)\)') {
            $parameterString = $matches[1].Trim()
            if ($parameterString -ne "") {
                $parameterCount = ($parameterString -split ',').Count
            }
        }
        
        # Calculate overall complexity score
        $complexityScore = $cyclomaticComplexity + ($parameterCount * 0.5) + ($lineCount * 0.1)
        
        # Determine complexity level
        $complexityLevel = if ($complexityScore -lt 5) { "Low" }
                          elseif ($complexityScore -lt 10) { "Medium" }
                          elseif ($complexityScore -lt 20) { "High" }
                          else { "Very High" }
        
        # Get line number
        $lineNumber = ($fileContent.Substring(0, $methodMatch.Index) -split "`n").Count
        
        return [PSCustomObject]@{
            FileName = $fileName
            MethodName = $methodName
            LineNumber = $lineNumber
            LineCount = $lineCount
            ParameterCount = $parameterCount
            CyclomaticComplexity = $cyclomaticComplexity
            ComplexityScore = [Math]::Round($complexityScore, 1)
            ComplexityLevel = $complexityLevel
            NeedsRefactoring = $complexityLevel -in @("High", "Very High")
        }
    }
    catch {
        Write-Host "⚠️  Error analyzing method in $(Split-Path $fileName -Leaf): $($_.Exception.Message)" -ForegroundColor DarkYellow
        return $null
    }
}

# Analyze all files with progress
Write-Host "`n🔍 Analyzing methods..." -ForegroundColor DarkCyan
$allMethods = @()
$processedFiles = 0
$totalFiles = $files.Count

foreach ($file in $files) {
    $processedFiles++
    
    # Show progress every 20 files
    if ($processedFiles % 20 -eq 0 -or $processedFiles -eq 1 -or $processedFiles -eq $totalFiles) {
        $percent = [Math]::Round(($processedFiles / $totalFiles) * 100, 1)
        Write-Host "   📈 Progress: $processedFiles/$totalFiles files ($percent%)" -ForegroundColor DarkGray
    }
    
    try {
        $content = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
        if (-not $content) { continue }
        
        # Find method definitions
        $methodPattern = '(public|private|protected|internal)\s+(?:static\s+|virtual\s+|override\s+|async\s+)*(?:Task<[^>]+>|Task|void|[A-Za-z0-9_<>\[\]]+)\s+([A-Za-z0-9_]+)\s*\(([^)]*)\)\s*\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}'
        $methodMatches = [regex]::Matches($content, $methodPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        
        foreach ($match in $methodMatches) {
            $analysis = Get-MethodAnalysis -methodMatch $match -fileName $file.FullName -fileContent $content
            if ($analysis) {
                $allMethods += $analysis
            }
        }
    }
    catch {
        Write-Host "⚠️  Error processing $(Split-Path $file.FullName -Leaf): $($_.Exception.Message)" -ForegroundColor DarkYellow
        continue
    }
}

Write-Host "`n=== METHOD COMPLEXITY ANALYSIS REPORT ===" -ForegroundColor DarkCyan
Write-Host "🕐 Analysis completed: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "📊 Total methods analyzed: $($allMethods.Count)" -ForegroundColor Gray

if ($allMethods.Count -eq 0) {
    Write-Host "⚠️  No methods found for analysis" -ForegroundColor DarkYellow
} else {
    # Calculate statistics
    $lowComplexity = $allMethods | Where-Object { $_.ComplexityLevel -eq "Low" }
    $mediumComplexity = $allMethods | Where-Object { $_.ComplexityLevel -eq "Medium" }
    $highComplexity = $allMethods | Where-Object { $_.ComplexityLevel -eq "High" }
    $veryHighComplexity = $allMethods | Where-Object { $_.ComplexityLevel -eq "Very High" }
    $needsRefactoring = $allMethods | Where-Object { $_.NeedsRefactoring }
    
    # Complexity distribution
    Write-Host "`n📊 Complexity Distribution:" -ForegroundColor DarkCyan
    Write-Host "   Low: $($lowComplexity.Count)" -ForegroundColor Green
    Write-Host "   Medium: $($mediumComplexity.Count)" -ForegroundColor DarkYellow
    Write-Host "   High: $($highComplexity.Count)" -ForegroundColor Red
    Write-Host "   Very High: $($veryHighComplexity.Count)" -ForegroundColor Red
    Write-Host "   Needs Refactoring: $($needsRefactoring.Count)" -ForegroundColor Red
    
    # Show top complex methods (limited for automation)
    if ($needsRefactoring.Count -gt 0) {
        Write-Host "`n🚨 Top Complex Methods (Need Refactoring):" -ForegroundColor Red
        
        $topComplex = $needsRefactoring | Sort-Object ComplexityScore -Descending | Select-Object -First 5
        foreach ($method in $topComplex) {
            $fileName = Split-Path $method.FileName -Leaf
            Write-Host "   • $($method.MethodName) in $fileName (Score: $($method.ComplexityScore))" -ForegroundColor Red
            Write-Host "     Lines: $($method.LineCount), Params: $($method.ParameterCount), Cyclomatic: $($method.CyclomaticComplexity)" -ForegroundColor DarkGray
        }
        
        if ($needsRefactoring.Count -gt 5) {
            Write-Host "   ... and $($needsRefactoring.Count - 5) more methods need refactoring" -ForegroundColor DarkGray
        }
    }
    
    # Summary statistics
    Write-Host "`n📈 Summary Statistics:" -ForegroundColor DarkCyan
    $avgComplexity = [Math]::Round(($allMethods | Measure-Object -Property ComplexityScore -Average).Average, 1)
    $maxComplexity = ($allMethods | Measure-Object -Property ComplexityScore -Maximum).Maximum
    $avgLines = [Math]::Round(($allMethods | Measure-Object -Property LineCount -Average).Average, 1)
    
    Write-Host "   Average Complexity Score: $avgComplexity" -ForegroundColor Gray
    Write-Host "   Maximum Complexity Score: $maxComplexity" -ForegroundColor Gray
    Write-Host "   Average Method Length: $avgLines lines" -ForegroundColor Gray
    
    # Quick recommendations
    Write-Host "`n💡 Recommendations:" -ForegroundColor DarkCyan
    if ($needsRefactoring.Count -gt 0) {
        Write-Host "   🚨 $($needsRefactoring.Count) methods need refactoring" -ForegroundColor Red
        Write-Host "   • Break down large methods into smaller functions" -ForegroundColor Gray
        Write-Host "   • Reduce parameter count using objects or builders" -ForegroundColor Gray
        Write-Host "   • Simplify complex conditional logic" -ForegroundColor Gray
    } else {
        Write-Host "   ✅ All methods have acceptable complexity levels" -ForegroundColor Green
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

# Generate detailed report
if ($allMethods.Count -gt 0) {
    Write-Host "`n📝 Generating detailed method complexity report..." -ForegroundColor DarkGray
    
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $reportPath = Join-Path $reportsDir "METHOD-COMPLEXITY-ANALYSIS_$timestamp.md"
    
    $reportContent = @()
    $reportContent += "# Method Complexity Analysis Report"
    $reportContent += ""
    $reportContent += "**Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $reportContent += "**Total Methods Analyzed**: $($allMethods.Count)"
    $reportContent += "**Files Analyzed**: $($files.Count)"
    $reportContent += ""
    
    # Summary statistics
    $reportContent += "## Summary Statistics"
    $reportContent += ""
    $reportContent += "| Complexity Level | Count | Percentage |"
    $reportContent += "|-----------------|-------|------------|"
    $reportContent += "| Low | $($lowComplexity.Count) | $([Math]::Round(($lowComplexity.Count / $allMethods.Count) * 100, 1))% |"
    $reportContent += "| Medium | $($mediumComplexity.Count) | $([Math]::Round(($mediumComplexity.Count / $allMethods.Count) * 100, 1))% |"
    $reportContent += "| High | $($highComplexity.Count) | $([Math]::Round(($highComplexity.Count / $allMethods.Count) * 100, 1))% |"
    $reportContent += "| Very High | $($veryHighComplexity.Count) | $([Math]::Round(($veryHighComplexity.Count / $allMethods.Count) * 100, 1))% |"
    $reportContent += ""
    
    # Top complex methods
    if ($needsRefactoring.Count -gt 0) {
        $reportContent += "## Methods Requiring Refactoring"
        $reportContent += ""
        $reportContent += "| Method | File | Complexity Score | Lines | Parameters | Cyclomatic |"
        $reportContent += "|--------|------|-----------------|-------|------------|------------|"
        
        $topRefactoring = $needsRefactoring | Sort-Object ComplexityScore -Descending | Select-Object -First 20
        foreach ($method in $topRefactoring) {
            $fileName = Split-Path $method.FileName -Leaf
            $reportContent += "| `$($method.MethodName)` | $fileName | $($method.ComplexityScore) | $($method.LineCount) | $($method.ParameterCount) | $($method.CyclomaticComplexity) |"
        }
        $reportContent += ""
    }
    
    # All methods (condensed)
    $reportContent += "## All Methods (Top 50 by Complexity)"
    $reportContent += ""
    $reportContent += "| Method | File | Score | Level |"
    $reportContent += "|--------|------|-------|-------|"
    
    $topMethods = $allMethods | Sort-Object ComplexityScore -Descending | Select-Object -First 50
    foreach ($method in $topMethods) {
        $fileName = Split-Path $method.FileName -Leaf
        $reportContent += "| `$($method.MethodName)` | $fileName | $($method.ComplexityScore) | $($method.ComplexityLevel) |"
    }
    
    $reportContent += ""
    $reportContent += "---"
    $reportContent += "*Generated by MixerThreholdMod DevOps Suite - Method Complexity Analyzer*"
    
    try {
        $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
        $saveSuccess = $true
    }
    catch {
        Write-Host "⚠️ Error saving detailed report: $_" -ForegroundColor DarkYellow
        $saveSuccess = $false
    }
} else {
    $saveSuccess = $false
}

Write-Host "`n🚀 Method complexity analysis complete!" -ForegroundColor Green

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
        Write-Host "   R - Re-run method complexity analysis" -ForegroundColor DarkYellow
        Write-Host "   X - Exit to DevOps menu" -ForegroundColor Gray
        
        $choice = Read-Host "`nEnter choice (D/R/X)"
        $choice = $choice.ToUpper()
        
        switch ($choice) {
            'D' {
                if ($saveSuccess) {
                    Write-Host "`n📋 DISPLAYING METHOD COMPLEXITY REPORT:" -ForegroundColor DarkCyan
                    Write-Host "========================================" -ForegroundColor DarkCyan
                    try {
                        $reportDisplay = Get-Content -Path $reportPath -Raw
                        Write-Host $reportDisplay -ForegroundColor White
                        Write-Host "`n========================================" -ForegroundColor DarkCyan
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
                Write-Host "`n🔄 RE-RUNNING METHOD COMPLEXITY ANALYSIS..." -ForegroundColor DarkYellow
                Write-Host "===========================================" -ForegroundColor DarkYellow
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