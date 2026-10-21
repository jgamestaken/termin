import 'package:flutter/material.dart';

void main() {
  runApp(const TerminApp());
}

class TerminApp extends StatelessWidget {
  const TerminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Termin',
      theme: ThemeData(colorSchemeSeed: Colors.teal),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: const Scaffold(body: Center(child: Text('Termin'))),
    );
  }
}
