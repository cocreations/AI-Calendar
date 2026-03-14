import 'package:flutter/material.dart';
import 'services/services.dart';
import 'screens/setup_screen.dart';
import 'screens/voice_screen.dart';

class AiCalendarApp extends StatelessWidget {
  const AiCalendarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Calendar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AppHome(),
    );
  }
}

class AppHome extends StatefulWidget {
  const AppHome({super.key});

  @override
  State<AppHome> createState() => _AppHomeState();
}

class _AppHomeState extends State<AppHome> {
  bool _loading = true;
  bool _setupComplete = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Services.init();

    // Try silent sign-in
    await Services.calendar.signInSilently();

    _setupComplete = await Services.storage.isSetupComplete() &&
        Services.calendar.isSignedIn;

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return _setupComplete ? const VoiceScreen() : const SetupScreen();
  }
}
