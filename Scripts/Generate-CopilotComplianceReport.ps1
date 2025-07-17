# MixerThreholdMod DevOps Tool: Copilot Instructions Compliance Checker (NON-INTERACTIVE)
# Verifies code follows .github/copilot-instructions.md rules and standards
# Checks for .NET 4.8.1 compatibility, thread safety, documentation, and more
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

Write-Host "🕐 Copilot compliance analysis started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "Checking Copilot Instructions compliance in: $ProjectRoot" -ForegroundColor DarkCyan
Write-Host "🚀 NON-INTERACTIVE VERSION - Compatible with automation" -ForegroundColor Green
Write-Host "Excluding: ForCopilot, Scripts, and Legacy directories" -ForegroundColor DarkGray

# Load copilot instructions if available
$copilotInstructionsPath = Join-Path $ProjectRoot ".github\copilot-instructions.md"
if (Test-Path $copilotInstructionsPath) {
    $copilotContent = Get-Content -Path $copilotInstructionsPath -Raw -ErrorAction SilentlyContinue
    Write-Host "📋 Found copilot instructions file" -ForegroundColor Gray
} else {
    Write-Host "⚠️  .github/copilot-instructions.md not found" -ForegroundColor DarkYellow
    $copilotContent = ""
}

# Find all C# files with CORRECTED exclusions
$files = Get-ChildItem -Path $ProjectRoot -Recurse -Include *.cs -ErrorAction SilentlyContinue | Where-Object {
    $_.PSIsContainer -eq $false -and
    $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy)[\\/]" -and
    $_.FullName -notmatch "[\\/]\.git[\\/]"
}

Write-Host "📊 Files to analyze: $($files.Count)" -ForegroundColor Gray

if ($files.Count -eq 0) {
    Write-Host "⚠️  No C# files found for compliance analysis" -ForegroundColor DarkYellow
    if ($IsInteractive -and -not $RunningFromScript) {
        Write-Host "`nPress ENTER to continue..." -ForegroundColor Gray -NoNewline
        Read-Host
    }
    return
}

# FIXED: Compliance check functions now include fileName parameter for PowerShell 5.1 compatibility
function Test-DotNet481Compatibility {
    param($content, $filePath, $fileName)
    
    $issues = @()
    
    # Check for string interpolation (critical for IL2CPP)
    if ($content -match '\$"[^"]*\{[^}]+\}[^"]*"') {
        $issues += [PSCustomObject]@{
            Rule = ".NET 4.8.1 Compatibility"
            Issue = "String interpolation detected (use string.Format instead)"
            Severity = "High"
            Context = "IL2CPP compatibility requirement"
            File = $fileName
        }
    }
    
    # Check for var usage (should use explicit types)
    $varCount = ([regex]::Matches($content, '(?m)^\s*var\s+\w+\s*=')).Count
    if ($varCount -gt 0) {
        $issues += [PSCustomObject]@{
            Rule = ".NET 4.8.1 Compatibility"
            Issue = "Implicit 'var' usage detected ($varCount occurrences)"
            Severity = "Medium"
            Context = "Use explicit types for IL2CPP compatibility"
            File = $fileName
        }
    }
    
    # Check for yield return in try/catch (critical error)
    if ($content -match 'try\s*\{[^}]*yield\s+return' -or $content -match 'catch[^}]*yield\s+return') {
        $issues += [PSCustomObject]@{
            Rule = ".NET 4.8.1 Compatibility"
            Issue = "yield return in try/catch block detected"
            Severity = "Critical"
            Context = "Not allowed in .NET 4.8.1 - will cause runtime errors"
            File = $fileName
        }
    }
    
    return $issues
}

