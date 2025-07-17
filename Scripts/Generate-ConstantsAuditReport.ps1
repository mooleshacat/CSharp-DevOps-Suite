# MixerThreholdMod DevOps Tool: Constants Audit Report Generator (NON-INTERACTIVE)
# Comprehensive verification and analysis of constant declarations and usage
# Scans for constant declarations and usage in:
# - Any file named Constants.cs (any location)
# - Any .cs file within the Constants directory or its subdirectories
# - Any .cs file in the project, EXCLUDING ForCopilot, Scripts, and Legacy directories

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ((Split-Path $ScriptDir -Leaf) -ieq "Scripts") {
    $ProjectRoot = Split-Path $ScriptDir -Parent
} else {
    $ProjectRoot = $ScriptDir
}

# Check if running interactively or from another script
$IsInteractive = [Environment]::UserInteractive -and $Host.Name -ne "ConsoleHost"
$RunningFromScript = $MyInvocation.InvocationName -notmatch "\.ps1$"

Write-Host "🕐 Constants audit started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "Scanning project root: $ProjectRoot" -ForegroundColor DarkCyan
Write-Host "🚀 NON-INTERACTIVE VERSION - Compatible with automation" -ForegroundColor Green
Write-Host "Excluding: ForCopilot, Scripts, and Legacy directories" -ForegroundColor DarkGray

function Get-ConstantDeclarations {
    param([string]$Path)
    
    try {
        $constantFiles = @()
        $constantFiles += Get-ChildItem -Path $Path -Recurse -Include Constants.cs -ErrorAction SilentlyContinue | Where-Object { 
            $_.PSIsContainer -eq $false -and
            $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy)[\\/]"
        }
        
        $constantsDir = Join-Path $Path "Constants"
        if (Test-Path $constantsDir) {
            $constantFiles += Get-ChildItem -Path $constantsDir -Recurse -Include *.cs -ErrorAction SilentlyContinue | Where-Object { 
                $_.PSIsContainer -eq $false -and
                $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy)[\\/]"
            }
        }
        
        $constantFiles = $constantFiles | Sort-Object -Unique

        $declarations = @()
        foreach ($fileObj in $constantFiles) {
            $file = $fileObj.FullName
            try {
                $matches = Select-String -Path $file -Pattern 'public\s+const\s+(\w+)\s+(\w+)\s*=' -ErrorAction SilentlyContinue
                foreach ($match in $matches) {
                    $type = $match.Matches[0].Groups[1].Value
                    $name = $match.Matches[0].Groups[2].Value
                    $declarations += [PSCustomObject]@{ 
                        File = $file
                        FileName = [System.IO.Path]::GetFileName($file)
                        Type = $type
                        Name = $name
                        LineNumber = $match.LineNumber
                    }
                }
            }
            catch {
                Write-Host "⚠️  Error processing file $($fileObj.Name): $_" -ForegroundColor DarkYellow
                continue
            }
        }
        return $declarations
    }
    catch {
        Write-Host "⚠️  Error scanning for constants: $_" -ForegroundColor DarkYellow
        return @()
    }
}

