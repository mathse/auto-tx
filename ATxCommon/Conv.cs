﻿namespace ATxCommon
{
    public static class Conv
    {
        public const int MegaBytes = 1024 * 1024;
        public const int GigaBytes = MegaBytes * 1024;

        /// <summary>
        /// Convert bytes into a human-readable string with the appropriate suffix (up to TB).
        /// </summary>
        /// <param name="numBytes">The number of bytes.</param>
        /// <returns>A formatted string with the size showing one decimal.</returns>
        public static string BytesToString(long numBytes) {
            string[] suffixes = {"Bytes", "KB", "MB", "GB", "TB"};
            var order = 0;
            while (numBytes >= 1024 && order < suffixes.Length - 1) {
                order++;
                numBytes /= 1024;
            }

            return $"{numBytes:0.#} {suffixes[order]}";
        }

        /// <summary>
        /// Wrapper to convert megabytes into human-readable size string.
        /// See <see cref="BytesToString"/> for more details.
        /// </summary>
        public static string MegabytesToString(long megaBytes) {
            return BytesToString(megaBytes * MegaBytes);
        }

        /// <summary>
        /// Wrapper to convert gigabytes into human-readable size string.
        /// See <see cref="BytesToString"/> for more details.
        /// </summary>
        public static string GigabytesToString(long gigaBytes) {
            return BytesToString(gigaBytes * GigaBytes);
        }
    }
}