function Test-ThreadSafety {
    param($content, $filePath, $fileName)
    
    $issues = @()
    
    # Check for Thread.Sleep usage (blocks main thread)
    if ($content -match 'Thread\.Sleep\s*\(') {
        $issues += [PSCustomObject]@{
            Rule = "Thread Safety & Performance"
            Issue = "Thread.Sleep detected"
            Severity = "High"
            Context = "Never block Unity main thread - use async patterns"
            File = $fileName
        }
    }
    
    # Check for missing ConfigureAwait(false)
    $awaitCount = ([regex]::Matches($content, 'await\s+[^;]+(?<!ConfigureAwait\(false\))\s*;')).Count
    $configureAwaitCount = ([regex]::Matches($content, 'ConfigureAwait\(false\)')).Count
    
    if ($awaitCount -gt $configureAwaitCount) {
        $missingCount = $awaitCount - $configureAwaitCount
        $issues += [PSCustomObject]@{
            Rule = "Thread Safety & Performance"
            Issue = "await without ConfigureAwait(false) ($missingCount occurrences)"
            Severity = "Medium"
            Context = "Use ConfigureAwait(false) for background operations"
            File = $fileName
        }
    }
    
    # Check for potentially blocking operations
    $blockingOps = @('\.Result\b', '\.Wait\(\)', 'Task\.Run\(.*\)\.Result')
    foreach ($op in $blockingOps) {
        if ($content -match $op) {
            $issues += [PSCustomObject]@{
                Rule = "Thread Safety & Performance"
                Issue = "Potentially blocking operation detected: $($op -replace '\\b', '')"
                Severity = "High"
                Context = "May block Unity main thread"
                File = $fileName
            }
            break  # Only report once per file
        }
    }
    
    return $issues
}

function Test-DocumentationCompliance {
    param($content, $filePath, $fileName)
    
    $issues = @()
    
    # Count public methods and XML documentation
    $publicMethodCount = ([regex]::Matches($content, '(?m)^\s*public\s+(?:static\s+|virtual\s+|override\s+|async\s+)*(?:Task<[^>]+>|Task|void|[A-Za-z0-9_<>\[\]]+)\s+[A-Za-z0-9_]+\s*\([^)]*\)')).Count
    $xmlDocCount = ([regex]::Matches($content, '^\s*///')).Count
    
    if ($publicMethodCount -gt 0 -and $xmlDocCount -eq 0) {
        $issues += [PSCustomObject]@{
            Rule = "Documentation & Workflow"
            Issue = "$publicMethodCount public methods without any XML documentation"
            Severity = "Medium"
            Context = "All public methods require XML documentation"
            File = $fileName
        }
    } elseif ($publicMethodCount -gt $xmlDocCount) {
        $undocumentedCount = $publicMethodCount - ($xmlDocCount / 3)  # Rough estimate
        if ($undocumentedCount -gt 0) {
            $issues += [PSCustomObject]@{
                Rule = "Documentation & Workflow"
                Issue = "Some public methods may lack XML documentation"
                Severity = "Low"
                Context = "Ensure all public methods are documented"
                File = $fileName
            }
        }
    }
    
    return $issues
}

function Test-SaveCrashPrevention {
    param($content, $filePath, $fileName)
    
    $issues = @()
    
    # Check for direct file operations without atomic patterns
    $directFileOps = @('File\.WriteAllText', 'File\.WriteAllBytes')
    foreach ($op in $directFileOps) {
        if ($content -match $op -and $content -notmatch '(atomic|temp|backup|\.tmp)') {
            $issues += [PSCustomObject]@{
                Rule = "Save Crash Prevention"
                Issue = "Direct file operation without atomic pattern"
                Severity = "High"
                Context = "Use atomic file operations to prevent save corruption"
                File = $fileName
            }
            break  # Only report once per file
        }
    }
    
    # Check for save methods without try-catch
    $saveMethodCount = ([regex]::Matches($content, 'public[^{]*(?:Save|Write|Persist)[^{]*\{')).Count
    $tryCatchCount = ([regex]::Matches($content, 'try\s*\{')).Count
    
    if ($saveMethodCount -gt 0 -and $tryCatchCount -eq 0) {
        $issues += [PSCustomObject]@{
            Rule = "Save Crash Prevention"
            Issue = "Save methods without try-catch error handling"
            Severity = "High"
            Context = "All save operations must have comprehensive error handling"
            File = $fileName
        }
    }
    
    return $issues
}

