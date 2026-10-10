import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../widgets.dart';
import '../storage_service.dart';
import '../tracker_service.dart';

class WeekPage extends StatefulWidget {
  const WeekPage({super.key});

  @override
  State<WeekPage> createState() => _WeekPageState();
}

class _WeekPageState extends State<WeekPage> {
  String _selectedTarget = 'Total';
  int? _hoveredBarStackIndex;
  bool _isClusteredWpm = true;

  List<_DayData> _pastDays = [];
  DateTime _lastLoadedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadHistoricalDays();
    TrackerService.instance.addListener(_onTrackerUpdate);
  }

  @override
  void dispose() {
    TrackerService.instance.removeListener(_onTrackerUpdate);
    super.dispose();
  }

  void _onTrackerUpdate() {
    final now = DateTime.now();
    if (now.day != _lastLoadedDate.day ||
        now.month != _lastLoadedDate.month ||
        now.year != _lastLoadedDate.year) {
      _loadHistoricalDays();
    } else {
      if (mounted) setState(() {});
    }
  }

  void _loadHistoricalDays() {
    final now = DateTime.now();
    _lastLoadedDate = now;
    final List<_DayData> history = [];

    for (int i = 6; i >= 1; i--) {
      final date = DateTime(now.year, now.month, now.day - i);
      final rawData = StorageService.loadDay(date);
      history.add(_parseDayData(date, rawData));
    }

    setState(() {
      _pastDays = history;
    });
  }

  static String _shortDayName(int weekday) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[(weekday - 1) % 7];
  }

  static String _fullDayName(int weekday) {
    const names = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday'
    ];
    return names[(weekday - 1) % 7];
  }

  _DayData _parseDayData(DateTime date, Map<String, dynamic>? data) {
    final short = _shortDayName(date.weekday);
    final full = _fullDayName(date.weekday);

    if (data == null) {
      return _DayData(
        shortDay: short,
        fullDay: full,
        appHours: {},
        appActiveSeconds: {},
        appTypingSeconds: {},
        appKeystrokes: {},
        idleHours: 0.0,
        activityPct: 0,
        wpm: 0,
        totalWindowSwitches: 0,
        appFocusBreaks: {},
      );
    }

    final idleSecs = (data['totalIdleSeconds'] as num?)?.toInt() ?? 0;
    final rawTotals = (data['appTotals'] as Map?) ?? {};
    final rawActive = (data['appActiveSeconds'] as Map?) ?? {};
    final rawTyping = (data['appTypingSeconds'] as Map?) ?? {};
    final rawKeys = (data['appKeystrokes'] as Map?) ?? {};

    final Map<String, double> appHours = {};
    final Map<String, int> appActive = {};
    final Map<String, int> appTyping = {};
    final Map<String, int> appKeys = {};

    rawTotals.forEach((k, v) {
      final secs = (v as num?)?.toInt() ?? 0;
      if (secs > 0) appHours[k.toString()] = secs / 3600.0;
    });

    rawActive.forEach((k, v) => appActive[k.toString()] = (v as num?)?.toInt() ?? 0);
    rawTyping.forEach((k, v) => appTyping[k.toString()] = (v as num?)?.toInt() ?? 0);
    rawKeys.forEach((k, v) => appKeys[k.toString()] = (v as num?)?.toInt() ?? 0);

    final totalAppSecs = rawTotals.values.fold<int>(0, (a, b) => a + ((b as num?)?.toInt() ?? 0));
    final totalTracked = totalAppSecs + idleSecs;
    final totalActiveSecs = appActive.values.fold<int>(0, (a, b) => a + b);
    final actPct = totalTracked > 0 ? ((totalActiveSecs / totalTracked) * 100).round().clamp(0, 100) : 0;

    final totalTypingSecs = appTyping.values.fold<int>(0, (a, b) => a + b);
    final totalKeystrokes = appKeys.values.fold<int>(0, (a, b) => a + b);
    final dayWpm = totalTypingSecs > 0 ? ((totalKeystrokes * 12) / totalTypingSecs).round().clamp(0, 250) : 0;

    final int loadedSwitches = (data['totalWindowSwitches'] as num?)?.toInt() ?? 0;
    final Map<String, int> loadedBreaks = {};
    if (data['appFocusBreaks'] is Map) {
      (data['appFocusBreaks'] as Map).forEach((k, v) {
        loadedBreaks[k.toString()] = (v as num?)?.toInt() ?? 0;
      });
    }

    return _DayData(
      shortDay: short,
      fullDay: full,
      appHours: appHours,
      appActiveSeconds: appActive,
      appTypingSeconds: appTyping,
      appKeystrokes: appKeys,
      idleHours: idleSecs / 3600.0,
      activityPct: actPct,
      wpm: dayWpm,
      totalWindowSwitches: loadedSwitches,
      appFocusBreaks: loadedBreaks,
    );
  }

  _DayData _buildTodayData() {
    final tracker = TrackerService.instance;
    final now = DateTime.now();

    final Map<String, double> appHours = {};
    tracker.appTotals.forEach((k, secs) {
      if (secs > 0) appHours[k] = secs / 3600.0;
    });

    return _DayData(
      shortDay: _shortDayName(now.weekday),
      fullDay: _fullDayName(now.weekday),
      appHours: appHours,
      appActiveSeconds: Map<String, int>.from(tracker.appActiveSeconds),
      appTypingSeconds: Map<String, int>.from(tracker.appTypingSeconds),
      appKeystrokes: Map<String, int>.from(tracker.appKeystrokes),
      idleHours: tracker.totalIdleSeconds / 3600.0,
      activityPct: tracker.overallActivityPercentage,
      wpm: tracker.dailyClusteredWpm,
      totalWindowSwitches: tracker.totalWindowSwitches,
      appFocusBreaks: Map<String, int>.from(tracker.appFocusBreaks),
    );
  }

  List<_DayData> get _weekDays => [..._pastDays, _buildTodayData()];

  Color _getAppColor(String name) => AppColors.getAppColor(name);

  Color _getSliceColor(String name) {
    if (name == 'Idle') return AppColors.idleGrey;
    if (name == 'Other') return const Color(0xFF94A3B8);
    return _getAppColor(name);
  }

  String _formatHours(double hours) {
    final totalMins = (hours * 60).round();
    final h = totalMins ~/ 60;
    final m = totalMins % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  List<MapEntry<String, double>> _getConsolidatedDaySlices(_DayData day, String target) {
    if (target != 'Total') {
      final hours = day.appHours[target] ?? 0.0;
      return hours > 0 ? [MapEntry(target, hours)] : [];
    }

    final sortedApps = day.appHours.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final Map<String, double> consolidated = {};
    double otherHours = 0.0;

    const double microThresholdHours = 0.4;
    const int maxIndividualApps = 3;

    for (int i = 0; i < sortedApps.length; i++) {
      final entry = sortedApps[i];
      if (entry.value < microThresholdHours || i >= maxIndividualApps) {
        otherHours += entry.value;
      } else {
        consolidated[entry.key] = entry.value;
      }
    }

    if (otherHours > 0) consolidated['Other'] = otherHours;
    if (day.idleHours > 0) consolidated['Idle'] = day.idleHours;

    return consolidated.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
  }

  @override
  Widget build(BuildContext context) {
    final days = _weekDays;
    final allApps = <String>{};
    for (final day in days) {
      allApps.addAll(day.appHours.keys);
    }

    final trackedApps = allApps.toList()
      ..sort((a, b) {
        final hoursA = days.fold<double>(0.0, (sum, d) => sum + (d.appHours[a] ?? 0.0));
        final hoursB = days.fold<double>(0.0, (sum, d) => sum + (d.appHours[b] ?? 0.0));
        return hoursB.compareTo(hoursA);
      });

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
                Expanded(flex: 3, child: _buildWeeklyStackedBarChart(days, trackedApps)),
                const SizedBox(width: 14),
                Expanded(flex: 2, child: _buildWeeklyMetricsPanel(days, trackedApps)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            flex: 1,
            child: _buildDynamicBreakdownList(days),
          ),
        ],
      ),
    );
  }

  // --- 1. WEEKLY STACKED BAR CHART ---
  Widget _buildWeeklyStackedBarChart(List<_DayData> days, List<String> trackedApps) {
    final isTotal = _selectedTarget == 'Total';

    final totalHours = days.fold<double>(0.0, (sum, day) {
      return sum + (isTotal ? day.totalHours : (day.appHours[_selectedTarget] ?? 0.0));
    });

    final totalIdleHours = isTotal
        ? days.fold<double>(0.0, (sum, day) => sum + day.idleHours)
        : 0.0;

    final idlePct = totalHours > 0 ? ((totalIdleHours / totalHours) * 100).round() : 0;

    double maxDayHeight = 0.0;
    for (final day in days) {
      final h = isTotal ? day.totalHours : (day.appHours[_selectedTarget] ?? 0.0);
      if (h > maxDayHeight) maxDayHeight = h;
    }
    final maxY = ((maxDayHeight * 1.25) / 4).ceil() * 4.0;
    final chartMaxY = maxY < 6 ? 6.0 : maxY;

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primaryCyan.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.primaryCyan.withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      _formatHours(totalHours),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.textDark,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Past 7 Days',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textMuted),
                  ),
                ],
              ),
              if (isTotal)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.idleGrey.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$idlePct% Idle',
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
          Expanded(
            child: BarChart(
              BarChartData(
                barTouchData: BarTouchData(
                  enabled: true,
                  touchCallback: (FlTouchEvent event, barTouchResponse) {
                    if (!event.isInterestedForInteractions ||
                        barTouchResponse == null ||
                        barTouchResponse.spot == null) {
                      _hoveredBarStackIndex = null;
                      return;
                    }
                    _hoveredBarStackIndex = barTouchResponse.spot!.touchedStackItemIndex;
                  },
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (group) => AppColors.textDark.withValues(alpha: 0.95),
                    tooltipBorderRadius: BorderRadius.circular(8),
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      if (groupIndex < 0 || groupIndex >= days.length) return null;
                      final day = days[groupIndex];
                      final slices = _getConsolidatedDaySlices(day, _selectedTarget);
                      if (slices.isEmpty) return null;

                      final stackIdx = _hoveredBarStackIndex ?? 0;
                      final targetEntry = (stackIdx >= 0 && stackIdx < slices.length)
                          ? slices[stackIdx]
                          : slices.first;

                      final name = targetEntry.key;
                      final timeStr = _formatHours(targetEntry.value);

final sliceColor = _getSliceColor(name);
final textColor = AppColors.ensureReadableOnDark(sliceColor);

return BarTooltipItem(
  '$name\n',
  TextStyle(
    color: textColor,
    fontWeight: FontWeight.bold,
    fontSize: 11,
  ),
                        children: [
                          TextSpan(
                            text: '$timeStr · ${day.fullDay}',
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
                alignment: BarChartAlignment.spaceAround,
                maxY: chartMaxY,
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      interval: (chartMaxY / 4).clamp(1.0, 10.0),
                      getTitlesWidget: (val, meta) {
                        if (val == 0) return const SizedBox();
                        return Text(
                          '${val.toInt()}h',
                          style: const TextStyle(fontSize: 8.5, color: AppColors.textMuted),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      getTitlesWidget: (val, meta) {
                        final idx = val.toInt();
                        if (idx >= 0 && idx < days.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              days[idx].shortDay,
                              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: AppColors.textMuted),
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
                  horizontalInterval: (chartMaxY / 4).clamp(1.0, 10.0),
                  getDrawingHorizontalLine: (val) => FlLine(
                    color: AppColors.border.withValues(alpha: 0.6),
                    strokeWidth: 0.8,
                    dashArray: const [4, 4],
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.8)),
                  ),
                ),
                barGroups: List.generate(days.length, (index) {
                  final day = days[index];
                  final slices = _getConsolidatedDaySlices(day, _selectedTarget);

                  double currentStackHeight = 0;
                  final List<BarChartRodStackItem> stackItems = [];

                  for (final entry in slices) {
                    final nextHeight = currentStackHeight + entry.value;
                    stackItems.add(
                      BarChartRodStackItem(
                        currentStackHeight,
                        nextHeight,
                        _getSliceColor(entry.key),
                      ),
                    );
                    currentStackHeight = nextHeight;
                  }

                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: currentStackHeight,
                        width: 18,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        rodStackItems: stackItems,
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _buildChartLegend(trackedApps),
        ],
      ),
    );
  }

  // --- 2. WEEKLY METRICS PANEL ---
  Widget _buildWeeklyMetricsPanel(List<_DayData> days, List<String> trackedApps) {
    final isTotal = _selectedTarget == 'Total';

    final totalHours = days.fold<double>(0.0, (sum, day) {
      return sum + (isTotal ? day.totalHours : (day.appHours[_selectedTarget] ?? 0.0));
    });
    final dailyAvgHours = days.isNotEmpty ? totalHours / days.length : 0.0;

    final avgIdlePct = isTotal && totalHours > 0
        ? ((days.fold<double>(0.0, (sum, d) => sum + d.idleHours) / totalHours) * 100).round()
        : 0;

    // --- ACTIVITY TREND & WEIGHTED AVERAGE ---
    final List<double> activityTrend = [];
    for (final d in days) {
      if (isTotal) {
        activityTrend.add(d.activityPct.toDouble());
      } else {
        final appHours = d.appHours[_selectedTarget] ?? 0.0;
        final appSecs = (appHours * 3600).round();
        final appActiveSecs = d.appActiveSeconds[_selectedTarget] ?? 0;
        final act = appSecs > 0 ? ((appActiveSecs / appSecs) * 100).clamp(0, 100).toDouble() : 0.0;
        activityTrend.add(act);
      }
    }

    final int totalActiveSecs;
    final int totalTrackedSecs;
    if (isTotal) {
      totalActiveSecs = days.fold<int>(
        0,
        (sum, d) => sum + d.appActiveSeconds.values.fold<int>(0, (a, b) => a + b),
      );
      totalTrackedSecs = (days.fold<double>(0.0, (sum, d) => sum + d.totalHours) * 3600).round();
    } else {
      totalActiveSecs = days.fold<int>(
        0,
        (sum, d) => sum + (d.appActiveSeconds[_selectedTarget] ?? 0),
      );
      totalTrackedSecs = ((days.fold<double>(0.0, (sum, d) => sum + (d.appHours[_selectedTarget] ?? 0.0))) * 3600).round();
    }

    final avgActivityPct = totalTrackedSecs > 0
        ? ((totalActiveSecs / totalTrackedSecs) * 100).round().clamp(0, 100)
        : 0;

    // --- WPM TREND & WEIGHTED AVERAGE ---
    final List<double> wpmTrend = [];
    for (final d in days) {
      if (isTotal) {
        final typingSecs = d.appTypingSeconds.values.fold<int>(0, (a, b) => a + b);
        final appSecs = (d.appHours.values.fold<double>(0.0, (a, b) => a + b) * 3600).round();
        final keys = d.appKeystrokes.values.fold<int>(0, (a, b) => a + b);

        final int denom = _isClusteredWpm ? typingSecs : appSecs;
        final dayWpm = denom > 0 ? ((keys * 12) / denom).clamp(0, 250).toDouble() : 0.0;
        wpmTrend.add(dayWpm);
      } else {
        final typingSecs = d.appTypingSeconds[_selectedTarget] ?? 0;
        final appSecs = ((d.appHours[_selectedTarget] ?? 0.0) * 3600).round();
        final keys = d.appKeystrokes[_selectedTarget] ?? 0;

        final int denom = _isClusteredWpm ? typingSecs : appSecs;
        final appWpm = denom > 0 ? ((keys * 12) / denom).clamp(0, 250).toDouble() : 0.0;
        wpmTrend.add(appWpm);
      }
    }

    final int totalKeys;
    final int totalWpmDenominator;
    if (isTotal) {
      totalKeys = days.fold<int>(
        0,
        (sum, d) => sum + d.appKeystrokes.values.fold<int>(0, (a, b) => a + b),
      );
      final totalTypingSecs = days.fold<int>(
        0,
        (sum, d) => sum + d.appTypingSeconds.values.fold<int>(0, (a, b) => a + b),
      );
      final totalAppSecs = (days.fold<double>(
        0.0,
        (sum, d) => sum + d.appHours.values.fold<double>(0.0, (a, b) => a + b),
      ) * 3600).round();

      totalWpmDenominator = _isClusteredWpm ? totalTypingSecs : totalAppSecs;
    } else {
      totalKeys = days.fold<int>(
        0,
        (sum, d) => sum + (d.appKeystrokes[_selectedTarget] ?? 0),
      );
      final totalTypingSecs = days.fold<int>(
        0,
        (sum, d) => sum + (d.appTypingSeconds[_selectedTarget] ?? 0),
      );
      final totalAppSecs = ((days.fold<double>(
        0.0,
        (sum, d) => sum + (d.appHours[_selectedTarget] ?? 0.0),
      )) * 3600).round();

      totalWpmDenominator = _isClusteredWpm ? totalTypingSecs : totalAppSecs;
    }

    final avgWpm = totalWpmDenominator > 0
        ? ((totalKeys * 12) / totalWpmDenominator).round().clamp(0, 250)
        : 0;

    final topApp = trackedApps.isNotEmpty ? trackedApps[0] : null;
    final secondApp = trackedApps.length > 1 ? trackedApps[1] : null;

    String getAppActivityLabel(String? app) {
      if (app == null) return '0%';
      int active = 0;
      double hours = 0.0;
      for (final d in days) {
        active += d.appActiveSeconds[app] ?? 0;
        hours += d.appHours[app] ?? 0.0;
      }
      final appSecs = (hours * 3600).round();
      if (appSecs == 0) return '0%';
      return '${((active / appSecs) * 100).round().clamp(0, 100)}%';
    }

    String getAppWpmLabel(String? app) {
      if (app == null) return '0 WPM';
      int typingSecs = 0;
      int keys = 0;
      for (final d in days) {
        typingSecs += d.appTypingSeconds[app] ?? 0;
        keys += d.appKeystrokes[app] ?? 0;
      }
      final int denom = _isClusteredWpm ? typingSecs : (totalHours * 3600).round();
      if (denom == 0) return '0 WPM';
      return '${((keys * 12) / denom).round().clamp(0, 250)} WPM';
    }

    // --- CONTEXT SWITCHES & FOCUS BREAKS ---
    final List<double> contextSwitchesTrend = [];
    final int totalSwitchesOrBreaks;

    if (isTotal) {
      for (final d in days) {
        contextSwitchesTrend.add(d.totalWindowSwitches.toDouble());
      }
      totalSwitchesOrBreaks = days.fold<int>(0, (s, d) => s + d.totalWindowSwitches);
    } else {
      for (final d in days) {
        final breaks = (d.appFocusBreaks[_selectedTarget] ?? 0).toDouble();
        contextSwitchesTrend.add(breaks);
      }
      totalSwitchesOrBreaks = days.fold<int>(
        0,
        (s, d) => s + (d.appFocusBreaks[_selectedTarget] ?? 0),
      );
    }

    final String switchCardTitle = isTotal
        ? 'Context Switches: $totalSwitchesOrBreaks'
        : 'Focus Breaks: $totalSwitchesOrBreaks';

    // --- % OF TIME ---
    final List<double> timePctTrend = [];
    final int displayTimePct;

    final totalTrackedHours = days.fold<double>(0.0, (s, d) => s + d.totalHours);
    final totalIdleHoursAll = days.fold<double>(0.0, (s, d) => s + d.idleHours);

    if (isTotal) {
      for (final d in days) {
        final activeHours = d.totalHours - d.idleHours;
        final pct = d.totalHours > 0
            ? ((activeHours / d.totalHours) * 100).clamp(0, 100).toDouble()
            : 0.0;
        timePctTrend.add(pct);
      }
      displayTimePct = totalTrackedHours > 0
          ? (((totalTrackedHours - totalIdleHoursAll) / totalTrackedHours) * 100).round().clamp(0, 100)
          : 0;
    } else {
      for (final d in days) {
        final appH = d.appHours[_selectedTarget] ?? 0.0;
        final pct = d.totalHours > 0
            ? ((appH / d.totalHours) * 100).clamp(0, 100).toDouble()
            : 0.0;
        timePctTrend.add(pct);
      }
      final totalAppHours = days.fold<double>(0.0, (s, d) => s + (d.appHours[_selectedTarget] ?? 0.0));
      displayTimePct = totalTrackedHours > 0
          ? ((totalAppHours / totalTrackedHours) * 100).round().clamp(0, 100)
          : 0;
    }

    double maxTimePct = 20.0;
    for (final p in timePctTrend) {
      if (p > maxTimePct) maxTimePct = p;
    }
    final double timeTrendMax = maxTimePct >= 80 ? 100.0 : (maxTimePct * 1.25).clamp(10.0, 100.0);

    // --- TOOLTIP DESCRIPTIONS ---
    final String activityTooltip = isTotal
        ? 'Percentage of tracked time spent actively engaging (typing or mouse activity) vs idle pauses.'
        : 'Percentage of time spent actively engaged while this app was in focus.';

    final String wpmTooltip = _isClusteredWpm
        ? 'Clustered WPM: Speed measured strictly during active typing bursts.'
        : 'Total WPM: Keystrokes divided across the total time the window remained open.';

    final String switchesTooltip = isTotal
        ? 'Total number of window transitions across all applications, tracking multitasking cadence.'
        : 'Focus Breaks: How many times you switched away from this app to another window.';

    final String timePctTooltip = isTotal
        ? 'Active screen time percentage compared to idle screen time.'
        : 'The proportion of total computer screen time consumed by this application.';

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
          Row(
            children: const [
              Icon(Icons.insights_rounded, size: 14, color: AppColors.primaryCyan),
              SizedBox(width: 5),
              Text(
                'WEEKLY METRICS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          _buildAppSelector(days, trackedApps, _selectedTarget, isTotal),
          const SizedBox(height: 10),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Daily Average', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                  const SizedBox(height: 2),
                  Text(_formatHours(dailyAvgHours), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ],
              ),
              if (isTotal)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Idle Ratio', style: TextStyle(fontSize: 10, color: AppColors.textMuted)),
                    const SizedBox(height: 2),
                    Text('$avgIdlePct%', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textMuted)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),

          // --- ROW 1: ACTIVITY & WPM ---
          Expanded(
            flex: 6,
            child: Row(
              children: [
                Expanded(
                  child: _metricSparklineCard(
                    title: 'Activity: $avgActivityPct%',
                    tooltipMessage: activityTooltip,
                    lineColor: const Color(0xFF10B981),
                    points: activityTrend,
                    customMax: 100.0,
                    valueFormatter: (v) => '${v.toInt()}%',
                    showStats: true,
                    stat1Label: topApp ?? 'App 1',
                    stat1Value: getAppActivityLabel(topApp),
                    stat1Color: _getAppColor(topApp ?? ''),
                    stat2Label: secondApp ?? 'App 2',
                    stat2Value: getAppActivityLabel(secondApp),
                    stat2Color: _getAppColor(secondApp ?? ''),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _metricSparklineCard(
                    title: 'WPM: $avgWpm avg',
                    tooltipMessage: wpmTooltip,
                    lineColor: AppColors.primaryCyan,
                    points: wpmTrend,
                    valueFormatter: (v) => '${v.toInt()} WPM',
                    showStats: true,
                    stat1Label: topApp ?? 'App 1',
                    stat1Value: getAppWpmLabel(topApp),
                    stat1Color: _getAppColor(topApp ?? ''),
                    stat2Label: secondApp ?? 'App 2',
                    stat2Value: getAppWpmLabel(secondApp),
                    stat2Color: _getAppColor(secondApp ?? ''),
                    headerAction: _buildWpmToggle(),
                  ),
                ),
              ],
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6.0),
            child: Divider(height: 1, color: AppColors.border),
          ),

          // --- ROW 2: CONTEXT SWITCHES & % OF TIME ---
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Expanded(
                  child: _metricSparklineCard(
                    title: switchCardTitle,
                    tooltipMessage: switchesTooltip,
                    lineColor: const Color(0xFFF59E0B),
                    points: contextSwitchesTrend,
                    valueFormatter: (v) => isTotal
                        ? '${v.toInt()} switches'
                        : '${v.toInt()} focus breaks',
                    showStats: false,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _metricSparklineCard(
                    title: '% of Time: $displayTimePct%',
                    tooltipMessage: timePctTooltip,
                    lineColor: const Color(0xFF8B5CF6),
                    points: timePctTrend,
                    customMax: timeTrendMax,
                    valueFormatter: (v) => isTotal
                        ? '${v.toInt()}% active'
                        : '${v.toInt()}% of screen time',
                    showStats: false,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- BOOLEAN WPM SWITCH WIDGET ---
  Widget _buildWpmToggle() {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isClusteredWpm = !_isClusteredWpm;
        });
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: AppColors.primaryCyan.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: AppColors.primaryCyan.withValues(alpha: 0.25),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isClusteredWpm ? 'Clustered' : 'Total',
                style: const TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryCyan,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                height: 14,
                width: 24,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Switch(
                    value: _isClusteredWpm,
                    activeColor: AppColors.primaryCyan,
                    activeTrackColor: AppColors.primaryCyan.withValues(alpha: 0.35),
                    inactiveThumbColor: AppColors.textMuted,
                    inactiveTrackColor: AppColors.border,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (val) {
                      setState(() {
                        _isClusteredWpm = val;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricSparklineCard({
    required String title,
    required String tooltipMessage,
    required Color lineColor,
    required List<double> points,
    double? customMax,
    required String Function(double) valueFormatter,
    bool showStats = true,
    String? stat1Label,
    String? stat1Value,
    Color? stat1Color,
    String? stat2Label,
    String? stat2Value,
    Color? stat2Color,
    Widget? headerAction,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 10.5,
                  color: AppColors.textDark,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            if (headerAction != null) ...[
              headerAction,
              const SizedBox(width: 5),
            ],
            InfoTooltip(message: tooltipMessage),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: _miniSparkline(
            points,
            customMax: customMax,
            tintColor: lineColor,
            valueFormatter: valueFormatter,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text('7d ago', style: TextStyle(fontSize: 8, color: AppColors.textMuted)),
            Text('now', style: TextStyle(fontSize: 8, color: AppColors.textMuted)),
          ],
        ),
        if (showStats && stat1Label != null && stat2Label != null) ...[
          const SizedBox(height: 5),
          _statRow(stat1Label, stat1Value ?? '', stat1Color ?? Colors.grey),
          const SizedBox(height: 2),
          _statRow(stat2Label, stat2Value ?? '', stat2Color ?? Colors.grey),
        ],
      ],
    );
  }

  Widget _statRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            SizedBox(
              width: 65,
              child: Text(
                label,
                style: const TextStyle(fontSize: 9, color: AppColors.textDark),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        Text(value, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
      ],
    );
  }

  // --- 3. DYNAMIC WEEKLY BREAKDOWN LIST ---
  Widget _buildDynamicBreakdownList(List<_DayData> days) {
    final Map<String, double> appTotals = {};
    double totalIdle = 0.0;

    for (final day in days) {
      day.appHours.forEach((app, hours) {
        appTotals[app] = (appTotals[app] ?? 0.0) + hours;
      });
      totalIdle += day.idleHours;
    }

    final allEntries = <MapEntry<String, double>>[
      ...appTotals.entries,
      if (totalIdle > 0) MapEntry('Idle', totalIdle),
    ];

    double maxHours = 0.1;
    for (final entry in allEntries) {
      if (entry.value > maxHours) maxHours = entry.value;
    }
    allEntries.sort((a, b) => b.value.compareTo(a.value));

    final items = allEntries.map((entry) {
      final name = entry.key;
      final hours = entry.value;
      final isIdle = name == 'Idle';

      int? appWpm;
      if (!isIdle) {
        int appKeys = 0;
        int appTypingSecs = 0;
        double appHours = 0.0;
        for (final d in days) {
          appKeys += d.appKeystrokes[name] ?? 0;
          appTypingSecs += d.appTypingSeconds[name] ?? 0;
          appHours += d.appHours[name] ?? 0.0;
        }
        final int denom = _isClusteredWpm ? appTypingSecs : (appHours * 3600).round();
        if (denom > 0 && appKeys > 0) {
          appWpm = ((appKeys * 12) / denom).round().clamp(0, 250);
        }
      }

      return BreakdownItem(
        name: name,
        dotColor: isIdle ? AppColors.idleGrey : _getAppColor(name),
        isHollow: isIdle,
        ratio: (hours / maxHours).clamp(0.0, 1.0),
        duration: _formatHours(hours),
        wpm: appWpm,
      );
    }).toList();

    return AppBreakdownList(items: items);
  }

  // --- HELPER COMPONENTS ---
  Widget _buildAppSelector(List<_DayData> days, List<String> trackedApps, String activeSelection, bool isTotal) {
    final totalWeeklyHours = days.fold<double>(0.0, (sum, d) => sum + d.totalHours);

    return PopupMenuButton<String>(
      tooltip: 'Select Target',
      offset: const Offset(0, 30),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      color: AppColors.cardBg,
      constraints: const BoxConstraints(minWidth: 190, maxWidth: 260, maxHeight: 310),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppColors.border.withValues(alpha: 0.9)),
      ),
      onSelected: (val) => setState(() => _selectedTarget = val),
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
                  decoration: const BoxDecoration(color: AppColors.totalDark, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Total (All Apps)',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isTotalSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isTotalSelected ? AppColors.primaryCyan : AppColors.textDark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _formatHours(totalWeeklyHours),
                    style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                  ),
                ),
                if (isTotalSelected) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.check_rounded, size: 14, color: AppColors.primaryCyan),
                ],
              ],
            ),
          ),
        );

        if (trackedApps.isNotEmpty) {
          menuEntries.add(const PopupMenuDivider(height: 1));

          for (final app in trackedApps) {
            final isSelected = app == activeSelection;
            final appTotal = days.fold<double>(0.0, (sum, d) => sum + (d.appHours[app] ?? 0.0));

            menuEntries.add(
              PopupMenuItem<String>(
                value: app,
                height: 34,
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: _getAppColor(app), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        app,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                          color: isSelected ? AppColors.primaryCyan : AppColors.textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _formatHours(appTotal),
                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                      ),
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.check_rounded, size: 14, color: AppColors.primaryCyan),
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
                color: isTotal ? AppColors.totalDark : _getAppColor(activeSelection),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                isTotal ? 'Total (All Apps)' : activeSelection,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textDark),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.unfold_more_rounded, size: 15, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _miniSparkline(
    List<double> points, {
    double? customMax,
    required Color tintColor,
    required String Function(double) valueFormatter,
  }) {
    double maxVal = customMax ?? 10.0;
    if (customMax == null) {
      for (final p in points) {
        if (p > maxVal) maxVal = p;
      }
      maxVal = (maxVal * 1.25).ceilToDouble();
    }

    final safePoints = points.isEmpty ? [0.0] : points;

    return Container(
      decoration: BoxDecoration(
        color: tintColor.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(4),
      ),
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxVal < 1 ? 1.0 : maxVal,
          minX: 0,
          maxX: (safePoints.length - 1).toDouble().clamp(1.0, 10.0),
          titlesData: const FlTitlesData(show: false),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(
            show: true,
            border: Border(
              bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.4), width: 0.8),
            ),
          ),
          lineTouchData: LineTouchData(
            enabled: true,
            handleBuiltInTouches: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (spot) => AppColors.textDark.withValues(alpha: 0.95),
              tooltipBorderRadius: BorderRadius.circular(6),
              fitInsideHorizontally: true,
              fitInsideVertically: false,
              tooltipPadding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              tooltipMargin: 6,
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final idx = spot.x.toInt();
                  final dayLabel = (idx >= 0 && idx < _weekDays.length)
                      ? _weekDays[idx].shortDay
                      : '';
                  final formattedVal = valueFormatter(spot.y);

                  return LineTooltipItem(
                    '$formattedVal\n',
                    TextStyle(
                      color: tintColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                    children: [
                      TextSpan(
                        text: dayLabel,
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
            getTouchedSpotIndicator: (LineChartBarData barData, List<int> spotIndexes) {
              return spotIndexes.map((spotIndex) {
                return TouchedSpotIndicatorData(
                  FlLine(
                    color: tintColor.withValues(alpha: 0.4),
                    strokeWidth: 1,
                    dashArray: const [2, 2],
                  ),
                  FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
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
              spots: safePoints.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
              isCurved: true,
              curveSmoothness: 0.35,
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

  Widget _buildChartLegend(List<String> trackedApps) {
    final topApps = trackedApps.take(2).toList();
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final app in topApps)
          _Legend(color: _getAppColor(app), label: app),
        const _Legend(color: Color(0xFF94A3B8), label: 'Other'),
        const _Legend(color: AppColors.idleGrey, label: 'Idle'),
      ],
    );
  }
}

class _DayData {
  final String shortDay;
  final String fullDay;
  final Map<String, double> appHours;
  final Map<String, int> appActiveSeconds;
  final Map<String, int> appTypingSeconds;
  final Map<String, int> appKeystrokes;
  final double idleHours;
  final int activityPct;
  final int wpm;
  final int totalWindowSwitches;
  final Map<String, int> appFocusBreaks;

  const _DayData({
    required this.shortDay,
    required this.fullDay,
    required this.appHours,
    required this.appActiveSeconds,
    required this.appTypingSeconds,
    required this.appKeystrokes,
    required this.idleHours,
    required this.activityPct,
    required this.wpm,
    required this.totalWindowSwitches,
    required this.appFocusBreaks,
  });

  double get totalHours => idleHours + appHours.values.fold(0.0, (a, b) => a + b);
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  const _Legend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: AppColors.textMuted),
        ),
      ],
    );
  }
}