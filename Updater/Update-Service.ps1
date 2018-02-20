# Script to be run by the task scheduler for automatic updates of the AutoTx
# service binaries and / or configuration file.

# Testing has been done on PowerShell 5.1 only, so we set this as a requirement:
#requires -version 5.1


[CmdletBinding()]
Param(
    [Parameter(Mandatory=$True)][string] $UpdaterSettings
)



###  function definitions  #####################################################

function ServiceIsRunning([string]$ServiceName) {
    try {
        $Service = Get-Service $ServiceName -ErrorAction Stop
        if ($Service.Status -ne "Running") {
            Log-Debug "Service $($ServiceName) is not running."
            Return $False
        }
    }
    catch {
        Log-Error "Error checking service state: $($_.Exception.Message)"
        Exit
    }
    Return $True
}


function ServiceIsBusy {
    $StatusXml = "$($InstallationPath)\status.xml"
    try {
        [xml]$XML = Get-Content $StatusXml -ErrorAction Stop
        # careful, we need a string comparison here:
        if ($XML.ServiceStatus.TransferInProgress -eq "true") {
            Return $True
        } else {
            Log-Debug "Service is idle, shutdown possible."
            Return $False
        }
    }
    catch {
        $ex = $_.Exception.Message
        $msg = "Trying to read the service status from [$($StatusXml)] failed! "
        $msg += "The reported error message was:`n$($ex)"
        Send-MailReport -Subject "Error parsing status of $($ServiceName)!" `
            -Body $msg
        Exit
    }
}


function Stop-TrayApp() {
    try {
        Stop-Process -Name "ATxTray" -Force -ErrorAction Stop
        Start-Sleep -Milliseconds 200
        Log-Debug "Stopped Tray App process."
    }
    catch {
        Log-Debug "Unable to stop tray app, is it running?"
    }
}


function Exit-IfDirMissing([string]$DirName, [string]$Desc) {
    if (Test-Path -PathType Container $DirName) {
        Write-Verbose "Verified $($Desc) path: [$($DirName)]"
        Return
    }
    $msg = "ERROR: can't find / access $($Desc) path: [$($DirName)]"
    Send-MailReport -Subject "path or permission error" -Body $msg
    Exit
}


function Get-LastLogLines([string]$Path, [int]$Count) {
    try {
        $msg = Get-Content -Path $Path -Tail $Count -ErrorAction Stop
    }
    catch {
        $ex = $_.Exception.Message
        $errxx = "XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX"
        $msg = "`n$errxx`n`n$ex `n`n$errxx"
    }
    # Out-String is required as otherwise all newlines from the log disappear:
    Return $msg | Out-String
}


function Stop-MyService([string]$Message) {
    if ((Get-Service $ServiceName).Status -eq "Stopped") {
        Log-Info "$($Message) (Service already in state 'Stopped')"
        Return
    }
    if (ServiceIsBusy) {
        $msg = "*DENYING* to stop the service $($ServiceName) as it is "
        $msg += "currently busy.`nShutdown reason was '$($Message)'."
        Log-Info $msg
        Exit
    }
    try {
        Log-Info "$($Message) Attempting service $($ServiceName) shutdown..."
        Stop-Service "$($ServiceName)" -ErrorAction Stop
        Write-Verbose "Stopped service $($ServiceName)."
    }
    catch {
        $ex = $_.Exception.Message
        Send-MailReport -Subject "Shutdown of service $($ServiceName) failed!" `
            -Body "Trying to stop the service results in this error:`n$($ex)"
        Exit
    }
}


function Start-MyService {
    if ((Get-Service $ServiceName).Status -eq "Running") {
        Return
    }
    try {
        Start-Service "$($ServiceName)" -ErrorAction Stop
        Write-Verbose "Started service $($ServiceName)."
    }
    catch {
        $ex = $_.Exception.Message
        $msg = "Trying to start the service results in this error:`n$($ex)`n`n"
        $msg += " -------------------- last 50 log lines --------------------`n"
        $msg += Get-LastLogLines "$($LogPath)\service.log" 50
        $msg += " -------------------- ----------------- --------------------`n"
        Send-MailReport -Subject "Startup of service $($ServiceName) failed!" `
            -Body $msg
        Exit
    }
}


function Get-WriteTime([string]$FileName) {
    try {
        $TimeStamp = (Get-Item "$FileName" -EA Stop).LastWriteTime
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        Write-Verbose "File [$($FileName)] can't be found!"
        throw [System.Management.Automation.ItemNotFoundException] `
            "File not found: $($FileName)."
    }
    catch {
        $ex = $_.Exception.Message
        Log-Error "Error determining file age of [$($FileName)]!`n$($ex)"
        Exit
    }
    Return $TimeStamp
}