function Get-ConstantUsages {
    param([string[]]$ConstantNames, [string]$Path)
    
    try {
        $usages = @()
        # Scan all .cs files in project, excluding ForCopilot, Scripts, Legacy, and Constants directories
        $files = Get-ChildItem -Path $Path -Recurse -Include *.cs -ErrorAction SilentlyContinue | Where-Object {
            $_.PSIsContainer -eq $false -and
            $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy|Constants)[\\/]" -and
            $_.Name -ne "Constants.cs"
        }
        $files = $files | Sort-Object -Unique

        Write-Host "   📂 Total files to scan for usage: $($files.Count)" -ForegroundColor DarkGray
        
        if ($files.Count -gt 0) {
            Write-Host "   📄 Sample files being scanned:" -ForegroundColor DarkGray
            $files | Select-Object -First 3 | ForEach-Object { 
                Write-Host "     • $([System.IO.Path]::GetFileName($_.FullName))" -ForegroundColor DarkGray 
            }
        }

        # Return both usages and files count
        $result = @{
            Usages = @()
            FilesCount = $files.Count
        }

        if ($ConstantNames.Count -eq 0) {
            return $result
        }

        $pattern = ($ConstantNames | ForEach-Object { [regex]::Escape($_) }) -join "|"
        $i = 0
        foreach ($fileObj in $files) {
            $i++
            if ($i % 20 -eq 0) {
                Write-Host "   📈 Progress: Scanned $i of $($files.Count) files..." -ForegroundColor DarkGray
            }
            
            $file = $fileObj.FullName
            try {
                $matches = Select-String -Path $file -Pattern $pattern -ErrorAction SilentlyContinue
                foreach ($match in $matches) {
                    # Skip lines that are constant declarations
                    if ($match.Line -notmatch 'public\s+const\s+') {
                        foreach ($name in $ConstantNames) {
                            if ($match.Line -match "\b$name\b") {
                                $result.Usages += [PSCustomObject]@{ 
                                    Name = $name
                                    File = $file
                                    FileName = [System.IO.Path]::GetFileName($file)
                                    LineNumber = $match.LineNumber
                                    Context = $match.Line.Trim()
                                    Count = 1 
                                }
                            }
                        }
                    }
                }
            }
            catch {
                # Skip files that can't be read
                continue
            }
        }
        return $result
    }
    catch {
        Write-Host "⚠️  Error scanning for constant usages: $_" -ForegroundColor DarkYellow
        return @{ Usages = @(); FilesCount = 0 }
    }
}

Write-Host "`n📂 Scanning for constants..." -ForegroundColor DarkGray
$constants = Get-ConstantDeclarations -Path $ProjectRoot

Write-Host "`n📊 Found $($constants.Count) constants in $(($constants | Select-Object -ExpandProperty File -Unique).Count) files" -ForegroundColor Gray

if ($constants.Count -eq 0) {
    Write-Host "⚠️  No constants found for analysis" -ForegroundColor DarkYellow
    if ($IsInteractive -and -not $RunningFromScript) {
        Write-Host "`nPress ENTER to continue..." -ForegroundColor Gray -NoNewline
        Read-Host
    }
    return
}

# Main Analysis
$constantNames = $constants | Select-Object -ExpandProperty Name
$duplicateNames = $constantNames | Group-Object | Where-Object { $_.Count -gt 1 } | Select-Object -ExpandProperty Name

Write-Host "`n🔍 Analyzing constant usage..." -ForegroundColor DarkGray
$usageResult = Get-ConstantUsages -ConstantNames $constantNames -Path $ProjectRoot
$usages = $usageResult.Usages
$scannedFilesCount = $usageResult.FilesCount
$usedNames = $usages | Select-Object -ExpandProperty Name | Sort-Object -Unique
$unusedNames = $constantNames | Where-Object { $usedNames -notcontains $_ }

# Calculate usage statistics - counts usage in NON-CONSTANT files
$fileStats = $constants | Group-Object File | ForEach-Object {
    $file = $_.Name
    $count = $_.Count
    # Get unique constants from this file that are used anywhere
    $usedFromThisFile = $constants | Where-Object { $_.File -eq $file } | Where-Object { $usedNames -contains $_.Name } | Select-Object -ExpandProperty Name -Unique
    $used = $usedFromThisFile.Count
    $percentUsed = if ($count -gt 0) { [Math]::Round(100 * $used / $count, 1) } else { 0 }
    [PSCustomObject]@{ 
        File = $file
        FileName = [System.IO.Path]::GetFileName($file)
        ConstantCount = $count
        UsedCount = $used
        PercentUsed = $percentUsed 
    }
}

