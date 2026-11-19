import 'package:flutter/material.dart';

/// Colours sampled from the reference citizen-safety app UI
/// (dark gradient header, maroon selected tab, grey 3D tiles, green
/// bordered info cards).
class AppColors {
  static const Color maroon = Color(0xFF7A1B2E);
  static const Color maroonDark = Color(0xFF4A0F1C);
  static const Color emergencyRed = Color(0xFFD32F2F);
  static const Color safeGreen = Color(0xFF2E7D32);
  static const Color whatsappGreen = Color(0xFF25D366);
  static const Color surfaceGrey = Color(0xFFF2F1F1);
  static const Color barGrey = Color(0xFF3A3A3A);

  // --- reference-UI palette ---
  static const Color tabMaroon = Color(0xFF7D2C45); // selected tab / buttons
  static const Color headingMaroon = Color(0xFF7A1F38); // big headings
  static const Color tileText = Color(0xFFA0103F); // text on grey tiles
  static const Color cardGreen = Color(0xFF4CAF50); // green bordered cards
  static const Color settingsBg = Color(0xFFEFEFF4); // settings / forms bg
  static const Color tickerGrey = Color(0xFF4B4B4B);
  static const Color tickerRed = Color(0xFFE31E24);
  static const Color linkBlue = Color(0xFF1F5FA8);
}

class AppTheme {
  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.surfaceGrey,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.maroon,
        primary: AppColors.maroon,
        secondary: AppColors.emergencyRed,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.barGrey,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 2,
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.black87,
        indicator: BoxDecoration(color: AppColors.tabMaroon),
        labelStyle: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
      fontFamily: 'Roboto',
    );
  }
}
