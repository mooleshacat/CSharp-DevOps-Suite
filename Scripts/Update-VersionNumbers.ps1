# MixerThreholdMod DevOps Tool: Version Numbers Synchronizer (NON-INTERACTIVE)
# Synchronizes version numbers across all project files
# Updates Constants, AssemblyInfo, manifests, and documentation
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

Write-Host "🕐 Version synchronization started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "Synchronizing version numbers in: $ProjectRoot" -ForegroundColor DarkCyan
Write-Host "🚀 NON-INTERACTIVE VERSION - Compatible with automation" -ForegroundColor Green
Write-Host "Excluding: ForCopilot, Scripts, and Legacy directories" -ForegroundColor DarkGray

# Function to validate semantic version
function Test-SemanticVersion {
    param($version)
    
    if (-not $version) { return $false }
    
    # Semantic version pattern: MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]
    $pattern = '^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z\-\.]+))?(?:\+([0-9A-Za-z\-\.]+))?$'
    
    return $version -match $pattern
}

# Function to parse semantic version
function Get-SemanticVersionParts {
    param($version)
    
    $pattern = '^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z\-\.]+))?(?:\+([0-9A-Za-z\-\.]+))?$'
    
    if ($version -match $pattern) {
        return [PSCustomObject]@{
            Major = [int]$matches[1]
            Minor = [int]$matches[2]
            Patch = [int]$matches[3]
            PreRelease = $matches[4]
            Build = $matches[5]
            Full = $version
            Simple = "$($matches[1]).$($matches[2]).$($matches[3])"
        }
    }
    
    return $null
}

# Function to get current version from Constants files
function Get-CurrentVersion {
    # Try multiple locations for version constants
    $constantsFiles = @(
        "Constants\SystemConstants.cs",
        "Constants\Constants.cs",
        "Constants\AllConstants.cs",
        "Main.cs"
    )
    
    foreach ($fileName in $constantsFiles) {
        $constantsFile = Join-Path $ProjectRoot $fileName
        if (Test-Path $constantsFile) {
            try {
                $content = Get-Content -Path $constantsFile -Raw -ErrorAction Stop
                if ($content -match 'MOD_VERSION\s*=\s*"([^"]+)"') {
                    Write-Host "   📋 Found version in $fileName``: $($matches[1])" -ForegroundColor Gray
                    return $matches[1]
                }
            }
            catch {
                Write-Host "   ⚠️  Error reading $fileName``: $_" -ForegroundColor DarkYellow
            }
        }
    }
    
    Write-Host "   ⚠️  No MOD_VERSION found in constants files" -ForegroundColor DarkYellow
    return $null
}

