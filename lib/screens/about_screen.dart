import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

/// The studio's marks and the 1983 souvenir page of Mr. M. Subramani Achary, Puthur.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: surfaceWarm,
        appBar: const BrandAppBar(title: 'About', back: true),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(child: Image.asset('assets/brand/logo.png', height: 200, semanticLabel: 'Vriksha Studio')),
            const SizedBox(height: 24),
            const Text('Souvenir, 1983', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            // pinch to read the small print
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: InteractiveViewer(
                maxScale: 5,
                child: Image.asset(
                  'assets/brand/souvenir-1983.png',
                  semanticLabel: 'Souvenir page: With best compliments from Mr. M. Subramani Achary, Puthur',
                ),
              ),
            ),
          ],
        ),
      );
}
