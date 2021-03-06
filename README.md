# ![AutoTx logo][img_autotx_logo] AutoTx - AutoTransfer Service

AutoTx is a Windows service doing background file transfers from a local disk to
a network share, licensed under the [GPLv3](LICENSE), developed and provided by
the [Imaging Core Facility (IMCF)][web_imcf] at the [Biozentrum][web_bioz],
[University of Basel][web_unibas], Switzerland.

It is primarily designed and developed for getting user-data off microscope
acquisition computers **after acquisition** (i.e. not in parallel!) with these
goals:

- The user owning the data should be able to log off from the computer after
  initiating the data transfer, enabling other users to log on while data is
  still being transferred.
- Any other interactive session at the computer must not be disturbed by the
  background data transfer (in particular any data acquisition done by the next
  user at the system).
- No additional software has to be operated by the user for initiating the
  transfer, avoiding the need for learning yet another tool.

## Features

- **User-initiated:** data is actively "handed over" to the service by the user
  to prevent interfering with running acquisitions.
- **Monitoring of system-critical parameters:** the service has a number of
  configurable system parameters that are constantly being monitored. If one of
  them is outside their defined valid range, any running transfer will be
  immediately suspended and no new transfers will be started.
- **Auto-Resume:** if a transfer is interrupted due to system limitations or the
  operating system being shut down the transfer gets automatically resumed as
  soon as possible without requiring any user interaction.
- **Email notifications:** the user is notified via email of completed
  transfers, as well as on transfer interruptions (system being shutdown or
  similar).
- **Error reporting:** in addition to user notifications, the service will send
  error notifications via email to a separate admin address. Optionally, the
  service offers the possibility to monitor free disk space on the local disks
  and send notifications to the admins as well. Various measures are implemented
  to prevent the service from flooding you with emails.
- **Tray Application:** complementary to the service an application running in
  the system tray is provided, showing details on what's going on to the user.
- **Headless and GUI:** submitting a folder for transfer can either be done by
  dropping it into a specific "*incoming*" folder (using the File Explorer or
  some post-acquisition script or whatever fits your scenario) or by using the
  guided folder selection dialog provided through the tray app context menu.

## Concept

The service is expected to operate in an *ActiveDirectory* (AD) environment,
with a dedicated AD-account (referred to as the *service account*) being used to
run the service on the client computer(s). Furthermore, a network share is
expected (currently only a single one is supported) where the service account
has appropriate permissions to copy data to.

For any user that should be allowed to use the transfer service, a dedicated
folder has to exist on this network share, the name of the folder being the
(short) AD account name (i.e. the login name or *sAMAccountName*) of the user.

After the user initiates a transfer (i.e. hands over a folder to the AutoTx
service), the folder gets **immediately** moved to the *spooling* location on
the same disk. This is done to prevent users from accidentially messing with
folders subject to being transferred as well as for internal bookkeeping of what
has to be transferred.

When no other transfer is running and all system parameters are within their
valid ranges, the AutoTx service will start copying the files and folders to a
temporary transfer directory inside the target location. Only when a transfer
has completed, it will be moved from the temporary location over to the user's
folder. This has the benefit that a user can't accidentially access data from
incomplete transfers as well as it serves as a kind of implicit notification: if
a folder shows up in their location, the user will know it has been fully
transferred.

Once the transfer is completed the folder is moved from the local *spooling*
directory to a "*grace*" location inside the spooling directory hierarchy. This
is done to prevent accidentially deleting user data. Currently no automatic
deletion of data is implemented. Instead, the service keeps track of the grace
location and will send notification emails to the admin once a given time
period has expired (defaulting to 30 days).

## Under the hood

For the actual transfer task, the service is using a C# wrapper for the
Microsoft RoboCopy tool called [RoboSharp][web_robosharp].

Logging is done using the amazing [NLog][web_nlog] framework, allowing a great
deal of flexibility in terms of log levels, targets (file, email, eventlog) and
rules.

## Requirements