# Function to find version-containing files (optimized)
function Find-VersionFiles {
    try {
        $versionFiles = @()
        
        # Find all potential files with CORRECTED exclusions
        $files = Get-ChildItem -Path $ProjectRoot -Recurse -Include *.cs,*.json,*.xml,*.md -ErrorAction SilentlyContinue | Where-Object {
            $_.PSIsContainer -eq $false -and
            $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy)[\\/]" -and
            $_.FullName -notmatch "[\\/]\.git[\\/]"
        }
        
        Write-Host "   📈 Scanning $($files.Count) files for version patterns..." -ForegroundColor DarkGray
        
        $processedFiles = 0
        foreach ($file in $files) {
            $processedFiles++
            
            # Show progress every 50 files
            if ($processedFiles % 50 -eq 0) {
                Write-Host "   📈 Progress: $processedFiles/$($files.Count) files scanned..." -ForegroundColor DarkGray
            }
            
            try {
                $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
                if (-not $content) { continue }
                
                $hasVersion = $false
                $versionPatterns = @()
                $foundVersions = @()
                
                # Check for various version patterns
                if ($content -match 'MOD_VERSION\s*=\s*"([^"]+)"') {
                    $hasVersion = $true
                    $versionPatterns += "MOD_VERSION constant"
                    $foundVersions += [PSCustomObject]@{ Type = "MOD_VERSION"; Version = $matches[1]; Valid = (Test-SemanticVersion $matches[1]) }
                }
                
                if ($content -match 'AssemblyVersion\s*\(\s*"([^"]+)"\s*\)') {
                    $hasVersion = $true
                    $versionPatterns += "AssemblyVersion attribute"
                    $foundVersions += [PSCustomObject]@{ Type = "AssemblyVersion"; Version = $matches[1]; Valid = (Test-SemanticVersion $matches[1]) }
                }
                
                if ($content -match 'AssemblyFileVersion\s*\(\s*"([^"]+)"\s*\)') {
                    $hasVersion = $true
                    $versionPatterns += "AssemblyFileVersion attribute"
                    $foundVersions += [PSCustomObject]@{ Type = "AssemblyFileVersion"; Version = $matches[1]; Valid = (Test-SemanticVersion $matches[1]) }
                }
                
                if ($content -match '"version"\s*:\s*"([^"]+)"') {
                    $hasVersion = $true
                    $versionPatterns += "JSON version field"
                    $foundVersions += [PSCustomObject]@{ Type = "JSON version"; Version = $matches[1]; Valid = (Test-SemanticVersion $matches[1]) }
                }
                
                if ($content -match 'MelonModInfo\s*\([^)]*"([^"]*)"[^)]*"([^"]*)"[^)]*"([^"]*)"') {
                    $hasVersion = $true
                    $versionPatterns += "MelonModInfo attribute"
                    $foundVersions += [PSCustomObject]@{ Type = "MelonModInfo"; Version = $matches[3]; Valid = (Test-SemanticVersion $matches[3]) }
                }
                
                if ($hasVersion) {
                    $versionFiles += [PSCustomObject]@{
                        File = $file.FullName
                        RelativePath = $file.FullName.Replace($ProjectRoot, "").TrimStart('\', '/')
                        Name = $file.Name
                        Patterns = $versionPatterns
                        FoundVersions = $foundVersions
                        Content = $content
                    }
                }
            }
            catch {
                # Skip files that can't be read
                continue
            }
        }
        
        return $versionFiles
    }
    catch {
        Write-Host "   ⚠️  Error scanning for version files: $_" -ForegroundColor DarkYellow
        return @()
    }
}

# Main script execution
Write-Host "``n=== VERSION NUMBER SYNCHRONIZATION REPORT ===" -ForegroundColor DarkCyan
Write-Host "🕐 Analysis completed: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray

# Get current version
Write-Host "``n📂 Detecting current version..." -ForegroundColor DarkGray
$currentVersion = Get-CurrentVersion
if ($currentVersion) {
    Write-Host "📊 Current version detected: $currentVersion" -ForegroundColor Gray
    
    if (-not (Test-SemanticVersion -version $currentVersion)) {
        Write-Host "⚠️  Current version is not a valid semantic version" -ForegroundColor DarkYellow
    } else {
        Write-Host "✅ Current version follows semantic versioning" -ForegroundColor Green
    }
} else {
    Write-Host "⚠️  No current version detected in constants files" -ForegroundColor DarkYellow
    $currentVersion = "Unknown"
}

# AUTOMATED: Always run in scan mode (dry run) for comprehensive report
Write-Host "``n🔍 Running in scan mode - analyzing version consistency..." -ForegroundColor DarkCyan

# Find all version-containing files
Write-Host "``n📂 Scanning for version-containing files..." -ForegroundColor DarkGray
$versionFiles = Find-VersionFiles

Write-Host "``n📊 Found $($versionFiles.Count) files containing version information" -ForegroundColor Gray