function Test-ErrorHandling {
    param($content, $filePath, $fileName)
    
    $issues = @()
    
    # Check for empty catch blocks
    if ($content -match 'catch[^{]*\{\s*\}') {
        $issues += [PSCustomObject]@{
            Rule = "Extreme Verbose Debugging"
            Issue = "Empty catch block detected"
            Severity = "High"
            Context = "All exceptions must be logged with context"
            File = $fileName
        }
    }
    
    # Check for catch blocks without logging
    $catchCount = ([regex]::Matches($content, 'catch\s*\([^)]*\)\s*\{')).Count
    $logCount = ([regex]::Matches($content, '(Log|logger\.|Main\.logger)')).Count
    
    if ($catchCount -gt 0 -and $logCount -eq 0) {
        $issues += [PSCustomObject]@{
            Rule = "Extreme Verbose Debugging"
            Issue = "Catch blocks without logging detected"
            Severity = "Medium"
            Context = "Log all exceptions with stack traces and context"
            File = $fileName
        }
    }
    
    return $issues
}

# Analyze all files with progress
Write-Host "`n🔍 Analyzing compliance..." -ForegroundColor DarkGray

$allIssues = @()
$fileAnalysis = @()
$processedFiles = 0

foreach ($file in $files) {
    $processedFiles++
    
    # Show progress every 20 files
    if ($processedFiles % 20 -eq 0 -or $processedFiles -eq 1 -or $processedFiles -eq $files.Count) {
        $percent = [Math]::Round(($processedFiles / $files.Count) * 100, 1)
        Write-Host "   📈 Progress: $processedFiles/$($files.Count) files ($percent%)" -ForegroundColor DarkGray
    }
    
    try {
        $content = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
        $fileName = [System.IO.Path]::GetFileName($file.FullName)
        
        # FIXED: Run all compliance checks with fileName parameter included
        $fileIssues = @()
        $fileIssues += Test-DotNet481Compatibility -content $content -filePath $file.FullName -fileName $fileName
        $fileIssues += Test-ThreadSafety -content $content -filePath $file.FullName -fileName $fileName
        $fileIssues += Test-DocumentationCompliance -content $content -filePath $file.FullName -fileName $fileName
        $fileIssues += Test-SaveCrashPrevention -content $content -filePath $file.FullName -fileName $fileName
        $fileIssues += Test-ErrorHandling -content $content -filePath $file.FullName -fileName $fileName
        
        # FIXED: No longer need to add File property - it's already included in object creation
        $allIssues += $fileIssues
        
        $fileAnalysis += [PSCustomObject]@{
            File = $fileName
            TotalIssues = $fileIssues.Count
            CriticalIssues = ($fileIssues | Where-Object { $_.Severity -eq "Critical" }).Count
            HighIssues = ($fileIssues | Where-Object { $_.Severity -eq "High" }).Count
            MediumIssues = ($fileIssues | Where-Object { $_.Severity -eq "Medium" }).Count
            LowIssues = ($fileIssues | Where-Object { $_.Severity -eq "Low" }).Count
        }
    }
    catch {
        Write-Host "⚠️  Error processing $($file.Name): $_" -ForegroundColor DarkYellow
        continue
    }
}

Write-Host "`n=== COPILOT INSTRUCTIONS COMPLIANCE REPORT ===" -ForegroundColor DarkCyan
Write-Host "🕐 Analysis completed: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "📊 Total files analyzed: $($files.Count)" -ForegroundColor Gray
Write-Host "📊 Total compliance issues found: $($allIssues.Count)" -ForegroundColor $(if ($allIssues.Count -eq 0) { "Green" } elseif ($allIssues.Count -lt 20) { "DarkYellow" } else { "Red" })