Write-Host "`n=== CONSTANTS AUDIT REPORT ===" -ForegroundColor DarkCyan
Write-Host "🕐 Analysis completed: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "📊 Total constants: $($constants.Count)" -ForegroundColor Gray
Write-Host "📊 Total unique constant names: $(($constantNames | Sort-Object -Unique).Count)" -ForegroundColor Gray
Write-Host "📊 Total constant files scanned: $(($fileStats | Measure-Object).Count)" -ForegroundColor Gray
Write-Host "📊 Total code files scanned for usage: $scannedFilesCount" -ForegroundColor Gray
Write-Host "🔄 Total duplicate constant names: $($duplicateNames.Count)" -ForegroundColor $(if ($duplicateNames.Count -eq 0) { "Green" } else { "Red" })
Write-Host "❌ Total unused constants: $($unusedNames.Count)" -ForegroundColor $(if ($unusedNames.Count -eq 0) { "Green" } else { "Red" })

# Show some example used constants for verification
if ($usedNames.Count -gt 0) {
    Write-Host "`n✅ Example constants that ARE being used:" -ForegroundColor DarkCyan
    $usedNames | Select-Object -First 5 | ForEach-Object { 
        $usage = $usages | Where-Object { $_.Name -eq $_ } | Select-Object -First 1
        Write-Host "   • $_ - used in $($usage.FileName)" -ForegroundColor Green 
    }
}

Write-Host "`n📊 Per-file stats (top 10 by constant count):" -ForegroundColor DarkCyan
$fileStats | Sort-Object -Property ConstantCount -Descending | Select-Object -First 10 | ForEach-Object {
    $color = if ($_.PercentUsed -eq 0) { "Red" } elseif ($_.PercentUsed -lt 10) { "DarkYellow" } else { "Green" }
    Write-Host "   $($_.FileName): $($_.ConstantCount) constants, $($_.UsedCount) used ($($_.PercentUsed)%)" -ForegroundColor $color
}

# Top N most duplicated constants
$N = 5  # Reduced for automation
$dupGroups = $constants | Group-Object Name | Where-Object { $_.Count -gt 1 }
if ($dupGroups.Count -gt 0) {
    Write-Host "`n🔄 Top $N most duplicated constants:" -ForegroundColor DarkCyan
    $dupGroups | Sort-Object -Property Count -Descending | Select-Object -First $N | ForEach-Object {
        $files = ($_.Group | Select-Object -ExpandProperty FileName | Sort-Object -Unique) -join ", "
        Write-Host "   • $($_.Name) ($($_.Count) times) in: $files" -ForegroundColor DarkYellow
    }
    if ($dupGroups.Count -gt $N) {
        $remaining = $dupGroups.Count - $N
        Write-Host "   ... and $remaining more duplicated constants" -ForegroundColor DarkGray 
    }
}

# Top N unused constants
if ($unusedNames.Count -gt 0) {
    Write-Host "`n❌ Top $N unused constants:" -ForegroundColor DarkCyan
    $unusedNames | Select-Object -First $N | ForEach-Object { Write-Host "   • $_" -ForegroundColor Red }
    if ($unusedNames.Count -gt $N) { 
        $remaining = $unusedNames.Count - $N
        Write-Host "   ... and $remaining more unused constants" -ForegroundColor DarkGray 
    }
}

# Files with 0 used constants
$zeroUsedFiles = $fileStats | Where-Object { $_.UsedCount -eq 0 }
if ($zeroUsedFiles.Count -gt 0) {
    Write-Host "`n📁 Files with 0 used constants:" -ForegroundColor DarkCyan
    $displayCount = [Math]::Min($zeroUsedFiles.Count, 5)  # Reduced for automation
    $zeroUsedFiles | Select-Object -First $displayCount | ForEach-Object { 
        Write-Host "   • $($_.FileName)" -ForegroundColor Red 
    }
    if ($zeroUsedFiles.Count -gt $displayCount) {
        $remaining = $zeroUsedFiles.Count - $displayCount
        Write-Host "   ... and $remaining more files with 0 used constants" -ForegroundColor DarkGray
    }
}