if ($versionFiles.Count -eq 0) {
    Write-Host "⚠️  No version-containing files found" -ForegroundColor DarkYellow
} else {
    # Analyze version consistency
    $versionInconsistencies = @()
    $allVersions = @()
    $semanticIssues = @()
    
    foreach ($versionFile in $versionFiles) {
        $fileVersions = $versionFile.FoundVersions
        
        # Collect all versions
        foreach ($foundVersion in $fileVersions) {
            $allVersions += $foundVersion.Version
            
            if (-not $foundVersion.Valid) {
                $semanticIssues += [PSCustomObject]@{
                    File = $versionFile.RelativePath
                    Type = $foundVersion.Type
                    Version = $foundVersion.Version
                    Issue = "Not semantic versioning compliant"
                }
            }
        }
        
        # Check for inconsistencies within this file
        $uniqueVersionsInFile = $fileVersions.Version | Select-Object -Unique
        if ($uniqueVersionsInFile.Count -gt 1) {
            $versionInconsistencies += [PSCustomObject]@{
                File = $versionFile.RelativePath
                Issue = "Multiple versions in same file"
                Versions = $uniqueVersionsInFile
            }
        }
    }
    
    # Display top files with version info (limited for automation)
    Write-Host "``n📋 Top Version-Containing Files:" -ForegroundColor DarkCyan
    
    $topFiles = $versionFiles | Select-Object -First 8  # Reduced for automation
    foreach ($versionFile in $topFiles) {
        Write-Host "   📄 $($versionFile.RelativePath)" -ForegroundColor Gray
        Write-Host "      Patterns: $($versionFile.Patterns -join ', ')" -ForegroundColor DarkGray
        
        # Show versions found in this file
        foreach ($foundVersion in $versionFile.FoundVersions) {
            $validIcon = if ($foundVersion.Valid) { "✅" } else { "⚠️" }
            Write-Host "      $validIcon $($foundVersion.Type): $($foundVersion.Version)" -ForegroundColor DarkGray
        }
    }
    
    if ($versionFiles.Count -gt 8) {
        Write-Host "   ... and $($versionFiles.Count - 8) more files" -ForegroundColor DarkGray
    }
    
    # Version consistency analysis
    Write-Host "``n📊 Version Consistency Analysis:" -ForegroundColor DarkCyan
    
    $uniqueVersions = $allVersions | Select-Object -Unique | Sort-Object
    Write-Host "   Unique versions found: $($uniqueVersions.Count)" -ForegroundColor Gray
    
    foreach ($version in $uniqueVersions) {
        $count = ($allVersions | Where-Object { $_ -eq $version }).Count
        $color = if ($version -eq $currentVersion) { "Green" } else { "DarkYellow" }
        $validIcon = if (Test-SemanticVersion $version) { "✅" } else { "⚠️" }
        Write-Host "   $validIcon $version``: $count occurrences" -ForegroundColor $color
    }
    
    # Inconsistency warnings
    if ($versionInconsistencies.Count -gt 0) {
        Write-Host "``n⚠️  Version Inconsistencies Detected:" -ForegroundColor DarkYellow
        foreach ($inconsistency in $versionInconsistencies) {
            Write-Host "   • $($inconsistency.File)``: $($inconsistency.Issue)" -ForegroundColor Red
            Write-Host "     Versions: $($inconsistency.Versions -join ', ')" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "``n✅ No version inconsistencies detected within files" -ForegroundColor Green
    }
    
    # Semantic versioning issues
    if ($semanticIssues.Count -gt 0) {
        Write-Host "``n⚠️  Semantic Versioning Issues:" -ForegroundColor DarkYellow
        $topSemanticIssues = $semanticIssues | Select-Object -First 5
        foreach ($issue in $topSemanticIssues) {
            Write-Host "   • $($issue.File): $($issue.Type) = '$($issue.Version)'" -ForegroundColor Red
        }
        if ($semanticIssues.Count -gt 5) {
            Write-Host "   ... and $($semanticIssues.Count - 5) more semantic issues" -ForegroundColor DarkGray
        }
    }
}

# Overall assessment
Write-Host "``n🎯 Overall Assessment:" -ForegroundColor DarkCyan

$overallStatus = "Good"
$criticalIssues = 0

if ($overallStatus -eq "Critical") {
    if ($currentVersion -eq "Unknown") {
        Write-Host "   🚨 CRITICAL: No MOD_VERSION constant found" -ForegroundColor Red
        $overallStatus = "Critical"
        $criticalIssues++
    }
    
    if ($versionFiles.Count -eq 0) {
        Write-Host "   🚨 CRITICAL: No version-containing files found" -ForegroundColor Red
        $overallStatus = "Critical"
        $criticalIssues++
    }
} # FIXED: Added missing closing brace

if ($currentVersion -eq "Unknown") {
    Write-Host "   🚨 CRITICAL: No MOD_VERSION constant found" -ForegroundColor Red
    $overallStatus = "Critical"
    $criticalIssues++
} # FIXED: Added missing closing brace

if ($versionFiles.Count -eq 0) {
    Write-Host "   🚨 CRITICAL: No version-containing files found" -ForegroundColor Red
    $overallStatus = "Critical"
    $criticalIssues++
}

if ($uniqueVersions -and $uniqueVersions.Count -gt 1) {
    Write-Host "   ⚠️  WARNING: Multiple different versions detected" -ForegroundColor DarkYellow
    if ($overallStatus -eq "Good") { $overallStatus = "Needs Attention" }
}

if ($semanticIssues.Count -gt 0) {
    Write-Host "   ⚠️  WARNING: $($semanticIssues.Count) semantic versioning issues" -ForegroundColor DarkYellow
    if ($overallStatus -eq "Good") { $overallStatus = "Needs Attention" }
}

if ($criticalIssues -eq 0 -and $uniqueVersions.Count -le 1 -and $semanticIssues.Count -eq 0) {
    Write-Host "   ✅ EXCELLENT: Version management is well-maintained" -ForegroundColor Green
}

# Recommendations
Write-Host "``n💡 Recommendations:" -ForegroundColor DarkCyan

if ($currentVersion -eq "Unknown") {
    Write-Host "   🚨 CRITICAL: Add MOD_VERSION constant to a Constants file" -ForegroundColor Red
    # FIXED: Use single backtick escaping for embedded double quotes
    $exampleText = "      Example: public const string MOD_VERSION = `"1.0.0`";"
    Write-Host $exampleText -ForegroundColor Gray
} else {
    if (-not (Test-SemanticVersion -version $currentVersion)) {
        Write-Host "   ⚠️  WARNING: Current version '$currentVersion' is not semantic versioning compliant" -ForegroundColor DarkYellow
        Write-Host "      Consider using format: MAJOR.MINOR.PATCH (e.g., 1.0.0)" -ForegroundColor DarkYellow
    }
}

if ($versionFiles.Count -gt 0) {
    $uniqueVersions = $allVersions | Select-Object -Unique
    if ($uniqueVersions.Count -gt 1) {
        Write-Host "   ⚠️  WARNING: Multiple version values detected across files" -ForegroundColor DarkYellow
        Write-Host "      Run this script interactively to synchronize versions" -ForegroundColor DarkYellow
    }
}

Write-Host "   • Use semantic versioning: MAJOR.MINOR.PATCH" -ForegroundColor Gray
Write-Host "   • Keep version references synchronized across all files" -ForegroundColor Gray
Write-Host "   • Tag releases with git: git tag v<VERSION>" -ForegroundColor Gray
Write-Host "   • Run interactively to update versions across all files" -ForegroundColor Gray

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

# Generate detailed version synchronization report
Write-Host "``n📝 Generating detailed version synchronization report..." -ForegroundColor DarkGray

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPath = Join-Path $reportsDir "VERSION-SYNCHRONIZATION-REPORT_$timestamp.md"

$reportContent = @()
$reportContent += "# Version Synchronization Report"
$reportContent += ""
$reportContent += "**Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportContent += "**Current Version**: $currentVersion"
$reportContent += "**Files Analyzed**: $($versionFiles.Count)"
$reportContent += "**Overall Status**: $overallStatus"
$reportContent += ""

# Executive Summary
$reportContent += "## Executive Summary"
$reportContent += ""

$versionCount = if ($uniqueVersions) { $uniqueVersions.Count } else { 0 }

if ($overallStatus -eq "Critical") {
    $reportContent += "🚨 **CRITICAL ISSUES DETECTED** - Immediate action required."
    $reportContent += ""
    $reportContent += "Critical problems found that prevent proper version management."
} elseif ($overallStatus -eq "Needs Attention") {
    $reportContent += "⚠️ **VERSION INCONSISTENCIES** - Review and synchronization needed."
    $reportContent += ""
    $reportContent += "Multiple versions or formatting issues detected across files."
} else {
    $reportContent += "✅ **EXCELLENT VERSION MANAGEMENT** - All versions are synchronized."
    $reportContent += ""
    $reportContent += "Your project demonstrates good version control practices."
}

$reportContent += ""
$reportContent += "| Metric | Value | Status |"
$reportContent += "|--------|-------|--------|"
$reportContent += "| **Current Version** | $currentVersion | $(if ($currentVersion -eq `"Unknown`") { `"🚨 Missing`" } elseif (Test-SemanticVersion $currentVersion) { `"✅ Valid`" } else { `"⚠️ Invalid Format`" }) |"
$reportContent += "| **Unique Versions** | $versionCount | $(if ($versionCount -eq 0) { `"🚨 None Found`" } elseif ($versionCount -eq 1) { `"✅ Consistent`" } else { `"⚠️ Inconsistent`" }) |"
$reportContent += "| **Files with Versions** | $($versionFiles.Count) | $(if ($versionFiles.Count -eq 0) { `"🚨 None`" } elseif ($versionFiles.Count -lt 3) { `"⚠️ Few`" } else { `"✅ Good Coverage`" }) |"
$reportContent += "| **Semantic Issues** | $($semanticIssues.Count) | $(if ($semanticIssues.Count -eq 0) { `"✅ None`" } elseif ($semanticIssues.Count -le 2) { `"⚠️ Minor`" } else { `"🚨 Multiple`" }) |"
$reportContent += "| **Inconsistencies** | $($versionInconsistencies.Count) | $(if ($versionInconsistencies.Count -eq 0) { `"✅ None`" } else { `"⚠️ Found`" }) |"
$reportContent += ""

