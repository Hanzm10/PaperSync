import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/ink_models.dart';
import '../paint/stroke_paint.dart';
import 'save_bytes.dart';

/// Exports one page.
///
/// PNG goes to the phone's Gallery, in a "PaperSync" album. PDF opens the
/// print dialog, where "Save as PDF" puts it in Downloads; where printing is
/// not available, the share sheet opens instead so it can be saved to Files
/// or Drive. On the web both download as files.
Future<void> exportPage(
  BuildContext context,
  NotebookPage page, {
  required bool asPdf,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  void show(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));
  final n = page.pageIndex;
  try {
    if (asPdf) {
      final bytes = await buildPagePdf(page);
      final name = 'page-$n.pdf';
      if (kIsWeb) {
        await saveBytes(bytes, name, 'application/pdf');
        show('Downloaded $name');
        return;
      }
      final printing = await _canPrint();
      if (printing) {
        final done = await Printing.layoutPdf(
          name: name,
          onLayout: (_) async => bytes,
        );
        if (done) show('Exported $name');
        return;
      }
      await Printing.sharePdf(bytes: bytes, filename: name);
      return;
    }
    final bytes = await buildPagePng(page);
    if (kIsWeb) {
      await saveBytes(bytes, 'page-$n.png', 'image/png');
      show('Downloaded page-$n.png');
      return;
    }
    if (!await Gal.hasAccess(toAlbum: true) &&
        !await Gal.requestAccess(toAlbum: true)) {
      show('Allow access to Photos to save pages to the Gallery');
      return;
    }
    await Gal.putImageBytes(bytes, album: 'PaperSync', name: 'page-$n');
    show('Saved page $n to the Gallery (PaperSync album)');
  } on GalException catch (e) {
    show(
      e.type == GalExceptionType.accessDenied
          ? 'Allow access to Photos to save pages to the Gallery'
          : "Couldn't save to the Gallery: ${e.type.message}",
    );
  } catch (_) {
    show("Couldn't export this page");
  }
}

Future<bool> _canPrint() async {
  try {
    return (await Printing.info()).canPrint;
  } catch (_) {
    return false;
  }
}

Future<Uint8List> buildPagePdf(NotebookPage page) async {
  final format = PdfPageFormat(
    pageWidthMm * PdfPageFormat.mm,
    pageHeightMm * PdfPageFormat.mm,
  );
  final document = pw.Document();
  document.addPage(
    pw.Page(
      pageFormat: format,
      margin: pw.EdgeInsets.zero,
      build: (context) {
        return pw.CustomPaint(
          size: PdfPoint(format.width, format.height),
          painter: (canvas, size) => _drawPdf(canvas, size, page.strokes),
        );
      },
    ),
  );
  return document.save();
}

void _drawPdf(PdfGraphics canvas, PdfPoint size, List<Stroke> strokes) {
  for (final stroke in strokes) {
    if (stroke.deletedAt != null) continue;
    final points = stroke.points.where((point) => point.touching).toList();
    if (points.length < 2) continue;
    final color = PdfColor(stroke.color.r, stroke.color.g, stroke.color.b);
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final t = ((a.pressure + b.pressure) / 2 / 16384).clamp(0.0, 1.0);
      final width = (0.35 + t * 0.55) * PdfPageFormat.mm;
      canvas
        ..setStrokeColor(color)
        ..setLineWidth(width)
        ..setLineCap(PdfLineCap.round)
        ..moveTo(
          a.xMm / pageWidthMm * size.x,
          size.y - a.yMm / pageHeightMm * size.y,
        )
        ..lineTo(
          b.xMm / pageWidthMm * size.x,
          size.y - b.yMm / pageHeightMm * size.y,
        )
        ..strokePath();
    }
  }
}

Future<Uint8List> buildPagePng(NotebookPage page) async {
  final image = await rasterizePage(page.strokes);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (data == null) {
    throw StateError('Could not encode the page');
  }
  return data.buffer.asUint8List();
}
