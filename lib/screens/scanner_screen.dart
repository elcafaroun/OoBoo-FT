import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerScreen extends StatefulWidget {
  // Mode : true pour enregistrer un produit (BD), false pour ajouter au panier
  final bool isForRegistration;

  const ScannerScreen({super.key, this.isForRegistration = false});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  bool _isScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isForRegistration ? "Scanner pour Enregistrer" : "Scanner un produit",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, child) {
                return Icon(
                  state.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off,
                  color: state.torchState == TorchState.on ? Colors.orange : Colors.grey,
                );
              },
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios, color: Colors.grey),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) async {
              if (_isScanned) return;

              final List<Barcode> barcodes = capture.barcodes;
              final barcode = barcodes.firstOrNull;

              if (barcode != null && barcode.rawValue != null) {
                setState(() => _isScanned = true);
                final String codeValue = barcode.rawValue!;

                // 1. Arrêter la détection et fermer la caméra proprement
                await _controller.stop();

                debugPrint("🎯 Code détecté : $codeValue");

                // 2. Retourner le résultat après avoir arrêté la caméra
                if (mounted) {
                  Navigator.pop(context, codeValue);
                }
              }
            },
          ),

          // Zone de viseur
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFFF9800), width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),

          // Instructions
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Text(
                "Placez le code QR ou le code-barres dans le viseur",
                style: TextStyle(color: Colors.white, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}