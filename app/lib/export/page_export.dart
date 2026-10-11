import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/ink_models.dart';
import '../paint/stroke_paint.dart';
import 'save_bytes.dart';

Future<void> exportPage(
  BuildContext context,
  NotebookPage page, {
  required bool asPdf,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    if (asPdf) {
      final bytes = await buildPagePdf(page);
      final name = 'page-${page.pageIndex}.pdf';
      final printed = await _tryPrint(bytes, name);
      if (!printed) {
        await saveBytes(bytes, name, 'application/pdf');
      }
    } else {
      final bytes = await buildPagePng(page);
      await saveBytes(bytes, 'page-${page.pageIndex}.png', 'image/png');
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          asPdf
              ? 'Exported page ${page.pageIndex}.pdf'
              : 'Exported page ${page.pageIndex}.png',
        ),
      ),
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text("Couldn't export this page")),
    );
  }
}

Future<bool> _tryPrint(Uint8List bytes, String name) async {
  try {
    final info = await Printing.info();
    if (!info.canPrint) return false;
    return await Printing.layoutPdf(name: name, onLayout: (_) async => bytes);
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
