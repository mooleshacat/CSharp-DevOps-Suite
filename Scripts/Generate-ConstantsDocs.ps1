# MixerThreholdMod DevOps Tool: Constants Documentation Generator (NON-INTERACTIVE)
# Auto-generates markdown documentation for all constants in the project
# Creates a comprehensive reference guide with categorization and usage examples
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

Write-Host "🕐 Constants documentation started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "Generating constants documentation for: $ProjectRoot" -ForegroundColor DarkCyan
Write-Host "🚀 NON-INTERACTIVE VERSION - Compatible with automation" -ForegroundColor Green
Write-Host "Excluding: ForCopilot, Scripts, and Legacy directories" -ForegroundColor DarkGray

# Function to get constant declarations with documentation (optimized)
function Get-ConstantDeclarations {
    param([string]$Path)
    
    try {
        $constantFiles = @()
        
        # Find constants files with CORRECTED exclusions
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
                $content = Get-Content -Path $file -Raw -ErrorAction Stop
                $lines = Get-Content -Path $file -ErrorAction Stop
                
                # Find constants with simplified regex
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    if ($lines[$i] -match 'public\s+const\s+(\w+)\s+(\w+)\s*=\s*(.+);') {
                        $type = $matches[1]
                        $name = $matches[2]
                        $value = $matches[3].Trim()
                        
                        # Look for documentation above (simplified)
                        $documentation = ""
                        $j = $i - 1
                        
                        # Check for XML documentation or comments
                        while ($j -ge 0 -and $j -gt ($i - 5) -and ($lines[$j] -match '^\s*///' -or $lines[$j] -match '^\s*//' -or $lines[$j] -match '^\s*$')) {
                            if ($lines[$j] -match '^\s*///?\s*(.*)') {
                                $docLine = $matches[1].Trim()
                                if ($docLine -and $docLine -notmatch '^</?summary>') {
                                    $documentation = $docLine + " " + $documentation
                                }
                            }
                            $j--
                        }
                        
                        $documentation = $documentation.Trim()
                        
                        # Categorize by file name
                        $category = "General"
                        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file)
                        if ($fileName -match "(\w+)Constants") {
                            $category = $matches[1]
                        } elseif ($fileName -eq "Constants") {
                            $category = "Core"
                        }
                        
                        $declarations += [PSCustomObject]@{
                            File = $file
                            FileName = [System.IO.Path]::GetFileName($file)
                            Category = $category
                            Type = $type
                            Name = $name
                            Value = $value
                            Documentation = $documentation
                            LineNumber = $i + 1
                        }
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

# Function to find constant usages (simplified for automation)
function Get-ConstantUsages {
    param([string]$constantName, [string]$Path)
    
    try {
        $usages = @()
        $files = Get-ChildItem -Path $Path -Recurse -Include *.cs -ErrorAction SilentlyContinue | Where-Object {
            $_.PSIsContainer -eq $false -and
            $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy|Constants)[\\/]" -and
            $_.Name -ne "Constants.cs"
        } | Select-Object -First 20  # Limit for performance
        
        foreach ($file in $files) {
            $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
            if ($content -and $content -match "\b$constantName\b") {
                $lines = $content -split "``n"
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    if ($lines[$i] -match "\b$constantName\b" -and $lines[$i] -notmatch "public\s+const") {
                        $usages += [PSCustomObject]@{
                            File = [System.IO.Path]::GetFileName($file.FullName)
                            LineNumber = $i + 1
                            Context = $lines[$i].Trim()
                        }
                        
                        if ($usages.Count -ge 2) { break }  # Limit for automation
                    }
                }
                if ($usages.Count -ge 2) { break }
            }
        }
        
        return $usages
    }
    catch {
        return @()
    }
}

Write-Host "``n📂 Scanning for constants..." -ForegroundColor DarkGray
$constants = Get-ConstantDeclarations -Path $ProjectRoot

Write-Host "📊 Found $($constants.Count) constants in $(($constants | Select-Object -ExpandProperty File -Unique).Count) files" -ForegroundColor Gray

