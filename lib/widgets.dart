import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

// --- Global App Colors & Dynamic Palette ---
class AppColors {
  static const Color primaryCyan = Color(0xFF29B6F6);
  static const Color background = Color(0xFFF8FAFC);
  static const Color cardBg = Colors.white;
  static const Color border = Color(0xFFE2E8F0);

  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color lightBlue = Color(0xFF60A5FA);
  static const Color idleGrey = Color(0xFFCBD5E1);
  static const Color totalDark = Color(0xFF334155);
  static const Color green = Color(0xFF22C55E);

  static const Color textDark = Color(0xFF1E293B);
  static const Color textMuted = Color(0xFF64748B);

  /// Automatically brightens dark colors so text is crisp and legible on dark tooltip backgrounds
  static Color ensureReadableOnDark(Color color) {
    // If the color's perceived luminance is too low for dark backgrounds,
    // boost its lightness to a bright, readable pastel/vibrant tone
    if (color.computeLuminance() < 0.28) {
      final hsl = HSLColor.fromColor(color);
      return hsl
          .withLightness(0.72)
          .withSaturation((hsl.saturation * 1.05).clamp(0.0, 1.0))
          .toColor();
    }
    return color;
  }

  /// Resolves distinct, high-contrast brand colors or a golden-ratio harmonic color
  static Color getAppColor(String name) {
    if (name == 'Total') return totalDark;
    if (name == 'Idle') return idleGrey;

    final lower = name.toLowerCase().trim();

    // 1. Dedicated High-Contrast Brand Palettes
    // AI & Chat
    if (lower.contains('chatgpt') || lower.contains('openai')) {
      return const Color(0xFF10A37F); // Official OpenAI Teal/Emerald
    }
    if (lower.contains('claude') || lower.contains('anthropic')) {
      return const Color(0xFFD97706); // Claude Amber/Bronze
    }

    // Code & Version Control
    if (lower.contains('github')) {
      return const Color(0xFF24292E); // Official GitHub Dark Charcoal
    }
    if (lower.contains('gitlab')) {
      return const Color(0xFFFC6D26); // GitLab Orange
    }
    if (lower.contains('code') ||
        lower.contains('vscode') ||
        lower.contains('visual studio')) {
      return const Color(0xFF0078D4); // VS Code Cobalt Blue
    }
    if (lower.contains('terminal') ||
        lower.contains('powershell') ||
        lower.contains('cmd.exe')) {
      return const Color(0xFF334155); // Terminal Dark Slate
    }

    // Browsers & Search
    if (lower.contains('chrome')) {
      return const Color(0xFFF59E0B); // Chrome Warm Amber
    }
    if (lower.contains('edge') || lower.contains('msedge')) {
      return const Color(0xFF0284C7); // Edge Sky Blue
    }
    if (lower.contains('firefox')) {
      return const Color(0xFFFF7139); // Firefox Flame Orange
    }
    if (lower.contains('brave')) {
      return const Color(0xFFFB542B); // Brave Deep Orange
    }
    if (lower.contains('google')) {
      return const Color(0xFF059669); // Google Emerald
    }
    if (lower.contains('searchx')) {
      return const Color(0xFF0D9488); // SearchX Teal
    }

    // Social & Communication
    if (lower.contains('discord')) {
      return const Color(0xFF5865F2); // Discord Blurple
    }
    if (lower.contains('slack')) {
      return const Color(0xFF4A154B); // Slack Aubergine
    }
    if (lower.contains('reddit')) {
      return const Color(0xFFEA580C); // Reddit Orange
    }
    if (lower.contains('twitter') ||
        lower == 'x.com' ||
        lower.contains('x.com')) {
      return const Color(0xFF0F172A); // X / Twitter Black
    }
    if (lower.contains('telegram')) {
      return const Color(0xFF229ED9); // Telegram Cyan
    }

    // Video & Media
    if (lower.contains('youtube')) {
      return const Color(0xFFEF4444); // YouTube Red
    }
    if (lower.contains('netflix')) {
      return const Color(0xFFB91C1C); // Netflix Crimson
    }
    if (lower.contains('twitch')) {
      return const Color(0xFF9333EA); // Twitch Purple
    }
    if (lower.contains('spotify')) {
      return const Color(0xFF1DB954); // Spotify Neon Green
    }
    if (lower.contains('vlc')) {
      return const Color(0xFFFF8800); // VLC Orange
    }

    // Gaming
    if (lower.contains('roblox')) {
      return const Color(0xFF0284C7); // Roblox Sky Blue
    }
    if (lower.contains('steam')) {
      return const Color(0xFF1B2838); // Steam Navy
    }
    if (lower.contains('minecraft')) {
      return const Color(0xFF65A30D); // Minecraft Lime
    }

    // Productivity & Tools
    if (lower.contains('figma')) {
      return const Color(0xFFA259FF); // Figma Violet
    }
    if (lower.contains('notion')) {
      return const Color(0xFF374151); // Notion Charcoal
    }
    if (lower.contains('focus tracker')) {
      return const Color(0xFF0284C7); // Tracker Sky
    }
    if (lower.contains('explorer') || lower.contains('desktop')) {
      return const Color(0xFF64748B); // System Slate
    }

    // 2. Golden-Ratio HSL Hue Dispersion for Any Other Application
    // Spreads colors 137.5° apart across the 360° wheel so arbitrary apps never collide
    int hash = 0;
    for (int i = 0; i < name.length; i++) {
      hash = (hash * 31 + name.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    final double hue = ((hash * 137.508) % 360).abs();
    return HSLColor.fromAHSL(1.0, hue, 0.72, 0.48).toColor();
  }
}

// --- App Categorizer (Grouping) ---
class AppCategory {
  static const String gaming = 'Gaming';
  static const String media = 'Media & Streaming';
  static const String dev = 'Development';
  static const String browsing = 'Browsing & Search';
  static const String social = 'Social & Communication';
  static const String system = 'System & Tools';
  static const String other = 'Other';

  static String getCategory(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('roblox') ||
        lower.contains('steam') ||
        lower.contains('game') ||
        lower.contains('minecraft')) {
      return gaming;
    }
    if (lower.contains('youtube') ||
        lower.contains('netflix') ||
        lower.contains('twitch') ||
        lower.contains('spotify') ||
        lower.contains('vlc') ||
        lower.contains('player')) {
      return media;
    }
    if (lower.contains('code') ||
        lower.contains('github') ||
        lower.contains('flutter') ||
        lower.contains('terminal') ||
        lower.contains('studio') ||
        lower.contains('chatgpt')) {
      return dev;
    }
    if (lower.contains('google') ||
        lower.contains('searchx') ||
        lower.contains('chrome') ||
        lower.contains('edge') ||
        lower.contains('firefox') ||
        lower.contains('brave')) {
      return browsing;
    }
    if (lower.contains('reddit') ||
        lower.contains('discord') ||
        lower.contains('twitter') ||
        lower.contains('x.com') ||
        lower.contains('slack')) {
      return social;
    }
    if (lower.contains('explorer') ||
        lower.contains('desktop') ||
        lower.contains('focus tracker') ||
        lower.contains('taskmgr')) {
      return system;
    }
    return other;
  }
}

// --- Top Header Bar ---
class HeaderBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTabChanged;

