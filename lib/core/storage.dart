import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small async key/value store. Two implementations ship: the Keystore-backed
/// secure store for secrets and a SharedPreferences store for UI settings.
/// Tests use [MemoryStore].
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
  Future<void> delete(String key);
  Future<void> clear();
}

/// Secrets: device token, device id, server URL. Android Keystore + EncryptedSharedPreferences.
class SecureStore implements KeyValueStore {
  SecureStore()
      : _s = const FlutterSecureStorage(
          aOptions: AndroidOptions(
            encryptedSharedPreferences: true,
            resetOnError: true,
            sharedPreferencesName: 'servepos_secure',
          ),
        );
  final FlutterSecureStorage _s;

  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String? value) =>
      value == null ? _s.delete(key: key) : _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
  @override
  Future<void> clear() => _s.deleteAll();
}

/// Non-secret preferences (language, timeout, selected profile).
class PrefsStore implements KeyValueStore {
  static const _prefix = 'sp.';
  Future<SharedPreferences> get _p => SharedPreferences.getInstance();

  @override
  Future<String?> read(String key) async => (await _p).getString('$_prefix$key');
  @override
  Future<void> write(String key, String? value) async {
    final p = await _p;
    if (value == null) {
      await p.remove('$_prefix$key');
    } else {
      await p.setString('$_prefix$key', value);
    }
  }

  @override
  Future<void> delete(String key) async => (await _p).remove('$_prefix$key');
  @override
  Future<void> clear() async {
    final p = await _p;
    for (final k in p.getKeys().where((k) => k.startsWith(_prefix)).toList()) {
      await p.remove(k);
    }
  }
}

class MemoryStore implements KeyValueStore {
  MemoryStore([Map<String, String>? initial]) : data = {...?initial};
  final Map<String, String> data;
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      data.remove(key);
    } else {
      data[key] = value;
    }
  }

  @override
  Future<void> delete(String key) async => data.remove(key);
  @override
  Future<void> clear() async => data.clear();
}

/// JSON documents (menu cache, carts, outbox) in the app-private documents dir.
abstract class JsonStore {
  Future<Object?> load(String name);
  Future<void> save(String name, Object? value);
  Future<void> clear();
}

class FileJsonStore implements JsonStore {
  Directory? _dir;

  Future<Directory> _root() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/servepos');
    if (!d.existsSync()) d.createSync(recursive: true);
    return _dir = d;
  }

  @override
  Future<Object?> load(String name) async {
    try {
      final f = File('${(await _root()).path}/$name.json');
      if (!f.existsSync()) return null;
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(String name, Object? value) async {
    final f = File('${(await _root()).path}/$name.json');
    if (value == null) {
      if (f.existsSync()) await f.delete();
      return;
    }
    // Write-then-rename so a crash never leaves half a file.
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(value), flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> clear() async {
    final d = await _root();
    if (d.existsSync()) await d.delete(recursive: true);
    _dir = null;
  }
}

class MemoryJsonStore implements JsonStore {
  final Map<String, String> data = {};
  @override
  Future<Object?> load(String name) async => data[name] == null ? null : jsonDecode(data[name]!);
  @override
  Future<void> save(String name, Object? value) async {
    if (value == null) {
      data.remove(name);
    } else {
      data[name] = jsonEncode(value);
    }
  }

  @override
  Future<void> clear() async => data.clear();
}