if ($constants.Count -eq 0) {
    Write-Host "⚠️  No constants found for documentation" -ForegroundColor DarkYellow
    if ($IsInteractive -and -not $RunningFromScript) {
        Write-Host "``nPress ENTER to continue..." -ForegroundColor Gray -NoNewline
        Read-Host
    }
    return
}

# Generate markdown documentation (streamlined)
$markdown = @"
# MixerThreholdMod Constants Reference

This document provides a comprehensive reference for all constants defined in the MixerThreholdMod project.

**Generated**: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")  
**Total Constants**: $($constants.Count)  
**Files Scanned**: $(($constants | Select-Object -ExpandProperty File -Unique).Count)

## Table of Contents

"@

# Get unique categories
$categories = $constants | Select-Object -ExpandProperty Category -Unique | Sort-Object

foreach ($category in $categories) {
    $categoryConstants = $constants | Where-Object { $_.Category -eq $category }
    $markdown += "- [$category Constants](#$($category.ToLower())-constants) ($($categoryConstants.Count) constants)``n"
}

$markdown += "``n---``n"

# Generate sections for each category
foreach ($category in $categories) {
    $categoryConstants = $constants | Where-Object { $_.Category -eq $category } | Sort-Object Name
    
    $markdown += "``n## $category Constants``n``n"
    
    # Group by file within category
    $fileGroups = $categoryConstants | Group-Object FileName
    
    foreach ($fileGroup in $fileGroups) {
        $markdown += "### $($fileGroup.Name)``n``n"
        $markdown += "| Constant | Type | Value | Description |``n"
        $markdown += "|----------|------|-------|-------------|``n"
        
        foreach ($const in $fileGroup.Group) {
            $value = $const.Value
            # Escape markdown special characters
            $value = $value -replace '\|', '\|' -replace '<', '&lt;' -replace '>', '&gt;'
            
            # Truncate long values
            if ($value.Length -gt 50) {
                $value = $value.Substring(0, 47) + "..."
            }
            
            $description = if ($const.Documentation) { $const.Documentation } else { "_No description_" }
            
            $markdown += "| ````$($const.Name)```` | $($const.Type) | ````$value```` | $description |``n"
        }
        
        $markdown += "``n"
    }
}

# Add usage statistics section (simplified)
$markdown += "``n## Usage Statistics``n``n"

# Constants by type
$markdown += "### Constants by Type``n``n"
$markdown += "| Type | Count | Percentage |``n"
$markdown += "|------|-------|------------|``n"

$typeStats = $constants | Group-Object Type | Sort-Object Count -Descending

foreach ($type in $typeStats) {
    $percentage = [Math]::Round(($type.Count / $constants.Count) * 100, 1)
    $markdown += "| $($type.Name) | $($type.Count) | $percentage% |``n"
}

# Add usage examples for important constants (limited for automation)
$markdown += "``n## Usage Examples``n``n"
$markdown += "Below are examples of how some key constants are used in the codebase:``n``n"

# Select a few important constants to show usage
$importantConstants = $constants | Where-Object { 
    $_.Name -match "MOD_NAME|MOD_VERSION|LOG_LEVEL|SAVE_FILENAME" 
} | Select-Object -First 3  # Reduced for automation

foreach ($const in $importantConstants) {
    Write-Host "   📋 Finding usages for $($const.Name)..." -ForegroundColor DarkGray
    $usages = Get-ConstantUsages -constantName $const.Name -Path $ProjectRoot
    
    if ($usages.Count -gt 0) {
        $markdown += "### $($const.Name)``n``n"
        $markdown += "**Definition**: ````$($const.Type) $($const.Name) = $($const.Value)````n``n"
        $markdown += "**Usage Examples**:``n" + '````````' + "``n"
        
        foreach ($usage in $usages) {
            $markdown += "// $($usage.File):$($usage.LineNumber)``n"
            $markdown += "$($usage.Context)``n``n"
        }
        $markdown += '````````' + "``n``n"
    }
}