if ($allIssues.Count -eq 0) {
    Write-Host "`n🎉 EXCELLENT! No compliance issues found!" -ForegroundColor Green
    Write-Host "   Your code follows all Copilot instructions perfectly!" -ForegroundColor Green
} else {
    # Severity breakdown
    $criticalIssues = $allIssues | Where-Object { $_.Severity -eq "Critical" }
    $highIssues = $allIssues | Where-Object { $_.Severity -eq "High" }
    $mediumIssues = $allIssues | Where-Object { $_.Severity -eq "Medium" }
    $lowIssues = $allIssues | Where-Object { $_.Severity -eq "Low" }
    
    Write-Host "`n🚨 Issues by Severity:" -ForegroundColor DarkCyan
    Write-Host "   Critical: $($criticalIssues.Count)" -ForegroundColor $(if ($criticalIssues.Count -eq 0) { "Green" } else { "Red" })
    Write-Host "   High: $($highIssues.Count)" -ForegroundColor $(if ($highIssues.Count -eq 0) { "Green" } elseif ($highIssues.Count -lt 10) { "DarkYellow" } else { "Red" })
    Write-Host "   Medium: $($mediumIssues.Count)" -ForegroundColor $(if ($mediumIssues.Count -lt 20) { "DarkYellow" } else { "Red" })
    Write-Host "   Low: $($lowIssues.Count)" -ForegroundColor Gray
    
    # Issues by rule (condensed)
    Write-Host "`n📋 Issues by Copilot Rule:" -ForegroundColor DarkCyan
    $ruleStats = $allIssues | Group-Object Rule | Sort-Object Count -Descending | Select-Object -First 5
    
    foreach ($ruleStat in $ruleStats) {
        $color = switch ($ruleStat.Count) {
            { $_ -eq 0 } { "Green" }
            { $_ -lt 5 } { "DarkYellow" }
            default { "Red" }
        }
        Write-Host "   $($ruleStat.Name): $($ruleStat.Count) issues" -ForegroundColor $color
    }
    
    if ($ruleStats.Count -gt 5) {
        Write-Host "   ... and $($ruleStats.Count - 5) more rule categories" -ForegroundColor DarkGray
    }
    
    # Critical and High issues (limited for automation)
    if ($criticalIssues.Count -gt 0) {
        Write-Host "`n🚨 CRITICAL Issues (Must Fix Immediately):" -ForegroundColor Red
        foreach ($issue in $criticalIssues | Select-Object -First 5) {
            Write-Host "   • $($issue.Issue) in $($issue.File)" -ForegroundColor Red
            Write-Host "     Context: $($issue.Context)" -ForegroundColor DarkGray
        }
        
        if ($criticalIssues.Count -gt 5) {
            Write-Host "   ... and $($criticalIssues.Count - 5) more critical issues" -ForegroundColor DarkGray
        }
    }
    
    if ($highIssues.Count -gt 0) {
        Write-Host "`n⚠️  HIGH Priority Issues:" -ForegroundColor DarkYellow
        foreach ($issue in $highIssues | Select-Object -First 5) {
            Write-Host "   • $($issue.Issue) in $($issue.File)" -ForegroundColor DarkYellow
        }
        
        if ($highIssues.Count -gt 5) {
            Write-Host "   ... and $($highIssues.Count - 5) more high priority issues" -ForegroundColor DarkGray
        }
    }
    
    # Top problematic files (limited)
    Write-Host "`n📁 Files with Most Issues:" -ForegroundColor DarkCyan
    $topProblematicFiles = $fileAnalysis | Where-Object { $_.TotalIssues -gt 0 } | Sort-Object TotalIssues -Descending | Select-Object -First 5
    
    foreach ($fileInfo in $topProblematicFiles) {
        $color = if ($fileInfo.CriticalIssues -gt 0) { "Red" } elseif ($fileInfo.HighIssues -gt 0) { "DarkYellow" } else { "Gray" }
        Write-Host "   $($fileInfo.File): $($fileInfo.TotalIssues) issues (C:$($fileInfo.CriticalIssues) H:$($fileInfo.HighIssues) M:$($fileInfo.MediumIssues) L:$($fileInfo.LowIssues))" -ForegroundColor $color
    }
}