function File-IsUpToDate([string]$ExistingFile, [string]$UpdateCandidate) {
    # Compare write-timestamps, return $False if $UpdateCandidate is newer.
    Write-Verbose "Comparing [$($UpdateCandidate)] vs. [$($ExistingFile)]..."
    $CandidateTime = Get-WriteTime -FileName $UpdateCandidate
    $ExistingTime = Get-WriteTime -FileName $ExistingFile
    if ($CandidateTime -le $ExistingTime) {
        Log-Debug "File [$($ExistingFile)] is up-to-date."
        Return $True
    }
    Write-Verbose "File [$($UpdateCandidate)] is newer than [$($ExistingFile)]."
    Return $False
}


function Create-Backup {
    # Rename a file using a time-stamp suffix like "2017-12-04T16.41.35" while
    # preserving its original suffix / extension.
    #
    # Return $True if the backup was created successfully, $False otherwise.
    Param (
        [Parameter(Mandatory=$True)]
        [ValidateScript({Test-Path -PathType Leaf $_})]
        [String]$FileName

    )
    $FileWithoutSuffix = [io.path]::GetFileNameWithoutExtension($FileName)
    $FileSuffix = [io.path]::GetExtension($FileName)
    $BaseDir = Split-Path -Parent $FileName

    # assemble a timestamp string like "2017-12-04T16.41.35"
    $BakTimeStamp = Get-Date -Format s | foreach {$_ -replace ":", "."}
    $BakName = "$($FileWithoutSuffix)_pre-$($BakTimeStamp)$($FileSuffix)"
    Log-Info "Creating backup of [$($FileName)] as [$($BaseDir)\$($BakName)]."

    try {
        Rename-Item "$FileName" "$BaseDir\$BakName"
    }
    catch {
        Log-Error "Backing up [$($DstFile)] FAILED:`n> $($_.Exception.Message)"
        Return $False
    }
    Return $True
}


function Update-File {
    # Use the given $SrcFile to update the file with the same name in $DstPath,
    # creating a backup of the original file before replacing it.
    #
    # Return $True if the file was updated, $False otherwise.
    Param (
        [Parameter(Mandatory=$True)]
        [ValidateScript({[IO.Path]::IsPathRooted($_)})]
        [String]$SrcFile,

        [Parameter(Mandatory=$True)]
        [ValidateScript({(Get-Item $_).PSIsContainer})]
        [String]$DstPath
    )

    $DstFile = "$($DstPath)\$(Split-Path -Leaf $SrcFile)"
    Write-Verbose "Trying to update [$($DstFile)] with [$($SrcFile)]..."

    if (-Not (Create-Backup -FileName $DstFile)) {
        Return $False
    }

    try {
        Copy-Item -Path $SrcFile -Destination $DstPath
        Log-Info "Updated config file [$($DstFile)]."
    }
    catch {
        Log-Error "Copying [$($SrcFile)] FAILED:`n> $($_.Exception.Message)"
        Return $False
    }
    Return $True
}


function Update-Configuration {
    # Update the common and host-specific configuration files with their new
    # versions, stopping the service if necessary.
    # The function DOES NOT do any checks, it simply runs the necessary update
    # commands - meaning everything else (do the files exist, is an update
    # required) has to be checked beforehand!!
    #
    # Return $True if all files were updated successfully.
    $NewComm = Join-Path $UpdPathConfig "config.common.xml"
    $NewHost = Join-Path $UpdPathConfig "$($env:COMPUTERNAME).xml"
    Write-Verbose "Updating configuration files:`n> $($NewComm)`n> $($NewHost)"

    Stop-MyService "Updating configuration using files at [$($UpdPathConfig)]."
    
    $Ret = Update-File $NewComm $ConfigPath
    # only continue if the first update worked:
    if ($Ret) {
        $Ret = Update-File $NewHost $ConfigPath
    }
    Return $Ret
}