# Add footer
$markdown += "``n---``n``n"
$markdown += "_This documentation was auto-generated by Generate-ConstantsDoc.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')_``n"

# Create Reports directory if it doesn't exist
$reportsDir = Join-Path $ProjectRoot "Reports"
if (-not (Test-Path $reportsDir)) {
    try {
        New-Item -Path $reportsDir -ItemType Directory -Force | Out-Null
        Write-Host "``n📁 Created Reports directory: $reportsDir" -ForegroundColor Green
    }
    catch {
        Write-Host "``n⚠️ Could not create Reports directory, using project root" -ForegroundColor DarkYellow
        $reportsDir = $ProjectRoot
    }
}

# Save both the traditional output and detailed report
$outputPath = Join-Path $ProjectRoot "Constants-Reference.md"

try {
    $markdown | Out-File -FilePath $outputPath -Encoding UTF8
    $savedSuccessfully = $true
}
catch {
    Write-Host "⚠️  Error saving documentation: $_" -ForegroundColor DarkYellow
    $savedSuccessfully = $false
}

# Generate detailed constants analysis report
Write-Host "``n📝 Generating detailed constants analysis report..." -ForegroundColor DarkGray

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPath = Join-Path $reportsDir "CONSTANTS-DOCUMENTATION-REPORT_$timestamp.md"

$reportContent = @()
$reportContent += "# Constants Documentation Analysis Report"
$reportContent += ""
$reportContent += "**Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportContent += "**Total Constants**: $($constants.Count)"
$reportContent += "**Files Processed**: $(($constants | Select-Object -ExpandProperty File -Unique).Count)"
$reportContent += "**Categories**: $($categories.Count)"
$reportContent += ""

# Executive Summary
$reportContent += "## Executive Summary"
$reportContent += ""

$constantsWithDocs = $constants | Where-Object { $_.Documentation }
$constantsWithoutDocs = $constants | Where-Object { -not $_.Documentation }
$docCoverage = if ($constants.Count -gt 0) { [Math]::Round(($constantsWithDocs.Count / $constants.Count) * 100, 1) } else { 0 }

$reportContent += "**Constants Documentation Coverage**: $docCoverage% ($($constantsWithDocs.Count)/$($constants.Count))"
$reportContent += ""

if ($docCoverage -ge 90) {
    $reportContent += "🎉 **EXCELLENT DOCUMENTATION!** Over 90% of constants are documented."
    $reportContent += ""
    $reportContent += "Your constants demonstrate outstanding documentation practices."
} elseif ($docCoverage -ge 75) {
    $reportContent += "✅ **GOOD DOCUMENTATION!** Over 75% of constants are documented."
    $reportContent += ""
    $reportContent += "Continue improving to reach 90%+ coverage for exceptional standards."
} elseif ($docCoverage -ge 50) {
    $reportContent += "⚠️ **MODERATE DOCUMENTATION** - 50-75% of constants documented."
    $reportContent += ""
    $reportContent += "**Recommendation**: Focus on documenting the most important constants first."
} else {
    $reportContent += "🚨 **LOW DOCUMENTATION** - Less than 50% of constants documented."
    $reportContent += ""
    $reportContent += "**Immediate Action Required**: Add documentation for maintainability."
}

$reportContent += ""
$reportContent += "| Metric | Value |"
$reportContent += "|--------|-------|"
$reportContent += "| **Total Constants** | $($constants.Count) |"
$reportContent += "| **Documented Constants** | $($constantsWithDocs.Count) |"
$reportContent += "| **Undocumented Constants** | $($constantsWithoutDocs.Count) |"
$reportContent += "| **Documentation Coverage** | $docCoverage% |"
$reportContent += "| **Categories** | $($categories.Count) |"
$reportContent += "| **Files** | $(($constants | Select-Object -ExpandProperty File -Unique).Count) |"
$reportContent += ""

# Constants by Category
$reportContent += "## Constants by Category"
$reportContent += ""
$reportContent += "| Category | Count | Documented | Coverage |"
$reportContent += "|----------|-------|------------|----------|"

