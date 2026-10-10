import 'package:flutter/material.dart';
import 'widgets.dart';
import 'tracker_service.dart';
import 'startup_service.dart';
import 'pages/today_page.dart';
import 'pages/week_page.dart';
import 'pages/month_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Automatically register app to launch at Windows boot
  await StartupService.enable();

  runApp(const FocusTrackerApp());
}

class FocusTrackerApp extends StatelessWidget {
  const FocusTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flow State Tracker',
      theme: ThemeData(
        fontFamily: 'Segoe UI',
        scaffoldBackgroundColor: AppColors.background,
        useMaterial3: true,
      ),
      home: const DashboardShell(),
    );
  }
}

class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key});

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell>
    with WidgetsBindingObserver {
  int _currentIndex = 0;

  final List<Widget> _pages = const [TodayPage(), WeekPage(), MonthPage()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    TrackerService.instance.saveToDisk();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Save when minimized or hidden
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      TrackerService.instance.saveToDisk();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            HeaderBar(
              selectedIndex: _currentIndex,
              onTabChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: IndexedStack(index: _currentIndex, children: _pages),
            ),
          ],
        ),
      ),
    );
  }
}
