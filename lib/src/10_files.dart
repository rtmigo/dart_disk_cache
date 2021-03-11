// SPDX-FileCopyrightText: (c) 2020 Art Galkin <ortemeo@gmail.com>
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:io';

/// Returns the result of [Directory.listSync], providing an empty list 
/// if [FileSystemException] occurs.
List<FileSystemEntity> listSyncCalm(Directory d, {bool recursive = false}) {
  try {
    return d.listSync(recursive: recursive);
  }
  on FileSystemException catch (_) {
    // Windows:
    //    FileSystemException: Directory listing failed, path = '...' 
    //    (OS Error: The system cannot find the path specified., errno = 3)
    // MacOS:    
    //    FileSystemException: Directory listing failed, path = '...'
    //    (OS Error: No such file or directory, errno = 2)
    //
    // I don't think it's a good idea trying to differentiate error code in 
    // imaginable OS. So if we got a file exception while trying to list,
    // we just assume we cannot list.
    return [];
  }
}

bool isDirectoryNotEmptyException(FileSystemException e)
{
  // https://www-numi.fnal.gov/offline_software/srt_public_context/WebDocs/Errors/unix_system_errors.html
  const LINUX_ENOTEMPTY = 39;
  if (Platform.isLinux && e.osError?.errorCode == LINUX_ENOTEMPTY)
    return true;

  // there is no evident source of macOS errors in 2021 O_O
  const GUESSING_MACOS_NOT_EMPTY = 66;
  if (Platform.isMacOS && e.osError?.errorCode == GUESSING_MACOS_NOT_EMPTY)
    return true;

  // https://docs.microsoft.com/en-us/windows/win32/debug/system-error-codes--0-499-
  const WINDOWS_DIR_NOT_EMPTY = 145; // 0x91
  if (Platform.isWindows && e.osError?.errorCode == WINDOWS_DIR_NOT_EMPTY)
    return true;

  return false;
}

void deleteDirIfEmptySync(Directory d) {
  try {
    d.deleteSync(recursive: false);
  } on FileSystemException catch (e) {

    if (!isDirectoryNotEmptyException(e))
      print("WARNING: Got unexpected osError.errorCode=${e.osError?.errorCode} "
          "trying to remove directory.");
  }
}

bool deleteSyncCalm(File file) {
  try {
    file.deleteSync();
    return true;
  } on FileSystemException catch (e) {
    print("WARNING: Failed to delete $file: $e");
    return false;
  }
}

Future<void> setTimestampToNow(File file) async {
  // since the cache is located in a temporary directory,
  // any file there can be deleted at any time
  try {
    file.setLastModifiedSync(DateTime.now());
  } on FileSystemException catch (e, _) {
    print("WARNING: Cannot set timestamp to file $file: $e");
  }
}