foreach ($category in $categories) {
    $categoryConstants = $constants | Where-Object { $_.Category -eq $category }
    $categoryDocumented = $categoryConstants | Where-Object { $_.Documentation }
    $categoryCoverage = if ($categoryConstants.Count -gt 0) { [Math]::Round(($categoryDocumented.Count / $categoryConstants.Count) * 100, 1) } else { 0 }
    
    $reportContent += "| $category | $($categoryConstants.Count) | $($categoryDocumented.Count) | $categoryCoverage% |"
}

$reportContent += ""

# Constants by Type
$reportContent += "## Constants by Type"
$reportContent += ""
$reportContent += "| Type | Count | Percentage | Examples |"
$reportContent += "|------|-------|------------|----------|"

foreach ($type in $typeStats) {
    $percentage = [Math]::Round(($type.Count / $constants.Count) * 100, 1)
    $examples = ($type.Group | Select-Object -First 3 | ForEach-Object { $_.Name }) -join ", "
    $reportContent += "| $($type.Name) | $($type.Count) | $percentage% | $examples |"
}

$reportContent += ""

# Undocumented Constants (if any)
if ($constantsWithoutDocs.Count -gt 0) {
    $reportContent += "## Undocumented Constants"
    $reportContent += ""
    $reportContent += "The following constants require documentation:"
    $reportContent += ""
    
    # Group by category
    $undocumentedByCategory = $constantsWithoutDocs | Group-Object Category | Sort-Object Name
    
    foreach ($categoryGroup in $undocumentedByCategory) {
        $reportContent += "### $($categoryGroup.Name) Category"
        $reportContent += ""
        
        foreach ($const in $categoryGroup.Group | Sort-Object Name) {
            $reportContent += "- **$($const.Name)** ($($const.Type)) in ````$($const.FileName)```` (Line $($const.LineNumber))"
        }
        $reportContent += ""
    }
}

# Well-Documented Examples
if ($constantsWithDocs.Count -gt 0) {
    $reportContent += "## Well-Documented Constants Examples"
    $reportContent += ""
    
    $wellDocumented = $constantsWithDocs | Where-Object { $_.Documentation.Length -gt 10 } | 
                      Sort-Object { $_.Documentation.Length } -Descending | 
                      Select-Object -First 5
    
    if ($wellDocumented.Count -gt 0) {
        $reportContent += "### Examples of Good Documentation"
        $reportContent += ""
        
        foreach ($const in $wellDocumented) {
            $reportContent += "#### $($const.Name)"
            $reportContent += ""
            $reportContent += "````````csharp"
            $reportContent += "// $($const.Documentation)"
            $constantDeclaration = "public const $($const.Type) $($const.Name) = $($const.Value);"
            $reportContent += $constantDeclaration
            $reportContent += "````````"
            $reportContent += ""
        }
    }
}

# Generated Documentation Files
$reportContent += "## Generated Documentation"
$reportContent += ""

if ($savedSuccessfully) {
    $reportContent += "### Primary Documentation"
    $reportContent += ""
    $reportContent += "- **Constants-Reference.md**: Complete constants reference with categories and usage examples"
    $reportContent += "  - Location: Project root directory"
    $reportContent += "  - Purpose: Developer reference and onboarding"
    $reportContent += "  - Contains: All $($constants.Count) constants organized by category"
    $reportContent += ""
} else {
    $reportContent += "⚠️ **Documentation Generation Failed**: Could not save Constants-Reference.md"
    $reportContent += ""
}

# Action Plan
$reportContent += "## 🎯 Action Plan"
$reportContent += ""

