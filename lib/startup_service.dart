import 'dart:io';

class StartupService {
  static const String _appName = 'FlowStateTracker';
  static const String _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

  /// Checks if the app is currently set to run on Windows startup
  static Future<bool> isEnabled() async {
    try {
      final result = await Process.run('reg', ['query', _runKey, '/v', _appName]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Registers the app executable to launch automatically on Windows startup
  static Future<bool> enable() async {
    try {
      final exePath = Platform.resolvedExecutable;
      // Wrap path in quotes to handle folder names with spaces
      final result = await Process.run('reg', [
        'add',
        _runKey,
        '/v',
        _appName,
        '/t',
        'REG_SZ',
        '/d',
        '"$exePath"',
        '/f',
      ]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Removes the app from Windows startup
  static Future<bool> disable() async {
    try {
      final result = await Process.run('reg', [
        'delete',
        _runKey,
        '/v',
        _appName,
        '/f',
      ]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Toggles the startup state
  static Future<bool> toggle() async {
    final currentlyEnabled = await isEnabled();
    if (currentlyEnabled) {
      await disable();
      return false;
    } else {
      await enable();
      return true;
    }
  }
}