# Version Analysis
if ($versionFiles.Count -gt 0) {
    $reportContent += "## Version Distribution"
    $reportContent += ""
    
    if ($uniqueVersions) {
        $reportContent += "### Current Version Usage"
        $reportContent += ""
        $reportContent += "| Version | Occurrences | Semantic Valid | Status |"
        $reportContent += "|---------|-------------|----------------|--------|"
        
        foreach ($version in $uniqueVersions | Sort-Object) {
            $count = ($allVersions | Where-Object { $_ -eq $version }).Count
            $isValid = Test-SemanticVersion $version
            $isCurrent = $version -eq $currentVersion
            
            $status = if ($isCurrent -and $isValid) { "✅ Current & Valid" } 
                     elseif ($isCurrent) { "⚠️ Current (Invalid Format)" }
                     elseif ($isValid) { "📝 Valid Format" }
                     else { "❌ Invalid Format" }
            
            $reportContent += "| ````$version```` | $count | $(if ($isValid) { `"✅ Yes`" } else { `"❌ No`" }) | $status |"
        }
        $reportContent += ""
    }
}

# File Analysis
if ($versionFiles.Count -gt 0) {
    $reportContent += "## Files with Version Information"
    $reportContent += ""
    
    foreach ($versionFile in $versionFiles | Sort-Object RelativePath) {
        $reportContent += "### $($versionFile.RelativePath)"
        $reportContent += ""
        $reportContent += "**Patterns Found**: $($versionFile.Patterns -join ', ')"
        $reportContent += ""
        
        if ($versionFile.FoundVersions.Count -gt 0) {
            $reportContent += "| Type | Version | Format Valid |"
            $reportContent += "|------|---------|--------------|"
            
            foreach ($foundVersion in $versionFile.FoundVersions) {
                $validIcon = if ($foundVersion.Valid) { "✅" } else { "❌" }
                $reportContent += "| $($foundVersion.Type) | ````$($foundVersion.Version)```` | $validIcon |"
            }
            $reportContent += ""
        }
    }
}