- **ActiveDirectory integration:** no authentication mechanisms for the target
  storage are currently supported, meaning the function account running the
  service on the client has to have local read-write permissions as well as full
  write permissions on the target location. The reason behind this is to avoid
  having to administer local accounts on all clients as well as having easy
  access to user information (email addresses, ...).
- **Permissions:** for the CPU load monitoring to work, the function account has
  to be a member of the "*Performance Monitor Users*" group, either via GPO /
  ActiveDirectory or by adding it to the corresponding local group on each
  client.
- **.NET Framework:** version 4.5 required.
- **Windows 7 / Server 2012 R2:** the service has been tested on those versions
  of Windows, other versions sharing the same kernels (*Server 2008 R2*,
  *Windows 8.1*) should be compatible as well but have yet been tested.
- **64 bit:** currently only 64-bit versions are available (mostly due to lack
  of options for testing), 32-bit support is planned though.


# Installation

See the [instructions for installing the service](INSTALLATION.md) for details.

# Operation

## Configuration

The AutoTx service configuration is done through two XML files. They are
structured in a very simple way and well-commented to make them easily
readable. The first file `config.common.xml` defines settings which are common
to all AutoTx installations in the same network. The second file contains the
host-specific settings for the service and is using the machine's hostname for
its file name (followed by the `.xml` suffix). Both files are located in the
`conf/` folder inside the service installation directory and share the exact
same syntax with the host-specific file having priority (i.e. all settings
defined in the common file can be overridden in the host-specific one).

Having the configuration in this *layered* way allows an administrator to have
the exact same `conf/` folder on all hosts where AutoTx is installed, thus
greatly simplifying automated management.

Example config files (fully commented) are provided with the source code:

- [A minimal set](Resources/conf-minimal/) of configuration settings required
  to run the service.
- [The full set](Resources/conf/) of all possible configuration settings.

## Email-Templates

Notification emails to users are based on the templates that can be found in
[Mail-Templates](Resources/Mail-Templates) subdirectory of the service
installation. Those files contain certain keywords that will be replaced with
current values by the service before sending the mail. This way the content of
the notifications can easily be adjusted without having to re-compile the
service.

## Logging

The Windows Event Log seems to be a good place for logging if you have a proper
monitoring solution in place, which centrally collects and checks it. Since we
don't have one, and none of the other ActiveDirectory setups known to us have on
either, the service places its log messages in a plain text file in good old
Unix habits.

Everything that needs attention is written into a file called
`<HOSTNAME>.AutoTx.log` in the `var/` subdirectory of the service's installation
directory. The contents of the log file can be monitored in real-time using the
PowerShell command `Get-Content -Wait "$($env:COMPUTERNAME).AutoTx.log"` or by
running the [Watch-Logfile.ps1](Scripts/Watch-Logfile.ps1) script.

The log level can be set through the configuration file.

## Status

Same as for the log messages, the service stores its status in a file, just this
is in XML format so it is easily usable from C# code using the core
Serialization / Deserialization functions. Likewise, this file is to be found in
the `var/` directory and called `status.xml`.

## Grace Location Cleanup

After a transfer has completed, the service moves all folders of that transfer
into one subfolder inside the `$ManagedDirectory/DONE/<username>/` location. The
subfolders are named with a timestamp `YYYY-MM-DD__hh-mm-ss`. The grace location
checks are done
 - at service startup
 - after a transfer has finished
 - once every *N* hours, configurable for every host

## Updates

The service comes with a dedicated updater to facilitate managing updates and
configurations on many machines. See the [Updater Readme](Updater/README.md) for
all the details.

# Contributing

Please see the [Development And Contribution Guide](CONTRIBUTING.md) for details
about compiling from source, filing pull requests etc.


[img_autotx_logo]: https://git.scicore.unibas.ch/vamp/auto-tx/raw/master/Resources/auto-tx-logo.png

[web_imcf]: https://www.biozentrum.unibas.ch/imcf
[web_bioz]: https://www.biozentrum.unibas.ch/
[web_unibas]: https://www.unibas.ch/
[web_robosharp]: https://github.com/tjscience/RoboSharp
[web_robosharp_fork]: https://git.scicore.unibas.ch/vamp/robosharp
[web_nlog]: http://nlog-project.org/