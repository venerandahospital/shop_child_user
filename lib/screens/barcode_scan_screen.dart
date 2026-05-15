import 'dart:async';

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
  final MobileScannerController _controller = MobileScannerController(
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoStart: true,
  );
  bool _scannerMounted = true;
  bool _exiting = false;
  bool _cameraStopped = false;

  Future<void> _releaseCamera() async {
    if (_cameraStopped) return;
    _cameraStopped = true;
    try {
      await _controller.stop();
    } catch (_) {
      // Camera may already be stopped when leaving the screen.
    }
  }

  /// Unmounts the preview, stops the camera, then pops — avoids restarting the
  /// camera during the route pop animation (which leaves Camera2 polling on some devices).
  Future<void> _exit([String? result]) async {
    if (_exiting) return;
    _exiting = true;
    if (mounted && _scannerMounted) {
      setState(() => _scannerMounted = false);
    }
    await WidgetsBinding.instance.endOfFrame;
    await _releaseCamera();
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  void dispose() {
    _exiting = true;
    if (_scannerMounted) {
      unawaited(_releaseCamera());
    }
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_exit());
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: _kSaleFlowAppBarBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: BackButton(
            onPressed: () => unawaited(_exit()),
          ),
          title: const SectionPageTitle(pageTitle: 'Scan barcode'),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_scannerMounted)
              MobileScanner(
                controller: _controller,
                useAppLifecycleState: false,
                onDetect: (BarcodeCapture capture) {
                  if (_exiting) return;
                  for (final b in capture.barcodes) {
                    final v = b.rawValue;
                    if (v != null && v.trim().isNotEmpty) {
                      unawaited(_exit(v.trim()));
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
      ),
    );
  }
}
