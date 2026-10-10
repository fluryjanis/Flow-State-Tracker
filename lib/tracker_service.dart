import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'storage_service.dart';

// --- Win32 Structs & Signatures ---
final class LASTINPUTINFO extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int dwTime;
}

typedef _GetTickCount64Dart = int Function();
typedef _GetLastInputInfoDart = int Function(Pointer<LASTINPUTINFO>);
typedef _GetForegroundWindowDart = int Function();
typedef _GetWindowTextWDart = int Function(int, Pointer<Uint16>, int);
typedef _GetWindowThreadProcessIdDart = int Function(int, Pointer<Uint32>);
typedef _OpenProcessDart = int Function(int, int, int);
typedef _QueryFullProcessImageNameWDart =
    int Function(int, int, Pointer<Uint16>, Pointer<Uint32>);
typedef _CloseHandleDart = int Function(int);
typedef _GetAsyncKeyStateDart = int Function(int);

// --- COM / WASAPI Audio Signatures ---
typedef _CoInitializeExDart = int Function(Pointer<Void>, int);
typedef _CoCreateInstanceDart =
    int Function(
      Pointer<Uint8>,
      Pointer<Void>,
      int,
      Pointer<Uint8>,
      Pointer<Pointer<IntPtr>>,
    );

class HourlyActivity {
  Map<String, int> appSeconds = {};
  Map<String, int> appActiveSeconds = {};
  Map<String, int> appTypingSeconds = {};
  Map<String, int> appKeystrokes = {};
  int idleSeconds = 0;
  int keystrokes = 0;

  HourlyActivity({
    Map<String, int>? appSeconds,
    Map<String, int>? appActiveSeconds,
    Map<String, int>? appTypingSeconds,
    Map<String, int>? appKeystrokes,
    int? idleSeconds,
    int? keystrokes,
  }) : appSeconds = appSeconds ?? {},
       appActiveSeconds = appActiveSeconds ?? {},
       appTypingSeconds = appTypingSeconds ?? {},
       appKeystrokes = appKeystrokes ?? {},
       idleSeconds = idleSeconds ?? 0,
       keystrokes = keystrokes ?? 0;
}

class TrackerService extends ChangeNotifier {
  static final TrackerService instance = TrackerService._internal();
  factory TrackerService() => instance;

  late final DynamicLibrary _kernel32;
  late final DynamicLibrary _user32;
  late final DynamicLibrary _ole32;

  late final _GetTickCount64Dart _getTickCount64;
  late final _GetLastInputInfoDart _getLastInputInfo;
  late final _GetForegroundWindowDart _getForegroundWindow;
  late final _GetWindowTextWDart _getWindowTextW;
  late final _GetWindowThreadProcessIdDart _getWindowThreadProcessId;
  late final _OpenProcessDart _openProcess;
  late final _QueryFullProcessImageNameWDart _queryFullProcessImageNameW;
  late final _CloseHandleDart _closeHandle;
  late final _GetAsyncKeyStateDart _getAsyncKeyState;

  late final _CoInitializeExDart _coInitializeEx;
  late final _CoCreateInstanceDart _coCreateInstance;
  int Function(Pointer<Utf8>)? _mediaSessionPlayingForProcess;
  int Function(int, Pointer<Uint16>, int)? _browserAddressBarValue;

  Timer? _ticker;
  Timer? _keyPoller;
  int _autoSaveCounter = 0;
  DateTime _currentDay = DateTime.now();
  int? _lastSampleTickMs;
  int _elapsedMsRemainder = 0;
  int _idleMsRemainder = 0;
  bool _wasCurrentlyIdle = false;

  static const int _bufferSize = 1024;
  late final Pointer<LASTINPUTINFO> _lastInputPtr;
  late final Pointer<Uint32> _pidPtr;
  late final Pointer<Uint32> _sizePtr;
  late final Pointer<Uint16> _strBuffer;

  int _keystrokesThisTick = 0;
  final List<int> _rollingKeystrokes = List<int>.filled(60, 0);
  final List<int> _rollingTypingSeconds = List<int>.filled(60, 0);
  int _rollingWindowStart = 0;
  int _rollingTotalKeystrokes = 0;
  int _rollingActiveTypingSeconds = 0;
  int _rollingElapsedSeconds = 0;
  int currentWpm = 0;
  int currentClusteredWpm = 0;

  String currentActiveApp = 'Idle';
  String _currentExeName = '';
  String _currentWindowTitle = '';
  bool isCurrentlyIdle = false;

  // Real-time Context Switch & Focus Break Tracking
  String _lastTrackedApp = '';
  int totalWindowSwitches = 0;
  Map<String, int> appFocusBreaks = {};

  // Throttled Media Playback Detection Cache
  DateTime? _lastWakeLockCheckTime;
  bool _cachedWakeLockState = false;
  DateTime? _lastAudioDetectedTime;
  DateTime? _lastMediaSessionCheckTime;
  bool _cachedMediaSessionPlaying = false;
  String _cachedMediaSessionProcess = '';
  DateTime? _lastBrowserAddressCheckTime;
  int _cachedBrowserWindowHandle = 0;
  String? _cachedBrowserAddress;

  Map<int, HourlyActivity> hourlyData = {
    for (int i = 0; i < 24; i++) i: HourlyActivity(),
  };

  Map<String, int> appTotals = {};
  Map<String, int> appActiveSeconds = {};
  Map<String, int> appTypingSeconds = {};
  Map<String, int> appKeystrokes = {};
  int totalIdleSeconds = 0;

  final Set<String> _browserProcesses = {
    'chrome.exe',
    'msedge.exe',
    'firefox.exe',
    'brave.exe',
    'opera.exe',
    'vivaldi.exe',
    'arc.exe',
  };