function NewConfig-Available {
    # Check the configuration update path and the given $DstPath for both
    # configuration files (common and host-specific) and compare their
    # respective file write-time.
    #
    # Return $True if the update path contains any newer file, $False otherwise.
    Param (
        [Parameter(Mandatory=$True)]
        [ValidateScript({(Get-Item $_).PSIsContainer})]
        [String]$DstPath
    )

    # old and new common configuration
    $OComm = Join-Path $DstPath "config.common.xml"
    $NComm = Join-Path $UpdPathConfig "config.common.xml"

    # old and new host-specific configuration
    $OHost = Join-Path $DstPath "$($env:COMPUTERNAME).xml"
    $NHost = Join-Path $UpdPathConfig "$($env:COMPUTERNAME).xml"

    $Ret = $True
    try {
        $Ret = (
            $(File-IsUpToDate -ExistingFile $OHost -UpdateCandidate $NHost) -And
            $(File-IsUpToDate -ExistingFile $OComm -UpdateCandidate $NComm)
        )
    }
    catch {
        Log-Error $("Checking for new configuration files failed:"
            "$($_.Exception.Message)")
        Return $False
    }

    if ($Ret) {
        Write-Verbose "Configuration is up to date, no new files available."
        Return $False
    }
    Log-Info "New configuration files found!"
    Return $True
}


function Config-IsValid {
    # Check if the new configuration provided at $UpdPathConfig validates with
    # the appropriate "AutoTxConfigTest" binary (either the existing one in the
    # service installation directory (if the service binaries won't be updated)
    # or the new one at the $UpdPathBinaries location in case the service itself
    # will be updated as well).
    #
    # Returns an array with two elements, the first one being $True in case the
    # configuration was successfully validated ($False otherwise) and the second
    # one containing the output of the configuration test tool as a string.
    Param (
        [Parameter(Mandatory=$True)]
        [ValidateScript({(Test-Path $_ -PathType Leaf)})]
        [String]$ConfigTest,

        [Parameter(Mandatory=$True)]
        [ValidateScript({(Test-Path $_ -PathType Container)})]
        [String]$ConfigPath
    )
    Write-Verbose "Running [$($ConfigTest) $($ConfigPath)]..."
    $Summary = & $ConfigTest $ConfigPath
    $Ret = $?
    # pipe through Out-String to preserve line breaks:
    $Summary = "$("=" * 80)`n$($Summary | Out-String)`n$("=" * 80)"

    if ($Ret) {
        Log-Debug "Validated config files at [$($ConfigPath)]:`n$($Summary)"
        Return $Ret, $Summary
    }
    Log-Error "Config at [$($ConfigPath)] FAILED VALIDATION:`n$($Summary)"
    Return $Ret, $Summary
}


function Find-InstallationPackage {
    Write-Verbose "Looking for installation package using pattern: $($Pattern)"
    $PkgDir = Get-ChildItem -Path $UpdPathBinaries -Directory -Name |
        Where-Object {$_ -match $Pattern} |
        Sort-Object |
        Select-Object -Last 1
    
    if ([string]::IsNullOrEmpty($PkgDir)) {
        Log-Error "couldn't find installation package matching '$($Pattern)'!"
        Exit
    }
    $PkgDir = "$($UpdPathBinaries)\$($PkgDir)"
    Write-Verbose "Found update installation package: [$($PkgDir)]"
    Return $PkgDir
}


function Copy-ServiceFiles {
    try {
        Write-Verbose "Looking for source package using pattern: $($Pattern)"
        $PkgDir = Get-ChildItem -Path $UpdPathBinaries -Directory -Name |
            Where-Object {$_ -match $Pattern} |
            Sort-Object |
            Select-Object -Last 1
        
        if ([string]::IsNullOrEmpty($PkgDir)) {
            Write-Host "ERROR: couldn't find package matching '$($Pattern)'!"
            Exit
        }
        Write-Verbose "Found update source package: [$($PkgDir)]"

        Stop-MyService "Trying to update service using package [$($PkgDir)]."
        Copy-Item -Recurse -Force -ErrorAction Stop `
            -Path "$($UpdPathBinaries)\$($PkgDir)\$($ServiceName)\*" `
            -Destination "$InstallationPath"
    }
    catch {
        Exit
        Log-Error "Updating service binaries FAILED:`n> $($_.Exception.Message)"
    }
    Log-Info "Updated service binaries with [$($PkgDir)]."
}