# AllConstants.cs analysis
$allConstantsFile = $fileStats | Where-Object { $_.FileName -match "AllConstants.cs" }
if ($allConstantsFile) {
    if ($allConstantsFile.UsedCount -eq 0) {
        Write-Host "`n📄 AllConstants.cs: $($allConstantsFile.ConstantCount) constants, $($allConstantsFile.UsedCount) used" -ForegroundColor Red
        Write-Host "   Note: AllConstants.cs may be a holding file or contains unused/duplicated constants." -ForegroundColor Red
    } else {
        Write-Host "`n📄 AllConstants.cs: $($allConstantsFile.ConstantCount) constants, $($allConstantsFile.UsedCount) used" -ForegroundColor DarkYellow
    }
}

# Quick recommendations
Write-Host "`n💡 Recommendations:" -ForegroundColor DarkCyan
if ($unusedNames.Count -gt 10) {
    Write-Host "   🚨 HIGH: $($unusedNames.Count) unused constants detected" -ForegroundColor Red
    Write-Host "   • Review and remove unused constants to reduce code bloat" -ForegroundColor Red
} elseif ($unusedNames.Count -gt 0) {
    Write-Host "   ⚠️  $($unusedNames.Count) unused constants detected" -ForegroundColor DarkYellow
    Write-Host "   • Consider removing unused constants during refactoring" -ForegroundColor Gray
} else {
    Write-Host "   ✅ All constants are being used!" -ForegroundColor Green
}