# Compliance score
$totalPossibleIssues = $files.Count * 5  # Conservative estimate
$complianceScore = if ($totalPossibleIssues -gt 0) { [Math]::Max(0, [Math]::Round((($totalPossibleIssues - $allIssues.Count) / $totalPossibleIssues) * 100, 1)) } else { 100 }

Write-Host "`n📊 Compliance Score: $complianceScore%" -ForegroundColor $(if ($complianceScore -gt 90) { "Green" } elseif ($complianceScore -gt 75) { "DarkYellow" } else { "Red" })

# Quick recommendations
Write-Host "`n💡 Priority Recommendations:" -ForegroundColor DarkCyan

if ($criticalIssues.Count -gt 0) {
    Write-Host "   🚨 IMMEDIATE: Fix $($criticalIssues.Count) critical issues first" -ForegroundColor Red
} elseif ($highIssues.Count -gt 0) {
    Write-Host "   ⚠️  Address $($highIssues.Count) high priority issues" -ForegroundColor DarkYellow
} elseif ($allIssues.Count -gt 0) {
    Write-Host "   ✅ Good compliance! Address remaining minor issues when convenient" -ForegroundColor Green
} else {
    Write-Host "   🎉 Perfect compliance! Your code follows all Copilot instructions!" -ForegroundColor Green
}

# Specific quick recommendations
$dotNetIssues = $allIssues | Where-Object { $_.Rule -like "*4.8.1*" }
if ($dotNetIssues.Count -gt 0) {
    Write-Host "   • Replace string interpolation with string.Format()" -ForegroundColor Gray
    Write-Host "   • Use explicit types instead of 'var'" -ForegroundColor Gray
}

