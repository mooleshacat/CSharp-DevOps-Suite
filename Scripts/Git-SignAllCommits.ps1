# MixerThreholdMod - Sign All Commits Script
# Signs all unsigned commits in the current repository

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ((Split-Path $ScriptDir -Leaf) -ieq "Scripts") {
    $ProjectRoot = Split-Path $ScriptDir -Parent
} else {
    $ProjectRoot = $ScriptDir
}

Write-Host "=== MixerThreholdMod Git Commit Signing Tool ===" -ForegroundColor DarkCyan
Write-Host "Working directory: $ProjectRoot" -ForegroundColor Gray

# Change to project root
Set-Location $ProjectRoot

# Check if we're in a git repository
if (!(Test-Path .git)) {
    Write-Host "Error: Not in a git repository!" -ForegroundColor Red
    Write-Host "Press ENTER to continue..." -ForegroundColor Gray -NoNewline
    Read-Host
    exit
}

# Check GPG configuration
$gpgKey = git config --get user.signingkey
if (!$gpgKey) {
    Write-Host "Error: No GPG signing key configured!" -ForegroundColor Red
    Write-Host "Run: git config --global user.signingkey YOUR_KEY_ID" -ForegroundColor DarkYellow
    Write-Host "Press ENTER to continue..." -ForegroundColor Gray -NoNewline
    Read-Host
    exit
}

Write-Host "Using GPG key: $gpgKey" -ForegroundColor Gray

# Get all unsigned commits
Write-Host "`nFinding unsigned commits..." -ForegroundColor DarkCyan
$unsignedCommits = git log --pretty="format:%H %s" --no-merges | ForEach-Object {
    $parts = $_ -split ' ', 2
    $hash = $parts[0]
    $message = $parts[1]
    
    $showOutput = git show --show-signature $hash 2>&1
    if ($showOutput -notmatch "gpg:") {
        [PSCustomObject]@{ Hash = $hash; Message = $message }
    }
}

if ($unsignedCommits.Count -eq 0) {
    Write-Host "All commits are already signed!" -ForegroundColor Green
    Write-Host "Press ENTER to continue..." -ForegroundColor Gray -NoNewline
    Read-Host
    exit
}

Write-Host "Found $($unsignedCommits.Count) unsigned commits" -ForegroundColor DarkYellow

# Display unsigned commits
Write-Host "`nUnsigned commits:" -ForegroundColor DarkCyan
$unsignedCommits | ForEach-Object {
    Write-Host ("  {0} - {1}" -f $_.Hash.Substring(0,8), $_.Message) -ForegroundColor Gray
}

Write-Host "`nDo you want to sign all these commits? (Y/N): " -NoNewline -ForegroundColor Green
$confirm = Read-Host

if ($confirm -ne 'Y' -and $confirm -ne 'y') {
    Write-Host "Operation cancelled." -ForegroundColor Gray
    Write-Host "Press ENTER to continue..." -ForegroundColor Gray -NoNewline
    Read-Host
    exit
}

# Sign commits
Write-Host "`nSigning commits..." -ForegroundColor DarkCyan
foreach ($commit in $unsignedCommits) {
    Write-Host ("Signing {0}..." -f $commit.Hash.Substring(0,8)) -ForegroundColor Gray
    git commit --amend --no-edit -S $commit.Hash
}

Write-Host "`nAll commits signed successfully!" -ForegroundColor Green
Write-Host "Remember to force push if these commits were already pushed: git push --force-with-lease" -ForegroundColor DarkYellow

Write-Host "`nPress ENTER to continue..." -ForegroundColor Gray -NoNewline
Read-Host