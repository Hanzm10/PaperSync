import 'package:papersync/domain/ink.dart';
import 'package:papersync/models/pen_link.dart';
import 'package:papersync/state/app_controller.dart';
import 'package:papersync/theme/app_colors.dart';

AppModel libraryModel() {
  final today = DateTime.now();
  return AppModel(
    notebooks: [
      _notebook(
        id: 'nb-lecture',
        name: 'Lecture notes',
        updatedAt: today,
        pages: [
          _page(
            notebookId: 'nb-lecture',
            id: 'page-lecture-1',
            index: 1,
            createdAt: DateTime(2026, 9, 23),
            text: 'mitochondria supply energy',
            color: AppColors.storedInk.toARGB32(),
            lines: const [(y: 28, x0: 18, x1: 148), (y: 42, x0: 18, x1: 132)],
          ),
          _page(
            notebookId: 'nb-lecture',
            id: 'page-lecture-3',
            index: 3,
            createdAt: DateTime(2026, 9, 26),
            text: 'office hours thursday',
            color: AppColors.storedInk.toARGB32(),
            lines: const [(y: 34, x0: 20, x1: 128), (y: 50, x0: 20, x1: 96)],
          ),
          _page(
            notebookId: 'nb-lecture',
            id: 'page-lecture-2',
            index: 2,
            createdAt: DateTime(2026, 9, 25),
            text: 'kinetic friction on the ramp',
            color: AppColors.inkBlue.toARGB32(),
            lines: const [(y: 30, x0: 22, x1: 150), (y: 46, x0: 22, x1: 110)],
          ),
        ],
      ),
      _notebook(
        id: 'nb-studio',
        name: 'Studio',
        updatedAt: DateTime(2020, 9, 25),
        pages: [
          _page(
            notebookId: 'nb-studio',
            id: 'page-studio-1',
            index: 1,
            createdAt: DateTime(2020, 9, 25),
            text: 'supplier samples in blue',
            color: AppColors.inkRed.toARGB32(),
            lines: const [(y: 36, x0: 24, x1: 146), (y: 54, x0: 24, x1: 100)],
          ),
        ],
      ),
    ],
    link: PenLink.paired(),
    nearbyPens: const ['PaperSync Pen'],
    liveNotebookId: null,
    livePageId: null,
    hover: null,
    history: const {},
  );
}

AppModel emptyModel({bool permissionGranted = false}) {
  return AppModel(
    notebooks: const [],
    link: PenLink.unpaired(permissionGranted: permissionGranted),
    nearbyPens: const ['PaperSync Pen'],
    liveNotebookId: null,
    livePageId: null,
    hover: null,
    history: const {},
  );
}

Notebook _notebook({
  required String id,
  required String name,
  required DateTime updatedAt,
  required List<NotebookPage> pages,
}) {
  return Notebook(
    id: id,
    name: name,
    pages: pages,
    inkColorArgb: AppColors.storedInk.toARGB32(),
    createdAt: DateTime(2026, 9, 1),
    updatedAt: updatedAt,
  );
}

NotebookPage _page({
  required String notebookId,
  required String id,
  required int index,
  required DateTime createdAt,
  required String text,
  required int color,
  required List<({double y, double x0, double x1})> lines,
}) {
  return NotebookPage(
    id: id,
    notebookId: notebookId,
    pageIndex: index,
    createdAt: createdAt,
    recognizedText: text,
    strokes: [
      for (var i = 0; i < lines.length; i++)
        Stroke(
          id: '$id-stroke-$i',
          colorArgb: color,
          createdAt: createdAt,
          points: [
            StrokePoint(
              xMm: lines[i].x0,
              yMm: lines[i].y,
              pressure: 9000,
              touching: true,
            ),
            StrokePoint(
              xMm: lines[i].x1,
              yMm: lines[i].y,
              pressure: 9000,
              touching: true,
            ),
          ],
        ),
    ],
  );
}
