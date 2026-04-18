import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFF90EE90); // Мягкий зеленый
  static const Color backgroundColor = Color(0xFFF5F5DC); // Теплый бежевый
  static const Color accentColor = Color(0xFFFFB6C1); // Мягкий розовый акцент
  static const Color textColor = Color(0xFF333333);
  
  // Telegram-style message bubble colors
  static const Color sentMessageColor = Color(0xFFE2FFC7); // Светло-зеленый для моих сообщений
  static const Color receivedMessageColor = Color(0xFFFFFFFF); // Белый для сообщений собеседника
  static const Color chatBackgroundColor = Color(0xFFE8E8E8); // Светло-серый фон чата
  static const Color timestampColor = Color(0xFF999999); // Серый для времени

  static ThemeData get lightTheme {
    return ThemeData(
      primaryColor: primaryColor,
      scaffoldBackgroundColor: backgroundColor,
      appBarTheme: AppBarTheme(
        backgroundColor: primaryColor,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.nunito(
          color: textColor,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: const IconThemeData(color: textColor),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: textColor,
          minimumSize: const Size(double.infinity, 60), // Массивные кнопки
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.nunito(
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      textTheme: TextTheme(
        bodyLarge: GoogleFonts.nunito(fontSize: 20, color: textColor), // Крупный шрифт
        bodyMedium: GoogleFonts.nunito(fontSize: 18, color: textColor),
        titleLarge: GoogleFonts.nunito(fontSize: 26, fontWeight: FontWeight.bold, color: textColor),
      ),
      cardTheme: CardTheme(
        color: Colors.white,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        labelStyle: GoogleFonts.nunito(fontSize: 18),
      ),
    );
  }
}