if ($duplicateNames.Count -gt 0) {
    Write-Host "   🔄 $($duplicateNames.Count) duplicate constant names detected" -ForegroundColor DarkYellow
    Write-Host "   • Consider consolidating duplicate constants" -ForegroundColor Gray
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

# Generate detailed constants audit report using PowerShell 5.1 safe approach
Write-Host "`n📝 Generating detailed constants audit report..." -ForegroundColor DarkGray

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPath = Join-Path $reportsDir "CONSTANTS-AUDIT-REPORT_$timestamp.md"

# Build report using separate variables for PowerShell 5.1 compatibility
$reportTitle = "# Constants Audit Report"
$reportGenerated = "**Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportTotalConstants = "**Total Constants**: $($constants.Count)"
$reportFilesScanned = "**Files Scanned**: $(($constants | Select-Object -ExpandProperty File -Unique).Count)"
$reportCodeFilesAnalyzed = "**Code Files Analyzed**: $scannedFilesCount"

$reportContent = @()
$reportContent += $reportTitle
$reportContent += ""
$reportContent += $reportGenerated
$reportContent += $reportTotalConstants
$reportContent += $reportFilesScanned
$reportContent += $reportCodeFilesAnalyzed
$reportContent += ""

# Executive Summary
$reportContent += "## Executive Summary"
$reportContent += ""

$utilizationRate = if ($constants.Count -gt 0) { [Math]::Round((($constants.Count - $unusedNames.Count) / $constants.Count) * 100, 1) } else { 0 }

if ($unusedNames.Count -eq 0 -and $duplicateNames.Count -eq 0) {
    $reportContent += "🎉 **EXCELLENT CONSTANTS HYGIENE!** All constants are used and no duplicates detected."
    $reportContent += ""
    $reportContent += "Your constants demonstrate outstanding management practices."
} elseif ($unusedNames.Count -eq 0) {
    $reportContent += "✅ **GOOD UTILIZATION!** All constants are being used."
    $reportContent += ""
    $reportContent += "Consider addressing duplicate constants for improved maintainability."
} elseif ($utilizationRate -ge 80) {
    $reportContent += "✅ **GOOD UTILIZATION!** Over 80% of constants are actively used."
    $reportContent += ""
    $reportContent += "Consider reviewing unused constants for potential cleanup."
} else {
    $reportContent += "⚠️ **MODERATE UTILIZATION** - $utilizationRate% of constants are actively used."
    $reportContent += ""
    $reportContent += "**Recommendation**: Review and clean up unused constants to reduce code bloat."
}

$reportContent += ""
$reportContent += "| Metric | Value | Status |"
$reportContent += "|--------|-------|--------|"
$reportContent += "| **Total Constants** | $($constants.Count) | - |"
$reportContent += "| **Used Constants** | $(($constants.Count - $unusedNames.Count)) | $(if ($unusedNames.Count -eq 0) { "✅ Excellent" } elseif ($utilizationRate -ge 80) { "✅ Good" } else { "⚠️ Needs Review" }) |"
$reportContent += "| **Unused Constants** | $($unusedNames.Count) | $(if ($unusedNames.Count -eq 0) { "✅ None" } elseif ($unusedNames.Count -le 5) { "⚠️ Few" } else { "🚨 Many" }) |"
$reportContent += "| **Duplicate Names** | $($duplicateNames.Count) | $(if ($duplicateNames.Count -eq 0) { "✅ None" } elseif ($duplicateNames.Count -le 3) { "⚠️ Few" } else { "🚨 Many" }) |"
$reportContent += "| **Utilization Rate** | $utilizationRate% | $(if ($utilizationRate -ge 90) { "🎉 Excellent" } elseif ($utilizationRate -ge 80) { "✅ Good" } elseif ($utilizationRate -ge 60) { "⚠️ Moderate" } else { "🚨 Poor" }) |"
$reportContent += ""

# Constants by File
$reportContent += "## Constants by File"
$reportContent += ""
$reportContent += "| File | Total | Used | Unused | Utilization |"
$reportContent += "|------|-------|------|--------|-------------|"

foreach ($fileStat in $fileStats | Sort-Object ConstantCount -Descending) {
    $status = if ($fileStat.PercentUsed -eq 100) { "🎉" } elseif ($fileStat.PercentUsed -ge 80) { "✅" } elseif ($fileStat.PercentUsed -ge 50) { "⚠️" } else { "🚨" }
    $unused = $fileStat.ConstantCount - $fileStat.UsedCount
    $reportContent += "| `$($fileStat.FileName)` | $($fileStat.ConstantCount) | $($fileStat.UsedCount) | $unused | $status $($fileStat.PercentUsed)% |"
}

$reportContent += ""

# Unused Constants Analysis
if ($unusedNames.Count -gt 0) {
    $reportContent += "## Unused Constants"
    $reportContent += ""
    $reportContent += "The following $($unusedNames.Count) constants are declared but never used:"
    $reportContent += ""
    
    # Group unused constants by file
    $unusedByFile = $constants | Where-Object { $unusedNames -contains $_.Name } | Group-Object FileName | Sort-Object Name
    
    foreach ($fileGroup in $unusedByFile) {
        $reportContent += "### $($fileGroup.Name)"
        $reportContent += ""
        
        foreach ($constant in $fileGroup.Group | Sort-Object Name) {
            $reportContent += "- **$($constant.Name)** ($($constant.Type)) - Line $($constant.LineNumber)"
        }
        $reportContent += ""
    }
    
    $reportContent += "### Cleanup Recommendations"
    $reportContent += ""
    if ($unusedNames.Count -gt 20) {
        $reportContent += "🚨 **High Priority**: $($unusedNames.Count) unused constants detected."
        $reportContent += ""
        $reportContent += "1. **Immediate Action**: Review constants for removal"
        $reportContent += "2. **Impact Assessment**: Verify constants aren't used in external modules"
        $reportContent += "3. **Gradual Cleanup**: Remove in batches to avoid merge conflicts"
    } else {
        $reportContent += "⚠️ **Standard Cleanup**: $($unusedNames.Count) unused constants detected."
        $reportContent += ""
        $reportContent += "1. **Code Review**: Verify these constants are truly unused"
        $reportContent += "2. **Safe Removal**: Remove during next refactoring cycle"
        $reportContent += "3. **Documentation**: Update any references in comments/docs"
    }
    $reportContent += ""
}

# Duplicate Constants Analysis
if ($duplicateNames.Count -gt 0) {
    $reportContent += "## Duplicate Constants"
    $reportContent += ""
    $reportContent += "The following constants have duplicate names across files:"
    $reportContent += ""
    
    $reportContent += "| Constant Name | Occurrences | Files |"
    $reportContent += "|---------------|-------------|-------|"
    
    foreach ($dupGroup in $dupGroups | Sort-Object Count -Descending) {
        $files = ($dupGroup.Group | Select-Object -ExpandProperty FileName | Sort-Object -Unique) -join ", "
        $reportContent += "| `$($dupGroup.Name)` | $($dupGroup.Count) | $files |"
    }
    
    $reportContent += ""
    $reportContent += "### Deduplication Recommendations"
    $reportContent += ""
    $reportContent += "1. **Review Values**: Ensure duplicate constants have identical values"
    $reportContent += "2. **Choose Primary**: Select one file to contain each constant"
    $reportContent += "3. **Update References**: Modify usages to reference the primary location"
    $reportContent += "4. **Remove Duplicates**: Delete redundant constant declarations"
    $reportContent += ""
}

# High Usage Constants
if ($usages.Count -gt 0) {
    $reportContent += "## High Usage Constants"
    $reportContent += ""
    
    $usageStats = $usages | Group-Object Name | Sort-Object Count -Descending | Select-Object -First 10
    
    if ($usageStats.Count -gt 0) {
        $reportContent += "Constants with the highest usage across the codebase:"
        $reportContent += ""
        $reportContent += "| Constant | Usage Count | Example Files |"
        $reportContent += "|----------|-------------|---------------|"
        
        foreach ($usage in $usageStats) {
            $exampleFiles = ($usage.Group | Select-Object -ExpandProperty FileName -Unique | Select-Object -First 3) -join ", "
            if ($usage.Group.Count -gt 3) {
                $exampleFiles += ", ..."
            }
            $reportContent += "| `$($usage.Name)` | $($usage.Count) | $exampleFiles |"
        }
        $reportContent += ""
    }
}

# Low Usage Files
$lowUsageFiles = $fileStats | Where-Object { $_.PercentUsed -lt 50 -and $_.ConstantCount -gt 1 }
if ($lowUsageFiles.Count -gt 0) {
    $reportContent += "## Low Utilization Files"
    $reportContent += ""
    $reportContent += "Files with less than 50% constant utilization:"
    $reportContent += ""
    
    foreach ($file in $lowUsageFiles | Sort-Object PercentUsed) {
        $reportContent += "### $($file.FileName)"
        $reportContent += ""
        $reportContent += "- **Total Constants**: $($file.ConstantCount)"
        $reportContent += "- **Used Constants**: $($file.UsedCount)"
        $reportContent += "- **Utilization**: $($file.PercentUsed)%"
        $reportContent += ""
        $reportContent += "**Recommendation**: Review this file for potential cleanup opportunities."
        $reportContent += ""
    }
}

# Action Plan - FIXED VARIABLE REFERENCE ISSUES
$reportContent += "## Action Plan"
$reportContent += ""

if ($unusedNames.Count -eq 0 -and $duplicateNames.Count -eq 0) {
    $reportContent += "### ✅ Maintenance Mode"
    $reportContent += ""
    $reportContent += "Excellent work! Your constants are well-managed. Focus on:"
    $reportContent += ""
    $reportContent += "1. **Regular Audits**: Run this analysis periodically"
    $reportContent += "2. **New Constant Guidelines**: Ensure new constants follow naming conventions"
    $reportContent += "3. **Documentation**: Keep constant purposes well-documented"
    $reportContent += "4. **Usage Tracking**: Monitor for constants becoming unused over time"
} else {
    $reportContent += "### Priority Actions"
    $reportContent += ""
    
    if ($unusedNames.Count -gt 0) {
        # FIXED: Separated priority variable creation for PowerShell 5.1 compatibility
        $priorityLevel = if ($unusedNames.Count -gt 20) { "🚨 HIGH" } elseif ($unusedNames.Count -gt 10) { "⚠️ MEDIUM" } else { "📝 LOW" }
        $prioritySection = "#### $priorityLevel - Remove Unused Constants"
        $reportContent += $prioritySection
        $reportContent += ""
        $reportContent += "**$($unusedNames.Count) unused constants** should be reviewed for removal:"
        $reportContent += ""
        $reportContent += "1. **Verify**: Confirm constants aren't used in external modules or config files"
        $reportContent += "2. **Document**: Note reasons for removal in commit messages"
        $reportContent += "3. **Remove**: Delete unused constant declarations"
        $reportContent += "4. **Test**: Ensure removal doesn't break compilation or runtime"
        $reportContent += ""
    }
    
    if ($duplicateNames.Count -gt 0) {
        # FIXED: Separated priority variable creation for PowerShell 5.1 compatibility
        $priorityLevel = if ($duplicateNames.Count -gt 10) { "⚠️ MEDIUM" } else { "📝 LOW" }
        $prioritySection = "#### $priorityLevel - Consolidate Duplicate Constants"
        $reportContent += $prioritySection
        $reportContent += ""
        $reportContent += "**$($duplicateNames.Count) duplicate constant names** detected:"
        $reportContent += ""
        $reportContent += "1. **Audit Values**: Ensure duplicates have identical values"
        $reportContent += "2. **Choose Primary**: Select one authoritative location per constant"
        $reportContent += "3. **Update References**: Modify code to use primary constant location"
        $reportContent += "4. **Remove Duplicates**: Delete redundant declarations"
        $reportContent += ""
    }
    
    $reportContent += "### Best Practices"
    $reportContent += ""
    $reportContent += "1. **Naming Conventions**: Use descriptive, consistent constant names"
    $reportContent += "2. **Organization**: Group related constants in appropriate files"
    $reportContent += "3. **Documentation**: Add comments explaining constant purposes"
    $reportContent += "4. **Regular Audits**: Run this analysis before major releases"
    $reportContent += "5. **Usage Verification**: Ensure new constants are actually used"
}

# Technical Details
$reportContent += ""
$reportContent += "## Technical Analysis Details"
$reportContent += ""
$reportContent += "### Scan Coverage"
$reportContent += ""
$reportContent += "- **Constants Files**: $(($constants | Select-Object -ExpandProperty File -Unique).Count) files"
$reportContent += "- **Usage Files**: $scannedFilesCount files"
$reportContent += "- **Total Constants**: $($constants.Count)"
$reportContent += "- **Total Usage References**: $($usages.Count)"
$reportContent += ""
$reportContent += "### Exclusions"
$reportContent += ""
$reportContent += "The following directories were excluded from analysis:"
$reportContent += "- ForCopilot/ - GitHub Copilot instruction files"
$reportContent += "- Scripts/ - DevOps and build scripts"
$reportContent += "- Legacy/ - Deprecated code"
$reportContent += ""
$reportContent += "### Detection Patterns"
$reportContent += ""
$reportContent += "- Constants: public const Type NAME = value"
$reportContent += "- Usage: Word boundary matches in non-constant files"
$reportContent += "- Files: Constants.cs and files in Constants/ directory"

# Footer
$reportContent += ""
$reportContent += "---"
$reportContent += ""
$reportContent += "**Utilization Target**: 85%+ for well-maintained codebases"
$reportContent += ""
$reportContent += "*Generated by MixerThreholdMod DevOps Suite - Constants Audit Generator*"

try {
    $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
    $saveSuccess = $true
}
catch {
    Write-Host "⚠️ Error saving detailed report: $_" -ForegroundColor DarkYellow
    $saveSuccess = $false
}

Write-Host "`n🚀 Constants audit complete!" -ForegroundColor Green

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
        Write-Host "   R - Re-run constants audit analysis" -ForegroundColor DarkYellow
        Write-Host "   X - Exit to DevOps menu" -ForegroundColor Gray
        
        $choice = Read-Host "`nEnter choice (D/R/X)"
        $choice = $choice.ToUpper()
        
        switch ($choice) {
            'D' {
                if ($saveSuccess) {
                    Write-Host "`n📋 DISPLAYING CONSTANTS AUDIT REPORT:" -ForegroundColor DarkCyan
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
                Write-Host "`n🔄 RE-RUNNING CONSTANTS AUDIT ANALYSIS..." -ForegroundColor DarkYellow
                Write-Host "========================================" -ForegroundColor DarkYellow
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