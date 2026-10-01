import 'package:flutter/material.dart';

/// A shared screen-template shape: a header over a body that fills the rest,
/// built from Stacks. Regression case for
/// https://github.com/CarlosMarioM/flutter2figma/issues/1 (the body used to
/// collapse to 0.01 px in Figma).
class StackLayoutScreen extends StatelessWidget {
  const StackLayoutScreen({super.key});

  static const _gap = 16.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                color: const Color(0xFF423F9A),
                padding: const EdgeInsets.all(_gap * 2), // arithmetic folds to 32
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios, size: 32),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: const BoxDecoration(color: Colors.white),
                      child: Column(
                        children: const [
                          Text('Body title'),
                          Text('Body content'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
