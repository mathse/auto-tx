﻿using System;
using System.IO;
using System.Management;
using ATxCommon;
using RoboSharp;

namespace ATxService
{
    public partial class AutoTx
    {
        private RoboCommand _roboCommand;

        /// <summary>
        /// Start transferring data from a given source directory to the destination
        /// location that is stored in CurrentTargetTmp. Requires CopyState to be in
        /// status "Stopped", sets CopyState to "Active" and FilecopyFinished to
        /// false. The currently processed path is stored in the global status
        /// variable CurrentTransferSrc.
        /// </summary>
        /// <param name="sourcePath">The full path to a folder.</param>
        private void StartTransfer(string sourcePath) {
            // only proceed when in a valid state:
            if (_transferState != TxState.Stopped)
                return;

            _status.CurrentTransferSrc = sourcePath;
            _status.CurrentTransferSize = FsUtils.GetDirectorySize(sourcePath);

            // the user name is expected to be the last part of the path:
            _status.CurrentTargetTmp = new DirectoryInfo(sourcePath).Name;
            FsUtils.CreateNewDirectory(_status.CurrentTargetTmpFull(), false);

            _transferState = TxState.Active;
            _status.TransferInProgress = true;
            try {
                // events
                _roboCommand.OnCopyProgressChanged += RsProgressChanged;
                _roboCommand.OnFileProcessed += RsFileProcessed;
                _roboCommand.OnCommandCompleted += RsCommandCompleted;

                // copy options
                _roboCommand.CopyOptions.Source = sourcePath;
                _roboCommand.CopyOptions.Destination = _status.CurrentTargetTmpFull();

                // limit the transfer bandwidth by waiting between packets:
                _roboCommand.CopyOptions.InterPacketGap = _config.InterPacketGap;

                // /S :: copy Subdirectories, but not empty ones
                // _roboCommand.CopyOptions.CopySubdirectories = true;

                // /E :: copy subdirectories, including Empty ones
                _roboCommand.CopyOptions.CopySubdirectoriesIncludingEmpty = true;

                // /PF :: check run hours on a Per File (not per pass) basis
                // _roboCommand.CopyOptions.CheckPerFile = true;

                // /SECFIX ::  fix file security on all files, even skipped files
                // _roboCommand.CopyOptions.FixFileSecurityOnAllFiles = true;

                // copyflags :
                //     D=Data, A=Attributes, T=Timestamps
                //     S=Security=NTFS ACLs, O=Owner info, U=aUditing info

                // /SEC :: copy files with security (equivalent to /COPY:DATS)
                // _roboCommand.CopyOptions.CopyFilesWithSecurity = true;
                // /COPYALL :: copy all file info (equivalent to /COPY:DATSOU)
                // _roboCommand.CopyOptions.CopyAll = true;
                _roboCommand.CopyOptions.CopyFlags = "DATO";

                // select options
                _roboCommand.SelectionOptions.ExcludeOlder = true;
                // retry options
                _roboCommand.RetryOptions.RetryCount = 0;
                _roboCommand.RetryOptions.RetryWaitTime = 2;
                _roboCommand.Start();
                Log.Info("Transfer started, total size: {0}",
                    Conv.BytesToString(_status.CurrentTransferSize));
                Log.Debug("RoboCopy command options: {0}", _roboCommand.CommandOptions);
            }
            catch (ManagementException ex) {
                Log.Error("Error in StartTransfer(): {0}", ex.Message);
            }
        }

        /// <summary>
        /// Pause a running transfer.
        /// </summary>
        private void PauseTransfer() {
            // only proceed when in a valid state:
            if (_transferState != TxState.Active)
                return;

            Log.Info("Pausing the active transfer...");
            _roboCommand.Pause();
            _transferState = TxState.Paused;
            Log.Debug("Transfer paused");
        }

        /// <summary>
        /// Resume a previously paused transfer.
        /// </summary>
        private void ResumePausedTransfer() {
            // only proceed when in a valid state:
            if (_transferState != TxState.Paused)
                return;

            Log.Info("Resuming the paused transfer...");
            _roboCommand.Resume();
            _transferState = TxState.Active;
            Log.Debug("Transfer resumed");
        }

        #region robocommand callbacks

        /// <summary>
        /// RoboSharp OnFileProcessed callback handler.
        /// 
        /// NOTE: the handler is called on any NEW message produced by RoboCopy, in particular this
        /// also means that a "new file" event is triggered when the transfer of a new file is
        /// about TO START! Therefore the "OnFileProcessed" name is slightly misleading.
        /// </summary>
        private void RsFileProcessed(object sender, FileProcessedEventArgs e) {
            try {
                var processed = e.ProcessedFile;

                Log.Trace("RsFileProcessed (OnFileProcessed handler) triggered:  " +
                    "Class [{1}]  -  Size [{2}]  -  Name [{0}]",
                    e.ProcessedFile.Name, e.ProcessedFile.FileClass, e.ProcessedFile.Size);

                // WARNING: RoboSharp doesn't seem to offer a culture invariant representation
                // of the FileClass, so this might fail in non-english environments:
                if (processed.FileClass.ToLower().Equals("new file")) {
                    _transferredFiles.Add(string.Format("{0} ({1})", processed.Name,
                        Conv.BytesToString(processed.Size)));
                }
            }
            catch (Exception ex) {
                Log.Error("Error in RsFileProcessed(): {0}", ex.Message);
            }
        }

        /// <summary>
        /// RoboSharp OnCommandCompleted callback handler.
        /// </summary>
        private void RsCommandCompleted(object sender, RoboCommandCompletedEventArgs e) {
            if (_transferState == TxState.DoNothing)
                return;

            _roboCommand.Stop();
            Log.Debug("Transfer stopped");
            _transferState = TxState.Stopped;
            _roboCommand.Dispose();
            _roboCommand = new RoboCommand();
            _status.TransferInProgress = false;
        }

        /// <summary>
        /// RoboSharp OnCopyProgressChanged callback handler.
        /// Print a log message if the progress has changed for more than 20%.
        /// </summary>
        private void RsProgressChanged(object sender, CopyProgressEventArgs e) {
            // e.CurrentFileProgress has the current progress in percent
            // report progress in steps of 20:
            var progress = ((int) e.CurrentFileProgress / 20) * 20;
            if (progress == _txProgress)
                return;

            _txProgress = progress;
            Log.Debug("Transfer progress {0}%", progress);
        }

        #endregion
    }
}