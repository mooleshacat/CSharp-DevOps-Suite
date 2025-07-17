# MixerThreholdMod DevOps Tool: Changelog Generator (NON-INTERACTIVE)
# Creates comprehensive changelog from git commits and project history
# Generates markdown changelog with categorized entries and version tracking
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

Write-Host "🕐 Changelog generation started: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray
Write-Host "Generating changelog in: $ProjectRoot" -ForegroundColor DarkCyan
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
function Get-GitTagsWithDates {
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

# Function to get all commits
function Get-AllCommits {
    param($limit = 200)  # Reasonable limit for automation
    
    try {
        $gitLogFormat = '--pretty=format:%H|%s|%an|%ad|%b'
        $commits = git log $gitLogFormat --date=short --no-merges -n $limit 2>$null
        
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
        return @()
    }
}

# Function to categorize commits
function Get-CommitCategory {
    param($message)
    
    $message = $message.ToLower()
    
    # High priority categories first
    if ($message -match '!:' -or $message -match 'breaking') { return "BREAKING" }
    if ($message -match '^feat(\(.+\))?:') { return "ADDED" }
    if ($message -match '^fix(\(.+\))?:') { return "FIXED" }
    if ($message -match '(security|vulnerability|cve)') { return "SECURITY" }
    
    # Project-specific categories
    if ($message -match '(save|backup|crash|emergency)') { return "FIXED" }
    if ($message -match '(thread|async|lock|concurrent)') { return "IMPROVED" }
    if ($message -match '(mixer|audio|volume|threshold)') { return "ADDED" }
    if ($message -match '(performance|optimize|memory|cpu)') { return "IMPROVED" }
    if ($message -match '(remove|delete|deprecat)') { return "REMOVED" }
    
    # Standard categories
    if ($message -match '^docs(\(.+\))?:') { return "DOCS" }
    if ($message -match '^chore(\(.+\))?:') { return "CHANGED" }
    if ($message -match '^style(\(.+\))?:') { return "CHANGED" }
    if ($message -match '^refactor(\(.+\))?:') { return "CHANGED" }
    
    return "CHANGED"
}

# Function to format commit for changelog
function Format-CommitForChangelog {
    param($commit)
    
    $message = $commit.Subject
    
    # Remove conventional commit prefixes for cleaner changelog
    $message = $message -replace '^(feat|fix|docs|style|refactor|perf|test|chore|build|ci)(\(.+\))?:\s*', ''
    
    # Capitalize first letter
    if ($message.Length -gt 0) {
        $message = $message.Substring(0, 1).ToUpper() + $message.Substring(1)
    }
    
    return $message
}

# Function to group commits by version/tag
function Group-CommitsByVersion {
    param($commits, $tags)
    
    $versionGroups = @()
    
    # Add current unreleased changes
    $currentVersion = Get-CurrentVersion
    $latestTag = if ($tags.Count -gt 0) { $tags[0] } else { $null }
    
    if ($latestTag) {
        # Get commits since last tag
        try {
            $unreleasedCommits = git log "$($latestTag.Name)..HEAD" --pretty=format:%H --no-merges 2>$null
            if ($LASTEXITCODE -eq 0 -and $unreleasedCommits) {
                $unreleasedHashes = $unreleasedCommits | Where-Object { $_ }
                $unreleasedCommitData = $commits | Where-Object { $unreleasedHashes -contains $_.FullHash }
                
                if ($unreleasedCommitData.Count -gt 0) {
                    $versionGroups += [PSCustomObject]@{
                        Version = "[$currentVersion] - Unreleased"
                        Date = [DateTime]::Now
                        Commits = $unreleasedCommitData
                        IsUnreleased = $true
                    }
                }
            }
        }
        catch {
            # If git command fails, just skip unreleased section
        }
    }
    
    # Group commits by existing tags
    for ($i = 0; $i -lt $tags.Count; $i++) {
        $currentTag = $tags[$i]
        $nextTag = if ($i + 1 -lt $tags.Count) { $tags[$i + 1] } else { $null }
        
        try {
            if ($nextTag) {
                $tagCommits = git log "$($nextTag.Name)..$($currentTag.Name)" --pretty=format:%H --no-merges 2>$null
            } else {
                $tagCommits = git log $currentTag.Name --pretty=format:%H --no-merges 2>$null
            }
            
            if ($LASTEXITCODE -eq 0 -and $tagCommits) {
                $tagHashes = $tagCommits | Where-Object { $_ }
                $tagCommitData = $commits | Where-Object { $tagHashes -contains $_.FullHash }
                
                if ($tagCommitData.Count -gt 0) {
                    $versionGroups += [PSCustomObject]@{
                        Version = "[$($currentTag.Name)] - $($currentTag.Date.ToString('yyyy-MM-dd'))"
                        Date = $currentTag.Date
                        Commits = $tagCommitData
                        IsUnreleased = $false
                    }
                }
            }
        }
        catch {
            # Skip this tag if git command fails
            continue
        }
    }
    
    # If no tags exist, create one big group
    if ($versionGroups.Count -eq 0) {
        $versionGroups += [PSCustomObject]@{
            Version = "[$currentVersion] - $(Get-Date -Format 'yyyy-MM-dd')"
            Date = [DateTime]::Now
            Commits = $commits
            IsUnreleased = $false
        }
    }
    
    return $versionGroups
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

Write-Host "``n📊 Analyzing project history..." -ForegroundColor DarkGray

# Get current version and tags
$currentVersion = Get-CurrentVersion
$tags = Get-GitTagsWithDates

Write-Host "📋 Current version: $currentVersion" -ForegroundColor Gray
Write-Host "📋 Available tags: $($tags.Count)" -ForegroundColor Gray

# Get all commits
Write-Host "``n🔍 Fetching commit history..." -ForegroundColor DarkGray
$allCommits = Get-AllCommits

if ($allCommits.Count -eq 0) {
    Write-Host "❌ No commits found in repository" -ForegroundColor Red
    Pop-Location
    if ($IsInteractive -and -not $RunningFromScript) {
        Write-Host "``nPress ENTER to continue..." -ForegroundColor Gray -NoNewline
        Read-Host
    }
    return
}

Write-Host "✅ Found $($allCommits.Count) commits in history" -ForegroundColor Gray

# Group commits by version
Write-Host "``n📋 Organizing commits by version..." -ForegroundColor DarkGray
$versionGroups = Group-CommitsByVersion -commits $allCommits -tags $tags

Write-Host "✅ Organized into $($versionGroups.Count) version groups" -ForegroundColor Gray

# Generate changelog content
$changelog = @()

# Header
$changelog += "# Changelog"
$changelog += ""
$changelog += "All notable changes to MixerThreholdMod will be documented in this file."
$changelog += ""
$changelog += "The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),"
$changelog += "and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)."
$changelog += ""

# Process each version group
foreach ($versionGroup in $versionGroups) {
    $changelog += "## $($versionGroup.Version)"
    $changelog += ""
    
    # Categorize commits within this version
    $categorizedCommits = $versionGroup.Commits | Group-Object Category | Sort-Object @{
        Expression = {
            switch ($_.Name) {
                "BREAKING" { 1 }
                "SECURITY" { 2 }
                "ADDED" { 3 }
                "IMPROVED" { 4 }
                "FIXED" { 5 }
                "CHANGED" { 6 }
                "REMOVED" { 7 }
                "DOCS" { 8 }
                default { 99 }
            }
        }
    }
    
    # Add content for each category
    foreach ($categoryGroup in $categorizedCommits) {
        $categoryName = $categoryGroup.Name
        $categoryCommits = $categoryGroup.Group
        
        # Map category to changelog section
        $sectionName = switch ($categoryName) {
            "BREAKING" { "⚠️ BREAKING CHANGES" }
            "SECURITY" { "🔒 Security" }
            "ADDED" { "✨ Added" }
            "IMPROVED" { "⚡ Improved" }
            "FIXED" { "🐛 Fixed" }
            "CHANGED" { "🔄 Changed" }
            "REMOVED" { "🗑️ Removed" }
            "DOCS" { "📝 Documentation" }
            default { "📌 Other" }
        }
        
        $changelog += "### $sectionName"
        $changelog += ""
        
        # Limit commits per category for readability
        $maxCommitsPerCategory = if ($categoryName -eq "BREAKING") { 20 } else { 15 }
        
        foreach ($commit in $categoryCommits | Select-Object -First $maxCommitsPerCategory) {
            $formattedMessage = Format-CommitForChangelog -commit $commit
            # FIXED: Use double backticks for PowerShell 5.1 compatibility
            $changelog += "- $formattedMessage ([````$($commit.Hash)````](../../commit/$($commit.FullHash)))"
        }
        
        if ($categoryCommits.Count -gt $maxCommitsPerCategory) {
            $remaining = $categoryCommits.Count - $maxCommitsPerCategory
            $changelog += "- ... and $remaining more changes"
        }
        
        $changelog += ""
    }
}

# Footer with metadata
$changelog += "---"
$changelog += ""
$changelog += "## About This Changelog"
$changelog += ""
$changelog += "- **Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$changelog += "- **Total Commits**: $($allCommits.Count)"
$changelog += "- **Version Groups**: $($versionGroups.Count)"
$changelog += "- **Current Version**: $currentVersion"
$changelog += ""
$changelog += "### Category Legend"
$changelog += ""
$changelog += "- **⚠️ BREAKING CHANGES**: Changes that may break existing functionality"
$changelog += "- **🔒 Security**: Security-related improvements and fixes"
$changelog += "- **✨ Added**: New features and functionality"
$changelog += "- **⚡ Improved**: Performance improvements and enhancements"
$changelog += "- **🐛 Fixed**: Bug fixes and error corrections"
$changelog += "- **🔄 Changed**: Changes to existing functionality"
$changelog += "- **🗑️ Removed**: Removed features and deprecated functionality"
$changelog += "- **📝 Documentation**: Documentation updates and improvements"
$changelog += ""
$changelog += "_This changelog is automatically generated from git commit history._"

# Save changelog
$outputPath = Join-Path $ProjectRoot "CHANGELOG.md"

try {
    $changelog | Out-File -FilePath $outputPath -Encoding UTF8
    $savedSuccessfully = $true
}
catch {
    Write-Host "⚠️  Error saving changelog: $_" -ForegroundColor DarkYellow
    $savedSuccessfully = $false
}

Pop-Location

Write-Host "``n=== CHANGELOG GENERATION REPORT ===" -ForegroundColor DarkCyan
Write-Host "🕐 Generation completed: $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Gray

if ($savedSuccessfully) {
    Write-Host "✅ Changelog generated successfully!" -ForegroundColor Green
    Write-Host "📄 Output saved to: $outputPath" -ForegroundColor Gray
} else {
    Write-Host "❌ Failed to save changelog" -ForegroundColor Red
}

Write-Host "📋 Total commits processed: $($allCommits.Count)" -ForegroundColor Gray
Write-Host "📋 Version groups: $($versionGroups.Count)" -ForegroundColor Gray
Write-Host "🏷️  Current version: $currentVersion" -ForegroundColor Gray

# Category breakdown (condensed for automation)
$allCategorizedCommits = $allCommits | Group-Object Category
Write-Host "``n📋 Overall Changes by Category:" -ForegroundColor DarkCyan
foreach ($category in $allCategorizedCommits | Sort-Object Count -Descending | Select-Object -First 6) {
    $color = switch ($category.Name) {
        "BREAKING" { "Red" }
        "SECURITY" { "Red" }
        "ADDED" { "Green" }
        "FIXED" { "DarkYellow" }
        default { "Gray" }
    }
    $displayName = switch ($category.Name) {
        "BREAKING" { "Breaking Changes" }
        "SECURITY" { "Security Updates" }
        "ADDED" { "New Features" }
        "IMPROVED" { "Improvements" }
        "FIXED" { "Bug Fixes" }
        "CHANGED" { "Changes" }
        "REMOVED" { "Removals" }
        "DOCS" { "Documentation" }
        default { "Other Changes" }
    }
    Write-Host "   $displayName``: $($category.Count) changes" -ForegroundColor $color
}

if ($allCategorizedCommits.Count -gt 6) {
    Write-Host "   ... and $($allCategorizedCommits.Count - 6) more categories" -ForegroundColor DarkGray
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

# Generate detailed changelog analysis report
Write-Host "``n📝 Generating detailed changelog analysis report..." -ForegroundColor DarkGray

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$reportPath = Join-Path $reportsDir "CHANGELOG-ANALYSIS-REPORT_$timestamp.md"

$reportContent = @()
$reportContent += "# Changelog Generation Analysis Report"
$reportContent += ""
$reportContent += "**Generated**: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$reportContent += "**Total Commits**: $($allCommits.Count)"
$reportContent += "**Version Groups**: $($versionGroups.Count)"
$reportContent += "**Current Version**: $currentVersion"
$reportContent += ""

# Executive Summary
$reportContent += "## Executive Summary"
$reportContent += ""

if ($savedSuccessfully) {
    $reportContent += "✅ **CHANGELOG GENERATED SUCCESSFULLY** - Complete project history documented."
    $reportContent += ""
    $reportContent += "The changelog has been generated with $($versionGroups.Count) version groups covering $($allCommits.Count) commits."
} else {
    $reportContent += "❌ **GENERATION FAILED** - Unable to create changelog file."
    $reportContent += ""
    $reportContent += "Check file permissions and disk space."
}

$reportContent += ""
$reportContent += "| Metric | Value | Status |"
$reportContent += "|--------|-------|--------|"
$reportContent += "| **Total Commits** | $($allCommits.Count) | $(if ($allCommits.Count -gt 0) { "✅ Good History" } else { "⚠️ Limited History" }) |"
$reportContent += "| **Version Groups** | $($versionGroups.Count) | $(if ($versionGroups.Count -gt 1) { "✅ Multiple Versions" } else { "📝 Single Version" }) |"
$reportContent += "| **Git Tags** | $($tags.Count) | $(if ($tags.Count -gt 0) { "✅ Tagged Releases" } else { "⚠️ No Tags" }) |"
$reportContent += "| **Changelog Saved** | $(if ($savedSuccessfully) { "Yes" } else { "No" }) | $(if ($savedSuccessfully) { "✅ Success" } else { "❌ Failed" }) |"
$reportContent += ""

# Version Analysis
if ($versionGroups.Count -gt 0) {
    $reportContent += "## Version Analysis"
    $reportContent += ""
    
    foreach ($versionGroup in $versionGroups | Select-Object -First 10) {
        $reportContent += "### $($versionGroup.Version)"
        $reportContent += ""
        $reportContent += "**Commits**: $($versionGroup.Commits.Count)"
        $reportContent += "**Date**: $($versionGroup.Date.ToString('yyyy-MM-dd'))"
        if ($versionGroup.IsUnreleased) {
            $reportContent += "**Status**: 🚧 Unreleased"
        } else {
            $reportContent += "**Status**: ✅ Released"
        }
        $reportContent += ""
        
        # Category breakdown for this version
        $versionCategories = $versionGroup.Commits | Group-Object Category | Sort-Object Count -Descending
        if ($versionCategories.Count -gt 0) {
            $reportContent += "#### Change Categories"
            $reportContent += ""
            foreach ($cat in $versionCategories) {
                $displayName = switch ($cat.Name) {
                    "BREAKING" { "⚠️ Breaking Changes" }
                    "SECURITY" { "🔒 Security" }
                    "ADDED" { "✨ Added" }
                    "IMPROVED" { "⚡ Improved" }
                    "FIXED" { "🐛 Fixed" }
                    "CHANGED" { "🔄 Changed" }
                    "REMOVED" { "🗑️ Removed" }
                    "DOCS" { "📝 Documentation" }
                    default { "📌 Other" }
                }
                $reportContent += "- $displayName``: $($cat.Count) changes"
            }
            $reportContent += ""
        }
    }
    
    if ($versionGroups.Count -gt 10) {
        $reportContent += "*... and $($versionGroups.Count - 10) more version groups*"
        $reportContent += ""
    }
}

# Category Statistics
$reportContent += "## Overall Category Statistics"
$reportContent += ""
$reportContent += "| Category | Count | Percentage | Description |"
$reportContent += "|----------|-------|------------|-------------|"

foreach ($category in $allCategorizedCommits | Sort-Object Count -Descending) {
    $percentage = [Math]::Round(($category.Count / $allCommits.Count) * 100, 1)
    $displayName = switch ($category.Name) {
        "BREAKING" { "⚠️ Breaking Changes" }
        "SECURITY" { "🔒 Security Updates" }
        "ADDED" { "✨ New Features" }
        "IMPROVED" { "⚡ Improvements" }
        "FIXED" { "🐛 Bug Fixes" }
        "CHANGED" { "🔄 Changes" }
        "REMOVED" { "🗑️ Removals" }
        "DOCS" { "📝 Documentation" }
        default { "📌 Other Changes" }
    }
    
    $description = switch ($category.Name) {
        "BREAKING" { "Changes that may break existing functionality" }
        "SECURITY" { "Security improvements and vulnerability fixes" }
        "ADDED" { "New features and functionality additions" }
        "IMPROVED" { "Performance and quality improvements" }
        "FIXED" { "Bug fixes and error corrections" }
        "CHANGED" { "Modifications to existing functionality" }
        "REMOVED" { "Deprecated or removed features" }
        "DOCS" { "Documentation updates and improvements" }
        default { "Miscellaneous changes and maintenance" }
    }
    
    $reportContent += "| $displayName | $($category.Count) | $percentage% | $description |"
}

$reportContent += ""

# Contributor Analysis
$topContributors = $allCommits | Group-Object Author | Sort-Object Count -Descending | Select-Object -First 5
if ($topContributors.Count -gt 0) {
    $reportContent += "## Top Contributors"
    $reportContent += ""
    $reportContent += "| Contributor | Commits | Percentage |"
    $reportContent += "|-------------|---------|------------|"
    
    foreach ($contributor in $topContributors) {
        $percentage = [Math]::Round(($contributor.Count / $allCommits.Count) * 100, 1)
        $reportContent += "| $($contributor.Name) | $($contributor.Count) | $percentage% |"
    }
    $reportContent += ""
}

# Technical Details
$reportContent += "## Technical Generation Details"
$reportContent += ""
$reportContent += "### Processing Summary"
$reportContent += ""
$reportContent += "- **Git Repository**: $(if (Test-GitRepository $ProjectRoot) { "✅ Valid" } else { "❌ Invalid" })"
$reportContent += "- **Commit Limit**: 200 commits (for performance)"
$reportContent += "- **Tag Detection**: $($tags.Count) tags found"
$reportContent += "- **Version Detection**: Automatic from constants files"
$reportContent += "- **Output Format**: Keep a Changelog compatible"
$reportContent += ""
$reportContent += "### File Locations"
$reportContent += ""
$reportContent += "- **Primary Output**: ````CHANGELOG.md```` (project root)"
$reportContent += "- **Analysis Report**: ````$($reportPath -replace [regex]::Escape($ProjectRoot), '.')```` (Reports directory)"
$reportContent += ""
$reportContent += "### Categorization Logic"
$reportContent += ""
$reportContent += "Commits are automatically categorized based on conventional commit patterns:"
$reportContent += ""
$reportContent += "- ````feat:```` → ✨ Added"
$reportContent += "- ````fix:```` → 🐛 Fixed"
$reportContent += "- ````docs:```` → 📝 Documentation"
$reportContent += "- ````chore:```` → 🔄 Changed"
$reportContent += "- Keywords like 'breaking' → ⚠️ Breaking Changes"
$reportContent += "- Security keywords → 🔒 Security"

# Recommendations
$reportContent += ""
$reportContent += "## 🎯 Recommendations"
$reportContent += ""

if ($tags.Count -eq 0) {
    $reportContent += "### 📝 Version Tagging"
    $reportContent += ""
    $reportContent += "**No git tags found** - Consider implementing version tagging:"
    $reportContent += ""
    $reportContent += "1. **Create initial tag**: ````git tag v$currentVersion````"
    # FIXED: Use double backticks for PowerShell 5.1 compatibility
    $reportContent += "2. **Tag future releases**: ````git tag v<VERSION>```` before releases"
    $reportContent += "3. **Push tags**: ````git push origin --tags````"
    $reportContent += ""
}

$breakingChanges = $allCommits | Where-Object { $_.Category -eq "BREAKING" }
if ($breakingChanges.Count -gt 0) {
    $reportContent += "### ⚠️ Breaking Changes Detected"
    $reportContent += ""
    $reportContent += "**$($breakingChanges.Count) breaking changes** found in history."
    $reportContent += ""
    $reportContent += "Consider creating migration guides for major version releases."
    $reportContent += ""
}

$reportContent += "### 📋 Best Practices"
$reportContent += ""
$reportContent += "1. **Consistent Commits**: Use conventional commit format for better categorization"
$reportContent += "2. **Regular Updates**: Regenerate changelog before releases"
$reportContent += "3. **Manual Review**: Review generated changelog for accuracy"
$reportContent += "4. **Version Tagging**: Tag releases with semantic versions"

# Footer
$reportContent += ""
$reportContent += "---"
$reportContent += ""
$reportContent += "**Changelog Format**: [Keep a Changelog](https://keepachangelog.com/)"
$reportContent += "**Versioning**: [Semantic Versioning](https://semver.org/)"
$reportContent += ""
$reportContent += "*Generated by MixerThreholdMod DevOps Suite - Changelog Generator*"

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

if ($tags.Count -eq 0) {
    Write-Host "   📝 Consider adding git tags for better version tracking" -ForegroundColor DarkYellow
    Write-Host "   • Create initial tag: git tag v$currentVersion" -ForegroundColor Gray
}

$breakingCommits = $allCommits | Where-Object { $_.Category -eq "BREAKING" }
if ($breakingCommits.Count -gt 0) {
    Write-Host "   ⚠️  $($breakingCommits.Count) breaking changes found in history" -ForegroundColor DarkYellow
    Write-Host "   • Review breaking changes section in changelog" -ForegroundColor Gray
}

if ($savedSuccessfully) {
    Write-Host "   ✅ Changelog ready for review and publication" -ForegroundColor Green
} else {
    Write-Host "   ❌ Fix file saving issues and regenerate" -ForegroundColor Red
}

Write-Host "   • Review generated content for accuracy" -ForegroundColor Gray
Write-Host "   • Update changelog manually for important releases" -ForegroundColor Gray

Write-Host "``n🚀 Changelog generation complete!" -ForegroundColor Green

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
        Write-Host "   R - Re-run changelog generation" -ForegroundColor DarkYellow
        Write-Host "   X - Exit to DevOps menu" -ForegroundColor Gray
        
        $choice = Read-Host "``nEnter choice (D/R/X)"
        $choice = $choice.ToUpper()
        
        switch ($choice) {
            'D' {
                if ($reportSaveSuccess) {
                    Write-Host "``n📋 DISPLAYING CHANGELOG ANALYSIS REPORT:" -ForegroundColor DarkCyan
                    Write-Host "=======================================" -ForegroundColor DarkCyan
                    try {
                        $reportDisplay = Get-Content -Path $reportPath -Raw
                        Write-Host $reportDisplay -ForegroundColor White
                        Write-Host "``n=======================================" -ForegroundColor DarkCyan
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
                Write-Host "``n🔄 RE-RUNNING CHANGELOG GENERATION..." -ForegroundColor DarkYellow
                Write-Host "====================================" -ForegroundColor DarkYellow
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