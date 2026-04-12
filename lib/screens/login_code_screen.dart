import 'package:flutter/material.dart';
import 'profile_selection_screen.dart';

class LoginCodeScreen extends StatefulWidget {
  const LoginCodeScreen({super.key});

  @override
  State<LoginCodeScreen> createState() => _LoginCodeScreenState();
}

class _LoginCodeScreenState extends State<LoginCodeScreen> {
  final TextEditingController _codeController = TextEditingController();
  final String _familyCode = 'Бубоглазики'; // Запрограммированный код

  void _checkCode() {
    if (_codeController.text.trim() == _familyCode) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const ProfileSelectionScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Неверный семейный код! Попробуйте еще раз.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.family_restroom,
                size: 100,
                color: Color(0xFF90EE90),
              ),
              const SizedBox(height: 32),
              Text(
                'Добро пожаловать!',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Введите семейный код для входа:',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _codeController,
                style: const TextStyle(fontSize: 22),
                decoration: const InputDecoration(
                  hintText: 'Семейный код',
                  prefixIcon: Icon(Icons.lock, size: 30),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 48),
              ElevatedButton(
                onPressed: _checkCode,
                child: const Text('Войти'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
