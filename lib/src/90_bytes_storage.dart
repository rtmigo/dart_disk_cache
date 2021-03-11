// SPDX-FileCopyrightText: (c) 2020 Art Galkin <ortemeo@gmail.com>
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:io';
import 'dart:typed_data';
import 'package:meta/meta.dart';
import 'package:disk_cache/src/10_file_removal.dart';
import 'package:disk_cache/src/10_readwrite.dart';
import 'package:disk_cache/src/80_unistor.dart';
import 'package:path/path.dart' as paths;
import '00_common.dart';
import '10_files.dart';
import '10_hashing.dart';

typedef DeleteFile(File file);


/// A persistent data storage that provides access to [Uint8List] binary items by [String] keys.
abstract class BytesStorageBase extends UniStorage {

  BytesStorageBase(directory): super(directory);

  String keyToHash(String key);

  // void compactSync({
  //   final int maxSizeBytes = JS_MAX_SAFE_INTEGER,
  //   final maxCount = JS_MAX_SAFE_INTEGER })
  // {
  //   List<FileAndStat> files = <FileAndStat>[];
  //
  //   List<FileSystemEntity> entries;
  //   try {
  //     entries = directory.listSync(recursive: true);
  //   } on FileSystemException catch (e) {
  //     throw FileSystemException(
  //         "DiskCache failed to listSync directory $directory right after creation. "
  //             "osError: ${e.osError}.");
  //   }
  //
  //   for (final entry in entries) {
  //     if (entry.path.endsWith(DIRTY_SUFFIX)) {
  //       deleteSyncCalm(File(entry.path));
  //       continue;
  //     }
  //     if (entry.path.endsWith(DATA_SUFFIX)) {
  //       final f = File(entry.path);
  //       files.add(FileAndStat(f));
  //     }
  //   }
  //
  //   FileAndStat.deleteOldest(files, maxSumSize: maxSizeBytes, maxCount: maxCount,
  //       deleteFile: (file) {
  //         // alternate deleteFile callback will not only delete file, but also
  //         // the parent dir, if empty
  //         deleteSyncCalm(file);
  //         deleteDirIfEmptySync(file.parent);
  //       });
  // }


  @override
  @protected
  void deleteFile(File file) {
    file.deleteSync();
    deleteDirIfEmptySync(file.parent);
  }

  bool delete(String key) {
    final file = this._findExistingFile(key);
    if (file==null)
      return false;
    assert(file.path.endsWith(DATA_SUFFIX));
    this.deleteFile(file);
    return true;
  }

  File writeBytes(String key, List<int> data) {

    final cacheFile = this._findExistingFile(key) ?? this._proposeUniqueFile(key);

    File? dirtyFile = _uniqueDirtyFn();
    try {
      writeKeyAndDataSync(dirtyFile, key, data); //# dirtyFile.writeAsBytes(data);

      try {
        Directory(paths.dirname(cacheFile.path)).createSync();
      } on FileSystemException {}

      if (cacheFile.existsSync()) cacheFile.deleteSync();
      dirtyFile.renameSync(cacheFile.path);
      dirtyFile = null;
    } finally {
      if (dirtyFile != null && dirtyFile.existsSync()) dirtyFile.delete();
    }

    return cacheFile;
  }

  /// Returns the target directory path for a file that holds the data for [key].
  /// The directory may exist or not.
  ///
  /// Each directory corresponds to a hash value. Due to hash collision different keys
  /// may produce the same hash. Files with the same hash will be placed in the same
  /// directory.
  Directory _keyToHypotheticalDir(String key) {
    String hash = this.keyToHash(key);
    assert(!hash.contains(paths.style.context.separator));
    return Directory(paths.join(this.directory.path, hash));
  }

  /// Returns all existing files whose key-hashes are the same as the hash of [key].
  /// Any of them may be the file that is currently storing the data for [key].
  /// It's also possible, that neither of them stores the data for [key].
  Iterable<File> _keyToExistingFiles(String key) sync* {
    final parent = this._keyToHypotheticalDir(key);
    for (final fse in listSyncCalm(parent))
      if (fse.path.endsWith(DATA_SUFFIX))
        yield File(fse.path);
  }

  /// Generates a unique filename in a directory that should contain file [key].
  File _proposeUniqueFile(String key) {
    final dirPath = _keyToHypotheticalDir(key).path;
    for (int i = 0;; ++i) {
      final candidateFile = File(paths.join(dirPath, "$i$DATA_SUFFIX"));
      if (!candidateFile.existsSync()) return candidateFile;
    }
  }

  /// Tries to find a file for the [key]. If file does not exist, returns `null`.
  File? _findExistingFile(String key) {
    for (final existingFile in this._keyToExistingFiles(key)) {
      if (readKeySync(existingFile) == key) return existingFile;
    }
    return null;
  }

  Uint8List? readBytes(String key) {
    for (final fileCandidate in _keyToExistingFiles(key)) {
      final data = readIfKeyMatchSync(fileCandidate, key);
      if (data != null) {
        setTimestampToNow(fileCandidate);  // calling async func w/o waiting
        return data;
      }
    }
    return null;
  }

  File _uniqueDirtyFn() {
    for (int i = 0;; ++i) {
      final f = File(directory.path + "/$i$DIRTY_SUFFIX");
      if (!f.existsSync()) return f;
    }
  }

  @override
  Uint8List? operator [](Object? key) {
    return readBytes(key as String);
  }

  @override
  void operator []=(String key, List<int>? value) {
    if (value==null)
      this.delete(key);
    else
      writeBytes(key, value);
  }

  @override
  void clear() {
    this.directory.deleteSync(recursive: true); // todo test
  }

  @override
  Iterable<String> get keys sync* {
    for (final f in listSyncCalm(this.directory, recursive: true)) {
      //print(f);
      if (this.isFile(f.path))
        yield readKeySync(File(f.path));
    }
  }

  @override
  Uint8List? remove(Object? key) {
    this.delete(key as String);
  }

  bool isFile(String path)
  {
    return FileSystemEntity.isFileSync(path);
    // todo calm for cache
  }

}

class BytesStorage extends BytesStorageBase {

  BytesStorage(Directory directory) : super(directory);

  @override
  String keyToHash(String key) => stringToMd5(key);

}