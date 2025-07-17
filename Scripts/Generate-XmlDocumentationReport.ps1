# MixerThreholdMod DevOps Tool: XML Documentation Verifier (NON-INTERACTIVE)
# Ensures all public methods, classes, and properties have proper XML documentation
# Validates XML documentation quality and completeness
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

Write-Host "🕐 XML documentation verification started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "Verifying XML documentation in: $ProjectRoot" -ForegroundColor DarkCyan
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

# Function to extract public members and their documentation (optimized)
function Get-PublicMembers {
    param($filePath)
    
    try {
        $content = Get-Content -Path $filePath -Raw -ErrorAction Stop
        if (-not $content -or $content.Length -lt 100) { return @() }
        
        $lines = Get-Content -Path $filePath -ErrorAction Stop
        $members = @()
        
        # Simplified patterns for better performance
        $patterns = @{
            'Class' = '(?m)^\s*public\s+(?:static\s+|abstract\s+|sealed\s+)*class\s+([A-Za-z0-9_<>]+)'
            'Method' = '(?m)^\s*public\s+(?:static\s+|virtual\s+|override\s+|async\s+)*(?:Task<[^>]+>|Task|void|[A-Za-z0-9_<>\[\]]+)\s+([A-Za-z0-9_]+)\s*\([^)]*\)'
            'Property' = '(?m)^\s*public\s+(?:static\s+)*([A-Za-z0-9_<>\[\]]+)\s+([A-Za-z0-9_]+)\s*\{\s*(?:get|set)'
        }
        
        foreach ($type in $patterns.Keys) {
            $matches = [regex]::Matches($content, $patterns[$type], [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            
            foreach ($match in $matches) {
                $memberName = if ($type -eq 'Class') { $match.Groups[1].Value } else { $match.Groups[2].Value }
                $lineNumber = ($content.Substring(0, $match.Index) -split "`n").Count
                
                # Skip auto-generated and common members
                if ($memberName -match '^(get_|set_|add_|remove_)' -or 
                    $memberName -eq 'ToString' -or 
                    $memberName -eq 'GetHashCode' -or 
                    $memberName -eq 'Equals') {
                    continue
                }
                
                # Check for XML documentation above the member (simplified)
                $hasXmlDoc = $false
                $docQuality = "None"
                $docContent = ""
                
                # Look for XML documentation in preceding lines
                $startLine = [Math]::Max(0, $lineNumber - 5)
                for ($i = $lineNumber - 2; $i -ge $startLine; $i--) {
                    if ($i -ge 0 -and $i -lt $lines.Count) {
                        if ($lines[$i] -match '^\s*///') {
                            $hasXmlDoc = $true
                            $docQuality = "Basic"
                            $docContent = $lines[$i] -replace '^\s*///', '' | Select-Object -First 1
                            break
                        } elseif ($lines[$i] -match '^\s*$' -or $lines[$i] -match '^\s*\[') {
                            continue
                        } else {
                            break
                        }
                    }
                }
                
                $members += [PSCustomObject]@{
                    File = $filePath
                    Type = $type
                    Name = $memberName
                    LineNumber = $lineNumber
                    HasXmlDoc = $hasXmlDoc
                    DocQuality = $docQuality
                    DocContent = $docContent.Trim()
                }
            }
        }
        
        return $members
    }
    catch {
        Write-Host "⚠️  Error processing $(Split-Path $filePath -Leaf): $($_.Exception.Message)" -ForegroundColor DarkYellow
        return @()
    }
}

# Analyze all files with progress
Write-Host "`n🔍 Analyzing public members..." -ForegroundColor DarkCyan
$allMembers = @()
$processedFiles = 0
$totalFiles = $files.Count

foreach ($file in $files) {
    $processedFiles++
    
    # Show progress every 20 files
    if ($processedFiles % 20 -eq 0 -or $processedFiles -eq 1 -or $processedFiles -eq $totalFiles) {
        $percent = [Math]::Round(($processedFiles / $totalFiles) * 100, 1)
        Write-Host "   📈 Progress: $processedFiles/$totalFiles files ($percent%)" -ForegroundColor DarkGray
    }
    
    $members = Get-PublicMembers -filePath $file.FullName
    $allMembers += $members
}

Write-Host "`n=== XML DOCUMENTATION VERIFICATION REPORT ===" -ForegroundColor DarkCyan
Write-Host "🕐 Analysis completed: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "📊 Total public members analyzed: $($allMembers.Count)" -ForegroundColor Gray

if ($allMembers.Count -eq 0) {
    Write-Host "⚠️  No public members found for analysis" -ForegroundColor DarkYellow
} else {
    # Calculate statistics
    $documented = $allMembers | Where-Object { $_.HasXmlDoc }
    $undocumented = $allMembers | Where-Object { -not $_.HasXmlDoc }
    
    # Overall statistics
    Write-Host "`n📊 Documentation Coverage:" -ForegroundColor DarkCyan
    $coveragePercent = if ($allMembers.Count -gt 0) { [Math]::Round(($documented.Count / $allMembers.Count) * 100, 1) } else { 0 }
    Write-Host "   Overall coverage: $coveragePercent% ($($documented.Count)/$($allMembers.Count))" -ForegroundColor $(if ($coveragePercent -gt 80) { "Green" } elseif ($coveragePercent -gt 60) { "DarkYellow" } else { "Red" })
    Write-Host "   Undocumented members: $($undocumented.Count)" -ForegroundColor $(if ($undocumented.Count -eq 0) { "Green" } else { "Red" })
    
    # Documentation by member type
    Write-Host "`n📝 Documentation by Member Type:" -ForegroundColor DarkCyan
    $typeStats = $allMembers | Group-Object Type | Sort-Object Name
    
    foreach ($typeStat in $typeStats) {
        $typeDocumented = $typeStat.Group | Where-Object { $_.HasXmlDoc }
        $typePercent = if ($typeStat.Count -gt 0) { [Math]::Round(($typeDocumented.Count / $typeStat.Count) * 100, 1) } else { 0 }
        $color = if ($typePercent -gt 80) { "Green" } elseif ($typePercent -gt 60) { "DarkYellow" } else { "Red" }
        Write-Host "   $($typeStat.Name): $typePercent% ($($typeDocumented.Count)/$($typeStat.Count))" -ForegroundColor $color
    }
    
    # Show top undocumented members (limited for automation)
    if ($undocumented.Count -gt 0) {
        Write-Host "`n🚨 Top Undocumented Members (Priority Order):" -ForegroundColor DarkCyan
        
        # Prioritize: Classes first, then Methods, then Properties
        $priorityOrder = @('Class', 'Method', 'Property')
        $undocumentedSorted = @()
        
        foreach ($priority in $priorityOrder) {
            $undocumentedSorted += $undocumented | Where-Object { $_.Type -eq $priority } | Sort-Object File, Name
        }
        
        $showCount = [Math]::Min(10, $undocumentedSorted.Count)  # Reduced for automation
        for ($i = 0; $i -lt $showCount; $i++) {
            $member = $undocumentedSorted[$i]
            $fileName = [System.IO.Path]::GetFileName($member.File)
            $color = switch ($member.Type) {
                'Class' { "Red" }
                'Method' { "DarkYellow" }
                default { "Gray" }
            }
            Write-Host "   $($member.Type): $($member.Name) in $fileName (line $($member.LineNumber))" -ForegroundColor $color
        }
        
        if ($undocumentedSorted.Count -gt 10) {
            Write-Host "   ... and $($undocumentedSorted.Count - 10) more undocumented members" -ForegroundColor DarkGray
        }
    }
    
    # Quick recommendations
    Write-Host "`n💡 Recommendations:" -ForegroundColor DarkCyan
    if ($coveragePercent -lt 80) {
        Write-Host "   🚨 PRIORITY: Documentation coverage is below 80%" -ForegroundColor Red
        Write-Host "   • Focus on documenting Classes and Methods first" -ForegroundColor Red
    } else {
        Write-Host "   ✅ Good documentation coverage achieved!" -ForegroundColor Green
    }
    
    if ($undocumented.Count -gt 0) {
        $classesNeedingDocs = $undocumented | Where-Object { $_.Type -eq "Class" }
        $methodsNeedingDocs = $undocumented | Where-Object { $_.Type -eq "Method" }
        
        if ($classesNeedingDocs.Count -gt 0) {
            Write-Host "   • Document $($classesNeedingDocs.Count) public classes" -ForegroundColor DarkYellow
        }
        if ($methodsNeedingDocs.Count -gt 0) {
            Write-Host "   • Document $($methodsNeedingDocs.Count) public methods" -ForegroundColor DarkYellow
        }
    }
    
    Write-Host "   • Add thread safety warnings to concurrent code" -ForegroundColor Gray
    Write-Host "   • Note .NET 4.8.1 compatibility requirements" -ForegroundColor Gray
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

# Generate detailed XML documentation report using PowerShell 5.1 safe approach
Write-Host "`n📝 Generating detailed XML documentation report..." -ForegroundColor DarkGray

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPath = Join-Path $reportsDir "XML-DOCUMENTATION-REPORT_$timestamp.md"

# Build report using separate variables for PowerShell 5.1 compatibility
$reportTitle = "# XML Documentation Coverage Report"
$reportGenerated = "**Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportFilesAnalyzed = "**Files Analyzed**: $($files.Count)"
$reportMembersAnalyzed = "**Public Members Analyzed**: $($allMembers.Count)"
$reportOverallCoverage = "**Overall Coverage**: $coveragePercent%"

$reportSummaryTitle = "## Executive Summary"

$reportContent = @()
$reportContent += $reportTitle
$reportContent += ""
$reportContent += $reportGenerated
$reportContent += $reportFilesAnalyzed
$reportContent += $reportMembersAnalyzed
$reportContent += $reportOverallCoverage
$reportContent += ""
$reportContent += $reportSummaryTitle
$reportContent += ""

if ($allMembers.Count -eq 0) {
    $reportContent += "⚠️ **No public members found** for XML documentation analysis."
    $reportContent += ""
    $reportContent += "This could indicate:"
    $reportContent += "- Codebase uses internal/private visibility extensively"
    $reportContent += "- Analysis patterns need adjustment for this codebase"
    $reportContent += "- Files may not contain standard C# class definitions"
} else {
    $reportContent += "**Documentation Status**: $($documented.Count) of $($allMembers.Count) public members documented"
    $reportContent += ""
    
    # Coverage assessment
    if ($coveragePercent -ge 90) {
        $reportContent += "🎉 **EXCELLENT COVERAGE!** Over 90% of public members are documented."
        $reportContent += ""
        $reportContent += "Your codebase demonstrates outstanding documentation practices."
    } elseif ($coveragePercent -ge 80) {
        $reportContent += "✅ **GOOD COVERAGE!** Over 80% of public members are documented."
        $reportContent += ""
        $reportContent += "Continue improving to reach 90%+ coverage for exceptional standards."
    } elseif ($coveragePercent -ge 60) {
        $reportContent += "⚠️ **MODERATE COVERAGE** - 60-80% of public members documented."
        $reportContent += ""
        $reportContent += "**Recommendation**: Focus on documenting critical public APIs first."
    } else {
        $reportContent += "🚨 **LOW COVERAGE** - Less than 60% of public members documented."
        $reportContent += ""
        $reportContent += "**Immediate Action Required**: Prioritize documentation for maintainability."
    }
    
    $reportContent += ""
    $reportContent += "| Metric | Value |"
    $reportContent += "|--------|-------|"
    $reportContent += "| **Overall Coverage** | $coveragePercent% |"
    $reportContent += "| **Documented Members** | $($documented.Count) |"
    $reportContent += "| **Undocumented Members** | $($undocumented.Count) |"
    $reportContent += "| **Files with Public APIs** | $(($allMembers | Group-Object File).Count) |"
    
    # Coverage by member type
    if ($typeStats.Count -gt 0) {
        $reportContent += ""
        $reportContent += "### Coverage by Member Type"
        $reportContent += ""
        $reportContent += "| Member Type | Documented | Total | Coverage |"
        $reportContent += "|-------------|------------|-------|----------|"
        
        foreach ($typeStat in $typeStats) {
            $typeDocumented = $typeStat.Group | Where-Object { $_.HasXmlDoc }
            $typePercent = if ($typeStat.Count -gt 0) { [Math]::Round(($typeDocumented.Count / $typeStat.Count) * 100, 1) } else { 0 }
            $reportContent += "| $($typeStat.Name) | $($typeDocumented.Count) | $($typeStat.Count) | $typePercent% |"
        }
    }
}

$reportContent += ""

# Detailed Analysis
if ($undocumented.Count -gt 0) {
    $reportContent += "## Undocumented Public Members"
    $reportContent += ""
    $reportContent += "The following public members require XML documentation:"
    $reportContent += ""
    
    # Group by file for better organization
    $fileGroups = $undocumented | Group-Object { [System.IO.Path]::GetFileName($_.File) } | Sort-Object Name
    
    foreach ($fileGroup in $fileGroups | Select-Object -First 20) {
        $reportContent += "### $($fileGroup.Name)"
        $reportContent += ""
        
        # Group by type within file
        $typeGroups = $fileGroup.Group | Group-Object Type | Sort-Object @{Expression={
            switch ($_.Name) {
                "Class" { 1 }
                "Method" { 2 }
                "Property" { 3 }
                default { 4 }
            }
        }}
        
        foreach ($typeGroup in $typeGroups) {
            if ($typeGroup.Group.Count -gt 0) {
                $reportContent += "#### $($typeGroup.Name)s"
                $reportContent += ""
                
                foreach ($member in $typeGroup.Group | Sort-Object Name) {
                    $priority = switch ($member.Type) {
                        "Class" { "🚨 HIGH" }
                        "Method" { "⚠️ MEDIUM" }
                        default { "📝 LOW" }
                    }
                    $reportContent += "- **$($member.Name)** (Line $($member.LineNumber)) - $priority"
                }
                $reportContent += ""
            }
        }
    }
    
    if ($fileGroups.Count -gt 20) {
        $reportContent += "*... and $(($fileGroups.Count - 20) * ($fileGroups | Select-Object -Skip 20 | ForEach-Object { $_.Group.Count } | Measure-Object -Sum).Sum) more undocumented members in $($fileGroups.Count - 20) additional files*"
        $reportContent += ""
    }
}

# Well-Documented Examples
if ($documented.Count -gt 0) {
    $reportContent += "## Well-Documented Examples"
    $reportContent += ""
    
    $wellDocumentedFiles = $documented | Group-Object { [System.IO.Path]::GetFileName($_.File) } | 
                          Where-Object { $_.Count -gt 2 } | 
                          Sort-Object Count -Descending | 
                          Select-Object -First 5
    
    if ($wellDocumentedFiles.Count -gt 0) {
        $reportContent += "### Files with Good Documentation Coverage"
        $reportContent += ""
        $reportContent += "| File | Documented Members | Examples |"
        $reportContent += "|------|-------------------|----------|"
        
        foreach ($fileGroup in $wellDocumentedFiles) {
            $examples = ($fileGroup.Group | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ", "
            $reportContent += "| `$($fileGroup.Name)` | $($fileGroup.Count) | $examples |"
        }
        $reportContent += ""
    }
}

# Action Plan
$reportContent += "## Documentation Action Plan"
$reportContent += ""

if ($undocumented.Count -eq 0) {
    $reportContent += "### ✅ Maintenance Mode"
    $reportContent += ""
    $reportContent += "Excellent work! All public members are documented. Focus on:"
    $reportContent += ""
    $reportContent += "1. **Quality Review**: Ensure documentation describes thread safety"
    $reportContent += "2. **Consistency Check**: Verify .NET 4.8.1 compatibility notes"
    $reportContent += "3. **Usage Examples**: Add code examples for complex APIs"
    $reportContent += "4. **Maintenance**: Keep documentation updated with code changes"
} else {
    $reportContent += "### Priority Actions"
    $reportContent += ""
    
    # High priority items
    $classesNeedingDocs = $undocumented | Where-Object { $_.Type -eq "Class" }
    if ($classesNeedingDocs.Count -gt 0) {
        $reportContent += "#### 🚨 HIGH PRIORITY: Document Public Classes"
        $reportContent += ""
        $reportContent += "**$($classesNeedingDocs.Count) public classes** need documentation:"
        $reportContent += ""
        foreach ($class in $classesNeedingDocs | Select-Object -First 10) {
            $fileName = [System.IO.Path]::GetFileName($class.File)
            $reportContent += "- **$($class.Name)** in `$fileName` (Line $($class.LineNumber))"
        }
        if ($classesNeedingDocs.Count -gt 10) {
            $reportContent += "- ... and $($classesNeedingDocs.Count - 10) more classes"
        }
        $reportContent += ""
    }
    
    # Medium priority items
    $methodsNeedingDocs = $undocumented | Where-Object { $_.Type -eq "Method" }
    if ($methodsNeedingDocs.Count -gt 0) {
        $reportContent += "#### ⚠️ MEDIUM PRIORITY: Document Public Methods"
        $reportContent += ""
        $reportContent += "**$($methodsNeedingDocs.Count) public methods** need documentation:"
        $reportContent += ""
        
        # Group by file and show top files
        $methodFileGroups = $methodsNeedingDocs | Group-Object { [System.IO.Path]::GetFileName($_.File) } | 
                           Sort-Object Count -Descending | Select-Object -First 5
        
        foreach ($fileGroup in $methodFileGroups) {
            $reportContent += "- **$($fileGroup.Name)**: $($fileGroup.Count) undocumented methods"
        }
        $reportContent += ""
    }
    
    # Documentation standards - COMPLETELY SAFE APPROACH
    $reportContent += "### Documentation Standards for MixerThreholdMod"
    $reportContent += ""
    $reportContent += "Include these elements in XML documentation:"
    $reportContent += ""
    $reportContent += "1. **Purpose**: What the member does"
    $reportContent += "2. **Thread Safety**: Specify if thread-safe or Unity main thread only"
    $reportContent += "3. **Parameters**: Document all parameters with types and constraints"
    $reportContent += "4. **Return Values**: Describe return value meaning and possible values"
    $reportContent += "5. **Exceptions**: Document thrown exceptions and conditions"
    $reportContent += "6. **Compatibility**: Note .NET 4.8.1 or IL2CPP specific requirements"
    $reportContent += ""
    
    # REMOVED COMPLEX XML DOCUMENTATION EXAMPLE ENTIRELY
    $reportContent += "### Documentation Guidelines"
    $reportContent += ""
    $reportContent += "**Best Practices for MixerThreholdMod XML Documentation:**"
    $reportContent += ""
    $reportContent += "- Use summary tags to describe the purpose of each member"
    $reportContent += "- Document all parameters with param tags including type constraints"
    $reportContent += "- Include returns tags for methods that return values"
    $reportContent += "- Add exception tags for potential exceptions"
    $reportContent += "- Use remarks tags for thread safety and compatibility notes"
    $reportContent += "- Always specify .NET 4.8.1 compatibility requirements"
    $reportContent += "- Include Unity main thread warnings where applicable"
    $reportContent += ""
}

# Technical Details
$reportContent += ""
$reportContent += "## Technical Analysis Details"
$reportContent += ""
$reportContent += "### Detection Patterns"
$reportContent += ""
$reportContent += "This analysis detected the following member types:"
$reportContent += ""
$reportContent += "- Classes: public class ClassName"
$reportContent += "- Methods: public ReturnType MethodName(parameters)"
$reportContent += "- Properties: public Type PropertyName { get; set; }"
$reportContent += ""
$reportContent += "### Exclusions"
$reportContent += ""
$reportContent += "The following were excluded from analysis:"
$reportContent += ""
$reportContent += "- Auto-generated accessors (get_, set_, add_, remove_)"
$reportContent += "- Standard Object overrides (ToString, GetHashCode, Equals)"
$reportContent += "- ForCopilot, Scripts, and Legacy directories"
$reportContent += "- Private and internal members"

# Footer
$reportContent += ""
$reportContent += "---"
$reportContent += ""
$reportContent += "**Coverage Target**: 90%+ for exceptional documentation standards"
$reportContent += ""
$reportContent += "*Generated by MixerThreholdMod DevOps Suite - XML Documentation Verifier*"

try {
    $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
    $saveSuccess = $true
}
catch {
    Write-Host "⚠️ Error saving detailed report: $_" -ForegroundColor DarkYellow
    $saveSuccess = $false
}

Write-Host "`n🚀 XML documentation verification complete!" -ForegroundColor Green

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
        Write-Host "   R - Re-run XML documentation analysis" -ForegroundColor DarkYellow
        Write-Host "   X - Exit to DevOps menu" -ForegroundColor Gray
        
        $choice = Read-Host "`nEnter choice (D/R/X)"
        $choice = $choice.ToUpper()
        
        switch ($choice) {
            'D' {
                if ($saveSuccess) {
                    Write-Host "`n📋 DISPLAYING XML DOCUMENTATION REPORT:" -ForegroundColor DarkCyan
                    Write-Host "=======================================" -ForegroundColor DarkCyan
                    try {
                        $reportDisplay = Get-Content -Path $reportPath -Raw
                        Write-Host $reportDisplay -ForegroundColor White
                        Write-Host "`n=======================================" -ForegroundColor DarkCyan
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
                Write-Host "`n🔄 RE-RUNNING XML DOCUMENTATION ANALYSIS..." -ForegroundColor DarkYellow
                Write-Host "==========================================" -ForegroundColor DarkYellow
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
    Write-Host "XML documentation analysis completed successfully" -ForegroundColor DarkGray
}