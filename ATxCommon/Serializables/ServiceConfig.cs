﻿using System;
using System.Collections.Generic;
using System.Configuration;
using System.IO;
using System.Xml;
using System.Xml.Linq;
using System.Xml.Serialization;
using NLog;

namespace ATxCommon.Serializables
{
    /// <summary>
    /// AutoTx service configuration class.
    /// </summary>
    [Serializable]
    public class ServiceConfig
    {
        private static readonly Logger Log = LogManager.GetCurrentClassLogger();


        #region required configuration parameters

        /// <summary>
        /// A human friendly name for the host, to be used in emails etc.
        /// </summary>
        public string HostAlias { get; set; }

        /// <summary>
        /// The base drive for the spooling directories (incoming and managed).
        /// </summary>
        public string SourceDrive { get; set; }

        /// <summary>
        /// The name of a directory on SourceDrive that is monitored for new files.
        /// </summary>
        public string IncomingDirectory { get; set; }

        /// <summary>
        /// A directory on SourceDrive to hold the three subdirectories "DONE",
        /// "PROCESSING" and "UNMATCHED" used during and after transfers.
        /// </summary>
        public string ManagedDirectory { get; set; }

        /// <summary>
        /// A human friendly name for the target, to be used in emails etc.
        /// </summary>
        public string DestinationAlias { get; set; }

        /// <summary>
        /// Target path to transfer files to. Usually a UNC location.
        /// </summary>
        public string DestinationDirectory { get; set; }

        /// <summary>
        /// The name of a subdirectory in the DestinationDirectory to be used
        /// to keep the temporary data of running transfers.
        /// </summary>
        public string TmpTransferDir { get; set; }

        /// <summary>
        /// The interval (in ms) for checking for new files and system parameters.
        /// </summary>
        public int ServiceTimer { get; set; }

        /// <summary>
        /// Maximum allowed CPU usage across all cores in percent. Running transfers will be paused
        /// if this limit is exceeded.
        /// </summary>
        public int MaxCpuUsage { get; set; }

        /// <summary>
        /// Minimum amount of free RAM (in MB) required for the service to operate.
        /// </summary>
        public int MinAvailableMemory { get; set; }

        #endregion


        #region optional configuration parameters

        /// <summary>
        /// Switch on debug log messages. Default: false.
        /// </summary>
        public bool Debug { get; set; } = false;

        /// <summary>
        /// The name of a marker file to be placed in all **sub**directories
        /// inside the IncomingDirectory.
        /// </summary>
        public string MarkerFile { get; set; }

        /// <summary>
        /// SMTP server to send mails and Fatal/Error log messages. No mails if omitted.
        /// </summary>
        public string SmtpHost { get; set; }

        /// <summary>
        /// SMTP port for sending emails. Default: 25.
        /// </summary>
        public int SmtpPort { get; set; } = 25;

        /// <summary>
        /// SMTP username to authenticate when sending emails (if required).
        /// </summary>
        public string SmtpUserCredential { get; set; }

        /// <summary>
        /// SMTP password to authenticate when sending emails (if required).
        /// </summary>
        public string SmtpPasswortCredential { get; set; }

        /// <summary>
        /// The email address to be used as "From:" when sending mail notifications.
        /// </summary>
        public string EmailFrom { get; set; }

        /// <summary>
        /// A prefix to be added to any email subject. Default: "[AutoTx Service] ".
        /// </summary>
        public string EmailPrefix { get; set; } = "[AutoTx Service] ";

        /// <summary>
        /// The mail recipient address for admin notifications (including "Fatal" log messages).
        /// </summary>
        public string AdminEmailAdress { get; set; }
        
        /// <summary>
        /// The mail recipient address for debug notifications (including "Error" log messages).
        /// </summary>
        public string AdminDebugEmailAdress { get; set; }

        /// <summary>
        /// Send an email to the user upon completed transfers. Default: true.
        /// </summary>
        public bool SendTransferNotification { get; set; } = true;

        /// <summary>
        /// Send email notifications to the admin on selected events. Default: true.
        /// </summary>
        public bool SendAdminNotification { get; set; } = true;