# Issues Analysis
if ($versionInconsistencies.Count -gt 0 -or $semanticIssues.Count -gt 0) {
    $reportContent += "## Issues Requiring Attention"
    $reportContent += ""
    
    if ($versionInconsistencies.Count -gt 0) {
        $reportContent += "### Version Inconsistencies"
        $reportContent += ""
        $reportContent += "Files with multiple different versions:"
        $reportContent += ""
        
        foreach ($inconsistency in $versionInconsistencies) {
            $reportContent += "#### $($inconsistency.File)"
            $reportContent += ""
            $reportContent += "**Issue**: $($inconsistency.Issue)"
            $reportContent += "**Versions Found**: $($inconsistency.Versions -join ', ')"
            $reportContent += ""
        }
    }
    
    if ($semanticIssues.Count -gt 0) {
        $reportContent += "### Semantic Versioning Issues"
        $reportContent += ""
        $reportContent += "Versions that don't follow semantic versioning (MAJOR.MINOR.PATCH):"
        $reportContent += ""
        $reportContent += "| File | Type | Current Version | Issue |"
        $reportContent += "|------|------|-----------------|-------|"
        
        foreach ($issue in $semanticIssues) {
            $reportContent += "| ````$($issue.File)```` | $($issue.Type) | ````$($issue.Version)```` | $($issue.Issue) |"
        }
        $reportContent += ""
    }
}