if ($constantsWithoutDocs.Count -eq 0) {
    $reportContent += "### ✅ Maintenance Mode"
    $reportContent += ""
    $reportContent += "Excellent work! All constants are documented. Focus on:"
    $reportContent += ""
    $reportContent += "1. **Quality Review**: Ensure documentation is clear and accurate"
    $reportContent += "2. **Consistency**: Verify consistent documentation style"
    $reportContent += "3. **Usage Examples**: Add examples for complex constants"
    $reportContent += "4. **Maintenance**: Keep documentation updated with constant changes"
} else {
    $reportContent += "### Documentation Priorities"
    $reportContent += ""
    
    if ($constantsWithoutDocs.Count -gt 0) {
        $reportContent += "#### 📝 Add Documentation"
        $reportContent += ""
        $reportContent += "**$($constantsWithoutDocs.Count) constants** need documentation. Priority order:"
        $reportContent += ""
        
        # Prioritize by category importance
        $categoryPriority = @{
            "Core" = 1
            "Mod" = 2
            "System" = 2
            "Error" = 3
            "Logging" = 3
        }
        
        $prioritizedCategories = $categories | Sort-Object {
            $priority = $categoryPriority[$_]
            if ($priority) { $priority } else { 4 }
        }
        
        foreach ($category in $prioritizedCategories) {
            $categoryUndocumented = $constantsWithoutDocs | Where-Object { $_.Category -eq $category }
            if ($categoryUndocumented.Count -gt 0) {
                $priority = switch ($categoryPriority[$category]) {
                    1 { "🚨 HIGH" }
                    2 { "⚠️ MEDIUM" }
                    3 { "📝 LOW" }
                    default { "📝 LOW" }
                }
                $reportContent += "- **$category Category**: $($categoryUndocumented.Count) constants - $priority"
            }
        }
        $reportContent += ""
    }
    
    $reportContent += "### Documentation Standards"
    $reportContent += ""
    $reportContent += "Use these guidelines when documenting constants:"
    $reportContent += ""
    $reportContent += "````````csharp"
    $reportContent += "/// <summary>"
    $reportContent += "/// Brief description of what this constant represents"
    $reportContent += "/// </summary>"
    $reportContent += "public const string CONSTANT_NAME = " + '"value";'
    $reportContent += ""
    $reportContent += "// Or using single-line comment for simple constants"
    $reportContent += "// Description of the constant's purpose"
    $reportContent += "public const int SIMPLE_CONSTANT = 42;"
    $reportContent += "````````"
}

# Technical Details
$reportContent += ""
$reportContent += "## Technical Analysis Details"
$reportContent += ""
$reportContent += "### Detection Patterns"
$reportContent += ""
$reportContent += "This analysis detected constants using the pattern:"
$reportContent += "- ````public const Type NAME = value;````"
$reportContent += ""
$reportContent += "### Documentation Sources"
$reportContent += ""
$reportContent += "Documentation was extracted from:"
$reportContent += "- XML documentation comments (````/// <summary>````)"
$reportContent += "- Single-line comments above constants (````// comment````)"
$reportContent += "- Multi-line comments (````/* comment */````)"
$reportContent += ""
$reportContent += "### File Coverage"
$reportContent += ""

$fileGroups = $constants | Group-Object FileName | Sort-Object Name
foreach ($fileGroup in $fileGroups) {
    $fileDocumented = $fileGroup.Group | Where-Object { $_.Documentation }
    $fileCoverage = if ($fileGroup.Count -gt 0) { [Math]::Round(($fileDocumented.Count / $fileGroup.Count) * 100, 1) } else { 0 }
    $reportContent += "- **$($fileGroup.Name)**: $($fileGroup.Count) constants, $fileCoverage% documented"
}

# Footer
$reportContent += ""
$reportContent += "---"
$reportContent += ""
$reportContent += "**Documentation Goal**: 90%+ coverage for exceptional standards"
$reportContent += ""
$reportContent += "*Generated by MixerThreholdMod DevOps Suite - Constants Documentation Generator*"

try {
    $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
    $reportSaveSuccess = $true
}
catch {
    Write-Host "⚠️ Error saving detailed report: $_" -ForegroundColor DarkYellow
    $reportSaveSuccess = $false
}

Write-Host "``n=== CONSTANTS DOCUMENTATION REPORT ===" -ForegroundColor DarkCyan
Write-Host "🕐 Generation completed: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray

if ($savedSuccessfully) {
    Write-Host "✅ Documentation generated successfully!" -ForegroundColor Green
    Write-Host "📄 Primary output saved to: $outputPath" -ForegroundColor Gray
} else {
    Write-Host "❌ Failed to save primary documentation" -ForegroundColor Red
}

Write-Host "📊 Documented $($constants.Count) constants across $($categories.Count) categories" -ForegroundColor Gray

# Summary (condensed for automation)
Write-Host "``n📋 Summary:" -ForegroundColor DarkCyan
Write-Host "   Total constants: $($constants.Count)" -ForegroundColor Gray
Write-Host "   Categories: $($categories -join ', ')" -ForegroundColor Gray
Write-Host "   Files processed: $(($constants | Select-Object -ExpandProperty File -Unique).Count)" -ForegroundColor Gray

Write-Host "   Constants with documentation: $($constantsWithDocs.Count)" -ForegroundColor Green
if ($constantsWithoutDocs.Count -gt 0) {
    Write-Host "   Constants needing documentation: $($constantsWithoutDocs.Count)" -ForegroundColor DarkYellow
}

# Quick recommendations
Write-Host "``n💡 Recommendations:" -ForegroundColor DarkCyan
if ($constantsWithoutDocs.Count -gt 0) {
    $percentage = [Math]::Round(($constantsWithoutDocs.Count / $constants.Count) * 100, 1)
    Write-Host "   ⚠️  $percentage% of constants lack documentation" -ForegroundColor DarkYellow
    Write-Host "   • Add XML documentation comments above constant declarations" -ForegroundColor Gray
} else {
    Write-Host "   ✅ All constants are documented!" -ForegroundColor Green
}

Write-Host "   • Review generated documentation for accuracy" -ForegroundColor Gray
Write-Host "   • Update constant values and descriptions as needed" -ForegroundColor Gray

Write-Host "``n🚀 Constants documentation generation complete!" -ForegroundColor Green

# OUTPUT PATH AT THE END for easy finding
if ($reportSaveSuccess) {
    Write-Host "``n📄 DETAILED REPORT SAVED:" -ForegroundColor Green
    Write-Host "   Location: $reportPath" -ForegroundColor Cyan
    Write-Host "   Size: $([Math]::Round((Get-Item $reportPath).Length / 1KB, 1)) KB" -ForegroundColor Gray
} else {
    Write-Host "``n⚠️ No detailed report generated" -ForegroundColor DarkYellow
}

# INTERACTIVE WORKFLOW LOOP (only when running standalone)
if ($IsInteractive -and -not $RunningFromScript) {
    do {
        Write-Host "``n🎯 What would you like to do next?" -ForegroundColor DarkCyan
        Write-Host "   D - Display report in console" -ForegroundColor Green
        Write-Host "   R - Re-run constants documentation generation" -ForegroundColor DarkYellow
        Write-Host "   X - Exit to DevOps menu" -ForegroundColor Gray
        
        $choice = Read-Host "``nEnter choice (D/R/X)"
        $choice = $choice.ToUpper()
        
        switch ($choice) {
            'D' {
                if ($reportSaveSuccess) {
                    Write-Host "``n📋 DISPLAYING CONSTANTS DOCUMENTATION REPORT:" -ForegroundColor DarkCyan
                    Write-Host "=============================================" -ForegroundColor DarkCyan
                    try {
                        $reportDisplay = Get-Content -Path $reportPath -Raw
                        Write-Host $reportDisplay -ForegroundColor White
                        Write-Host "``n=============================================" -ForegroundColor DarkCyan
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
                Write-Host "``n🔄 RE-RUNNING CONSTANTS DOCUMENTATION GENERATION..." -ForegroundColor DarkYellow
                Write-Host "=================================================" -ForegroundColor DarkYellow
                & $MyInvocation.MyCommand.Path
                return
            }
            'X' {
                Write-Host "``n👋 Returning to DevOps menu..." -ForegroundColor Gray
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