        /// <summary>
        /// Minimum time in minutes between two notifications to the admin. Default: 60.
        /// </summary>
        public int AdminNotificationDelta { get; set; } = 60;

        /// <summary>
        /// Minimum time in minutes between two mails about expired folders. Default: 720 (12h).
        /// </summary>
        public int GraceNotificationDelta { get; set; } = 720;

        /// <summary>
        /// Minimum time in minutes between two low-space notifications. Default: 720 (12h).
        /// </summary>
        public int StorageNotificationDelta { get; set; } = 720;

        /// <summary>
        /// Number of days after data in the "DONE" location expires. Default: 30.
        /// </summary>
        public int GracePeriod { get; set; } = 30;

        /// <summary>
        /// A list of process names causing transfers to be suspended if running.
        /// </summary>
        [XmlArray]
        [XmlArrayItem(ElementName = "ProcessName")]
        public List<string> BlacklistedProcesses { get; set; }

        /// <summary>
        /// Whether to enforce ACL inheritance when moving files and directories, see 
        /// https://support.microsoft.com/en-us/help/320246 for more details. Default: false.
        /// </summary>
        public bool EnforceInheritedACLs { get; set; } = false;

        /// <summary>
        /// A list of drives and thresholds to monitor free space.
        /// </summary>
        [XmlArray]
        [XmlArrayItem(ElementName = "DriveToCheck")]
        public List<DriveToCheck> SpaceMonitoring { get; set; }

        /// <summary>
        /// Limit RoboCopy transfer bandwidth (mostly for testing purposes). Default: 0.
        /// </summary>
        /// See the RoboCopy documentation for more details.
        public int InterPacketGap { get; set; } = 0;

        #endregion

        
        #region wrappers for derived parameters

        /// <summary>
        /// The full path to the incoming directory.
        /// </summary>
        [XmlIgnore]
        public string IncomingPath => Path.Combine(SourceDrive, IncomingDirectory);

        /// <summary>
        /// The full path to the managed directory.
        /// </summary>
        [XmlIgnore]
        public string ManagedPath => Path.Combine(SourceDrive, ManagedDirectory);

        /// <summary>
        /// The full path to the processing directory.
        /// </summary>
        [XmlIgnore]
        public string ProcessingPath => Path.Combine(ManagedPath, "PROCESSING");

        /// <summary>
        /// The full path to the done directory / grace location.
        /// </summary>
        [XmlIgnore]
        public string DonePath => Path.Combine(ManagedPath, "DONE");

        /// <summary>
        /// The full path to the directory for unmatched user directories.
        /// </summary>
        [XmlIgnore]
        public string UnmatchedPath => Path.Combine(ManagedPath, "UNMATCHED");

        #endregion


        /// <summary>
        /// ServiceConfig constructor, currently empty.
        /// </summary>
        private ServiceConfig() {
            Log.Trace("ServiceConfig() constructor.");
        }

        /// <summary>
        /// Dummy method raising an exception (this class must not be serialized).
        /// </summary>
        public static void Serialize(string file, ServiceConfig c) {
            // the config is never meant to be written by us, therefore:
            throw new SettingsPropertyIsReadOnlyException("The config file must not be written by the service!");
        }

        /// <summary>
        /// Load the host specific and the common XML configuration files, combine them and
        /// deserialize them into a ServiceConfig object. The host specific configuration file's
        /// name is defined as the hostname with an ".xml" suffix.
        /// </summary>
        /// <param name="path">The path to the configuration files.</param>
        /// <returns>A ServiceConfig object with validated settings.</returns>
        public static ServiceConfig Deserialize(string path) {
            ServiceConfig config;

            var commonFile = Path.Combine(path, "config.common.xml");
            var specificFile = Path.Combine(path, Environment.MachineName + ".xml");

            // for parsing the configuration from two separate files we are using the default
            // behaviour of the .NET XmlSerializer on duplicates: only the first occurrence is
            // used, all other ones are silentley being discarded - this way we simply append the
            // contents of the common config file to the host-specific and deserialize then:
            var combined = XElement.Load(specificFile);
            Log.Debug("Loaded host specific configuration XML file: [{0}]", specificFile);
            // the common configuration file is optional, so check if it exists at all:
            if (File.Exists(commonFile)) {
                var common = XElement.Load(commonFile);
                Log.Debug("Loaded common configuration XML file: [{0}]", commonFile);
                combined.Add(common.Nodes());
                Log.Trace("Combined XML structure:\n\n{0}\n\n", combined);
            }

            using (var reader = XmlReader.Create(new StringReader(combined.ToString()))) {
                Log.Debug("Trying to parse combined XML.");
                var serializer = new XmlSerializer(typeof(ServiceConfig));
                config = (ServiceConfig) serializer.Deserialize(reader);
            }

            ValidateConfiguration(config);
            
            Log.Debug("Successfully parsed and validated configuration XML.");
            return config;
        }