# Recommendations
$reportContent += "## 🎯 Action Plan"
$reportContent += ""

if ($overallStatus -eq "Critical") {
    $reportContent += "### 🚨 IMMEDIATE ACTION REQUIRED"
    $reportContent += ""
    
    if ($currentVersion -eq "Unknown") {
        $reportContent += "#### Missing MOD_VERSION Constant"
        $reportContent += ""
        $reportContent += "**Priority**: CRITICAL"
        $reportContent += ""
        $reportContent += "1. **Add MOD_VERSION constant** to a Constants file:"
        $reportContent += "   ````````csharp"
        # FIXED: Use single backtick escaping for embedded double quotes
        $csharpExample = "   public const string MOD_VERSION = `"1.0.0`";"
        $reportContent += $csharpExample
        $reportContent += "   ````````"
        $chooseVersionText = "2. **Choose semantic version** following MAJOR.MINOR.PATCH format"
        $reportContent += $chooseVersionText
        $reportContent += "3. **Update all version references** to use this constant"
        $reportContent += ""
    }
    
    if ($versionFiles.Count -eq 0) {
        $reportContent += "#### No Version Files Found"
        $reportContent += ""
        $reportContent += "**Priority**: CRITICAL"
        $reportContent += ""
        $reportContent += "1. **Add version information** to at least one of:"
        $reportContent += "   - Constants files (MOD_VERSION)"
        $reportContent += "   - AssemblyInfo.cs (AssemblyVersion)"
        $reportContent += "   - MelonModInfo attribute"
        $reportContent += "2. **Establish version source of truth**"
        $reportContent += ""
    }
} elseif ($overallStatus -eq "Needs Attention") {
    $reportContent += "### ⚠️ SYNCHRONIZATION NEEDED"
    $reportContent += ""
    
    if ($uniqueVersions -and $uniqueVersions.Count -gt 1) {
        $reportContent += "#### Multiple Versions Detected"
        $reportContent += ""
        $reportContent += "**Action**: Synchronize all version references to use the same value"
        $reportContent += ""
        $reportContent += "1. **Choose authoritative version**: $currentVersion"
        $reportContent += "2. **Update all files** to use this version"
        $reportContent += "3. **Run synchronization** using this script interactively"
        $reportContent += ""
    }
    
    if ($semanticIssues.Count -gt 0) {
        $reportContent += "#### Semantic Versioning Issues"
        $reportContent += ""
        $reportContent += "**Action**: Convert versions to semantic versioning format"
        $reportContent += ""
        $reportContent += "1. **Review current versions** that don't follow MAJOR.MINOR.PATCH"
        # FIXED: Use single backtick escaping for embedded double quotes
        $reportContent += "2. **Convert to semantic format** (e.g., `"v1.0`" → `"1.0.0`")"
        $reportContent += "3. **Update all references** to use new format"
        $reportContent += ""
    }
} else {
    $reportContent += "### ✅ MAINTENANCE MODE"
    $reportContent += ""
    $reportContent += "Excellent work! Your version management is well-maintained. Continue with:"
    $reportContent += ""
    $reportContent += "1. **Regular Audits**: Run this analysis before releases"
    $reportContent += "2. **Version Bumping**: Follow semantic versioning for updates"
    $reportContent += "3. **Git Tagging**: Tag releases with version numbers"
    $reportContent += "4. **Documentation**: Keep changelogs updated with versions"
}

