import 'dart:io';
import 'package:flutter/material.dart';
import '../services/services.dart';

class BackgroundManager {
  static const builtInBackgrounds = [
    'assets/bg.jpg',
    'assets/bg2.jpg',
    'assets/bg3.jpg',
  ];

  static final ValueNotifier<ImageProvider> current = ValueNotifier(
    const AssetImage('assets/bg.jpg'),
  );

  static String _currentValue = 'assets/bg.jpg';
  static String get currentValue => _currentValue;

  static Future<void> init() async {
    final pref = await Services.storage.getBackground();
    _currentValue = pref ?? 'assets/bg.jpg';
    current.value = _resolveImage(_currentValue);
  }

  static ImageProvider _resolveImage(String value) {
    if (value.startsWith('assets/')) return AssetImage(value);
    final file = File(value);
    if (file.existsSync()) return FileImage(file);
    return const AssetImage('assets/bg.jpg');
  }

  static Future<void> setBackground(String value) async {
    _currentValue = value;
    current.value = _resolveImage(value);
    await Services.storage.setBackground(value);
  }
}

class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ImageProvider>(
      valueListenable: BackgroundManager.current,
      builder: (context, image, _) {
        return DecoratedBox(
          decoration: BoxDecoration(
            image: DecorationImage(
              image: image,
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          child: child,
        );
      },
    );
  }
}
