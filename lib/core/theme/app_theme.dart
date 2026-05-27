import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hiddify/core/theme/app_theme_mode.dart';
import 'package:hiddify/core/theme/cosmic_palette.dart';
import 'package:hiddify/core/theme/theme_extensions.dart';

// R-VPN+ runs a single fixed "dark_star" cosmic theme (see cosmic_palette.dart).
// Material-You / system light schemes are intentionally ignored so the brand
// look is identical on every device. app.dart forces ThemeMode.dark; lightTheme
// returns the same cosmic theme as a safety net.
class AppTheme {
  AppTheme(this.mode, this.fontFamily);
  final AppThemeMode mode;
  final String fontFamily;

  ThemeData lightTheme(ColorScheme? lightColorScheme) => _cosmic();

  ThemeData darkTheme(ColorScheme? darkColorScheme) => _cosmic();

  ThemeData _cosmic() {
    final scheme = Cosmic.scheme;
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: Cosmic.fontFamily,
      scaffoldBackgroundColor: Cosmic.deepest,
      canvasColor: Cosmic.bg,
      splashColor: Cosmic.violet.withValues(alpha: .12),
      highlightColor: Cosmic.violet.withValues(alpha: .08),
      dividerColor: Cosmic.section,
      extensions: const <ThemeExtension<dynamic>>{ConnectionButtonTheme.cosmic},
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: Cosmic.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: Cosmic.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.white.withValues(alpha: .06)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: Cosmic.text2,
        textColor: Cosmic.text,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Cosmic.card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Cosmic.section,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Cosmic.cardHi,
        contentTextStyle: const TextStyle(color: Cosmic.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Cosmic.section,
        hintStyle: const TextStyle(color: Cosmic.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: .06)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: .06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Cosmic.violetBright, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Cosmic.violet,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Cosmic.violet,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: Cosmic.violetBright),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Cosmic.violet,
        foregroundColor: Colors.white,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: Cosmic.violetBright),
      chipTheme: ChipThemeData(
        backgroundColor: Cosmic.section,
        side: BorderSide(color: Colors.white.withValues(alpha: .06)),
        labelStyle: const TextStyle(color: Cosmic.text2),
      ),
    );
  }

  CupertinoThemeData cupertinoThemeData(bool sysDark, ColorScheme? lightColorScheme, ColorScheme? darkColorScheme) {
    const def = CupertinoThemeData(brightness: Brightness.dark);
    final materialTheme = _cosmic();
    return MaterialBasedCupertinoThemeData(
      materialTheme: materialTheme.copyWith(
        cupertinoOverrideTheme: def.copyWith(
          textTheme: CupertinoTextThemeData(
            textStyle: def.textTheme.textStyle.copyWith(fontFamily: Cosmic.fontFamily),
            actionTextStyle: def.textTheme.actionTextStyle.copyWith(fontFamily: Cosmic.fontFamily),
            navActionTextStyle: def.textTheme.navActionTextStyle.copyWith(fontFamily: Cosmic.fontFamily),
            navTitleTextStyle: def.textTheme.navTitleTextStyle.copyWith(fontFamily: Cosmic.fontFamily),
            navLargeTitleTextStyle: def.textTheme.navLargeTitleTextStyle.copyWith(fontFamily: Cosmic.fontFamily),
            pickerTextStyle: def.textTheme.pickerTextStyle.copyWith(fontFamily: Cosmic.fontFamily),
            dateTimePickerTextStyle: def.textTheme.dateTimePickerTextStyle.copyWith(fontFamily: Cosmic.fontFamily),
            tabLabelTextStyle: def.textTheme.tabLabelTextStyle.copyWith(fontFamily: Cosmic.fontFamily),
          ),
          barBackgroundColor: Cosmic.section,
          scaffoldBackgroundColor: Cosmic.deepest,
        ),
      ),
    );
  }
}