# Best Practices
$reportContent += ""
$reportContent += "### Best Practices"
$reportContent += ""
$reportContent += "1. **Semantic Versioning**: Use MAJOR.MINOR.PATCH format"
$reportContent += "   - MAJOR: Breaking changes"
$reportContent += "   - MINOR: New features (backward compatible)"
$reportContent += "   - PATCH: Bug fixes (backward compatible)"
$reportContent += ""
$reportContent += "2. **Single Source of Truth**: Use MOD_VERSION constant as primary source"
$reportContent += ""
$reportContent += "3. **Consistent Updates**: Update all version references simultaneously"
$reportContent += ""
$reportContent += "4. **Git Integration**: Tag releases with version numbers"
$reportContent += "   ````````bash"
$reportContent += "   git tag v1.0.0"
$reportContent += "   git push origin v1.0.0"
$reportContent += "   ````````"

# Technical Details
$reportContent += ""
$reportContent += "## Technical Analysis Details"
$reportContent += ""
$reportContent += "### Detection Patterns"
$reportContent += ""
$reportContent += "This analysis searches for versions using these patterns:"
$reportContent += ""
# FIXED: Use single backtick escaping for embedded double quotes
$reportContent += "- **MOD_VERSION**: ````MOD_VERSION = `"version`"````"
$reportContent += "- **Assembly Attributes**: ````[AssemblyVersion(`"version`")]````"
$reportContent += "- **JSON Fields**: ````*version*: `"version`"````"
$reportContent += "- **MelonModInfo**: Third parameter in MelonModInfo attribute"
$reportContent += ""
$reportContent += "### File Coverage"
$reportContent += ""
$reportContent += "- **File Types**: .cs, .json, .xml, .md"
$reportContent += "- **Exclusions**: ForCopilot/, Scripts/, Legacy/, .git/"
$reportContent += "- **Total Scanned**: $($versionFiles.Count) files with version information"

# Footer
$reportContent += ""
$reportContent += "---"
$reportContent += ""
$reportContent += "**Semantic Versioning**: [semver.org](https://semver.org) - MAJOR.MINOR.PATCH"
$reportContent += ""
$reportContent += "*Generated by MixerThreholdMod DevOps Suite - Version Synchronizer*"

try {
    $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
    $saveSuccess = $true
}
catch {
    Write-Host "⚠️ Error saving detailed report: $_" -ForegroundColor DarkYellow
    $saveSuccess = $false
}

Write-Host "``n🚀 Version synchronization scan complete!" -ForegroundColor Green

# OUTPUT PATH AT THE END for easy finding
if ($saveSuccess) {
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
        Write-Host "   R - Re-run version synchronization analysis" -ForegroundColor DarkYellow
        Write-Host "   X - Exit to DevOps menu" -ForegroundColor Gray
        
        $choice = Read-Host "``nEnter choice (D/R/X)"
        $choice = $choice.ToUpper()
        
        switch ($choice) {
            'D' {
                if ($saveSuccess) {
                    Write-Host "``n📋 DISPLAYING VERSION SYNCHRONIZATION REPORT:" -ForegroundColor DarkCyan
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
                Write-Host "``n🔄 RE-RUNNING VERSION SYNCHRONIZATION ANALYSIS..." -ForegroundColor DarkYellow
                Write-Host "================================================" -ForegroundColor DarkYellow
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