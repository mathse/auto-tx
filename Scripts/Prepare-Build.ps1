[CmdletBinding()]
Param(
    [Parameter(Mandatory=$True)][string] $ProjectDir
)

function Write-BuildDetails {
    Param (
        [Parameter(Mandatory=$True)]
        [String]$Target,

        [Parameter(Mandatory=$True)]
        [Array]$Desc,

        [Parameter(Mandatory=$True)]
        [String]$Branch,

        [Parameter(Mandatory=$True)]
        [String]$Date
    )

    $CommitName = "$($Desc[0]).$($Desc[1])-$($Desc[2])-$($Desc[3])"
    Write-Output "Generating [$($Target)]..."
    Write-Output " > $($CommitName)"
    $CSharp = $("
    public static class BuildDetails
    {
        public const string GitCommitName = `"$($CommitName)`";
        public const string GitBranch = `"$($Branch)`";
        public const string GitMajor = `"$($Desc[0])`";
        public const string GitMinor = `"$($Desc[1])`";
        public const string GitPatch = `"$($Desc[2])`";
        public const string BuildDate = `"$($Date)`";
    }")
    Write-Verbose $CSharp
    Write-Output $CSharp > $Target
}

function Parse-GitDescribe([string]$CommitName) {
    Write-Verbose "Parsing 'git describe' result [$($CommitName)]..."
    try {
        $Items = $CommitName.Split('-').Split('.')
        if ($Items.Length -ne 4) { throw }
    }
    catch {
        throw "Can't parse commit name [$($CommitName)]!"
    }
    Write-Verbose "Just some $($Items[2]) commits after the last tag."
    Return $Items
}


$ErrorActionPreference = "Stop"

$oldpwd = pwd
cd $ProjectDir -ErrorAction Stop

try {
    $CommitName = & git describe --tags --long --match "[0-9].[0-9]"
    if (-Not $?) { throw }
    $GitStatus = & git status --porcelain
    if (-Not $?) { throw }
    $GitBranch = & git symbolic-ref --short HEAD
    if (-Not $?) { throw }

    $DescItems = Parse-GitDescribe $CommitName

    if ($GitStatus.Length -gt 0) {
        $StatusWarning = "  <--  WARNING: repository has uncommitted changes!"
        $CommitName = "$($CommitName)-unclean"
    }
}
catch {
    $CommitName = "commit unknown"
    $GitBranch = "branch unknown"
    Write-Output "$(">"*8) Running git failed, using default values! $("<"*8)"
}


$Date = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'


$BCommit = "$($ProjectDir)\Resources\BuildCommit.txt"
$BuildDate = "$($ProjectDir)\Resources\BuildDate.txt"
$BuildDetailsCS = "$($ProjectDir)\..\Resources\BuildDetails.cs"

Write-Output $CommitName > $BCommit
Write-Output $Date > $BuildDate

Write-Output "build-date: $($Date)"
Write-Output "git-branch: $($GitBranch)"
Write-Output "git-description: $($CommitName)$($StatusWarning)"

Write-BuildDetails $BuildDetailsCS $DescItems $GitBranch $Date 

cd $oldpwd