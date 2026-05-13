import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../widgets/section_page_title.dart';

const _kSaleFlowAppBarBlue = Color(0xFF5181da);

/// Full-screen camera barcode scan. Pops with the decoded string, or null if closed.
class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key});

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  bool _handled = false;

  void _finish(String code) {
    if (_handled) return;
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    _handled = true;
    if (!mounted) return;
    Navigator.of(context).pop<String>(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: _kSaleFlowAppBarBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const SectionPageTitle(pageTitle: 'Scan barcode'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            onDetect: (BarcodeCapture capture) {
              for (final b in capture.barcodes) {
                final v = b.rawValue;
                if (v != null && v.trim().isNotEmpty) {
                  _finish(v);
                  return;
                }
              }
            },
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 32,
            child: Text(
              'Point the camera at the barcode on the product',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92),
                fontSize: 16,
                shadows: const [
                  Shadow(blurRadius: 8, color: Colors.black54),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