function Update-ServiceBinaries {
    $NewService = NewServiceBinaries-Available
    if (-Not ($NewService)) {
        Return $False
    }

    Stop-TrayApp
    Copy-ServiceFiles
    try {
        New-Item -Type File "$MarkerFile" -ErrorAction Stop | Out-Null
        Log-Debug "Created marker file [$($MarkerFile)]."
    }
    catch {
        Log-Error "Creating [$($MarkerFile)] FAILED:`n> $($_.Exception.Message)"
        Exit
    }
    Return $True
}


function NewServiceBinaries-Available {
    $MarkerFile = "$($UpdPathMarkerFiles)\$($env:COMPUTERNAME)"
    if (Test-Path "$MarkerFile" -Type Leaf) {
        Log-Debug "Found marker [$($MarkerFile)], not updating service."
        Return $False
    }
    Write-Verbose "Marker [$($MarkerFile)] missing, service should be updated!"
    Return $True
}


function Upload-LogFiles {
    $Dest = "$($UploadPathLogs)\$($env:COMPUTERNAME)"
    New-Item -Force -Type Directory $Dest | Out-Null
    try {
        Copy-Item -Force -ErrorAction Stop `
            -Path "$($LogPath)\AutoTx.log" `
            -Destination $Dest
        Log-Debug "Uploaded logfile to [$($Dest)]."
    }
    catch {
        Log-Warning "Uploading logfile FAILED!`n$($_.Exception.Message)"
    }
}


function Get-HostDescription() {
    $Desc = $env:COMPUTERNAME
    $ConfigXml = "$($ConfigPath)\$($Desc).xml"
    try {
        [xml]$XML = Get-Content $ConfigXml -ErrorAction Stop
        # careful, we need a string comparison here:
        $Desc += " ($($XML.ServiceConfig.HostAlias))"
    }
    catch {
        $ex = $_.Exception.Message
        $msg = "Trying to read the service config from [$($ConfigXml)] failed! "
        $msg += "The reported error message was:`n$($ex)"
        Log-Error $msg
    }
    Return $Desc
}


function Send-MailReport([string]$Subject, [string]$Body) {
    $Body = "Notification from $(Get-HostDescription)`n`n$($Body)"
    $Subject = "[$($Me)] $($env:COMPUTERNAME) - $($Subject)"
    $msg = "------------------------------`n"
    $msg += "From: $($EmailFrom)`n"
    $msg += "To: $($EmailTo)`n"
    $msg += "Subject: $($Subject)`n`n"
    $msg += "Body: $($Body)"
    $msg += "`n------------------------------`n"
    try {
        Send-MailMessage `
            -SmtpServer $EmailSMTP `
            -From $EmailFrom `
            -To $EmailTo `
            -Body $Body `
            -Subject $Subject `
            -ErrorAction Stop
        Log-Info -Message "Sent Mail Message:`n$($msg)"
    }
    catch {
        $ex = $_.Exception.Message
        $msg = "Sending email failed!`n`n$($msg)"
        $msg += "Exception message: $($ex)"
        Log-Warning -Message $msg
    }
}


function Log-Message([string]$Type, [string]$Message, [int]$Id){
    # NOTE: by convention, this script is setting the $Id parameter to match the
    # numbers for the output types described in 'Help about_Redirection'
    try {
        Write-EventLog `
            -LogName Application `
            -Source $Me `
            -Category 0 `
            -EventId $Id `
            -EntryType $Type `
            -Message "[$($Me)]: $($Message)" `
            -ErrorAction Stop
        $msg = "[EventLog $($Type)/$($Id)]: $($Message)"
    }
    catch {
        $ex = $_.Exception.Message
        $msg = "Error logging message (Id=$($Id), Type=$($Type))!`n"
        $msg += "--- Log Message ---`n$($Message)`n--- Log Message ---`n"
        $msg += "--- Exception ---`n$($ex)`n--- Exception ---"
    }
    Write-Verbose $msg
}


