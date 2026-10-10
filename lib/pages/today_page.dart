import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../widgets.dart';
import '../storage_service.dart';
import '../tracker_service.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  final tracker = TrackerService.instance;
  String? _selectedBreakdownApp;
  bool _isClusteredWpm = false;

  int? _hoveredStackIndex;

  Map<int, HourlyActivity> _yesterdayHourlyData = {};
  DateTime _lastLoadedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadYesterdayData();
    tracker.addListener(_onUpdate);
  }

  @override
  void dispose() {
    tracker.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    final now = DateTime.now();
    if (now.day != _lastLoadedDate.day ||
        now.month != _lastLoadedDate.month ||
        now.year != _lastLoadedDate.year) {
      _loadYesterdayData();
    } else {
      if (mounted) setState(() {});
    }
  }

  void _loadYesterdayData() {
    final now = DateTime.now();
    _lastLoadedDate = now;
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final raw = StorageService.loadDay(yesterday);
    final Map<int, HourlyActivity> parsed = {};

    if (raw != null && raw['hourlyData'] is Map) {
      final rawHourly = raw['hourlyData'] as Map;
      rawHourly.forEach((hStr, val) {
        final h = int.tryParse(hStr.toString());
        if (h != null && val is Map) {
          final appSecs = (val['appSeconds'] as Map? ?? {}).map(
            (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
          );
          final appActive = (val['appActiveSeconds'] as Map? ?? {}).map(
            (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
          );
          final appTyping = (val['appTypingSeconds'] as Map? ?? {}).map(
            (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
          );
          final appKeys = (val['appKeystrokes'] as Map? ?? {}).map(
            (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
          );
          final idle = (val['idleSeconds'] as num?)?.toInt() ?? 0;
          final keys = (val['keystrokes'] as num?)?.toInt() ?? 0;

          parsed[h] = HourlyActivity(
            appSeconds: appSecs,
            appActiveSeconds: appActive,
            appTypingSeconds: appTyping,
            appKeystrokes: appKeys,
            idleSeconds: idle,
            keystrokes: keys,
          );
        }
      });
    }

    setState(() {
      _yesterdayHourlyData = parsed;
    });
  }

  HourlyActivity? _getHourlyActivityForIndex(int index) {
    final now = DateTime.now();
    final targetTime = now.add(Duration(hours: index - 23));
    final h = targetTime.hour;

    if (targetTime.day == now.day) {
      return tracker.hourlyData[h];
    } else {
      return _yesterdayHourlyData[h];
    }
  }

  // --- Rolling 24-Hour Aggregations ---

  Duration get _rolling24hTotalDuration {
    int totalSecs = 0;
    for (int i = 0; i < 24; i++) {
      final activity = _getHourlyActivityForIndex(i);
      if (activity != null) {
        totalSecs += activity.idleSeconds;
        totalSecs += activity.appSeconds.values.fold<int>(0, (a, b) => a + b);
      }
    }
    return Duration(seconds: totalSecs);
  }

  double get _rolling24hIdlePercentage {
    int idleSecs = 0;
    int totalSecs = 0;
    for (int i = 0; i < 24; i++) {
      final activity = _getHourlyActivityForIndex(i);
      if (activity != null) {
        idleSecs += activity.idleSeconds;
        final appTotal = activity.appSeconds.values.fold<int>(
          0,
          (a, b) => a + b,
        );
        totalSecs += activity.idleSeconds + appTotal;
      }
    }
    if (totalSecs == 0) return 0.0;
    return (idleSecs / totalSecs) * 100;
  }

  Map<String, int> get _rolling24hAppTotals {
    final Map<String, int> totals = {};
    for (int i = 0; i < 24; i++) {
      final activity = _getHourlyActivityForIndex(i);
      if (activity != null) {
        activity.appSeconds.forEach((app, secs) {
          if (secs > 0) {
            totals[app] = (totals[app] ?? 0) + secs;
          }
        });
      }
    }
    return totals;
  }

  int get _rolling24hIdleSeconds {
    int idle = 0;
    for (int i = 0; i < 24; i++) {
      final activity = _getHourlyActivityForIndex(i);
      if (activity != null) {
        idle += activity.idleSeconds;
      }
    }
    return idle;
  }

  Color _getAppColor(String name) => AppColors.getAppColor(name);

  Color _getSliceColor(String name) {
    if (name == 'Idle') return AppColors.idleGrey;
    if (name == 'Other') return const Color(0xFF94A3B8);
    return _getAppColor(name);
  }

  List<MapEntry<String, int>> _getConsolidatedHourSlices(
    HourlyActivity? hourActivity,
  ) {
    if (hourActivity == null) return [];

    final Map<String, int> appSecs = {};
    hourActivity.appSeconds.forEach((app, secs) {
      final s = secs;
      if (s > 0) {
        final appName = app.toString();
        appSecs[appName] = (appSecs[appName] ?? 0) + s;
      }
    });

    final sortedApps = appSecs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final Map<String, int> consolidated = {};
    int otherSecs = 0;

    const int microThresholdSecs = 60;
    const int maxIndividualApps = 4;

    final idleSecs = hourActivity.idleSeconds;
    final hasMultipleEntries = (sortedApps.length + (idleSecs > 0 ? 1 : 0)) > 1;

    for (int i = 0; i < sortedApps.length; i++) {
      final entry = sortedApps[i];
      final isMicro = entry.value < microThresholdSecs && hasMultipleEntries;
      final isExcess = i >= maxIndividualApps;

      if (isMicro || isExcess) {
        otherSecs += entry.value;
      } else {
        consolidated[entry.key] = entry.value;
      }
    }

    if (otherSecs > 0) consolidated['Other'] = otherSecs;
    if (idleSecs > 0) consolidated['Idle'] = idleSecs;

    return consolidated.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(18.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _buildHourlyChartCard()),
                const SizedBox(width: 14),
                Expanded(flex: 1, child: _buildProductivityCard()),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(flex: 1, child: _buildDynamicBreakdownList()),
        ],
      ),
    );
  }

  Widget _buildHourlyChartCard() {
    final now = DateTime.now();
    final rollingDuration = _rolling24hTotalDuration;
    final rollingIdlePct = _rolling24hIdlePercentage;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryCyan.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppColors.primaryCyan.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Text(
                      TrackerService.formatDuration(rollingDuration),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.textDark,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Past 24h (${TrackerService.formatDuration(tracker.totalTrackedDuration)} today)',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.idleGrey.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${rollingIdlePct.toStringAsFixed(0)}% Idle',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Main Stacked Bar Chart
          Expanded(
            child: BarChart(
              BarChartData(
                barTouchData: BarTouchData(
                  enabled: true,
                  touchCallback: (FlTouchEvent event, barTouchResponse) {
                    if (!event.isInterestedForInteractions ||
                        barTouchResponse == null ||
                        barTouchResponse.spot == null) {
                      _hoveredStackIndex = null;
                      return;
                    }
                    _hoveredStackIndex =
                        barTouchResponse.spot!.touchedStackItemIndex;
                  },
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (group) =>
                        AppColors.textDark.withValues(alpha: 0.95),
                    tooltipBorderRadius: BorderRadius.circular(8),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      if (groupIndex < 0 || groupIndex >= 24) return null;
                      final hourActivity = _getHourlyActivityForIndex(
                        groupIndex,
                      );
                      if (hourActivity == null) return null;

                      final slices = _getConsolidatedHourSlices(hourActivity);
                      if (slices.isEmpty) return null;

                      final stackIdx = _hoveredStackIndex ?? 0;
                      final targetEntry =
                          (stackIdx >= 0 && stackIdx < slices.length)
                          ? slices[stackIdx]
                          : slices.first;

                      final name = targetEntry.key;
                      final secs = targetEntry.value;
                      final mins = secs ~/ 60;
                      final remSecs = secs % 60;
                      final timeStr = mins > 0 ? '${mins}m' : '${remSecs}s';

                      final targetTime = now.add(
                        Duration(hours: groupIndex - 23),
                      );
                      final h = targetTime.hour;
                      final hourLabel = h == 0
                          ? '12am'
                          : h == 12
                          ? '12pm'
                          : h > 12
                          ? '${h - 12}pm'
                          : '${h}am';

                      final dayLabel = targetTime.day == now.day
                          ? 'Today'
                          : 'Yesterday';

                      final sliceColor = _getSliceColor(name);
                      final textColor = AppColors.ensureReadableOnDark(
                        sliceColor,
                      );

                      return BarTooltipItem(
                        '$name\n',
                        TextStyle(
                          color:
                              textColor, // Bright, readable tone with 100% hue preservation
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                        children: [
                          TextSpan(
                            text: '$timeStr · $hourLabel ($dayLabel)',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                alignment: BarChartAlignment.spaceEvenly,
                maxY: 60,
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (val, meta) {
                        if (val == 15 || val == 30 || val == 45) {
                          return Text(
                            '${val.toInt()}m',
                            style: const TextStyle(
                              fontSize: 8.5,
                              color: AppColors.textMuted,
                            ),
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      getTitlesWidget: (val, meta) {
                        final idx = val.toInt();
                        if (idx >= 0 && idx < 24) {
                          final targetTime = now.add(Duration(hours: idx - 23));
                          final h = targetTime.hour;
                          final label = h == 0
                              ? '12a'
                              : h == 12
                              ? '12p'
                              : h > 12
                              ? '${h - 12}p'
                              : '${h}a';
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontSize: 8.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  checkToShowHorizontalLine: (val) =>
                      val == 15 || val == 30 || val == 45,
                  getDrawingHorizontalLine: (val) => FlLine(
                    color: AppColors.border.withValues(alpha: 0.6),
                    strokeWidth: 0.8,
                    dashArray: const [4, 4],
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.border.withValues(alpha: 0.8),
                    ),
                  ),
                ),
                barGroups: List.generate(24, (index) {
                  final hourActivity = _getHourlyActivityForIndex(index);
                  final slices = _getConsolidatedHourSlices(hourActivity);

                  double currentStackHeight = 0;
                  final List<BarChartRodStackItem> stackItems = [];

                  for (final entry in slices) {
                    final mins = entry.value / 60.0;
                    if (mins > 0) {
                      final nextHeight = (currentStackHeight + mins).clamp(
                        0.0,
                        60.0,
                      );
                      if (nextHeight > currentStackHeight) {
                        stackItems.add(
                          BarChartRodStackItem(
                            currentStackHeight,
                            nextHeight,
                            _getSliceColor(entry.key),
                            borderSide: const BorderSide(
                              color: Colors.white,
                              width: 1.0,
                            ),
                          ),
                        );
                        currentStackHeight = nextHeight;
                      }
                    }
                  }

                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: currentStackHeight,
                        width: 10,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2.5),
                        ),
                        rodStackItems: stackItems,
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _buildChartLegend(),
        ],
      ),
    );
  }

  // --- 24-HOUR DYNAMIC BREAKDOWN LIST ---
  Widget _buildDynamicBreakdownList() {
    final List<BreakdownItem> items = [];
    final appTotals = _rolling24hAppTotals;
    final idleSecs = _rolling24hIdleSeconds;

    final allEntries = <MapEntry<String, int>>[
      ...appTotals.entries,
      if (idleSecs > 0) MapEntry('Idle', idleSecs),
    ];

    int maxSecs = 1;
    for (final entry in allEntries) {
      if (entry.value > maxSecs) maxSecs = entry.value;
    }

    allEntries.sort((a, b) => b.value.compareTo(a.value));

    for (final entry in allEntries) {
      final name = entry.key;
      final secs = entry.value;
      final isIdle = name == 'Idle';

      int? appWpm;
      if (!isIdle) {
        int totalKeys = 0;
        int totalTypingSecs = 0;
        int totalAppSecs = 0;
        for (int i = 0; i < 24; i++) {
          final act = _getHourlyActivityForIndex(i);
          if (act != null) {
            totalKeys += act.appKeystrokes[name] ?? 0;
            totalTypingSecs += act.appTypingSeconds[name] ?? 0;
            totalAppSecs += act.appSeconds[name] ?? 0;
          }
        }
        final int denom = _isClusteredWpm ? totalTypingSecs : totalAppSecs;
        if (denom > 0 && totalKeys > 0) {
          appWpm = ((totalKeys * 12) / denom).round().clamp(0, 250);
        }
      }

      items.add(
        BreakdownItem(
          name: name,
          dotColor: isIdle ? AppColors.idleGrey : _getAppColor(name),
          isHollow: isIdle,
          ratio: secs / maxSecs,
          duration: TrackerService.formatDuration(Duration(seconds: secs)),
          wpm: appWpm,
        ),
      );
    }

    if (items.isEmpty) {
      items.add(
        BreakdownItem(
          name: tracker.currentActiveApp,
          dotColor: _getAppColor(tracker.currentActiveApp),
          ratio: 1.0,
          duration: '1s',
          wpm: 0,
        ),
      );
    }

    return AppBreakdownList(items: items);
  }

  // --- PRODUCTIVITY CARD ---
  Widget _buildProductivityCard() {
    final appTotals = _rolling24hAppTotals;
    final trackedApps =
        appTotals.keys.where((k) => k != 'Idle' && k.trim().isNotEmpty).toList()
          ..sort((a, b) {
            final secsA = appTotals[a] ?? 0;
            final secsB = appTotals[b] ?? 0;
            return secsB.compareTo(secsA);
          });

    final dropdownOptions = ['Total', ...trackedApps];
    final activeSelection =
        _selectedBreakdownApp != null &&
            dropdownOptions.contains(_selectedBreakdownApp)
        ? _selectedBreakdownApp!
        : 'Total';

    final bool isTotal = activeSelection == 'Total';

    // 1. 24h WPM calculation
    int totalKeys = 0;
    int totalTypingSecs = 0;
    int totalAppSecs = 0;
    for (int i = 0; i < 24; i++) {
      final act = _getHourlyActivityForIndex(i);
      if (act != null) {
        if (isTotal) {
          totalKeys += act.keystrokes;
          totalTypingSecs += act.appTypingSeconds.values.fold<int>(
            0,
            (a, b) => a + b,
          );
          totalAppSecs += act.appSeconds.values.fold<int>(0, (a, b) => a + b);
        } else {
          totalKeys += act.appKeystrokes[activeSelection] ?? 0;
          totalTypingSecs += act.appTypingSeconds[activeSelection] ?? 0;
          totalAppSecs += act.appSeconds[activeSelection] ?? 0;
        }
      }
    }
    final int denom = _isClusteredWpm ? totalTypingSecs : totalAppSecs;
    final int displayWpm = denom > 0
        ? ((totalKeys * 12) / denom).round().clamp(0, 250)
        : 0;

    // 2. 24h Activity %
    int totalActiveSecs = 0;
    int totalTrackedSecs = 0;
    for (int i = 0; i < 24; i++) {
      final act = _getHourlyActivityForIndex(i);
      if (act != null) {
        if (isTotal) {
          totalActiveSecs += act.appActiveSeconds.values.fold<int>(
            0,
            (a, b) => a + b,
          );
          totalTrackedSecs +=
              act.idleSeconds +
              act.appSeconds.values.fold<int>(0, (a, b) => a + b);
        } else {
          totalActiveSecs += act.appActiveSeconds[activeSelection] ?? 0;
          totalTrackedSecs += act.appSeconds[activeSelection] ?? 0;
        }
      }
    }
    final int activityPct = totalTrackedSecs > 0
        ? ((totalActiveSecs / totalTrackedSecs) * 100).round().clamp(0, 100)
        : 0;

    // 3. 24h Target Usage Duration
    final int targetSecs = isTotal
        ? _rolling24hTotalDuration.inSeconds
        : (appTotals[activeSelection] ?? 0);
    final String displayUsageTime = TrackerService.formatDuration(
      Duration(seconds: targetSecs),
    );

    final wpm24h = _get24HourWpmTrend(activeSelection, _isClusteredWpm);
    final activity24h = _get24HourActivityTrend(activeSelection);
    final usage24h = _get24HourUsageTrend(activeSelection);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.bolt_rounded, size: 14, color: AppColors.primaryCyan),
              SizedBox(width: 4),
              Text(
                'PRODUCTIVITY',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          _buildAppSelector(trackedApps, activeSelection, isTotal, appTotals),
          const SizedBox(height: 10),

          // Metric 1: WPM
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'WPM: ',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                  Text(
                    '$displayWpm',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  InfoTooltip(
                    message: _isClusteredWpm
                        ? 'Clustered WPM: Measures burst typing speed, excluding idle pauses.'
                        : 'Total WPM: Average speed across all time spent in the app.',
                  ),
                ],
              ),
              _buildWpmToggle(),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _miniSparkline(
              wpm24h,
              tintColor: AppColors.primaryCyan,
              valueFormatter: (val) => '${val.toInt()} WPM',
            ),
          ),
          const SizedBox(height: 2),
          _buildTrendTimeFooter(),

          const SizedBox(height: 8),

          // Metric 2: Activity
          Row(
            children: [
              const Text(
                'Activity: ',
                style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
              ),
              Text(
                '$activityPct%',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              const InfoTooltip(
                message:
                    'Active vs. Passive: Ratio of interactive focus (typing/clicking) versus passive display.',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _miniSparkline(
              activity24h,
              customMax: 100.0,
              tintColor: const Color(0xFF10B981),
              valueFormatter: (val) => '${val.toInt()}%',
            ),
          ),
          const SizedBox(height: 2),
          _buildTrendTimeFooter(),

          const SizedBox(height: 8),

          // Metric 3: Time Usage
          Row(
            children: [
              const Text(
                'Time: ',
                style: TextStyle(fontSize: 10.5, color: AppColors.textMuted),
              ),
              Text(
                displayUsageTime,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 4),
              const InfoTooltip(
                message:
                    'Total tracked time in target and hourly usage across 24h.',
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _miniSparkline(
              usage24h,
              customMax: 60.0,
              tintColor: const Color(0xFF6366F1),
              valueFormatter: (val) {
                final totalS = (val * 60).round();
                final mins = totalS ~/ 60;
                final secs = totalS % 60;
                if (mins == 0) return '${secs}s';
                if (secs == 0) return '${mins}m';
                return '${mins}m ${secs}s';
              },
            ),
          ),
          const SizedBox(height: 2),
          _buildTrendTimeFooter(),
        ],
      ),
    );
  }

  Widget _buildTrendTimeFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          tracker.startHourLabel,
          style: const TextStyle(fontSize: 8, color: AppColors.textMuted),
        ),
        const Text(
          'now',
          style: TextStyle(fontSize: 8, color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _buildAppSelector(
    List<String> trackedApps,
    String activeSelection,
    bool isTotal,
    Map<String, int> appTotals,
  ) {
    return PopupMenuButton<String>(
      tooltip: 'Select Target',
      offset: const Offset(0, 30),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      color: AppColors.cardBg,
      constraints: const BoxConstraints(
        minWidth: 190,
        maxWidth: 260,
        maxHeight: 310,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.border.withValues(alpha: 0.9)),
      ),
      onSelected: (val) => setState(() => _selectedBreakdownApp = val),
      itemBuilder: (context) {
        final List<PopupMenuEntry<String>> menuEntries = [];

        final isTotalSelected = activeSelection == 'Total';
        menuEntries.add(
          PopupMenuItem<String>(
            value: 'Total',
            height: 36,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.totalDark,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Total (All Apps)',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isTotalSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isTotalSelected
                          ? AppColors.primaryCyan
                          : AppColors.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    TrackerService.formatDuration(_rolling24hTotalDuration),
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                if (isTotalSelected) ...[
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: AppColors.primaryCyan,
                  ),
                ],
              ],
            ),
          ),
        );

        if (trackedApps.isNotEmpty) {
          menuEntries.add(const PopupMenuDivider(height: 1));

          for (final app in trackedApps) {
            final isSelected = app == activeSelection;
            final appDuration = Duration(seconds: appTotals[app] ?? 0);

            menuEntries.add(
              PopupMenuItem<String>(
                value: app,
                height: 34,
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _getAppColor(app),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        app,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isSelected
                              ? AppColors.primaryCyan
                              : AppColors.textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        TrackerService.formatDuration(appDuration),
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: AppColors.primaryCyan,
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
        }

        return menuEntries;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.025),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
        ),
        child: Row(
          children: [
            Container(
              width: 7.5,
              height: 7.5,
              decoration: BoxDecoration(
                color: isTotal
                    ? AppColors.totalDark
                    : _getAppColor(activeSelection),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                isTotal ? 'Total (All Apps)' : activeSelection,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(
              Icons.unfold_more_rounded,
              size: 15,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  List<double> _get24HourActivityTrend(String targetName) {
    return List.generate(24, (index) {
      final activity = _getHourlyActivityForIndex(index);
      if (activity == null) return 0.0;

      if (targetName == 'Total') {
        final totalHourSecs =
            activity.idleSeconds +
            activity.appSeconds.values.fold<int>(0, (a, b) => a + b);
        if (totalHourSecs == 0) return 0.0;

        final activeSecs = activity.appActiveSeconds.values.fold<int>(
          0,
          (a, b) => a + b,
        );
        return ((activeSecs / totalHourSecs) * 100.0).clamp(0.0, 100.0);
      } else {
        final appSecs = activity.appSeconds[targetName] ?? 0;
        if (appSecs == 0) return 0.0;

        final activeSecs = activity.appActiveSeconds[targetName] ?? 0;
        return ((activeSecs / appSecs) * 100.0).clamp(0.0, 100.0);
      }
    });
  }

  List<double> _get24HourUsageTrend(String targetName) {
    return List.generate(24, (index) {
      final activity = _getHourlyActivityForIndex(index);
      if (activity == null) return 0.0;

      if (targetName == 'Total') {
        final totalSecs = activity.appSeconds.values.fold<int>(
          0,
          (a, b) => a + b,
        );
        return (totalSecs / 60.0).clamp(0.0, 60.0);
      } else {
        final appSecs = activity.appSeconds[targetName] ?? 0;
        return (appSecs / 60.0).clamp(0.0, 60.0);
      }
    });
  }

  List<double> _get24HourWpmTrend(String targetName, bool clustered) {
    return List.generate(24, (index) {
      final activity = _getHourlyActivityForIndex(index);
      if (activity == null) return 0.0;

      if (targetName == 'Total') {
        final totalKeys = activity.keystrokes;
        if (totalKeys <= 0) return 0.0;

        if (clustered) {
          final typingSecs = activity.appTypingSeconds.values.fold<int>(
            0,
            (a, b) => a + b,
          );
          return typingSecs > 0
              ? ((totalKeys * 12.0) / typingSecs).clamp(0.0, 200.0)
              : 0.0;
        } else {
          final activeSecs = activity.appSeconds.values.fold<int>(
            0,
            (a, b) => a + b,
          );
          return activeSecs > 0
              ? ((totalKeys * 12.0) / activeSecs).clamp(0.0, 200.0)
              : 0.0;
        }
      } else {
        final appKeys = activity.appKeystrokes[targetName] ?? 0;
        if (appKeys <= 0) return 0.0;

        if (clustered) {
          final typingSecs = activity.appTypingSeconds[targetName] ?? 0;
          return typingSecs > 0
              ? ((appKeys * 12.0) / typingSecs).clamp(0.0, 200.0)
              : 0.0;
        } else {
          final appSecs = activity.appSeconds[targetName] ?? 0;
          return appSecs > 0
              ? ((appKeys * 12.0) / appSecs).clamp(0.0, 200.0)
              : 0.0;
        }
      }
    });
  }

  Widget _buildWpmToggle() {
    return Container(
      height: 18,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleBtn(
            'Total',
            !_isClusteredWpm,
            () => setState(() => _isClusteredWpm = false),
          ),
          _toggleBtn(
            'Clustered',
            _isClusteredWpm,
            () => setState(() => _isClusteredWpm = true),
          ),
        ],
      ),
    );
  }

  Widget _toggleBtn(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 8.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.textDark : AppColors.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _miniSparkline(
    List<double> points, {
    double? customMax,
    Color tintColor = AppColors.textDark,
    String Function(double value)? valueFormatter,
  }) {
    double maxVal = customMax ?? 40.0;
    if (customMax == null) {
      for (final p in points) {
        if (p > maxVal) maxVal = p;
      }
      maxVal *= 1.25;
    }

    return Container(
      decoration: BoxDecoration(
        color: tintColor.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(4),
      ),
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxVal,
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          titlesData: const FlTitlesData(show: false),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(
            show: true,
            border: Border(
              bottom: BorderSide(
                color: AppColors.border.withValues(alpha: 0.4),
                width: 0.8,
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            enabled: true,
            handleBuiltInTouches: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (spot) =>
                  AppColors.textDark.withValues(alpha: 0.95),
              tooltipBorderRadius: BorderRadius.circular(6),
              fitInsideHorizontally: true,
              fitInsideVertically: false,
              tooltipPadding: const EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 4,
              ),
              tooltipMargin: 6,
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final idx = spot.x.toInt();
                  final targetTime = DateTime.now().add(
                    Duration(hours: idx - 23),
                  );
                  final h = targetTime.hour;
                  final hourLabel = h == 0
                      ? '12am'
                      : h == 12
                      ? '12pm'
                      : h > 12
                      ? '${h - 12}pm'
                      : '${h}am';
                  final timeStr = idx == 23 ? 'Now · $hourLabel' : hourLabel;

                  final formattedVal = valueFormatter != null
                      ? valueFormatter(spot.y)
                      : spot.y.toStringAsFixed(0);

                  return LineTooltipItem(
                    '$formattedVal\n',
                    TextStyle(
                      color: tintColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                    children: [
                      TextSpan(
                        text: timeStr,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  );
                }).toList();
              },
            ),
            getTouchedSpotIndicator:
                (LineChartBarData barData, List<int> spotIndexes) {
                  return spotIndexes.map((spotIndex) {
                    return TouchedSpotIndicatorData(
                      FlLine(
                        color: tintColor.withValues(alpha: 0.4),
                        strokeWidth: 1,
                        dashArray: const [2, 2],
                      ),
                      FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) =>
                            FlDotCirclePainter(
                              radius: 2.5,
                              color: tintColor,
                              strokeWidth: 1.5,
                              strokeColor: Colors.white,
                            ),
                      ),
                    );
                  }).toList();
                },
          ),
          lineBarsData: [
            LineChartBarData(
              spots: points
                  .asMap()
                  .entries
                  .map((e) => FlSpot(e.key.toDouble(), e.value))
                  .toList(),
              isCurved: true,
              curveSmoothness: 0.25,
              preventCurveOverShooting: true,
              color: tintColor,
              barWidth: 1.5,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    tintColor.withValues(alpha: 0.16),
                    tintColor.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartLegend() {
    return Row(
      children: [
        _Legend(
          color: _getAppColor(tracker.currentActiveApp),
          label: tracker.currentActiveApp,
        ),
        const SizedBox(width: 14),
        const _Legend(color: Color(0xFF94A3B8), label: 'Other'),
        const SizedBox(width: 14),
        const _Legend(color: AppColors.idleGrey, label: 'Idle'),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
