# MixerThreholdMod DevOps Tool: Namespace Alignment Auditor
# 🆕 Namespace consistency and structure analysis with corruption detection
# Validates namespace declarations, alignment with folder structure, and consistency across project
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

Write-Host "🕐 Namespace audit started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "Analyzing namespaces in: $ProjectRoot" -ForegroundColor DarkCyan
Write-Host "🆕 NEW ENHANCED TOOL - Advanced namespace alignment analysis" -ForegroundColor Green
Write-Host "Excluding: ForCopilot, Scripts, and Legacy directories" -ForegroundColor DarkGray

# Function to extract project/mod version for consistency checking
function Get-ProjectVersion {
    param([string]$ProjectPath)
    
    $versions = @()
    
    try {
        # Search for version constants in C# files
        $files = Get-ChildItem -Path $ProjectPath -Recurse -Include *.cs -ErrorAction SilentlyContinue | Where-Object {
            $_.PSIsContainer -eq $false -and
            $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy)[\\/]" -and
            $_.FullName -notmatch "[\\/]\.git[\\/]"
        }
        
        foreach ($file in $files) {
            try {
                $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
                if ($content) {
                    # Look for version constants
                    if ($content -match 'MOD_VERSION\s*=\s*`"([^`"]+)`"') {
                        $versions += [PSCustomObject]@{
                            Source = "MOD_VERSION Constant"
                            Version = $matches[1]
                            File = $file.Name
                            Location = $file.FullName.Replace($ProjectPath, "").TrimStart('\', '/')
                        }
                    }
                    if ($content -match 'AssemblyVersion\s*\(\s*`"([^`"]+)`"\s*\)') {
                        $versions += [PSCustomObject]@{
                            Source = "Assembly Version"
                            Version = $matches[1]
                            File = $file.Name
                            Location = $file.FullName.Replace($ProjectPath, "").TrimStart('\', '/')
                        }
                    }
                }
            }
            catch {
                # Skip files that can't be read
            }
        }
        
        # Check project files
        $projectFiles = Get-ChildItem -Path $ProjectPath -Recurse -Include *.csproj,*.json -ErrorAction SilentlyContinue
        foreach ($projFile in $projectFiles) {
            try {
                $content = Get-Content -Path $projFile.FullName -Raw -ErrorAction SilentlyContinue
                if ($content) {
                    if ($content -match '<Version>([^<]+)</Version>') {
                        $versions += [PSCustomObject]@{
                            Source = "Project File Version"
                            Version = $matches[1]
                            File = $projFile.Name
                            Location = $projFile.FullName.Replace($ProjectPath, "").TrimStart('\', '/')
                        }
                    }
                    if ($content -match '`"version`"\s*:\s*`"([^`"]+)`"') {
                        $versions += [PSCustomObject]@{
                            Source = "JSON Version"
                            Version = $matches[1]
                            File = $projFile.Name
                            Location = $projFile.FullName.Replace($ProjectPath, "").TrimStart('\', '/')
                        }
                    }
                }
            }
            catch {
                # Skip files that can't be read
            }
        }
    }
    catch {
        Write-Host "⚠️ Error detecting project version: $_" -ForegroundColor DarkYellow
    }
    
    return $versions
}

# Function to perform comprehensive namespace audit
function Get-NamespaceAudit {
    param([string]$Path)
    
    try {
        $files = Get-ChildItem -Path $Path -Recurse -Include *.cs -ErrorAction SilentlyContinue | Where-Object {
            $_.PSIsContainer -eq $false -and
            $_.FullName -notmatch "[\\/](ForCopilot|Scripts|Legacy)[\\/]" -and
            $_.FullName -notmatch "[\\/]\.git[\\/]"
        }
        
        $audit = @()
        $rootNamespaces = @{}
        $folderStructure = @{}
        
        foreach ($file in $files) {
            try {
                $content = Get-Content -Path $file.FullName -Raw -ErrorAction Stop
                $relativePath = $file.FullName.Replace($Path, "").TrimStart('\', '/')
                $folderPath = Split-Path $relativePath -Parent
                $fileName = $file.Name
                
                # Extract namespace declarations
                $namespaceMatches = [regex]::Matches($content, 'namespace\s+([A-Za-z0-9_.]+)\s*{')
                $usingStatements = [regex]::Matches($content, 'using\s+([A-Za-z0-9_.]+)\s*;')
                
                $namespaces = @()
                $usings = @()
                
                foreach ($match in $namespaceMatches) {
                    $namespaces += $match.Groups[1].Value
                }
                
                foreach ($match in $usingStatements) {
                    $usings += $match.Groups[1].Value
                }
                
                # Analyze folder structure alignment
                $folderParts = if ($folderPath) { $folderPath -split '[\\/]' } else { @() }
                $expectedNamespace = if ($folderParts.Count -gt 0) { $folderParts -join '.' } else { "" }
                
                # Check for root namespace consistency
                $primaryNamespace = if ($namespaces.Count -gt 0) { $namespaces[0] } else { "" }
                $rootNamespace = if ($primaryNamespace) { ($primaryNamespace -split '\.')[0] } else { "" }
                
                if ($rootNamespace) {
                    if (-not $rootNamespaces.ContainsKey($rootNamespace)) {
                        $rootNamespaces[$rootNamespace] = 0
                    }
                    $rootNamespaces[$rootNamespace]++
                }
                
                # Store folder structure mapping
                if ($folderPath -and $primaryNamespace) {
                    $folderStructure[$folderPath] = $primaryNamespace
                }
                
                # Detect issues
                $issues = @()
                $warnings = @()
                $suggestions = @()
                
                # No namespace declaration
                if ($namespaces.Count -eq 0) {
                    $issues += "No namespace declaration found"
                }
                
                # Multiple namespace declarations
                if ($namespaces.Count -gt 1) {
                    $warnings += "Multiple namespace declarations: $($namespaces -join ', ')"
                }
                
                # Folder structure misalignment
                if ($expectedNamespace -and $primaryNamespace) {
                    $namespaceLower = $primaryNamespace.ToLower()
                    $expectedLower = $expectedNamespace.ToLower()
                    
                    if (-not $namespaceLower.EndsWith($expectedLower) -and $expectedLower -ne "") {
                        $warnings += "Namespace doesn't align with folder structure. Expected suffix: '$expectedNamespace', Got: '$primaryNamespace'"
                    }
                }
                
                # Using statement analysis
                $systemUsings = $usings | Where-Object { $_ -like "System*" }
                $projectUsings = $usings | Where-Object { $_ -notlike "System*" -and $_ -notlike "Microsoft*" }
                
                if ($usings.Count -eq 0) {
                    $warnings += "No using statements found"
                }
                
                # Check for potential circular references
                $currentNamespaceParts = $primaryNamespace -split '\.'
                foreach ($using in $projectUsings) {
                    $usingParts = $using -split '\.'
                    if ($using.StartsWith($primaryNamespace) -and $using -ne $primaryNamespace) {
                        $warnings += "Potential circular reference: using '$using' in namespace '$primaryNamespace'"
                    }
                }
                
                # Namespace depth analysis
                $namespaceDepth = if ($primaryNamespace) { ($primaryNamespace -split '\.').Count } else { 0 }
                if ($namespaceDepth -gt 5) {
                    $suggestions += "Consider flattening namespace hierarchy (current depth: $namespaceDepth)"
                }
                
                # Calculate namespace score
                $namespaceScore = 100
                $namespaceScore -= $issues.Count * 30  # Critical issues
                $namespaceScore -= $warnings.Count * 15  # Warnings
                $namespaceScore -= $suggestions.Count * 5  # Suggestions
                $namespaceScore = [Math]::Max(0, $namespaceScore)
                
                $audit += [PSCustomObject]@{
                    File = $file.FullName
                    RelativePath = $relativePath
                    FileName = $fileName
                    FolderPath = $folderPath
                    Namespaces = $namespaces
                    PrimaryNamespace = $primaryNamespace
                    RootNamespace = $rootNamespace
                    ExpectedNamespace = $expectedNamespace
                    UsingStatements = $usings
                    SystemUsings = $systemUsings
                    ProjectUsings = $projectUsings
                    NamespaceDepth = $namespaceDepth
                    Issues = $issues
                    Warnings = $warnings
                    Suggestions = $suggestions
                    NamespaceScore = $namespaceScore
                    HasCriticalIssues = ($issues.Count -gt 0)
                    IsAligned = ($issues.Count -eq 0 -and $warnings.Count -eq 0)
                }
            }
            catch {
                $audit += [PSCustomObject]@{
                    File = $file.FullName
                    RelativePath = $file.FullName.Replace($Path, "").TrimStart('\', '/')
                    FileName = $file.Name
                    FolderPath = Split-Path ($file.FullName.Replace($Path, "").TrimStart('\', '/')) -Parent
                    Namespaces = @()
                    PrimaryNamespace = ""
                    RootNamespace = ""
                    ExpectedNamespace = ""
                    UsingStatements = @()
                    SystemUsings = @()
                    ProjectUsings = @()
                    NamespaceDepth = 0
                    Issues = @("Error reading file: $($_.Exception.Message)")
                    Warnings = @()
                    Suggestions = @()
                    NamespaceScore = 0
                    HasCriticalIssues = $true
                    IsAligned = $false
                }
                
                Write-Host "⚠️ Error processing $($file.Name): $_" -ForegroundColor DarkYellow
                continue
            }
        }
        
        return @{
            Files = $audit
            RootNamespaces = $rootNamespaces
            FolderStructure = $folderStructure
        }
    }
    catch {
        Write-Host "⚠️ Error scanning for namespace audit: $_" -ForegroundColor DarkYellow
        return @{
            Files = @()
            RootNamespaces = @{}
            FolderStructure = @{}
        }
    }
}

Write-Host "`n🔍 Detecting project versions..." -ForegroundColor DarkGray
$projectVersions = Get-ProjectVersion -ProjectPath $ProjectRoot

Write-Host "`n📂 Performing comprehensive namespace audit..." -ForegroundColor DarkGray
$auditResult = Get-NamespaceAudit -Path $ProjectRoot
$audit = $auditResult.Files
$rootNamespaces = $auditResult.RootNamespaces
$folderStructure = $auditResult.FolderStructure

Write-Host "📊 Analyzed $($audit.Count) C# files" -ForegroundColor Gray

if ($audit.Count -eq 0) {
    Write-Host "⚠️ No C# files found for namespace audit" -ForegroundColor DarkYellow
    if ($IsInteractive -and -not $RunningFromScript) {
        Write-Host "`nPress ENTER to continue..." -ForegroundColor Gray -NoNewline
        Read-Host
    }
    return
}

# Calculate overall statistics
$filesWithIssues = $audit | Where-Object { $_.HasCriticalIssues }
$filesWithWarnings = $audit | Where-Object { $_.Warnings.Count -gt 0 }
$alignedFiles = $audit | Where-Object { $_.IsAligned }
$filesWithoutNamespace = $audit | Where-Object { $_.PrimaryNamespace -eq "" }

$totalIssues = ($audit | ForEach-Object { $_.Issues.Count } | Measure-Object -Sum).Sum
$totalWarnings = ($audit | ForEach-Object { $_.Warnings.Count } | Measure-Object -Sum).Sum
$totalSuggestions = ($audit | ForEach-Object { $_.Suggestions.Count } | Measure-Object -Sum).Sum
$averageScore = if ($audit.Count -gt 0) { [Math]::Round(($audit | ForEach-Object { $_.NamespaceScore } | Measure-Object -Average).Average, 1) } else { 0 }

Write-Host "`n=== NAMESPACE AUDIT REPORT ===" -ForegroundColor DarkCyan
Write-Host "🕐 Audit completed: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray

# Version Consistency Analysis
if ($projectVersions.Count -gt 0) {
    Write-Host "`n🏷️ Version Consistency Analysis:" -ForegroundColor DarkCyan
    $uniqueVersions = $projectVersions | Select-Object -Property Version -Unique
    
    if ($uniqueVersions.Count -eq 1) {
        Write-Host "   ✅ All versions consistent: $($uniqueVersions[0].Version)" -ForegroundColor Green
    } else {
        Write-Host "   🚨 Version inconsistencies detected!" -ForegroundColor Red
        foreach ($version in $uniqueVersions) {
            $count = ($projectVersions | Where-Object { $_.Version -eq $version.Version }).Count
            Write-Host "      • Version '$($version.Version)': $count occurrences" -ForegroundColor DarkYellow
        }
    }
    
    Write-Host "   📋 Version sources found:" -ForegroundColor Gray
    foreach ($version in $projectVersions) {
        Write-Host "      • $($version.Source): $($version.Version) in $($version.File)" -ForegroundColor DarkGray
    }
} else {
    Write-Host "`n🏷️ Version Analysis: No version information found" -ForegroundColor DarkYellow
}

# Overall Namespace Health Assessment
Write-Host "`n📊 Overall Namespace Health:" -ForegroundColor DarkCyan
$alignmentPercent = if ($audit.Count -gt 0) { [Math]::Round(($alignedFiles.Count / $audit.Count) * 100, 1) } else { 0 }
Write-Host "   Properly aligned files: $($alignedFiles.Count)/$($audit.Count) ($alignmentPercent%)" -ForegroundColor $(if ($alignmentPercent -gt 90) { "Green" } elseif ($alignmentPercent -gt 75) { "DarkYellow" } else { "Red" })
Write-Host "   Average namespace score: $averageScore/100" -ForegroundColor $(if ($averageScore -gt 90) { "Green" } elseif ($averageScore -gt 75) { "DarkYellow" } else { "Red" })

# Root Namespace Analysis
Write-Host "`n🌳 Root Namespace Analysis:" -ForegroundColor DarkCyan
if ($rootNamespaces.Count -gt 0) {
    $sortedRoots = $rootNamespaces.GetEnumerator() | Sort-Object Value -Descending
    Write-Host "   Found $($rootNamespaces.Count) root namespaces:" -ForegroundColor Gray
    foreach ($root in $sortedRoots) {
        $percentage = [Math]::Round(($root.Value / $audit.Count) * 100, 1)
        Write-Host "      • $($root.Key): $($root.Value) files ($percentage%)" -ForegroundColor $(if ($percentage -gt 50) { "Green" } else { "DarkGray" })
    }
    
    # Detect primary root namespace
    $primaryRoot = $sortedRoots[0]
    if ($primaryRoot.Value / $audit.Count -gt 0.8) {
        Write-Host "   ✅ Primary root namespace: $($primaryRoot.Key) (good consistency)" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️ No dominant root namespace (consider standardization)" -ForegroundColor DarkYellow
    }
} else {
    Write-Host "   ❌ No root namespaces found" -ForegroundColor Red
}

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

if ($totalSuggestions -gt 0) {
    Write-Host "   Suggestions: $totalSuggestions optimization opportunities" -ForegroundColor Cyan
}

if ($filesWithoutNamespace.Count -gt 0) {
    Write-Host "   Files without namespaces: $($filesWithoutNamespace.Count)" -ForegroundColor Red
}

# Show critical issues (limited for automation)
if ($filesWithIssues.Count -gt 0) {
    Write-Host "`n🚨 Critical Issues Found:" -ForegroundColor Red
    $topIssues = $filesWithIssues | Sort-Object { $_.Issues.Count } -Descending | Select-Object -First 5
    foreach ($file in $topIssues) {
        Write-Host "   📄 $($file.RelativePath) (Score: $($file.NamespaceScore)/100)" -ForegroundColor Red
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
    Write-Host "`n⚠️ Warnings Detected:" -ForegroundColor DarkYellow
    foreach ($file in $filesWithWarnings | Select-Object -First 3) {
        Write-Host "   📄 $($file.RelativePath)" -ForegroundColor DarkYellow
        $file.Warnings | ForEach-Object {
            Write-Host "      • $_" -ForegroundColor Gray
        }
    }
}

# Namespace Statistics
Write-Host "`n📈 Namespace Statistics:" -ForegroundColor DarkCyan
$totalUsings = ($audit | ForEach-Object { $_.UsingStatements.Count } | Measure-Object -Sum).Sum
$avgUsings = if ($audit.Count -gt 0) { [Math]::Round(($totalUsings / $audit.Count), 1) } else { 0 }
$maxDepth = ($audit | ForEach-Object { $_.NamespaceDepth } | Measure-Object -Maximum).Maximum
$avgDepth = if ($audit.Count -gt 0) { [Math]::Round(($audit | ForEach-Object { $_.NamespaceDepth } | Measure-Object -Average).Average, 1) } else { 0 }

Write-Host "   Total using statements: $totalUsings" -ForegroundColor Gray
Write-Host "   Average usings per file: $avgUsings" -ForegroundColor Gray
Write-Host "   Maximum namespace depth: $maxDepth" -ForegroundColor Gray
Write-Host "   Average namespace depth: $avgDepth" -ForegroundColor Gray

# Recommendations
Write-Host "`n💡 Recommendations:" -ForegroundColor DarkCyan

if ($filesWithIssues.Count -gt 0) {
    Write-Host "   🚨 CRITICAL: Fix $totalIssues namespace issues in $($filesWithIssues.Count) files" -ForegroundColor Red
    Write-Host "   • Add missing namespace declarations" -ForegroundColor Red
    Write-Host "   • Align namespaces with folder structure" -ForegroundColor Red
}

if ($projectVersions.Count -gt 1 -and ($projectVersions | Select-Object -Property Version -Unique).Count -gt 1) {
    Write-Host "   🏷️ CRITICAL: Standardize version numbers across all files" -ForegroundColor Red
}

if ($rootNamespaces.Count -gt 3) {
    Write-Host "   🌳 Consider consolidating to fewer root namespaces" -ForegroundColor DarkYellow
}

if ($avgDepth -gt 4) {
    Write-Host "   📊 Consider flattening namespace hierarchy (average depth: $avgDepth)" -ForegroundColor DarkYellow
}

Write-Host "   • Use consistent naming conventions" -ForegroundColor Gray
Write-Host "   • Group related functionality in same namespace" -ForegroundColor Gray
Write-Host "   • Follow .NET namespace guidelines" -ForegroundColor Gray

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

# Generate detailed namespace audit report
Write-Host "`n📝 Generating detailed namespace audit report..." -ForegroundColor DarkGray

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPath = Join-Path $reportsDir "NAMESPACE-AUDIT-REPORT_$timestamp.md"

$reportContent = @()
$reportContent += "# Namespace Audit Report"
$reportContent += ""
$reportContent += "**Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportContent += "**Files Analyzed**: $($audit.Count)"
$reportContent += "**Alignment Health**: $alignmentPercent%"
$reportContent += "**Average Namespace Score**: $averageScore/100"
$reportContent += ""

# Executive Summary
$reportContent += "## Executive Summary"
$reportContent += ""

if ($alignmentPercent -ge 95 -and $averageScore -ge 90) {
    $reportContent += "🎉 **EXCELLENT NAMESPACE ORGANIZATION!** Alignment: $alignmentPercent%, Score: $averageScore/100"
    $reportContent += ""
    $reportContent += "Your codebase demonstrates outstanding namespace consistency and organization."
} elseif ($alignmentPercent -ge 80 -and $averageScore -ge 75) {
    $reportContent += "✅ **GOOD NAMESPACE STRUCTURE!** Alignment: $alignmentPercent%, Score: $averageScore/100"
    $reportContent += ""
    $reportContent += "Minor namespace issues exist but overall organization is good."
} elseif ($alignmentPercent -ge 60 -or $averageScore -ge 50) {
    $reportContent += "⚠️ **NAMESPACE ISSUES DETECTED** - Alignment: $alignmentPercent%, Score: $averageScore/100"
    $reportContent += ""
    $reportContent += "**Recommendation**: Improve namespace consistency and alignment."
} else {
    $reportContent += "🚨 **CRITICAL NAMESPACE PROBLEMS** - Alignment: $alignmentPercent%, Score: $averageScore/100"
    $reportContent += ""
    $reportContent += "**Immediate Action Required**: Major namespace restructuring needed."
}

$reportContent += ""
$reportContent += "| Metric | Value | Status |"
$reportContent += "|--------|-------|--------|"
$reportContent += "| **Aligned Files** | $($alignedFiles.Count)/$($audit.Count) | $(if ($alignmentPercent -ge 95) { `"✅ Excellent`" } elseif ($alignmentPercent -ge 80) { `"⚠️ Good`" } else { `"🚨 Needs Work`" }) |"
$reportContent += "| **Average Score** | $averageScore/100 | $(if ($averageScore -ge 90) { `"✅ Excellent`" } elseif ($averageScore -ge 75) { `"⚠️ Good`" } else { `"🚨 Poor`" }) |"
$reportContent += "| **Critical Issues** | $totalIssues | $(if ($totalIssues -eq 0) { `"✅ None`" } elseif ($totalIssues -le 5) { `"⚠️ Few`" } else { `"🚨 Many`" }) |"
$reportContent += "| **Root Namespaces** | $($rootNamespaces.Count) | $(if ($rootNamespaces.Count -le 3) { `"✅ Good`" } elseif ($rootNamespaces.Count -le 5) { `"⚠️ Many`" } else { `"🚨 Too Many`" }) |"
$reportContent += "| **Missing Namespaces** | $($filesWithoutNamespace.Count) | $(if ($filesWithoutNamespace.Count -eq 0) { `"✅ None`" } else { `"🚨 Found`" }) |"
$reportContent += ""

# Version Consistency Analysis
if ($projectVersions.Count -gt 0) {
    $reportContent += "## 🏷️ Version Consistency Analysis"
    $reportContent += ""
    
    $uniqueVersions = $projectVersions | Select-Object -Property Version -Unique
    if ($uniqueVersions.Count -eq 1) {
        $reportContent += "✅ **All versions are consistent!**"
        $reportContent += ""
        $reportContent += "| Source | Version | File |"
        $reportContent += "|--------|---------|------|"
        foreach ($version in $projectVersions) {
            $reportContent += "| $($version.Source) | ````$($version.Version)```` | ````$($version.File)```` |"
        }
    } else {
        $reportContent += "🚨 **Version inconsistencies detected!**"
        $reportContent += ""
        $reportContent += "| Source | Version | File | Status |"
        $reportContent += "|--------|---------|------|--------|"
        
        $primaryVersion = ($projectVersions | Group-Object Version | Sort-Object Count -Descending)[0].Name
        foreach ($version in $projectVersions) {
            $status = if ($version.Version -eq $primaryVersion) { "✅ Primary" } else { "🚨 Inconsistent" }
            $reportContent += "| $($version.Source) | ````$($version.Version)```` | ````$($version.File)```` | $status |"
        }
        
        $reportContent += ""
        $reportContent += "**⚠️ Action Required**: Standardize all versions to match the primary version: ````$primaryVersion````"
    }
    $reportContent += ""
} else {
    $reportContent += "## 🏷️ Version Analysis"
    $reportContent += ""
    $reportContent += "⚠️ **No version information found in the project.**"
    $reportContent += ""
    $reportContent += "Consider adding version constants or project version information."
    $reportContent += ""
}

# Root Namespace Analysis
$reportContent += "## 🌳 Root Namespace Distribution"
$reportContent += ""

if ($rootNamespaces.Count -gt 0) {
    $reportContent += "| Root Namespace | Files | Percentage | Status |"
    $reportContent += "|----------------|-------|------------|--------|"
    
    $sortedRoots = $rootNamespaces.GetEnumerator() | Sort-Object Value -Descending
    foreach ($root in $sortedRoots) {
        $percentage = [Math]::Round(($root.Value / $audit.Count) * 100, 1)
        $status = if ($percentage -gt 50) { "✅ Primary" } elseif ($percentage -gt 20) { "⚠️ Secondary" } else { "📝 Minor" }
        $reportContent += "| ````$($root.Key)```` | $($root.Value) | $percentage% | $status |"
    }
    
    $reportContent += ""
    $primaryRoot = $sortedRoots[0]
    if ($primaryRoot.Value / $audit.Count -gt 0.8) {
        $reportContent += "✅ **Good namespace consistency** - Primary root namespace ````$($primaryRoot.Key)```` covers $([Math]::Round(($primaryRoot.Value / $audit.Count) * 100, 1))% of files."
    } else {
        $reportContent += "⚠️ **Consider namespace consolidation** - No single root namespace dominates the project."
    }
} else {
    $reportContent += "❌ **No root namespaces found** - All C# files need namespace declarations."
}

$reportContent += ""

# Critical Issues Analysis
if ($filesWithIssues.Count -gt 0) {
    $reportContent += "## 🚨 Critical Namespace Issues"
    $reportContent += ""
    $reportContent += "Files requiring immediate attention:"
    $reportContent += ""
    $reportContent += "| File | Score | Issues | Details |"
    $reportContent += "|------|-------|--------|---------|"
    
    foreach ($file in $filesWithIssues | Sort-Object NamespaceScore) {
        $issueList = ($file.Issues | Select-Object -First 2) -join "; "
        if ($file.Issues.Count -gt 2) {
            $issueList += "; ... +$($file.Issues.Count - 2) more"
        }
        $reportContent += "| ````$($file.RelativePath)```` | $($file.NamespaceScore)/100 | $($file.Issues.Count) | $issueList |"
    }
    $reportContent += ""
}

# Alignment Issues
if ($filesWithWarnings.Count -gt 0) {
    $reportContent += "## ⚠️ Namespace Alignment Warnings"
    $reportContent += ""
    $reportContent += "Files with alignment or consistency issues:"
    $reportContent += ""
    $reportContent += "| File | Current Namespace | Expected Pattern | Warnings |"
    $reportContent += "|------|-------------------|------------------|----------|"
    
    foreach ($file in $filesWithWarnings | Sort-Object { $_.Warnings.Count } -Descending) {
        $warningList = ($file.Warnings | Select-Object -First 2) -join "; "
        if ($file.Warnings.Count -gt 2) {
            $warningList += "; ... +$($file.Warnings.Count - 2) more"
        }
        $expected = if ($file.ExpectedNamespace) { $file.ExpectedNamespace } else { "N/A" }
        $current = if ($file.PrimaryNamespace) { $file.PrimaryNamespace } else { "None" }
        $reportContent += "| ````$($file.RelativePath)```` | ````$current```` | ````$expected```` | $warningList |"
    }
    $reportContent += ""
}

# Namespace Statistics
$reportContent += "## 📈 Namespace Statistics"
$reportContent += ""
$reportContent += "| Metric | Value |"
$reportContent += "|--------|-------|"
$reportContent += "| **Total Files** | $($audit.Count) |"
$reportContent += "| **Files with Namespaces** | $(($audit | Where-Object { $_.PrimaryNamespace -ne `"`" }).Count) |"
$reportContent += "| **Total Using Statements** | $totalUsings |"
$reportContent += "| **Average Usings per File** | $avgUsings |"
$reportContent += "| **Maximum Namespace Depth** | $maxDepth |"
$reportContent += "| **Average Namespace Depth** | $avgDepth |"
$reportContent += "| **Unique Root Namespaces** | $($rootNamespaces.Count) |"
$reportContent += ""

# Folder Structure Analysis
if ($folderStructure.Count -gt 0) {
    $reportContent += "## 📂 Folder Structure Mapping"
    $reportContent += ""
    $reportContent += "| Folder Path | Namespace | Alignment |"
    $reportContent += "|-------------|-----------|-----------|"
    
    foreach ($folder in $folderStructure.GetEnumerator() | Sort-Object Key) {
        $alignment = if ($folder.Value.ToLower().EndsWith($folder.Key.ToLower().Replace('\', '.').Replace('/', '.'))) { "✅ Aligned" } else { "⚠️ Misaligned" }
        $reportContent += "| ````$($folder.Key)```` | ````$($folder.Value)```` | $alignment |"
    }
    $reportContent += ""
}

# Action Plan
$reportContent += "## 🎯 Action Plan"
$reportContent += ""

if ($filesWithIssues.Count -gt 0) {
    $reportContent += "### 🚨 CRITICAL: Fix Namespace Issues"
    $reportContent += ""
    $reportContent += "**$totalIssues critical namespace issues** require immediate attention:"
    $reportContent += ""
    $reportContent += "1. **Add Missing Namespaces**: $($filesWithoutNamespace.Count) files need namespace declarations"
    $reportContent += "2. **Fix Alignment Issues**: Align namespaces with folder structure"
    $reportContent += "3. **Resolve Conflicts**: Address multiple namespace declarations"
    $reportContent += ""
}

if ($projectVersions.Count -gt 1 -and ($projectVersions | Select-Object -Property Version -Unique).Count -gt 1) {
    $reportContent += "### 🏷️ CRITICAL: Standardize Version Numbers"
    $reportContent += ""
    $reportContent += "**Version inconsistencies detected** across multiple files:"
    $reportContent += ""
    $reportContent += "1. **Choose Primary Version**: Select the correct version number"
    $reportContent += "2. **Update All Sources**: Ensure consistency across all version declarations"
    $reportContent += "3. **Establish Process**: Create version management guidelines"
    $reportContent += ""
}

if ($rootNamespaces.Count -gt 3) {
    $reportContent += "### 🌳 OPTIMIZE: Consolidate Root Namespaces"
    $reportContent += ""
    $reportContent += "**$($rootNamespaces.Count) root namespaces** found - consider consolidation:"
    $reportContent += ""
    $reportContent += "1. **Identify Primary**: Choose main project namespace"
    $reportContent += "2. **Migrate Secondary**: Move related functionality to primary namespace"
    $reportContent += "3. **Update References**: Fix using statements and dependencies"
    $reportContent += ""
}

# Best Practices
$reportContent += "### Best Practices for .NET 6"
$reportContent += ""
$reportContent += "1. **Namespace-Folder Alignment**: Match namespace hierarchy to folder structure"
$reportContent += "2. **Consistent Root Namespace**: Use single primary root namespace"
$reportContent += "3. **Logical Grouping**: Group related functionality in same namespace"
$reportContent += "4. **Depth Management**: Keep namespace depth reasonable (≤ 4 levels)"
$reportContent += "5. **Using Organization**: Group System usings separately from project usings"

# Technical Details
$reportContent += ""
$reportContent += "## Technical Analysis Details"
$reportContent += ""
$reportContent += "### Validation Checks Performed"
$reportContent += ""
$reportContent += "- **Namespace Declaration**: Presence and format validation"
$reportContent += "- **Folder Alignment**: Namespace vs. folder structure comparison"
$reportContent += "- **Using Statement Analysis**: System vs. project reference analysis"
$reportContent += "- **Circular Reference Detection**: Potential circular dependency identification"
$reportContent += "- **Depth Analysis**: Namespace hierarchy complexity measurement"
$reportContent += "- **Version Consistency**: Cross-file version comparison"
$reportContent += ""
$reportContent += "### Scoring Methodology"
$reportContent += ""
$reportContent += "- **Base Score**: 100 points"
$reportContent += "- **Critical Issues**: -30 points each (missing namespaces, errors)"
$reportContent += "- **Warnings**: -15 points each (alignment issues, multiple declarations)"
$reportContent += "- **Suggestions**: -5 points each (depth, optimization opportunities)"
$reportContent += "- **Minimum Score**: 0 points"

# Footer
$reportContent += ""
$reportContent += "---"
$reportContent += ""
$reportContent += "**Target Alignment**: 95%+ files properly aligned"
$reportContent += ""
$reportContent += "*Generated by MixerThreholdMod DevOps Suite - Namespace Audit Tool*"

try {
    $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
    $saveSuccess = $true
}
catch {
    Write-Host "⚠️ Error saving detailed report: $_" -ForegroundColor DarkYellow
    $saveSuccess = $false
}

Write-Host "`n🚀 Namespace audit complete!" -ForegroundColor Green

# OUTPUT PATH AT THE END for easy finding
if ($saveSuccess) {
    Write-Host "`n📄 DETAILED REPORT SAVED:" -ForegroundColor Green
    Write-Host "   Location: $reportPath" -ForegroundColor Cyan
    Write-Host "   Size: $([Math]::Round((Get-Item $reportPath).Length / 1KB, 1)) KB" -ForegroundColor Gray
    Write-Host "   Alignment Score: $alignmentPercent%" -ForegroundColor $(if ($alignmentPercent -ge 95) { "Green" } elseif ($alignmentPercent -ge 80) { "DarkYellow" } else { "Red" })
} else {
    Write-Host "`n⚠️ No detailed report generated" -ForegroundColor DarkYellow
}

# INTERACTIVE WORKFLOW LOOP (D/R/X) - only when running standalone
if ($IsInteractive -and -not $RunningFromScript) {
    do {
        Write-Host "`n🎯 What would you like to do next?" -ForegroundColor DarkCyan
        Write-Host "   D - Display report in console" -ForegroundColor Green
        Write-Host "   R - Re-run namespace audit analysis" -ForegroundColor DarkYellow
        Write-Host "   X - Exit to DevOps menu" -ForegroundColor Gray
        
        $choice = Read-Host "`nEnter choice (D/R/X)"
        $choice = $choice.ToUpper()
        
        switch ($choice) {
            'D' {
                if ($saveSuccess) {
                    Write-Host "`n📋 DISPLAYING NAMESPACE AUDIT REPORT:" -ForegroundColor DarkCyan
                    Write-Host "======================================" -ForegroundColor DarkCyan
                    try {
                        $reportDisplay = Get-Content -Path $reportPath -Raw
                        Write-Host $reportDisplay -ForegroundColor White
                        Write-Host "`n======================================" -ForegroundColor DarkCyan
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
                Write-Host "`n🔄 RE-RUNNING NAMESPACE AUDIT..." -ForegroundColor DarkYellow
                Write-Host "===============================" -ForegroundColor DarkYellow
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