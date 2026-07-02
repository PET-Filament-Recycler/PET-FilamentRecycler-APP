import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/locale_service.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => LocaleService(),
      child: const PetFrApp(),
    ),
  );
}

class PetFrApp extends StatelessWidget {
  const PetFrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PET Filament Recycler',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
