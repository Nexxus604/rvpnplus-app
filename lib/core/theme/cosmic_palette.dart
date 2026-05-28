// R-VPN+ "dark_star" cosmic palette — mirrors rocketvpn.net / ru.rvpn.space
// (deep-space purples + violet accent + mint "connected"). Single source of
// truth for the app-wide dark theme; see app_theme.dart.

import 'package:flutter/material.dart';

abstract final class Cosmic {
  // Backgrounds — deep space, darkening top → down.
  static const deepest = Color(0xFF02031C); // scaffold base / page bottom
  static const bg = Color(0xFF0F0B22); // main surface
  static const section = Color(0xFF15122B); // sections, inputs, dropdowns
  static const card = Color(0xFF1C1641); // cards
  static const cardHi = Color(0xFF261E4E); // elevated / hover

  // Brand violet.
  static const violet = Color(0xFF6239EC); // primary CTA
  static const violetBright = Color(0xFF835FFD); // links / highlights / glow
  static const violetDeep = Color(0xFF332170); // pressed / hover
  static const indigoBorder = Color(0xFF32309D);

  // Text.
  static const text = Color(0xFFFFFFFF);
  static const text2 = Color(0xFFA0A0C7); // cool grey-purple secondary
  static const muted = Color(0xFF8C8CAE);

  // Status.
  static const success = Color(0xFF2FE6A7); // connected (mint)
  static const onSuccess = Color(0xFF00261A);
  static const error = Color(0xFFFF1D38);

  // Connection FX — "cosmic blue" when the tunnel is up, plus an electric
  // highlight for the arcs/lightning around the connect button.
  static const connectedBlue = Color(0xFF4AA8FF); // VPN connected glow / glyph
  static const electric = Color(0xFF9FE0FF); // electric arc highlight

  static const fontFamily = 'Inter';

  /// Fixed cosmic dark scheme — ignores Material-You so the brand look is
  /// consistent across devices.
  static ColorScheme get scheme => const ColorScheme.dark(
        primary: violet,
        onPrimary: Colors.white,
        primaryContainer: violetDeep,
        onPrimaryContainer: Colors.white,
        secondary: violetBright,
        onSecondary: Colors.white,
        secondaryContainer: card,
        onSecondaryContainer: text2,
        tertiary: success,
        onTertiary: onSuccess,
        tertiaryContainer: violetDeep,
        onTertiaryContainer: Colors.white,
        surface: bg,
        surfaceTint: violet,
        surfaceContainerLowest: deepest,
        surfaceContainerLow: section,
        surfaceContainer: card,
        surfaceContainerHigh: cardHi,
        surfaceContainerHighest: cardHi,
        onSurfaceVariant: text2,
        outline: indigoBorder,
        outlineVariant: section,
        error: error,
        onError: Colors.white,
        inverseSurface: text,
        onInverseSurface: deepest,
      );
}
