import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/cart_provider.dart';

class ReceiptService {
  Future<void> generateAndPrintReceipt({
    required CartProvider cart,
    required String customerPhone,
    required String customerName,
    required String paymentMethod,
  }) async {
    final pdf = pw.Document();
    final dateStr = DateTime.now().toString().substring(0, 16);

    // Récupération du nom de la structure
    final prefs = await SharedPreferences.getInstance();
    final String nomBoutique = prefs.getString('selected_structure_name') ?? "MA BOUTIQUE";

    // Données pour le QR Code
    final String qrData = "CMD-${DateTime.now().millisecondsSinceEpoch}|Client:$customerName|$customerPhone|Total:${cart.totalAmount}";

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start, // Correction de l'erreur
            children: [
              pw.Center(
                child: pw.Column(
                    children: [
                      pw.Text(nomBoutique.toUpperCase(), style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(height: 5),
                      pw.Text("RECU DE VENTE", style: pw.TextStyle(fontSize: 10, decoration: pw.TextDecoration.underline)),
                    ]
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text("Date : $dateStr"),
              pw.Text("Client : ${customerName.toUpperCase()}"),
              pw.Text("Tél : $customerPhone"),
              pw.Text("Paiement : $paymentMethod"),
              pw.Divider(thickness: 1),

              // Liste des articles
              pw.Column(
                children: cart.items.values.map((item) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Expanded(child: pw.Text("${item.name} x${item.quantity}")),
                        pw.Text("${(item.price * item.quantity).toStringAsFixed(0)} F"),
                      ],
                    ),
                  );
                }).toList(),
              ),

              pw.Divider(thickness: 1),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("TOTAL", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                  pw.Text("${cart.totalAmount.toStringAsFixed(0)} FCFA", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                ],
              ),
              pw.SizedBox(height: 15),

              // QR Code
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: qrData,
                      width: 70,
                      height: 70,
                    ),
                    pw.SizedBox(height: 5),
                    pw.Text("Merci de votre fidélité !", style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    // Lancer l'impression
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }
}