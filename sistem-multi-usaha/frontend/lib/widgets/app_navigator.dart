import 'package:flutter/material.dart';

/// Helper navigasi khusus untuk halaman mandiri/fullscreen (seperti POS Kasir, Login, Notifikasi)
/// Memberikan animasi halus (fade + subtle scale) yang elegan tanpa membuat layar berkedip.
class AppNavigator {
  static void pushFullscreen(BuildContext context, Widget targetScreen) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => targetScreen,
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curve,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1.0).animate(curve),
              child: child,
            ),
          );
        },
      ),
    );
  }

  static void pushReplacementFullscreen(BuildContext context, Widget targetScreen) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => targetScreen,
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curve,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.96, end: 1.0).animate(curve),
              child: child,
            ),
          );
        },
      ),
    );
  }

  /// Navigasi kembali ke Dashboard utama (tanpa efek kedip)
  static void backToDashboard(BuildContext context, Widget dashboardScreen) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => dashboardScreen,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 150),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      ),
    );
  }
}
