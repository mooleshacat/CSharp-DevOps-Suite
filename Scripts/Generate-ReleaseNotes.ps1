# MixerThreholdMod DevOps Tool: Release Notes Generator (NON-INTERACTIVE)
# Creates professional release notes from git commits and closed issues
# Integrates with changelog and generates formatted release documentation
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

Write-Host "🕐 Release notes generation started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "Generating release notes in: $ProjectRoot" -ForegroundColor DarkCyan
Write-Host "🚀 NON-INTERACTIVE VERSION - Compatible with automation" -ForegroundColor Green

# Function to get current version
function Get-CurrentVersion {
    # Try multiple locations for version constants
    $constantsFiles = @(
        "Constants\SystemConstants.cs",
        "Constants\Constants.cs",
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
    
    Write-Host "   📋 Using default version: 1.0.0" -ForegroundColor Gray
    return "1.0.0"  # Default version
}

# Function to check git repository
function Test-GitRepository {
    param($path)
    
    try {
        Push-Location $path
        $null = git rev-parse --git-dir 2>$null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
    finally {
        Pop-Location
    }
}

# Function to get git tags with dates
function Get-GitTags {
    try {
        $tags = git tag --sort=-version:refname 2>$null
        if ($LASTEXITCODE -ne 0) { return @() }
        
        $tagData = @()
        foreach ($tag in $tags) {
            if ($tag) {
                try {
                    $tagDate = git log -1 --format=%ai $tag 2>$null
                    $tagData += [PSCustomObject]@{
                        Name = $tag
                        Date = if ($tagDate) { [DateTime]::Parse($tagDate) } else { [DateTime]::Now }
                    }
                }
                catch {
                    $tagData += [PSCustomObject]@{
                        Name = $tag
                        Date = [DateTime]::Now
                    }
                }
            }
        }
        
        return $tagData | Sort-Object Date -Descending
    }
    catch {
        return @()
    }
}

# Function to get commits for release
function Get-ReleaseCommits {
    param($fromTag, $toRef)
    
    try {
        if ($fromTag) {
            $gitRange = "$($fromTag.Name)..$toRef"
        } else {
            $gitRange = $toRef
        }
        
        Write-Host "   📈 Fetching commits from range: $gitRange" -ForegroundColor DarkGray
        
        $gitLogFormat = '--pretty=format:%H|%s|%an|%ad|%b'
        $commits = git log $gitRange $gitLogFormat --date=short --no-merges 2>$null
        
        if ($LASTEXITCODE -ne 0) {
            return @()
        }
        
        $commitData = @()
        foreach ($commitLine in $commits) {
            if (-not $commitLine) { continue }
            
            $parts = $commitLine -split '\|', 5
            if ($parts.Count -lt 4) { continue }
            
            $hash = $parts[0]
            $subject = $parts[1]
            $author = $parts[2]
            $date = $parts[3]
            $body = if ($parts.Count -gt 4) { $parts[4] } else { "" }
            
            # Skip merge commits
            if ($subject -match '^Merge ') { continue }
            
            $commitData += [PSCustomObject]@{
                Hash = $hash.Substring(0, 7)
                FullHash = $hash
                Subject = $subject
                Author = $author
                Date = [DateTime]::Parse($date)
                Body = $body
                Category = Get-CommitCategory -message $subject
            }
        }
        
        return $commitData | Sort-Object Date -Descending
    }
    catch {
        Write-Host "   ⚠️  Error fetching commits: $_" -ForegroundColor DarkYellow
        return @()
    }
}

# Function to categorize commits
function Get-CommitCategory {
    param($message)
    
    $message = $message.ToLower()
    
    # High priority categories first
    if ($message -match '!:' -or $message -match 'breaking') { return "BREAKING" }
    if ($message -match '^feat(\(.+\))?:') { return "FEATURE" }
    if ($message -match '^fix(\(.+\))?:') { return "BUGFIX" }
    if ($message -match '(security|vulnerability|cve)') { return "SECURITY" }
    
    # Project-specific categories
    if ($message -match '(save|backup|crash|emergency)') { return "SAVE_SYSTEM" }
    if ($message -match '(thread|async|lock|concurrent)') { return "THREAD_SAFETY" }
    if ($message -match '(mixer|audio|volume|threshold)') { return "MIXER_FEATURES" }
    if ($message -match '(performance|optimize|memory|cpu)') { return "PERFORMANCE" }
    
    # Standard categories
    if ($message -match '^docs(\(.+\))?:') { return "DOCUMENTATION" }
    if ($message -match '^chore(\(.+\))?:') { return "MAINTENANCE" }
    
    return "OTHER"
}

# Function to format commit for release notes
function Format-CommitForRelease {
    param($commit)
    
    $message = $commit.Subject
    
    # Remove conventional commit prefixes
    $message = $message -replace '^(feat|fix|docs|style|refactor|perf|test|chore|build|ci)(\(.+\))?:\s*', ''
    
    # Capitalize first letter
    if ($message.Length -gt 0) {
        $message = $message.Substring(0, 1).ToUpper() + $message.Substring(1)
    }
    
    return $message
}

# Function to get release type based on commits
function Get-ReleaseType {
    param($commits)
    
    $hasBreaking = $commits | Where-Object { $_.Category -eq "BREAKING" }
    $hasFeatures = $commits | Where-Object { $_.Category -eq "FEATURE" }
    $hasBugfixes = $commits | Where-Object { $_.Category -eq "BUGFIX" }
    $hasSecurity = $commits | Where-Object { $_.Category -eq "SECURITY" }
    
    if ($hasBreaking) { return "Major Release" }
    if ($hasFeatures -or $hasSecurity) { return "Minor Release" }
    if ($hasBugfixes) { return "Patch Release" }
    return "Maintenance Release"
}

# Main script execution
if (-not (Test-GitRepository -path $ProjectRoot)) {
    Write-Host "❌ Not a git repository or git not available" -ForegroundColor Red
    Write-Host "This script requires git and must be run in a git repository" -ForegroundColor DarkYellow
    if ($IsInteractive -and -not $RunningFromScript) {
        Write-Host "``nPress ENTER to continue..." -ForegroundColor Gray -NoNewline
        Read-Host
    }
    return
}

Push-Location $ProjectRoot

Write-Host "``n📊 Analyzing release data..." -ForegroundColor DarkGray

# Get current version and tags
$currentVersion = Get-CurrentVersion
$tags = Get-GitTags

Write-Host "📋 Current version: $currentVersion" -ForegroundColor Gray
Write-Host "📋 Available tags: $($tags.Count)" -ForegroundColor Gray

# AUTOMATED: Always use current version with latest tag as FROM reference
$releaseVersion = $currentVersion
$fromTag = if ($tags.Count -gt 0) { $tags[0] } else { $null }
$toRef = "HEAD"

if ($fromTag) {
    Write-Host "📋 Generating release notes from $($fromTag.Name) to HEAD for version $releaseVersion" -ForegroundColor Green
} else {
    Write-Host "📋 Generating release notes from beginning to HEAD for version $releaseVersion" -ForegroundColor Green
}

# Get commits for this release
Write-Host "``n🔍 Fetching commits..." -ForegroundColor DarkGray
$commits = Get-ReleaseCommits -fromTag $fromTag -toRef $toRef

if ($commits.Count -eq 0) {
    Write-Host "❌ No commits found for release range" -ForegroundColor Red
    Pop-Location
    if ($IsInteractive -and -not $RunningFromScript) {
        Write-Host "``nPress ENTER to continue..." -ForegroundColor Gray -NoNewline
        Read-Host
    }
    return
}

Write-Host "✅ Found $($commits.Count) commits for release" -ForegroundColor Gray

# Categorize commits
$categorizedCommits = $commits | Group-Object Category | Sort-Object @{
    Expression = {
        switch ($_.Name) {
            "BREAKING" { 1 }
            "SECURITY" { 2 }
            "FEATURE" { 3 }
            "BUGFIX" { 4 }
            "SAVE_SYSTEM" { 5 }
            "THREAD_SAFETY" { 6 }
            "MIXER_FEATURES" { 7 }
            "PERFORMANCE" { 8 }
            "DOCUMENTATION" { 9 }
            "MAINTENANCE" { 10 }
            "OTHER" { 99 }
            default { 50 }
        }
    }
}

# Determine release type
$releaseType = Get-ReleaseType -commits $commits

# Generate release notes content (streamlined for automation)
$releaseNotes = @()

# Header
$releaseNotes += "# MixerThreholdMod v$releaseVersion"
$releaseNotes += ""
$releaseNotes += "**Release Type**: $releaseType"
$releaseNotes += "**Release Date**: $(Get-Date -Format 'yyyy-MM-dd')"
$releaseNotes += "**Commits**: $($commits.Count)"

# Add author info if available
$topAuthor = $commits | Group-Object Author | Sort-Object Count -Descending | Select-Object -First 1
if ($topAuthor) {
    $releaseNotes += "**Primary Contributor**: $($topAuthor.Name)"
}

$releaseNotes += ""

# Release highlights
$releaseNotes += "## 🎯 Release Highlights"
$releaseNotes += ""

$highlights = @()
$featureCount = ($categorizedCommits | Where-Object { $_.Name -eq "FEATURE" }).Count
$bugfixCount = ($categorizedCommits | Where-Object { $_.Name -eq "BUGFIX" }).Count
$performanceCount = ($categorizedCommits | Where-Object { $_.Name -eq "PERFORMANCE" }).Count

if ($featureCount -gt 0) { $highlights += "✨ **$featureCount new features** added" }
if ($bugfixCount -gt 0) { $highlights += "🐛 **$bugfixCount bug fixes** resolved" }
if ($performanceCount -gt 0) { $highlights += "⚡ **$performanceCount performance improvements**" }

$securityCommits = $categorizedCommits | Where-Object { $_.Name -eq "SECURITY" }
if ($securityCommits) { $highlights += "🔒 **Security updates** included" }

$breakingCommits = $categorizedCommits | Where-Object { $_.Name -eq "BREAKING" }
if ($breakingCommits) { $highlights += "🚨 **Breaking changes** - see migration guide below" }

foreach ($highlight in $highlights) {
    $releaseNotes += "- $highlight"
}

if ($highlights.Count -eq 0) {
    $releaseNotes += "- 🔧 Maintenance release with code quality improvements"
}

$releaseNotes += ""

# Downloads section (simplified)
$releaseNotes += "## 📥 Downloads"
$releaseNotes += ""
$releaseNotes += "| Platform | Download |"
$releaseNotes += "|----------|----------|"
$releaseNotes += "| **Windows (x64)** | [MixerThreholdMod-$releaseVersion-win-x64.dll](../../releases/download/v$releaseVersion/MixerThreholdMod-$releaseVersion-win-x64.dll) |"
$releaseNotes += "| **Source Code** | [Source (zip)](../../archive/v$releaseVersion.zip) |"
$releaseNotes += ""

# What's Changed section (condensed)
$releaseNotes += "## 📋 What's Changed"
$releaseNotes += ""

foreach ($categoryGroup in $categorizedCommits) {
    $categoryName = $categoryGroup.Name
    $categoryCommits = $categoryGroup.Group
    
    # Map category to display info
    $categoryInfo = switch ($categoryName) {
        "BREAKING" { @{ Icon = "🚨"; Title = "Breaking Changes" } }
        "SECURITY" { @{ Icon = "🔒"; Title = "Security Updates" } }
        "FEATURE" { @{ Icon = "✨"; Title = "New Features" } }
        "BUGFIX" { @{ Icon = "🐛"; Title = "Bug Fixes" } }
        "SAVE_SYSTEM" { @{ Icon = "💾"; Title = "Save System" } }
        "THREAD_SAFETY" { @{ Icon = "🔒"; Title = "Thread Safety" } }
        "MIXER_FEATURES" { @{ Icon = "🎵"; Title = "Mixer Features" } }
        "PERFORMANCE" { @{ Icon = "⚡"; Title = "Performance" } }
        "DOCUMENTATION" { @{ Icon = "📝"; Title = "Documentation" } }
        "MAINTENANCE" { @{ Icon = "🧹"; Title = "Maintenance" } }
        default { @{ Icon = "📌"; Title = "Other Changes" } }
    }
    
    $releaseNotes += "### $($categoryInfo.Icon) $($categoryInfo.Title)"
    $releaseNotes += ""
    
    foreach ($commit in $categoryCommits | Sort-Object Date -Descending | Select-Object -First 10) {  # Limit for automation
        $formattedMessage = Format-CommitForRelease -commit $commit
        # FIXED: Use double backticks for PowerShell 5.1 compatibility
        $releaseNotes += "- $formattedMessage ([````$($commit.Hash)````](../../commit/$($commit.FullHash)))"
    }
    
    if ($categoryCommits.Count -gt 10) {
        $releaseNotes += "- ... and $($categoryCommits.Count - 10) more changes"
    }
    
    $releaseNotes += ""
}

# Compatibility section (simplified)
$releaseNotes += "## ⚙️ Compatibility"
$releaseNotes += ""
$releaseNotes += "- **Schedule 1**: Latest version"
$releaseNotes += "- **MelonLoader**: 0.5.7+"
$releaseNotes += "- **.NET Framework**: 4.8.1"
$releaseNotes += "- **Platform**: Windows/Linux"
$releaseNotes += ""

# Installation instructions
$releaseNotes += "## 🔄 Installation"
$releaseNotes += ""
if ($breakingCommits) {
    $releaseNotes += "⚠️ **Important**: This release contains breaking changes."
    $releaseNotes += ""
    $releaseNotes += "1. **Backup your saves** before upgrading"
    $releaseNotes += "2. Download the new version"
    $releaseNotes += "3. Replace the old DLL in your ````Mods```` folder"
    $releaseNotes += "4. **Test thoroughly** after upgrade"
} else {
    $releaseNotes += "1. Download the DLL from the links above"
    $releaseNotes += "2. Place in your ````Mods```` folder"
    $releaseNotes += "3. Restart Schedule 1"
}
$releaseNotes += ""

# Footer
$releaseNotes += "---"
$releaseNotes += ""
if ($fromTag) {
    $releaseNotes += "**Full Changelog**: https://github.com/YourRepo/MixerThreholdMod/compare/$($fromTag.Name)...v$releaseVersion"
}
$releaseNotes += ""
$releaseNotes += "_Generated automatically by Generate-ReleaseNotes.ps1 on $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')_"

# Save release notes
$outputPath = Join-Path $ProjectRoot "RELEASE-NOTES-v$releaseVersion.md"

try {
    $releaseNotes | Out-File -FilePath $outputPath -Encoding UTF8
    $savedSuccessfully = $true
}
catch {
    Write-Host "⚠️  Error saving release notes: $_" -ForegroundColor DarkYellow
    $savedSuccessfully = $false
}

Pop-Location

Write-Host "``n=== RELEASE NOTES GENERATION REPORT ===" -ForegroundColor DarkCyan
Write-Host "🕐 Generation completed: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray

if ($savedSuccessfully) {
    Write-Host "✅ Release notes generated successfully!" -ForegroundColor Green
    Write-Host "📄 Output saved to: $outputPath" -ForegroundColor Gray
} else {
    Write-Host "❌ Failed to save release notes" -ForegroundColor Red
}

Write-Host "📋 Release type: $releaseType" -ForegroundColor Gray
Write-Host "📊 Total commits: $($commits.Count)" -ForegroundColor Gray
Write-Host "🏷️  Version: $releaseVersion" -ForegroundColor Gray

# Category breakdown (condensed)
Write-Host "``n📋 Changes by Category:" -ForegroundColor DarkCyan
foreach ($category in $categorizedCommits | Sort-Object Count -Descending | Select-Object -First 5) {
    $color = switch ($category.Name) {
        "BREAKING" { "Red" }
        "SECURITY" { "Red" }
        "FEATURE" { "Green" }
        "BUGFIX" { "DarkYellow" }
        default { "Gray" }
    }
    $displayName = switch ($category.Name) {
        "BREAKING" { "Breaking Changes" }
        "SECURITY" { "Security Updates" }
        "FEATURE" { "New Features" }
        "BUGFIX" { "Bug Fixes" }
        "SAVE_SYSTEM" { "Save System" }
        "THREAD_SAFETY" { "Thread Safety" }
        "MIXER_FEATURES" { "Mixer Features" }
        "PERFORMANCE" { "Performance" }
        "DOCUMENTATION" { "Documentation" }
        "MAINTENANCE" { "Maintenance" }
        default { "Other Changes" }
    }
    Write-Host "   $displayName``: $($category.Count) changes" -ForegroundColor $color
}

if ($categorizedCommits.Count -gt 5) {
    Write-Host "   ... and $($categorizedCommits.Count - 5) more categories" -ForegroundColor DarkGray
}

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

# Generate detailed release notes analysis report
Write-Host "``n📝 Generating detailed release notes analysis report..." -ForegroundColor DarkGray

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPath = Join-Path $reportsDir "RELEASE-NOTES-ANALYSIS-REPORT_$timestamp.md"

$reportContent = @()
$reportContent += "# Release Notes Generation Analysis Report"
$reportContent += ""
$reportContent += "**Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportContent += "**Release Version**: $releaseVersion"
$reportContent += "**Release Type**: $releaseType"
$reportContent += "**Commits Analyzed**: $($commits.Count)"
$reportContent += ""

# Executive Summary
$reportContent += "## Executive Summary"
$reportContent += ""

if ($savedSuccessfully) {
    $reportContent += "✅ **RELEASE NOTES GENERATED SUCCESSFULLY** - Ready for publication."
    $reportContent += ""
    $reportContent += "Professional release notes created for version $releaseVersion with $($commits.Count) commits analyzed."
} else {
    $reportContent += "❌ **GENERATION FAILED** - Unable to create release notes file."
    $reportContent += ""
    $reportContent += "Check file permissions and disk space."
}

$reportContent += ""
$reportContent += "| Metric | Value | Status |"
$reportContent += "|--------|-------|--------|"
$reportContent += "| **Release Version** | $releaseVersion | - |"
$reportContent += "| **Release Type** | $releaseType | $(if ($releaseType -eq "Major Release") { "🚨 Breaking Changes" } elseif ($releaseType -eq "Minor Release") { "✨ Features Added" } else { "🔧 Maintenance" }) |"
$reportContent += "| **Commits Analyzed** | $($commits.Count) | $(if ($commits.Count -gt 0) { "✅ Changes Found" } else { "⚠️ No Changes" }) |"
$reportContent += "| **Categories** | $($categorizedCommits.Count) | $(if ($categorizedCommits.Count -gt 3) { "✅ Diverse Changes" } else { "📝 Focused Changes" }) |"
$reportContent += "| **Release Notes Saved** | $(if ($savedSuccessfully) { "Yes" } else { "No" }) | $(if ($savedSuccessfully) { "✅ Success" } else { "❌ Failed" }) |"

# Check for critical items
$hasCritical = $breakingCommits -or $securityCommits
$reportContent += "| **Critical Items** | $(if ($hasCritical) { "Yes" } else { "No" }) | $(if ($hasCritical) { "🚨 Review Required" } else { "✅ Standard Release" }) |"

$reportContent += ""

# Release Composition Analysis
if ($categorizedCommits.Count -gt 0) {
    $reportContent += "## Release Composition Analysis"
    $reportContent += ""
    
    $reportContent += "### Changes by Category"
    $reportContent += ""
    $reportContent += "| Category | Count | Percentage | Impact |"
    $reportContent += "|----------|-------|------------|--------|"
    
    foreach ($categoryGroup in $categorizedCommits | Sort-Object Count -Descending) {
        $percentage = [Math]::Round(($categoryGroup.Count / $commits.Count) * 100, 1)
        
        $impact = switch ($categoryGroup.Name) {
            "BREAKING" { "🚨 HIGH - Breaking changes" }
            "SECURITY" { "🔒 HIGH - Security updates" }
            "FEATURE" { "✨ MEDIUM - New functionality" }
            "BUGFIX" { "🐛 MEDIUM - Fixes issues" }
            "PERFORMANCE" { "⚡ MEDIUM - Improves speed" }
            default { "📝 LOW - Maintenance" }
        }
        
        $displayName = switch ($categoryGroup.Name) {
            "BREAKING" { "🚨 Breaking Changes" }
            "SECURITY" { "🔒 Security Updates" }
            "FEATURE" { "✨ New Features" }
            "BUGFIX" { "🐛 Bug Fixes" }
            "SAVE_SYSTEM" { "💾 Save System" }
            "THREAD_SAFETY" { "🔒 Thread Safety" }
            "MIXER_FEATURES" { "🎵 Mixer Features" }
            "PERFORMANCE" { "⚡ Performance" }
            "DOCUMENTATION" { "📝 Documentation" }
            "MAINTENANCE" { "🧹 Maintenance" }
            default { "📌 Other Changes" }
        }
        
        $reportContent += "| $displayName | $($categoryGroup.Count) | $percentage% | $impact |"
    }
    
    $reportContent += ""
    
    # Highlight important categories
    if ($breakingCommits) {
        $reportContent += "### ⚠️ Breaking Changes Alert"
        $reportContent += ""
        $reportContent += "**$($breakingCommits.Count) breaking changes** detected in this release:"
        $reportContent += ""
        foreach ($commit in $breakingCommits | Select-Object -First 5) {
            $formattedMessage = Format-CommitForRelease -commit $commit
            $reportContent += "- $formattedMessage ([````$($commit.Hash)````](../../commit/$($commit.FullHash)))"
        }
        if ($breakingCommits.Count -gt 5) {
            $reportContent += "- ... and $($breakingCommits.Count - 5) more breaking changes"
        }
        $reportContent += ""
        $reportContent += "**Required Actions:**"
        $reportContent += "1. Add migration guide to release notes"
        $reportContent += "2. Update documentation for breaking changes"
        $reportContent += "3. Notify users about required updates"
        $reportContent += ""
    }
    
    if ($securityCommits) {
        $reportContent += "### 🔒 Security Updates"
        $reportContent += ""
        $reportContent += "**Security improvements** included in this release."
        $reportContent += ""
        $reportContent += "Ensure security updates are highlighted in release announcement."
        $reportContent += ""
    }
}

# Git Analysis
$reportContent += "## Git Analysis"
$reportContent += ""

if ($fromTag) {
    $reportContent += "### Release Range"
    $reportContent += ""
    $reportContent += "- **From**: $($fromTag.Name) ($($fromTag.Date.ToString('yyyy-MM-dd')))"
    $reportContent += "- **To**: HEAD (current)"
    $reportContent += "- **Range**: $($fromTag.Name)..HEAD"
    $reportContent += ""
} else {
    $reportContent += "### Full History Release"
    $reportContent += ""
    $reportContent += "- **Range**: Complete repository history"
    $reportContent += "- **Note**: No previous tags found - this appears to be the first tagged release"
    $reportContent += ""
}

# Contributor Analysis
$contributors = $commits | Group-Object Author | Sort-Object Count -Descending
if ($contributors.Count -gt 0) {
    $reportContent += "### Contributors"
    $reportContent += ""
    $reportContent += "| Contributor | Commits | Percentage |"
    $reportContent += "|-------------|---------|------------|"
    
    foreach ($contributor in $contributors | Select-Object -First 5) {
        $percentage = [Math]::Round(($contributor.Count / $commits.Count) * 100, 1)
        $reportContent += "| $($contributor.Name) | $($contributor.Count) | $percentage% |"
    }
    
    if ($contributors.Count -gt 5) {
        $reportContent += ""
        $reportContent += "*... and $($contributors.Count - 5) more contributors*"
    }
    $reportContent += ""
}

# Generated Files
$reportContent += "## Generated Files"
$reportContent += ""

if ($savedSuccessfully) {
    $reportContent += "### Release Notes"
    $reportContent += ""
    $reportContent += "- **File**: ````RELEASE-NOTES-v$releaseVersion.md````"
    # FIXED: Use separate variable for safer string concatenation
    $locationText = "- **Location**: Project root directory"
    $reportContent += $locationText
    $reportContent += "- **Size**: $(if (Test-Path $outputPath) { "$([Math]::Round((Get-Item $outputPath).Length / 1KB, 1)) KB" } else { "Unknown" })"
    $reportContent += "- **Format**: GitHub-compatible markdown"
    $reportContent += ""
    $reportContent += "### Content Sections"
    $reportContent += ""
    $reportContent += "- ✅ Release highlights and summary"
    $reportContent += "- ✅ Download links for releases"
    $reportContent += "- ✅ Categorized change list"
    $reportContent += "- ✅ Compatibility information"
    $reportContent += "- ✅ Installation instructions"
    if ($breakingCommits) {
        $reportContent += "- ⚠️ Breaking changes warnings"
    }
    $reportContent += ""
} else {
    $reportContent += "### ❌ Release Notes Generation Failed"
    $reportContent += ""
    $reportContent += "**Issues to resolve:**"
    $reportContent += "- Check file system permissions"
    $reportContent += "- Verify disk space availability"
    $reportContent += "- Ensure project root is writable"
    $reportContent += ""
}

# Recommendations
$reportContent += "## 🎯 Recommendations"
$reportContent += ""

if ($savedSuccessfully) {
    $reportContent += "### ✅ Pre-Publication Checklist"
    $reportContent += ""
    $reportContent += "1. **Review Content**: Verify generated release notes for accuracy"
    $reportContent += "2. **Update Links**: Ensure download links point to correct releases"
    $reportContent += "3. **Test Downloads**: Verify release assets are available"
    
    if ($breakingCommits) {
        $reportContent += "4. **⚠️ Breaking Changes**: Add detailed migration guide"
        $reportContent += "5. **⚠️ User Communication**: Prepare announcement about breaking changes"
    } else {
        $reportContent += "4. **Smooth Update**: Standard release - no special precautions needed"
    }
    
    $reportContent += ""
    $reportContent += "### 🚀 Publication Steps"
    $reportContent += ""
    # FIXED: Split git command to avoid && operator issue in PowerShell 5.1
    $gitTagCommand = "1. **Create Git Tag**: ````git tag v$releaseVersion```` and ````git push origin v$releaseVersion````"
    $reportContent += $gitTagCommand
    $reportContent += "2. **GitHub Release**: Create release on GitHub with generated notes"
    $reportContent += "3. **Upload Assets**: Attach compiled DLL and documentation"
    $reportContent += "4. **Announce**: Share release information with community"
} else {
    $reportContent += "### ❌ Fix Generation Issues"
    $reportContent += ""
    $reportContent += "1. **Resolve Errors**: Fix file system or permission issues"
    $reportContent += "2. **Re-run Script**: Generate release notes again"
    $reportContent += "3. **Verify Output**: Ensure files are created successfully"
}

# Technical Details
$reportContent += ""
$reportContent += "## Technical Generation Details"
$reportContent += ""
$reportContent += "### Process Summary"
$reportContent += ""
$reportContent += "- **Git Repository**: $(if (Test-GitRepository $ProjectRoot) { "✅ Valid" } else { "❌ Invalid" })"
$reportContent += "- **Version Detection**: Automatic from constants files"
$reportContent += "- **Commit Range**: $(if ($fromTag) { "Tag-based ($($fromTag.Name)..HEAD)" } else { "Full history" })"
$reportContent += "- **Categorization**: Conventional commit patterns + project-specific rules"
$reportContent += "- **Output Format**: GitHub release-compatible markdown"
$reportContent += ""
$reportContent += "### Release Type Logic"
$reportContent += ""
$reportContent += "- **Major Release**: Contains breaking changes"
$reportContent += "- **Minor Release**: New features or security updates"
$reportContent += "- **Patch Release**: Bug fixes only"
$reportContent += "- **Maintenance Release**: Documentation or maintenance changes"

# Footer
$reportContent += ""
$reportContent += "---"
$reportContent += ""
$reportContent += "**Release Management**: Follow semantic versioning for consistent releases"
$reportContent += ""
$reportContent += "*Generated by MixerThreholdMod DevOps Suite - Release Notes Generator*"

try {
    $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
    $reportSaveSuccess = $true
}
catch {
    Write-Host "⚠️ Error saving analysis report: $_" -ForegroundColor DarkYellow
    $reportSaveSuccess = $false
}

# Quick recommendations
Write-Host "``n💡 Recommendations:" -ForegroundColor DarkCyan
if ($breakingCommits) {
    Write-Host "   🚨 CRITICAL: Review breaking changes in generated notes" -ForegroundColor Red
    Write-Host "   • Update migration documentation" -ForegroundColor Red
} else {
    Write-Host "   ✅ Release notes ready for publication" -ForegroundColor Green
}

if ($savedSuccessfully) {
    Write-Host "   • Review generated content for accuracy" -ForegroundColor Gray
    Write-Host "   • Create git tag: git tag v$releaseVersion" -ForegroundColor Gray
    Write-Host "   • Publish the release on GitHub" -ForegroundColor Gray
} else {
    Write-Host "   ❌ Fix file saving issues and regenerate" -ForegroundColor Red
}

Write-Host "``n🚀 Release notes generation complete!" -ForegroundColor Green

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
        Write-Host "   R - Re-run release notes generation" -ForegroundColor DarkYellow
        Write-Host "   X - Exit to DevOps menu" -ForegroundColor Gray
        
        $choice = Read-Host "``nEnter choice (D/R/X)"
        $choice = $choice.ToUpper()
        
        switch ($choice) {
            'D' {
                if ($reportSaveSuccess) {
                    Write-Host "``n📋 DISPLAYING RELEASE NOTES ANALYSIS REPORT:" -ForegroundColor DarkCyan
                    Write-Host "===========================================" -ForegroundColor DarkCyan
                    try {
                        $reportDisplay = Get-Content -Path $reportPath -Raw
                        Write-Host $reportDisplay -ForegroundColor White
                        Write-Host "``n===========================================" -ForegroundColor DarkCyan
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
                Write-Host "``n🔄 RE-RUNNING RELEASE NOTES GENERATION..." -ForegroundColor DarkYellow
                Write-Host "=========================================" -ForegroundColor DarkYellow
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