  TrackerService._internal() {
    _kernel32 = DynamicLibrary.open('kernel32.dll');
    _user32 = DynamicLibrary.open('user32.dll');
    _ole32 = DynamicLibrary.open('ole32.dll');
    try {
      _mediaSessionPlayingForProcess =
          DynamicLibrary.open('media_session_detector.dll').lookupFunction<
            Int32 Function(Pointer<Utf8>),
            int Function(Pointer<Utf8>)
          >('IsMediaSessionPlayingForProcess');
      _browserAddressBarValue =
          DynamicLibrary.open('media_session_detector.dll').lookupFunction<
            Int32 Function(IntPtr, Pointer<Uint16>, Int32),
            int Function(int, Pointer<Uint16>, int)
          >('GetBrowserAddressBarValue');
    } catch (_) {
      // Continue with wake-lock and audio detection if the native helper is
      // unavailable (for example, when running an older packaged build).
    }

    _getTickCount64 = _kernel32
        .lookup<NativeFunction<Uint64 Function()>>('GetTickCount64')
        .asFunction();
    _closeHandle = _kernel32
        .lookup<NativeFunction<Int32 Function(IntPtr)>>('CloseHandle')
        .asFunction();
    _openProcess = _kernel32
        .lookup<NativeFunction<IntPtr Function(Uint32, Int32, Uint32)>>(
          'OpenProcess',
        )
        .asFunction();
    _queryFullProcessImageNameW = _kernel32
        .lookup<
          NativeFunction<
            Int32 Function(IntPtr, Uint32, Pointer<Uint16>, Pointer<Uint32>)
          >
        >('QueryFullProcessImageNameW')
        .asFunction();

    _getLastInputInfo = _user32
        .lookup<NativeFunction<Int32 Function(Pointer<LASTINPUTINFO>)>>(
          'GetLastInputInfo',
        )
        .asFunction();
    _getForegroundWindow = _user32
        .lookup<NativeFunction<IntPtr Function()>>('GetForegroundWindow')
        .asFunction();
    _getWindowTextW = _user32
        .lookup<NativeFunction<Int32 Function(IntPtr, Pointer<Uint16>, Int32)>>(
          'GetWindowTextW',
        )
        .asFunction();
    _getWindowThreadProcessId = _user32
        .lookup<NativeFunction<Uint32 Function(IntPtr, Pointer<Uint32>)>>(
          'GetWindowThreadProcessId',
        )
        .asFunction();
    _getAsyncKeyState = _user32
        .lookup<NativeFunction<Int16 Function(Int32)>>('GetAsyncKeyState')
        .asFunction();

    _coInitializeEx = _ole32
        .lookup<NativeFunction<Int32 Function(Pointer<Void>, Uint32)>>(
          'CoInitializeEx',
        )
        .asFunction();
    _coCreateInstance = _ole32
        .lookup<
          NativeFunction<
            Int32 Function(
              Pointer<Uint8>,
              Pointer<Void>,
              Uint32,
              Pointer<Uint8>,
              Pointer<Pointer<IntPtr>>,
            )
          >
        >('CoCreateInstance')
        .asFunction();

    try {
      _coInitializeEx(nullptr, 0x2); // COINIT_APARTMENTTHREADED
    } catch (_) {}

    _lastInputPtr = calloc<LASTINPUTINFO>()
      ..ref.cbSize = sizeOf<LASTINPUTINFO>();
    _pidPtr = calloc<Uint32>();
    _sizePtr = calloc<Uint32>();
    _strBuffer = calloc<Uint16>(_bufferSize);

    _loadSavedDataForToday();
    _startKeyPoller();
    _startTracking();
  }

  final Set<int> _keysDown = {};

  void _startKeyPoller() {
    final List<int> typingKeys = [
      8, 9, 13, 32, // Backspace, Tab, Enter, Space
      for (int i = 48; i <= 57; i++) i, // 0-9
      for (int i = 65; i <= 90; i++) i, // A-Z
      186, 187, 188, 189, 190, 191, 192, 219, 220, 221, 222, // Punctuation
    ];

    _keyPoller = Timer.periodic(const Duration(milliseconds: 30), (_) {
      try {
        for (final k in typingKeys) {
          final isDown = (_getAsyncKeyState(k) & 0x8000) != 0;
          if (isDown) {
            if (!_keysDown.contains(k)) {
              _keysDown.add(k);
              _keystrokesThisTick++;
            }
          } else {
            _keysDown.remove(k);
          }
        }
      } catch (_) {}
    });
  }

