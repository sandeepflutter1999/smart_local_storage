import 'package:flutter/material.dart';

import 'pages/advanced_page.dart';
import 'pages/map_page.dart';
import 'pages/typed_page.dart';

/// No init() needed - boxes open themselves the first time you ask.
void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'smart_local_cache demo',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;

  static const _pages = <Widget>[MapPage(), TypedPage(), AdvancedPage()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.data_object), label: '1. Maps'),
          NavigationDestination(icon: Icon(Icons.class_outlined), label: '2. Typed'),
          NavigationDestination(icon: Icon(Icons.speed), label: '3. Advanced'),
        ],
      ),
    );
  }
}