  const HeaderBar({
    super.key,
    required this.selectedIndex,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/logo.png',
                width: 30,
                height: 30,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 10),
              const Text(
                'Flow State Tracker',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark,
                ),
              ),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 34,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primaryCyan),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTab('Today', 0),
                  _buildTab('Week', 1),
                  _buildTab('Month', 2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isSelected = selectedIndex == index;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onTabChanged(index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          alignment: Alignment.center,
          color: isSelected ? AppColors.primaryCyan : Colors.white,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : AppColors.primaryCyan,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

// --- Breakdown Item Model ---
class BreakdownItem {
  final String name;
  final Color dotColor;
  final bool isHollow;
  final double ratio;
  final String duration;
  final int? wpm;
  final String? badgeText;

  BreakdownItem({
    required this.name,
    required this.dotColor,
    this.isHollow = false,
    double? ratio,
    double? progress,
    required this.duration,
    this.wpm,
    this.badgeText,
  }) : ratio = ratio ?? progress ?? 0.0;
}

// --- Bottom App Breakdown List ---
class AppBreakdownList extends StatelessWidget {
  final List<BreakdownItem> items;

  const AppBreakdownList({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: items.length,
      itemBuilder: (context, index) => _buildItemRow(items[index]),
    );
  }

  Widget _buildItemRow(BreakdownItem item) {
    const double maxLineWidth = 220.0;
    final double lineWidth = (item.ratio * maxLineWidth).clamp(
      12.0,
      maxLineWidth,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: item.isHollow ? Colors.transparent : item.dotColor,
              shape: BoxShape.circle,
              border: Border.all(color: item.dotColor, width: 1.5),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 95,
            child: Text(
              item.name,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.textDark,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: lineWidth,
            height: 2.0,
            decoration: BoxDecoration(
              color: item.dotColor,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            item.duration,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textMuted,
            ),
          ),
          if (item.wpm != null || item.badgeText != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'WPM ',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryBlue,
                    ),
                  ),
                  Container(
                    width: 14,
                    height: 14,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${item.wpm ?? item.badgeText ?? ""}',
                      style: const TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// --- Hover Tooltip (?) Icon ---
class InfoTooltip extends StatelessWidget {
  final String message;

  const InfoTooltip({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      waitDuration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.textDark,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      textStyle: const TextStyle(
        fontSize: 11,
        color: Colors.white,
        height: 1.3,
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.help,
        child: Container(
          width: 13,
          height: 13,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.textMuted.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
          child: const Text(
            '?',
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.bold,
              color: AppColors.textMuted,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}