$threadIssues = $allIssues | Where-Object { $_.Rule -like "*Thread*" }
if ($threadIssues.Count -gt 0) {
    Write-Host "   • Add ConfigureAwait(false) to await statements" -ForegroundColor Gray
    Write-Host "   • Replace Thread.Sleep with async patterns" -ForegroundColor Gray
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

# Generate detailed compliance report using PowerShell 5.1 safe approach
Write-Host "`n📝 Generating detailed compliance report..." -ForegroundColor DarkGray

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPath = Join-Path $reportsDir "COPILOT-COMPLIANCE-REPORT_$timestamp.md"

# Build report using separate variables for PowerShell 5.1 compatibility
$reportTitle = "# Copilot Instructions Compliance Report"
$reportGenerated = "**Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportFilesAnalyzed = "**Files Analyzed**: $($files.Count)"
$reportTotalIssues = "**Total Issues Found**: $($allIssues.Count)"
$reportComplianceScore = "**Compliance Score**: $complianceScore%"

$reportContent = @()
$reportContent += $reportTitle
$reportContent += ""
$reportContent += $reportGenerated
$reportContent += $reportFilesAnalyzed
$reportContent += $reportTotalIssues
$reportContent += $reportComplianceScore
$reportContent += ""

# Executive Summary
$reportContent += "## Executive Summary"
$reportContent += ""
if ($allIssues.Count -eq 0) {
    $reportContent += "🎉 **EXCELLENT COMPLIANCE!** Your code follows all GitHub Copilot instructions perfectly."
    $reportContent += ""
    $reportContent += "All analyzed files meet the required standards for:"
    $reportContent += "- .NET 4.8.1 compatibility and IL2CPP support"
    $reportContent += "- Thread safety and Unity main thread protection"
    $reportContent += "- Comprehensive error handling and debugging"
    $reportContent += "- Save corruption prevention mechanisms"
    $reportContent += "- Documentation and workflow standards"
} else {
    $reportContent += "**Compliance Status**: $($allIssues.Count) issues found across $($files.Count) files"
    $reportContent += ""
    $reportContent += "| Severity | Count | Impact |"
    $reportContent += "|----------|-------|--------|"
    $reportContent += "| Critical | $($criticalIssues.Count) | Runtime errors, crashes |"
    $reportContent += "| High | $($highIssues.Count) | Performance issues, thread blocking |"
    $reportContent += "| Medium | $($mediumIssues.Count) | Compatibility concerns |"
    $reportContent += "| Low | $($lowIssues.Count) | Documentation gaps |"
}
$reportContent += ""

# Issues by Copilot Rule
if ($allIssues.Count -gt 0) {
    $reportContent += "## Issues by Copilot Rule"
    $reportContent += ""
    
    $ruleGroups = $allIssues | Group-Object Rule | Sort-Object Count -Descending
    foreach ($ruleGroup in $ruleGroups) {
        $reportContent += "### $($ruleGroup.Name)"
        $reportContent += ""
        $reportContent += "**Total Issues**: $($ruleGroup.Count)"
        $reportContent += ""
        
        # Group by severity within each rule
        $severityGroups = $ruleGroup.Group | Group-Object Severity | Sort-Object @{Expression={
            switch ($_.Name) {
                "Critical" { 1 }
                "High" { 2 }
                "Medium" { 3 }
                "Low" { 4 }
                default { 5 }
            }
        }}
        
        foreach ($severityGroup in $severityGroups) {
            $reportContent += "#### $($severityGroup.Name) Priority ($($severityGroup.Count) issues)"
            $reportContent += ""
            
            $topIssues = $severityGroup.Group | Select-Object -First 10
            foreach ($issue in $topIssues) {
                $reportContent += "- **$($issue.File)**: $($issue.Issue)"
                $reportContent += "  - Context: $($issue.Context)"
            }
            
            if ($severityGroup.Group.Count -gt 10) {
                $reportContent += "- ... and $($severityGroup.Group.Count - 10) more $($severityGroup.Name.ToLower()) issues"
            }
            $reportContent += ""
        }
    }
}

# File Analysis
if ($fileAnalysis.Count -gt 0) {
    $reportContent += "## File Analysis Summary"
    $reportContent += ""
    
    $problematicFiles = $fileAnalysis | Where-Object { $_.TotalIssues -gt 0 } | Sort-Object TotalIssues -Descending
    
    if ($problematicFiles.Count -gt 0) {
        $reportContent += "### Files Requiring Attention"
        $reportContent += ""
        $reportContent += "| File | Total | Critical | High | Medium | Low |"
        $reportContent += "|------|-------|----------|------|--------|-----|"
        
        foreach ($fileInfo in $problematicFiles | Select-Object -First 20) {
            $reportContent += "| `$($fileInfo.File)` | $($fileInfo.TotalIssues) | $($fileInfo.CriticalIssues) | $($fileInfo.HighIssues) | $($fileInfo.MediumIssues) | $($fileInfo.LowIssues) |"
        }
        
        if ($problematicFiles.Count -gt 20) {
            $reportContent += ""
            $reportContent += "... and $($problematicFiles.Count - 20) more files with issues"
        }
    }
    
    $cleanFiles = $fileAnalysis | Where-Object { $_.TotalIssues -eq 0 }
    if ($cleanFiles.Count -gt 0) {
        $reportContent += ""
        $reportContent += "### ✅ Compliant Files"
        $reportContent += ""
        $reportContent += "**$($cleanFiles.Count) files** follow all Copilot instructions perfectly!"
    }
}

# Recommendations
$reportContent += ""
$reportContent += "## Action Items & Recommendations"
$reportContent += ""

if ($criticalIssues.Count -gt 0) {
    $reportContent += "### 🚨 IMMEDIATE ACTION REQUIRED"
    $reportContent += ""
    $reportContent += "Critical issues must be fixed immediately as they can cause runtime errors:"
    $reportContent += ""
    
    $criticalByRule = $criticalIssues | Group-Object Rule
    foreach ($ruleGroup in $criticalByRule) {
        $reportContent += "#### $($ruleGroup.Name)"
        foreach ($issue in $ruleGroup.Group | Select-Object -First 5) {
            $reportContent += "- Fix in `$($issue.File)`: $($issue.Issue)"
        }
        if ($ruleGroup.Group.Count -gt 5) {
            $reportContent += "- ... and $($ruleGroup.Group.Count - 5) more critical issues"
        }
    }
    $reportContent += ""
}

if ($highIssues.Count -gt 0) {
    $reportContent += "### ⚠️ High Priority Items"
    $reportContent += ""
    $reportContent += "Address these issues to prevent performance problems and thread blocking:"
    $reportContent += ""
    
    if ($dotNetIssues.Count -gt 0) {
        $reportContent += "- **Replace string interpolation** with string.Format() for IL2CPP compatibility"
        $reportContent += "- **Use explicit types** instead of var for AOT compilation safety"
    }
    
    if ($threadIssues.Count -gt 0) {
        $reportContent += "- **Add ConfigureAwait(false)** to all await statements in background operations"
        $reportContent += "- **Replace Thread.Sleep** with async patterns to avoid blocking Unity main thread"
    }
    $reportContent += ""
}

$reportContent += "### 📋 Best Practices"
$reportContent += ""
$reportContent += "Continue following these Copilot instruction standards:"
$reportContent += ""
$reportContent += "1. **Thread Safety**: All operations must be thread-safe with proper async patterns"
$reportContent += "2. **Error Handling**: Comprehensive try-catch with detailed logging and recovery"
$reportContent += "3. **Save Protection**: Use atomic file operations to prevent corruption"
$reportContent += "4. **Documentation**: XML documentation for all public methods with thread safety notes"
$reportContent += "5. **Compatibility**: .NET 4.8.1 syntax compatible with both MONO and IL2CPP"
$reportContent += ""

# Footer
$reportContent += "---"
$reportContent += ""
$reportContent += "**Compliance Standards**: Based on .github/copilot-instructions.md"
$reportContent += ""
# FIXED: Removed problematic asterisk that was causing operator parsing errors
$footerText = "Generated by MixerThreholdMod DevOps Suite - Copilot Compliance Checker"
$reportContent += $footerText

try {
    $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
    $saveSuccess = $true
}
catch {
    Write-Host "⚠️ Error saving detailed report: $_" -ForegroundColor DarkYellow
    $saveSuccess = $false
}

Write-Host "`n🚀 Copilot compliance analysis complete!" -ForegroundColor Green

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
        Write-Host "   R - Re-run copilot compliance analysis" -ForegroundColor DarkYellow
        Write-Host "   X - Exit to DevOps menu" -ForegroundColor Gray
        
        $choice = Read-Host "`nEnter choice (D/R/X)"
        $choice = $choice.ToUpper()
        
        switch ($choice) {
            'D' {
                if ($saveSuccess) {
                    Write-Host "`n📋 DISPLAYING COPILOT COMPLIANCE REPORT:" -ForegroundColor DarkCyan
                    Write-Host "==========================================" -ForegroundColor DarkCyan
                    try {
                        $reportDisplay = Get-Content -Path $reportPath -Raw
                        Write-Host $reportDisplay -ForegroundColor White
                        Write-Host "`n==========================================" -ForegroundColor DarkCyan
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
                Write-Host "`n🔄 RE-RUNNING COPILOT COMPLIANCE ANALYSIS..." -ForegroundColor DarkYellow
                Write-Host "=============================================" -ForegroundColor DarkYellow
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