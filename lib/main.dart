import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/app_state.dart';
import 'theme/app_theme.dart';
import 'screens/setup_screen.dart';
import 'screens/dashboard_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState()..init(),
      child: const ManageMeApp(),
    ),
  );
}

class ManageMeApp extends StatelessWidget {
  const ManageMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ManageMe',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const _SplashGate(),
      routes: {
        '/setup': (_) => const SetupScreen(),
        '/dashboard': (_) => const DashboardScreen(),
      },
    );
  }
}

class _SplashGate extends StatefulWidget {
  const _SplashGate();

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Give AppState time to load tokens
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.accent, Color(0xFF5856D6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(color: AppColors.accent.withAlpha(40), blurRadius: 24, offset: const Offset(0, 8))],
                ),
                alignment: Alignment.center,
                child: const Text('M', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
              const SizedBox(height: 20),
              const Text('ManageMe', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.text0, letterSpacing: -0.5)),
              const SizedBox(height: 24),
              const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accent)),
            ],
          ),
        ),
      );
    }

    final state = context.watch<AppState>();
    if (state.connections.hasAny) {
      return const DashboardScreen();
    }
    return const SetupScreen();
  }
}
