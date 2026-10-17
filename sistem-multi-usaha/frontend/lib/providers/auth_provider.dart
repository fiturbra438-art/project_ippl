import 'package:flutter/material.dart';

class AuthProvider extends ChangeNotifier {
  bool _isAuthenticated = false;
  String _userEmail = 'owner@bisnis.com';
  String _userName = 'Pemilik Usaha';
  String _userRole = 'owner';

  bool get isAuthenticated => _isAuthenticated;
  String get userEmail => _userEmail;
  String get userName => _userName;
  String get userRole => _userRole;

  Future<bool> login(String email, String password) async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (email.isNotEmpty && password.length >= 6) {
      _isAuthenticated = true;
      _userEmail = email;
      _userName = email.split('@').first.toUpperCase();
      notifyListeners();
      return true;
    }
    return false;
  }

  void logout() {
    _isAuthenticated = false;
    notifyListeners();
  }
}
