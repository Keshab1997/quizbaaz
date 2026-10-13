import 'package:flutter/material.dart';

class AppColors {
  // Deep space canvas.
  static const Color bgDark = Color(0xFF070A18);
  static const Color bgNavy = Color(0xFF0D1328);
  static const Color bgCard = Color(0xFF151E38);
  static const Color bgCardGlass = Color(0x6616203D);
  static const Color surfaceElevated = Color(0xFF1B2646);
  static const Color outline = Color(0x263C4B78);

  // Brand accents.
  static const Color neonCyan = Color(0xFF53E6FF);
  static const Color neonPurple = Color(0xFF9C6BFF);
  static const Color neonPink = Color(0xFFFF5FB7);
  static const Color neonGold = Color(0xFFFFC857);
  static const Color neonGreen = Color(0xFF35D39A);
  static const Color neonRed = Color(0xFFFF6B7A);
  static const Color neonOrange = Color(0xFFFF9B3D);

  // Google branding, used only for the sign-in mark.
  static const Color googleBlue = Color(0xFF4285F4);
  static const Color googleRed = Color(0xFFEA4335);
  static const Color googleYellow = Color(0xFFFBBC05);
  static const Color googleGreen = Color(0xFF34A853);

  // Intentional gradients used throughout the app.
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF7C4DFF), Color(0xFF4E5BFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient violetGradient = LinearGradient(
    colors: [Color(0xFFB16CFF), Color(0xFF6F4DFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cyanGradient = LinearGradient(
    colors: [Color(0xFF63F1FF), Color(0xFF428BFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFFFE08A), Color(0xFFFFB52E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkCardGradient = LinearGradient(
    colors: [Color(0xB31C2A4D), Color(0x66202A49)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient fireGradient = LinearGradient(
    colors: [Color(0xFFFF4D4D), Color(0xFFFF9B3D), Color(0xFFFFE16B)],
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
  );

  static const LinearGradient pageGradient = LinearGradient(
    colors: [Color(0xFF070A18), Color(0xFF0C1024), Color(0xFF0B0D1C)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Text colors.
  static const Color textPrimary = Color(0xFFF7F8FF);
  static const Color textSecondary = Color(0xFFB7C0D9);
  static const Color textMuted = Color(0xFF7783A6);
}