function Log-Warning([string]$Message) {
    Log-Message -Type Warning -Message $Message -Id 3
}


function Log-Error([string]$Message){
    Log-Message -Type Error -Message $Message -Id 2
}


function Log-Info([string]$Message) {
    Log-Message -Type Information -Message $Message -Id 1
}


function Log-Debug([string]$Message) {
    if ($UpdaterDebugLogging) {
        Log-Message -Type Information -Message $Message -Id 5
    }
}

################################################################################


$ErrorActionPreference = "Stop"

try {
    . $UpdaterSettings
}
catch {
    $ex = $_.Exception.Message
    Write-Host "Error reading settings file: '$($UpdaterSettings)' [$($ex)]"
    Exit
}

# NOTE: $MyInvocation is not available when run as ScheduledJob, so we have to
# set a shortcut for our name explicitly ourselves here:
$Me = "$($ServiceName)-Updater"

if (-Not ([System.Diagnostics.EventLog]::SourceExists($Me))) {
    try {
        New-EventLog -LogName Application -Source $Me
    }
    catch {
        $ex = $_.Exception.Message
        Write-Verbose "Error creating event log source: $($ex)"
    }
}
Log-Debug "$($Me) started..."


# first check if the service is installed and running at all
$ServiceRunningBefore = ServiceIsRunning $ServiceName

$UpdPathConfig = "$($UpdateSourcePath)\Configs"
$UpdPathMarkerFiles = "$($UpdateSourcePath)\Service\UpdateMarkers"
$UpdPathBinaries = "$($UpdateSourcePath)\Service\Binaries"
$UploadPathLogs = "$($UpdateSourcePath)\Logs"

Exit-IfDirMissing $InstallationPath "installation"
Exit-IfDirMissing $LogPath "log files"
Exit-IfDirMissing $ConfigPath "configuration files"
Exit-IfDirMissing $UpdateSourcePath "update source"
Exit-IfDirMissing $UpdPathConfig "configuration update"
Exit-IfDirMissing $UpdPathMarkerFiles "update marker"
Exit-IfDirMissing $UpdPathBinaries "service binaries update"
Exit-IfDirMissing $UploadPathLogs "log file target"


# NOTE: Upload-LogFiles is called before AND after the main tasks to make sure
#       the logfiles are uploaded no matter if one of the other tasks fails and
#       terminates the entire script:
Upload-LogFiles

$ConfigShouldBeUpdated = NewConfig-Available $ConfigPath
$ServiceShouldBeUpdated = NewServiceBinaries-Available
if (-Not ($ConfigShouldBeUpdated -Or $ServiceShouldBeUpdated)) {
    Log-Debug "No update action found to be necessary."
    Exit
}

# define where the configuration is located that should be tested:
$ConfigToTest = $ConfigPath
if ($ConfigShouldBeUpdated) {
    $ConfigToTest = $UpdPathConfig
}

# define which configuration checker executable should be used for testing:
$ConfigTestBinary = "$($InstallationPath)\AutoTxConfigTest.exe"
if ($ServiceShouldBeUpdated) {
    $UpdPackage = Find-InstallationPackage
    $ConfigTestBinary = "$($UpdPackage)\AutoTx\AutoTxConfigTest.exe"
}

# now we're all set and can run the config test:
$ConfigValid, $ConfigSummary = Config-IsValid $ConfigTestBinary $ConfigToTest


# if we don't have a valid configuration we complain and terminate the update:
if (-Not ($ConfigValid)) {
    Log-Error "Configuration not valid for service, $($Me) terminating!"
    Send-MailReport -Subject "Update failed, configuration invalid!" `
        -Body $("An update action was found to be necessary, however the"
            "configuration didn't`npass the validator.`n`nThe following summary"
            "was generated by the configuration checker:`n`n$($ConfigSummary)")
    Exit
}

Exit

$ServiceUpdated = Update-ServiceBinaries

if ($msg -ne "") {
    if ($ServiceRunningBefore) {
        Log-Debug "Update action occurred, finishing up..."
        Start-MyService
    } else {
        Log-Debug "Not starting the service as it was not running before."
    }
    Send-MailReport -Subject "Config and / or service has been updated!" `
        -Body $msg
}

Upload-LogFiles

Log-Debug "$($Me) finished."