  void _loadSavedDataForToday() {
    try {
      final saved = StorageService.loadDay(_currentDay);
      if (saved != null) {
        totalIdleSeconds = (saved['totalIdleSeconds'] as num?)?.toInt() ?? 0;
        totalWindowSwitches =
            (saved['totalWindowSwitches'] as num?)?.toInt() ?? 0;

        if (saved['appFocusBreaks'] is Map) {
          final rawBreaks = saved['appFocusBreaks'] as Map;
          appFocusBreaks = rawBreaks.map(
            (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
          );
        }

        if (saved['appTotals'] is Map) {
          final rawTotals = saved['appTotals'] as Map;
          appTotals = rawTotals.map(
            (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
          );
        }

        if (saved['appActiveSeconds'] is Map) {
          final rawActive = saved['appActiveSeconds'] as Map;
          appActiveSeconds = rawActive.map(
            (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
          );
        }

        if (saved['appTypingSeconds'] is Map) {
          final rawTyping = saved['appTypingSeconds'] as Map;
          appTypingSeconds = rawTyping.map(
            (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
          );
        }

        if (saved['appKeystrokes'] is Map) {
          final rawKeys = saved['appKeystrokes'] as Map;
          appKeystrokes = rawKeys.map(
            (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
          );
        }

        if (saved['hourlyData'] is Map) {
          final rawHourly = saved['hourlyData'] as Map;
          rawHourly.forEach((hStr, val) {
            final h = int.tryParse(hStr.toString());
            if (h != null && val is Map) {
              final rawAppSecs = val['appSeconds'] as Map? ?? {};
              final appSecs = rawAppSecs.map(
                (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
              );

              final rawAppActiveSecs = val['appActiveSeconds'] as Map? ?? {};
              final appActiveSecs = rawAppActiveSecs.map(
                (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
              );

              final rawAppTypingSecs = val['appTypingSeconds'] as Map? ?? {};
              final appTypingSecs = rawAppTypingSecs.map(
                (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
              );

              final rawAppKeys = val['appKeystrokes'] as Map? ?? {};
              final appKeys = rawAppKeys.map(
                (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
              );

              final idleSecs = (val['idleSeconds'] as num?)?.toInt() ?? 0;
              final keyCount = (val['keystrokes'] as num?)?.toInt() ?? 0;

              hourlyData[h] = HourlyActivity(
                appSeconds: appSecs,
                appActiveSeconds: appActiveSecs,
                appTypingSeconds: appTypingSecs,
                appKeystrokes: appKeys,
                idleSeconds: idleSecs,
                keystrokes: keyCount,
              );
            }
          });
        }
      }
    } catch (_) {}
  }

  void saveToDisk() {
    StorageService.saveDay(
      date: _currentDay,
      appTotals: appTotals,
      appActiveSeconds: appActiveSeconds,
      appTypingSeconds: appTypingSeconds,
      appKeystrokes: appKeystrokes,
      totalIdleSeconds: totalIdleSeconds,
      hourlyData: hourlyData,
      totalWindowSwitches: totalWindowSwitches,
      appFocusBreaks: appFocusBreaks,
    );
  }

  void _startTracking() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    try {
      final now = DateTime.now();

      // Timer.periodic can be delayed by a busy UI thread or a suspended app.
      // Use the monotonic Windows clock so those delays do not silently discard
      // tracked time. Carry sub-second jitter forward instead of rounding each
      // sample independently.
      final currentTick = _getTickCount64();
      final previousTick = _lastSampleTickMs;
      _lastSampleTickMs = currentTick;
      var elapsedIntervalMs = 1000;
      var elapsedSeconds = 1;
      if (previousTick != null) {
        final elapsedMs = currentTick - previousTick;
        if (elapsedMs >= 0) {
          elapsedIntervalMs = elapsedMs;
          final totalElapsedMs = _elapsedMsRemainder + elapsedMs;
          elapsedSeconds = totalElapsedMs ~/ 1000;
          _elapsedMsRemainder = totalElapsedMs % 1000;
        }
      }

      if (now.day != _currentDay.day ||
          now.month != _currentDay.month ||
          now.year != _currentDay.year) {
        saveToDisk();
        _currentDay = now;
        hourlyData = {for (int i = 0; i < 24; i++) i: HourlyActivity()};
        appTotals.clear();
        appActiveSeconds.clear();
        appTypingSeconds.clear();
        appKeystrokes.clear();
        totalIdleSeconds = 0;
        totalWindowSwitches = 0;
        appFocusBreaks.clear();
        _lastTrackedApp = '';
        _lastAudioDetectedTime = null;
        _lastWakeLockCheckTime = null;
        _elapsedMsRemainder = 0;
        _idleMsRemainder = 0;
        _wasCurrentlyIdle = false;
      }

      final currentHour = now.hour;
      final activeTarget = _fetchActiveTarget();

      final keysThisSecond = _keystrokesThisTick;
      _keystrokesThisTick = 0;

      // 90 seconds idle threshold: prevents false idle during reading and thinking
      const idleThresholdMs = 90000;
      int elapsedIdle = 0;

      if (_getLastInputInfo(_lastInputPtr) != 0) {
        elapsedIdle =
            ((currentTick & 0xFFFFFFFF) - _lastInputPtr.ref.dwTime) &
            0xFFFFFFFF;
      }

      // A key observed by our poller is activity even if GetLastInputInfo is
      // stale or unavailable for this sample.
      final isInputIdle = elapsedIdle >= idleThresholdMs && keysThisSecond == 0;

      // Multi-tiered video/audio detection (Video Wake Lock + Audio Meter)
      final bool isMediaPlaying =
          isInputIdle &&
          _isMediaActivelyPlaying(
            activeTarget,
            _currentExeName,
            _currentWindowTitle,
          );
      final bool isCurrentlyEngaged = elapsedIdle < 1500 || keysThisSecond > 0;
      var activeSecondsThisSample = 0;
      if (elapsedSeconds > 0 && isCurrentlyEngaged) {
        activeSecondsThisSample = keysThisSecond > 0
            ? 1
            : ((elapsedIdle + 999) ~/ 1000).clamp(1, elapsedSeconds).toInt();
      }
      final typingSecondsThisSample = keysThisSecond > 0 ? 1 : 0;

      isCurrentlyIdle = isInputIdle && !isMediaPlaying;
      var idleSecondsThisSample = 0;
      if (isCurrentlyIdle) {
        // Count only the part of this interval beyond the threshold, so a
        // delayed callback does not classify pre-threshold time as idle.
        final idleIntervalMs = _wasCurrentlyIdle
            ? elapsedIntervalMs
            : (elapsedIdle - idleThresholdMs)
                  .clamp(0, elapsedIntervalMs)
                  .toInt();
        final accumulatedIdleMs = _idleMsRemainder + idleIntervalMs;
        idleSecondsThisSample = accumulatedIdleMs ~/ 1000;
        _idleMsRemainder = accumulatedIdleMs % 1000;
      } else {
        _idleMsRemainder = 0;
      }
      _wasCurrentlyIdle = isCurrentlyIdle;

      if (isCurrentlyIdle) {
        currentActiveApp = 'Idle';
        totalIdleSeconds += idleSecondsThisSample;
        hourlyData[currentHour]!.idleSeconds += idleSecondsThisSample;
      } else {
        currentActiveApp = activeTarget;

        if (_lastTrackedApp.isNotEmpty &&
            currentActiveApp != _lastTrackedApp &&
            currentActiveApp != 'Desktop' &&
            _lastTrackedApp != 'Idle') {
          totalWindowSwitches++;
          if (_lastTrackedApp != 'Desktop') {
            appFocusBreaks[_lastTrackedApp] =
                (appFocusBreaks[_lastTrackedApp] ?? 0) + 1;
          }
        }
        _lastTrackedApp = currentActiveApp;

        appTotals[currentActiveApp] =
            (appTotals[currentActiveApp] ?? 0) + elapsedSeconds;
        final hourMap = hourlyData[currentHour]!.appSeconds;
        hourMap[currentActiveApp] =
            (hourMap[currentActiveApp] ?? 0) + elapsedSeconds;

        if (activeSecondsThisSample > 0) {
          appActiveSeconds[currentActiveApp] =
              (appActiveSeconds[currentActiveApp] ?? 0) +
              activeSecondsThisSample;
          final hourActiveMap = hourlyData[currentHour]!.appActiveSeconds;
          hourActiveMap[currentActiveApp] =
              (hourActiveMap[currentActiveApp] ?? 0) + activeSecondsThisSample;
        }

        if (typingSecondsThisSample > 0) {
          appTypingSeconds[currentActiveApp] =
              (appTypingSeconds[currentActiveApp] ?? 0) +
              typingSecondsThisSample;
          final hourTypingMap = hourlyData[currentHour]!.appTypingSeconds;
          hourTypingMap[currentActiveApp] =
              (hourTypingMap[currentActiveApp] ?? 0) + typingSecondsThisSample;

          appKeystrokes[currentActiveApp] =
              (appKeystrokes[currentActiveApp] ?? 0) + keysThisSecond;
          hourlyData[currentHour]!.keystrokes += keysThisSecond;

          final hourKeyMap = hourlyData[currentHour]!.appKeystrokes;
          hourKeyMap[currentActiveApp] =
              (hourKeyMap[currentActiveApp] ?? 0) + keysThisSecond;
        }
      }

      if (elapsedSeconds > 0) {
        _rollingElapsedSeconds = (_rollingElapsedSeconds + elapsedSeconds)
            .clamp(0, 60)
            .toInt();
        if (elapsedSeconds >= 60) {
          _rollingKeystrokes.fillRange(0, _rollingKeystrokes.length, 0);
          _rollingKeystrokes[59] = keysThisSecond;
          _rollingTypingSeconds.fillRange(0, _rollingTypingSeconds.length, 0);
          _rollingTypingSeconds[59] = keysThisSecond > 0 ? 1 : 0;
          _rollingWindowStart = 0;
          _rollingTotalKeystrokes = keysThisSecond;
          _rollingActiveTypingSeconds = keysThisSecond > 0 ? 1 : 0;
        } else {
          for (var second = 0; second < elapsedSeconds; second++) {
            final nextKeys = second == elapsedSeconds - 1 ? keysThisSecond : 0;
            final nextTypingSecond =
                second == elapsedSeconds - 1 && keysThisSecond > 0 ? 1 : 0;
            final droppedIndex = _rollingWindowStart;

            _rollingTotalKeystrokes -= _rollingKeystrokes[droppedIndex];
            _rollingKeystrokes[droppedIndex] = nextKeys;
            _rollingTotalKeystrokes += nextKeys;

            _rollingActiveTypingSeconds -= _rollingTypingSeconds[droppedIndex];
            _rollingTypingSeconds[droppedIndex] = nextTypingSecond;
            _rollingActiveTypingSeconds += nextTypingSecond;
            _rollingWindowStart = (droppedIndex + 1) % 60;
          }
        }
      } else if (keysThisSecond > 0) {
        // Preserve a keypress if two timer callbacks happen within one clock
        // second; it belongs to the newest slot in the rolling window.
        final newestIndex = (_rollingWindowStart + 59) % 60;
        _rollingKeystrokes[newestIndex] += keysThisSecond;
        _rollingTotalKeystrokes += keysThisSecond;
        if (_rollingTypingSeconds[newestIndex] == 0) {
          _rollingTypingSeconds[newestIndex] = 1;
          _rollingActiveTypingSeconds++;
        }
      }

      currentWpm = _rollingElapsedSeconds > 0
          ? ((_rollingTotalKeystrokes * 12) / _rollingElapsedSeconds).round()
          : 0;

      if (_rollingActiveTypingSeconds > 0 && _rollingTotalKeystrokes > 0) {
        currentClusteredWpm =
            ((_rollingTotalKeystrokes * 12) / _rollingActiveTypingSeconds)
                .round();
      } else {
        currentClusteredWpm = 0;
      }

      _autoSaveCounter += elapsedSeconds;
      if (_autoSaveCounter >= 30) {
        _autoSaveCounter = 0;
        saveToDisk();
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Tracker tick non-fatal: $e');
    }
  }

  // --- MULTI-TIERED VIDEO & AUDIO PLAYBACK DETECTION ---

  /// Primary check: Inspects Windows Kernel Power Requests for active Video Wake Locks
  bool _checkWindowsMediaWakeLock(String exeName) {
    final now = DateTime.now();

    // Throttle check to once every 3 seconds to keep CPU overhead at 0.00%
    if (_lastWakeLockCheckTime != null &&
        now.difference(_lastWakeLockCheckTime!).inSeconds < 3) {
      return _cachedWakeLockState;
    }

    _lastWakeLockCheckTime = now;
    try {
      final result = Process.runSync('powercfg', ['/requests']);
      if (result.exitCode == 0) {
        final output = result.stdout.toString().toLowerCase();

        // 1. Check DISPLAY section (where Chromium/video players register Video Wake Lock)
        final displayIndex = output.indexOf('display:');
        if (displayIndex != -1) {
          final nextSectionIndex = output.indexOf('system:', displayIndex);
          final displaySection = nextSectionIndex != -1
              ? output.substring(displayIndex, nextSectionIndex)
              : output.substring(displayIndex);

          // Video Wake Lock is actively requested by the browser/media player
          if (displaySection.contains('video wake lock')) {
            _cachedWakeLockState = true;
            return true;
          }

          if (exeName.isNotEmpty &&
              displaySection.contains(exeName.toLowerCase())) {
            _cachedWakeLockState = true;
            return true;
          }
        }

        // 2. Check SYSTEM / AUDIO section for active media streaming
        if (exeName.isNotEmpty) {
          final lowerExe = exeName.toLowerCase();
          if (output.contains(lowerExe)) {
            if (output.contains('audio stream is currently in use') ||
                output.contains('audio wake lock') ||
                output.contains('playing audio')) {
              _cachedWakeLockState = true;
              return true;
            }
          }
        }
      }
    } catch (_) {}

    _cachedWakeLockState = false;
    return false;
  }

  bool _isMediaCandidate(String activeApp, String windowTitle) {
    final lowerApp = activeApp.toLowerCase();
    final lowerTitle = windowTitle.toLowerCase();

    // Dedicated desktop players
    const mediaApps = [
      'spotify.exe',
      'vlc.exe',
      'wmplayer.exe',
      'mpc-hc.exe',
      'potplayer.exe',
      'itunes.exe',
      'foobar2000.exe',
      'tidal.exe',
    ];
    for (final app in mediaApps) {
      if (lowerApp.contains(app)) return true;
    }

    // Streaming websites
    const mediaSites = [
      'youtube',
      'netflix',
      'twitch',
      'spotify',
      'disneyplus',
      'hulu',
      'primevideo',
      'soundcloud',
      'crunchyroll',
      'kick.com',
      'vimeo',
    ];

    for (final site in mediaSites) {
      if (lowerApp.contains(site) || lowerTitle.contains(site)) {
        // Exclude blank YouTube homepage/tab
        if (site == 'youtube') {
          final isJustHome =
              lowerTitle == 'youtube' ||
              lowerTitle == 'youtube - google chrome' ||
              lowerTitle == 'youtube - microsoft​ edge' ||
              lowerTitle == 'youtube - brave' ||
              lowerTitle.isEmpty;
          if (isJustHome) return false;
        }
        return true;
      }
    }

    return false;
  }

  /// Secondary check: Hardware Audio Peak Meter
  bool _isAudioPlayingOnSystem() {
    Pointer<Uint8>? clsidMMDevice;
    Pointer<Uint8>? iidMMDevice;
    Pointer<Uint8>? iidMeter;
    Pointer<Pointer<IntPtr>>? ppEnumerator;
    Pointer<Pointer<IntPtr>>? ppDevice;
    Pointer<Pointer<IntPtr>>? ppMeter;
    Pointer<Float>? pPeak;

    Pointer<IntPtr>? pEnumerator;
    Pointer<IntPtr>? pDevice;
    Pointer<IntPtr>? pMeter;

    try {
      clsidMMDevice = calloc<Uint8>(16);
      iidMMDevice = calloc<Uint8>(16);
      iidMeter = calloc<Uint8>(16);

      _writeGuid(clsidMMDevice, [
        0x95,
        0x03,
        0xDE,
        0xBC,
        0x2F,
        0xE5,
        0x7C,
        0x46,
        0x8E,
        0x3D,
        0xC4,
        0x57,
        0x92,
        0x91,
        0x69,
        0x2E,
      ]);

      _writeGuid(iidMMDevice, [
        0xD2,
        0x64,
        0x56,
        0xA9,
        0x14,
        0x96,
        0x35,
        0x4F,
        0xA7,
        0x46,
        0xDE,
        0x8D,
        0xB6,
        0x36,
        0x17,
        0xE6,
      ]);

      _writeGuid(iidMeter, [
        0xF6,
        0x16,
        0x22,
        0xC0,
        0x67,
        0x8C,
        0x5B,
        0x4B,
        0x9D,
        0x00,
        0xD0,
        0x26,
        0xFE,
        0x06,
        0x3E,
        0x0D,
      ]);

      ppEnumerator = calloc<Pointer<IntPtr>>();
      final hrEnum = _coCreateInstance(
        clsidMMDevice,
        nullptr,
        23, // CLSCTX_ALL
        iidMMDevice,
        ppEnumerator,
      );

      if (hrEnum != 0 || ppEnumerator.value == nullptr)
        return _checkAudioGracePeriod();
      pEnumerator = ppEnumerator.value;

      final enumeratorVtable = Pointer<IntPtr>.fromAddress(pEnumerator.value);

      // Method 4: GetDefaultAudioEndpoint(eRender = 0, eRole = 0 or 1, IMMDevice** ppEndpoint)
      final fnGetDefaultEndpoint =
          Pointer<
                NativeFunction<
                  Int32 Function(
                    Pointer<Void>,
                    Int32,
                    Int32,
                    Pointer<Pointer<IntPtr>>,
                  )
                >
              >.fromAddress(enumeratorVtable[4])
              .asFunction<
                int Function(Pointer<Void>, int, int, Pointer<Pointer<IntPtr>>)
              >();

      ppDevice = calloc<Pointer<IntPtr>>();
      int hrEndpoint = fnGetDefaultEndpoint(pEnumerator.cast(), 0, 0, ppDevice);
      if (hrEndpoint != 0 || ppDevice.value == nullptr) {
        hrEndpoint = fnGetDefaultEndpoint(pEnumerator.cast(), 0, 1, ppDevice);
      }

      if (hrEndpoint != 0 || ppDevice.value == nullptr)
        return _checkAudioGracePeriod();
      pDevice = ppDevice.value;

      final deviceVtable = Pointer<IntPtr>.fromAddress(pDevice.value);

      // Method 3: Activate(REFIID iid, DWORD dwClsCtx, PROPVARIANT* pActivationParams, void** ppInterface)
      final fnActivate =
          Pointer<
                NativeFunction<
                  Int32 Function(
                    Pointer<Void>,
                    Pointer<Uint8>,
                    Uint32,
                    Pointer<Void>,
                    Pointer<Pointer<IntPtr>>,
                  )
                >
              >.fromAddress(deviceVtable[3])
              .asFunction<
                int Function(
                  Pointer<Void>,
                  Pointer<Uint8>,
                  int,
                  Pointer<Void>,
                  Pointer<Pointer<IntPtr>>,
                )
              >();

      ppMeter = calloc<Pointer<IntPtr>>();
      final hrActivate = fnActivate(
        pDevice.cast(),
        iidMeter,
        23,
        nullptr,
        ppMeter,
      );

      if (hrActivate != 0 || ppMeter.value == nullptr)
        return _checkAudioGracePeriod();
      pMeter = ppMeter.value;

      final meterVtable = Pointer<IntPtr>.fromAddress(pMeter.value);

      // Method 3: GetPeakValue(float* pfPeak)
      final fnGetPeakValue =
          Pointer<
                NativeFunction<Int32 Function(Pointer<Void>, Pointer<Float>)>
              >.fromAddress(meterVtable[3])
              .asFunction<int Function(Pointer<Void>, Pointer<Float>)>();

      pPeak = calloc<Float>();
      final hrPeak = fnGetPeakValue(pMeter.cast(), pPeak);

      if (hrPeak == 0 && pPeak.value > 0.0001) {
        _lastAudioDetectedTime = DateTime.now();
        return true;
      }

      return _checkAudioGracePeriod();
    } catch (_) {
      return _checkAudioGracePeriod();
    } finally {
      if (pMeter != null && pMeter != nullptr) _releaseComObject(pMeter);
      if (pDevice != null && pDevice != nullptr) _releaseComObject(pDevice);
      if (pEnumerator != null && pEnumerator != nullptr)
        _releaseComObject(pEnumerator);

      if (clsidMMDevice != null) calloc.free(clsidMMDevice);
      if (iidMMDevice != null) calloc.free(iidMMDevice);
      if (iidMeter != null) calloc.free(iidMeter);
      if (ppEnumerator != null) calloc.free(ppEnumerator);
      if (ppDevice != null) calloc.free(ppDevice);
      if (ppMeter != null) calloc.free(ppMeter);
      if (pPeak != null) calloc.free(pPeak);
    }
  }

  bool _checkAudioGracePeriod() {
    if (_lastAudioDetectedTime == null) return false;
    return DateTime.now().difference(_lastAudioDetectedTime!).inSeconds < 15;
  }

  void _releaseComObject(Pointer<IntPtr> pInterface) {
    try {
      final vtable = Pointer<IntPtr>.fromAddress(pInterface.value);
      final fnRelease =
          Pointer<NativeFunction<Uint32 Function(Pointer<Void>)>>.fromAddress(
            vtable[2],
          ).asFunction<int Function(Pointer<Void>)>();
      fnRelease(pInterface.cast());
    } catch (_) {}
  }

  static void _writeGuid(Pointer<Uint8> ptr, List<int> bytes) {
    for (int i = 0; i < 16; i++) {
      ptr[i] = bytes[i];
    }
  }

  /// Evaluates both OS Video Wake Lock and Audio output
  bool _isMediaActivelyPlaying(
    String activeApp,
    String exeName,
    String windowTitle,
  ) {
    if (!_isMediaCandidate(activeApp, windowTitle)) return false;

    // 1. Check the app's media-session status. This works for muted video too.
    if (_isMediaSessionPlaying(exeName)) return true;

    // 2. Check OS Video Wake Lock for browsers/players that publish one.
    if (_checkWindowsMediaWakeLock(exeName)) return true;

    // 3. Fall back to the endpoint audio meter for apps without media sessions.
    if (_isAudioPlayingOnSystem()) return true;

    return false;
  }

  bool _isMediaSessionPlaying(String exeName) {
    final query = _mediaSessionPlayingForProcess;
    if (query == null || exeName.isEmpty) return false;

    final now = DateTime.now();
    if (_cachedMediaSessionProcess == exeName &&
        _lastMediaSessionCheckTime != null &&
        now.difference(_lastMediaSessionCheckTime!).inSeconds < 3) {
      return _cachedMediaSessionPlaying;
    }

    _lastMediaSessionCheckTime = now;
    _cachedMediaSessionProcess = exeName;
    Pointer<Utf8>? processName;
    try {
      processName = exeName.toNativeUtf8();
      _cachedMediaSessionPlaying = query(processName) != 0;
    } catch (_) {
      _cachedMediaSessionPlaying = false;
    } finally {
      if (processName != null) malloc.free(processName);
    }
    return _cachedMediaSessionPlaying;
  }

  // --- DAY_PAGE HELPER METHODS (PRESERVED) ---

  int getAppWpm(String appName, {bool clustered = false}) {
    final keys = appKeystrokes[appName] ?? 0;
    if (keys == 0) return 0;

    if (clustered) {
      final typingSecs = appTypingSeconds[appName] ?? 0;
      if (typingSecs == 0) return 0;
      return ((keys * 12) / typingSecs).round().clamp(0, 250);
    } else {
      final totalSecs = appTotals[appName] ?? 0;
      if (totalSecs == 0) return 0;
      return ((keys * 12) / totalSecs).round();
    }
  }

  int getAppActivityPercentage(String appName) {
    final total = appTotals[appName] ?? 0;
    if (total == 0) return 0;
    final active = appActiveSeconds[appName] ?? 0;
    return ((active / total) * 100).round().clamp(0, 100);
  }

  int get overallActivityPercentage {
    final int totalSecs = totalTrackedDuration.inSeconds;
    if (totalSecs == 0) return 0;

    final int activeSecs = appActiveSeconds.values.fold<int>(
      0,
      (a, b) => a + b,
    );
    return ((activeSecs / totalSecs) * 100).round().clamp(0, 100);
  }

  int get totalDailyKeystrokes {
    return appKeystrokes.values.fold<int>(0, (a, b) => a + b);
  }

  int get dailyAverageWpm {
    final activeSecs = appTotals.values.fold<int>(0, (a, b) => a + b);
    final totalKeys = totalDailyKeystrokes;
    if (activeSecs == 0 || totalKeys == 0) return 0;
    return ((totalKeys * 12) / activeSecs).round();
  }

  int get dailyClusteredWpm {
    final typingSecs = appTypingSeconds.values.fold<int>(0, (a, b) => a + b);
    final totalKeys = totalDailyKeystrokes;
    if (typingSecs == 0 || totalKeys == 0) return 0;
    return ((totalKeys * 12) / typingSecs).round().clamp(0, 250);
  }

  List<double> get24HourWpmTrend({
    String targetName = 'Total',
    bool clustered = false,
  }) {
    final currentHour = DateTime.now().hour;
    final hours = List.generate(
      24,
      (i) => ((currentHour - 23 + i) % 24 + 24) % 24,
    );

    return hours.asMap().entries.map((entry) {
      final idx = entry.key;
      final h = entry.value;

      final activity = hourlyData[h];
      if (activity == null) return 0.0;

      if (targetName == 'Total') {
        final totalKeys = activity.keystrokes;

        double hourAvgWpm = 0.0;
        if (totalKeys > 0) {
          if (clustered) {
            final typingSecs = activity.appTypingSeconds.values.fold<int>(
              0,
              (a, b) => a + b,
            );
            if (typingSecs > 0) {
              hourAvgWpm = (totalKeys * 12.0) / typingSecs;
            } else {
              final activeSecs = activity.appSeconds.values.fold<int>(
                0,
                (a, b) => a + b,
              );
              if (activeSecs > 0) hourAvgWpm = (totalKeys * 12.0) / activeSecs;
            }
          } else {
            final totalActiveSecs = activity.appSeconds.values.fold<int>(
              0,
              (a, b) => a + b,
            );
            if (totalActiveSecs > 0) {
              hourAvgWpm = (totalKeys * 12.0) / totalActiveSecs;
            }
          }
        }

        if (idx == 23) {
          final liveWpm = (clustered ? currentClusteredWpm : currentWpm)
              .toDouble();
          if (liveWpm > 0) return liveWpm.clamp(0.0, 200.0);
          if (hourAvgWpm > 0) return hourAvgWpm.clamp(0.0, 200.0);

          final dayWpm = (clustered ? dailyClusteredWpm : dailyAverageWpm)
              .toDouble();
          if (dayWpm > 0) return dayWpm.clamp(0.0, 200.0);
          return 0.0;
        }

        return hourAvgWpm.clamp(0.0, 200.0);
      } else {
        final appKeys = activity.appKeystrokes[targetName] ?? 0;

        double appHourAvgWpm = 0.0;
        if (appKeys > 0) {
          if (clustered) {
            final typingSecs = activity.appTypingSeconds[targetName] ?? 0;
            if (typingSecs > 0) {
              appHourAvgWpm = (appKeys * 12.0) / typingSecs;
            } else {
              final appSecs = activity.appSeconds[targetName] ?? 0;
              if (appSecs > 0) appHourAvgWpm = (appKeys * 12.0) / appSecs;
            }
          } else {
            final appSecs = activity.appSeconds[targetName] ?? 0;
            if (appSecs > 0) {
              appHourAvgWpm = (appKeys * 12.0) / appSecs;
            }
          }
        }

        if (idx == 23) {
          final appWpm = getAppWpm(targetName, clustered: clustered).toDouble();
          if (appWpm > 0) return appWpm.clamp(0.0, 200.0);
          if (appHourAvgWpm > 0) return appHourAvgWpm.clamp(0.0, 200.0);
          return 0.0;
        }

        return appHourAvgWpm.clamp(0.0, 200.0);
      }
    }).toList();
  }

  void resetTodayData() {
    hourlyData = {for (int i = 0; i < 24; i++) i: HourlyActivity()};
    appTotals.clear();
    appActiveSeconds.clear();
    appTypingSeconds.clear();
    appKeystrokes.clear();
    totalIdleSeconds = 0;
    currentWpm = 0;
    currentClusteredWpm = 0;
    totalWindowSwitches = 0;
    appFocusBreaks.clear();
    _lastTrackedApp = '';
    _lastAudioDetectedTime = null;
    _lastWakeLockCheckTime = null;
    _rollingKeystrokes.fillRange(0, _rollingKeystrokes.length, 0);
    _rollingTypingSeconds.fillRange(0, _rollingTypingSeconds.length, 0);
    _rollingWindowStart = 0;
    _rollingTotalKeystrokes = 0;
    _rollingActiveTypingSeconds = 0;
    _rollingElapsedSeconds = 0;
    _keystrokesThisTick = 0;
    _idleMsRemainder = 0;
    _wasCurrentlyIdle = false;
    currentActiveApp = 'Idle';
    isCurrentlyIdle = false;

    StorageService.saveDay(
      date: _currentDay,
      appTotals: {},
      appActiveSeconds: {},
      appTypingSeconds: {},
      appKeystrokes: {},
      totalIdleSeconds: 0,
      hourlyData: hourlyData,
      totalWindowSwitches: 0,
      appFocusBreaks: {},
    );

    notifyListeners();
  }

  String get startHourLabel {
    final startHour = ((DateTime.now().hour - 23) % 24 + 24) % 24;
    if (startHour == 0) return '12am';
    if (startHour == 12) return '12pm';
    return startHour > 12 ? '${startHour - 12}pm' : '${startHour}am';
  }

  String _fetchActiveTarget() {
    try {
      final hwnd = _getForegroundWindow();
      if (hwnd == 0) {
        _currentWindowTitle = '';
        _currentExeName = '';
        return 'Desktop';
      }

      _getWindowThreadProcessId(hwnd, _pidPtr);
      final pid = _pidPtr.value;
      if (pid <= 4) {
        _currentWindowTitle = '';
        _currentExeName = '';
        return 'System';
      }

      String exeName = '';
      final hProcess = _openProcess(0x1000, 0, pid);
      if (hProcess != 0) {
        _sizePtr.value = _bufferSize;
        if (_queryFullProcessImageNameW(hProcess, 0, _strBuffer, _sizePtr) !=
            0) {
          final len = _sizePtr.value;
          if (len > 0 && len <= _bufferSize) {
            final path = _strBuffer.cast<Utf16>().toDartString(length: len);
            exeName = path.split(r'\').last;
          }
        }
        _closeHandle(hProcess);
      }
      _currentExeName = exeName;

      final titleLen = _getWindowTextW(hwnd, _strBuffer, _bufferSize);
      String title = '';
      if (titleLen > 0 && titleLen <= _bufferSize) {
        title = _strBuffer.cast<Utf16>().toDartString(length: titleLen);
      }
      _currentWindowTitle = title;

      final lowerExe = exeName.toLowerCase();
      if (lowerExe.contains('flow_state_tracker')) return 'Focus Tracker';
      if (!_browserProcesses.contains(lowerExe))
        return exeName.isNotEmpty ? exeName : 'Desktop';

      final addressBarValue = _getBrowserAddressBarValue(hwnd);
      final addressHost = _extractWebHost(addressBarValue);
      if (addressHost != null) return addressHost;

      return _resolveDomainName(title, exeName);
    } catch (e) {
      _currentWindowTitle = '';
      _currentExeName = '';
      return 'Desktop';
    }
  }

  String _resolveDomainName(String title, String fallbackExe) {
    if (title.isEmpty) return fallbackExe;

    String cleaned = title
        .replaceAll(
          RegExp(
            r'\s*[-—|]\s*(Google Chrome|Microsoft​? Edge|Mozilla Firefox|Brave|Opera|Vivaldi|Arc).*$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();

    if (cleaned.isEmpty || cleaned.toLowerCase() == 'new tab')
      return fallbackExe;
    final lower = cleaned.toLowerCase();

    const knownSites = {
      'youtube': 'youtube.com',
      'github': 'github.com',
      'reddit': 'reddit.com',
      'stackoverflow': 'stackoverflow.com',
      'stack overflow': 'stackoverflow.com',
      'chatgpt': 'chatgpt.com',
      'openai': 'openai.com',
      'twitter': 'x.com',
      'x.com': 'x.com',
      'twitch': 'twitch.tv',
      'netflix': 'netflix.com',
      'wikipedia': 'wikipedia.org',
      'amazon': 'amazon.com',
      'discord': 'discord.com',
      'spotify': 'spotify.com',
    };

    for (final entry in knownSites.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }

    final domainRegex = RegExp(
      r'(?<![a-zA-Z0-9-])((?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,})(?![a-zA-Z0-9-])',
      caseSensitive: false,
    );

    final match = domainRegex.firstMatch(cleaned);
    if (match != null) {
      return match.group(1)!.toLowerCase();
    }
    return fallbackExe;
  }

  String? _getBrowserAddressBarValue(int windowHandle) {
    final query = _browserAddressBarValue;
    if (query == null) return null;

    final now = DateTime.now();
    if (_cachedBrowserWindowHandle == windowHandle &&
        _lastBrowserAddressCheckTime != null &&
        now.difference(_lastBrowserAddressCheckTime!).inMilliseconds < 2000) {
      return _cachedBrowserAddress;
    }

    _cachedBrowserWindowHandle = windowHandle;
    _lastBrowserAddressCheckTime = now;
    _cachedBrowserAddress = null;
    final buffer = calloc<Uint16>(4096);
    try {
      final length = query(windowHandle, buffer, 4096);
      if (length <= 0 || length >= 4096) return null;
      _cachedBrowserAddress = buffer.cast<Utf16>().toDartString(length: length);
      return _cachedBrowserAddress;
    } catch (_) {
      return null;
    } finally {
      calloc.free(buffer);
    }
  }

  String? _extractWebHost(String? address) {
    if (address == null || address.trim().isEmpty) return null;
    var candidate = address.trim();
    if (!candidate.contains('://')) candidate = 'https://$candidate';

    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    return uri.host.toLowerCase();
  }

  Duration get totalTrackedDuration {
    final int totalSecs =
        totalIdleSeconds + appTotals.values.fold<int>(0, (a, b) => a + b);
    return Duration(seconds: totalSecs);
  }

  static String formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);

    if (h > 0) {
      return '${h}h ${m}m ${s}s';
    } else if (m > 0) {
      return '${m}m ${s}s';
    } else {
      return '${s}s';
    }
  }

  double get idlePercentage {
    final int total =
        totalIdleSeconds + appTotals.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) return 0.0;
    return (totalIdleSeconds / total) * 100;
  }

  @override
  void dispose() {
    _keyPoller?.cancel();
    _ticker?.cancel();
    saveToDisk();

    calloc.free(_lastInputPtr);
    calloc.free(_pidPtr);
    calloc.free(_sizePtr);
    calloc.free(_strBuffer);

    super.dispose();
  }
}
