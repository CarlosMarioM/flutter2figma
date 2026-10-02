import 'package:flutter/material.dart';

import 'screens/shop_home_screen.dart';
import 'theme.dart';

void main() => runApp(const ShowcaseApp());

class ShowcaseApp extends StatelessWidget {
  const ShowcaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Showcase',
      debugShowCheckedModeBanner: false,
      theme: ShowcaseTheme.light,
      darkTheme: ShowcaseTheme.dark,
      home: const ShopHomeScreen(),
    );
  }
}