        /// <summary>
        /// Validate the configuration, throwing exceptions on invalid parameters.
        /// </summary>
        private static void ValidateConfiguration(ServiceConfig c) {
            var errmsg = "";

            string CheckEmpty(string value, string name) {
                // if the string is null terminate the validation immediately since this means the
                // file doesn't contain a required parameter at all:
                if (value == null) {
                    var msg = $"mandatory parameter missing: <{name}>";
                    Log.Error(msg);
                    throw new ConfigurationErrorsException(msg);
                }

                if (string.IsNullOrWhiteSpace(value))
                    return $"mandatory parameter unset: <{name}>\n";

                return string.Empty;
            }

            string CheckMinValue(int value, string name, int min) {
                if (value == 0)
                    return $"<{name}> is unset (or set to 0), minimal accepted value is {min}\n";

                if (value < min)
                    return $"<{name}> must not be smaller than {min}\n";

                return string.Empty;
            }

            string CheckLocalDrive(string value, string name) {
                var driveType = new DriveInfo(value).DriveType;
                if (driveType != DriveType.Fixed)
                    return $"<{name}> ({value}) must be a local fixed drive, not '{driveType}'!\n";
                return string.Empty;
            }

            void SubOptimal(string name, string value, string msg) {
                Log.Warn(">>> Sub-optimal setting detected: <{0}> [{1}] {2}", name, value, msg);
            }

            void LogAndThrow(string msg) {
                msg = $"Configuration issues detected:\n{msg}";
                Log.Error(msg);
                throw new ConfigurationErrorsException(msg);
            }

            // check if all required parameters are there and non-empty / non-zero:
            errmsg += CheckEmpty(c.HostAlias, nameof(c.HostAlias));
            errmsg += CheckEmpty(c.SourceDrive, nameof(c.SourceDrive));
            errmsg += CheckEmpty(c.IncomingDirectory, nameof(c.IncomingDirectory));
            errmsg += CheckEmpty(c.ManagedDirectory, nameof(c.ManagedDirectory));
            errmsg += CheckEmpty(c.DestinationAlias, nameof(c.DestinationAlias));
            errmsg += CheckEmpty(c.DestinationDirectory, nameof(c.DestinationDirectory));
            errmsg += CheckEmpty(c.TmpTransferDir, nameof(c.TmpTransferDir));

            errmsg += CheckMinValue(c.ServiceTimer, nameof(c.ServiceTimer), 1000);
            errmsg += CheckMinValue(c.MaxCpuUsage, nameof(c.MaxCpuUsage), 5);
            errmsg += CheckMinValue(c.MinAvailableMemory, nameof(c.MinAvailableMemory), 256);

            // if any of the required parameter checks failed we terminate now as many of the
            // string checks below would fail on empty strings:
            if (!string.IsNullOrWhiteSpace(errmsg)) 
                LogAndThrow(errmsg);


            ////////// REQUIRED PARAMETERS SETTINGS VALIDATION //////////

            // SourceDrive
            if (c.SourceDrive.Substring(1) != @":\")
                errmsg += "<SourceDrive> must be of form [X:\\]\n!";
            errmsg += CheckLocalDrive(c.SourceDrive, nameof(c.SourceDrive));

            // spooling directories: IncomingDirectory + ManagedDirectory
            if (c.IncomingDirectory.StartsWith(@"\"))
                errmsg += "<IncomingDirectory> must not start with a backslash!\n";
            if (c.ManagedDirectory.StartsWith(@"\"))
                errmsg += "<ManagedDirectory> must not start with a backslash!\n";

            // DestinationDirectory
            if (!Directory.Exists(c.DestinationDirectory))
                errmsg += $"can't find (or reach) destination: {c.DestinationDirectory}\n";

            // TmpTransferDir
            var tmpTransferPath = Path.Combine(c.DestinationDirectory, c.TmpTransferDir);
            if (!Directory.Exists(tmpTransferPath))
                errmsg += $"can't find (or reach) temporary transfer dir: {tmpTransferPath}\n";


            ////////// OPTIONAL PARAMETERS SETTINGS VALIDATION //////////

            // DriveName
            foreach (var driveToCheck in c.SpaceMonitoring) {
                errmsg += CheckLocalDrive(driveToCheck.DriveName, nameof(driveToCheck.DriveName));
            }


            ////////// WEAK CHECKS ON PARAMETERS SETTINGS //////////
            // those checks are non-critical and are simply reported to the logs

            if (!c.DestinationDirectory.StartsWith(@"\\"))
                SubOptimal("DestinationDirectory", c.DestinationDirectory, "is not a UNC path!");


            if (string.IsNullOrWhiteSpace(errmsg))
                return;

            LogAndThrow(errmsg);
        }

        /// <summary>
        /// Generate a human-readable sumary of the current configuration.
        /// </summary>
        /// <returns>A string with details on the configuration.</returns>
        public string Summary() {
            var msg =
                $"HostAlias: {HostAlias}\n" +
                $"SourceDrive: {SourceDrive}\n" +
                $"IncomingDirectory: {IncomingDirectory}\n" +
                $"MarkerFile: {MarkerFile}\n" +
                $"ManagedDirectory: {ManagedDirectory}\n" +
                $"GracePeriod: {GracePeriod} (" +
                TimeUtils.DaysToHuman(GracePeriod, false) + ")\n" +
                $"DestinationDirectory: {DestinationDirectory}\n" +
                $"TmpTransferDir: {TmpTransferDir}\n" +
                $"EnforceInheritedACLs: {EnforceInheritedACLs}\n" +
                $"ServiceTimer: {ServiceTimer} ms\n" +
                $"InterPacketGap: {InterPacketGap}\n" +
                $"MaxCpuUsage: {MaxCpuUsage}%\n" +
                $"MinAvailableMemory: {MinAvailableMemory}\n";
            foreach (var processName in BlacklistedProcesses) {
                msg += $"BlacklistedProcess: {processName}\n";
            }
            foreach (var drive in SpaceMonitoring) {
                msg += $"Drive to check free space: {drive.DriveName} " +
                       $"(threshold: {Conv.MegabytesToString(drive.SpaceThreshold)})\n";
            }
            if (string.IsNullOrEmpty(SmtpHost)) {
                msg += "SmtpHost: ====== Not configured, disabling email! ======" + "\n";
            } else {
                msg +=
                    $"SmtpHost: {SmtpHost}\n" +
                    $"SmtpUserCredential: {SmtpUserCredential}\n" +
                    $"EmailPrefix: {EmailPrefix}\n" +
                    $"EmailFrom: {EmailFrom}\n" +
                    $"AdminEmailAdress: {AdminEmailAdress}\n" +
                    $"AdminDebugEmailAdress: {AdminDebugEmailAdress}\n" +
                    $"StorageNotificationDelta: {StorageNotificationDelta} (" +
                    TimeUtils.MinutesToHuman(StorageNotificationDelta, false) + ")\n" +
                    $"AdminNotificationDelta: {AdminNotificationDelta} (" +
                    TimeUtils.MinutesToHuman(AdminNotificationDelta, false) + ")\n" +
                    $"GraceNotificationDelta: {GraceNotificationDelta} (" +
                    TimeUtils.MinutesToHuman(GraceNotificationDelta, false) + ")\n";
            }
            return msg;
        }
    }
}
