import '../domain/ids.dart';
import '../domain/ink.dart';
import 'points.dart';
import 'records.dart';
import 'schema.dart';

/// Opens the meta box, then runs these steps, and only then reads notebooks.
abstract class MigrationHost {
  Future<int> readSchemaVersion();

  Future<void> writeSchemaVersion(int value);

  Future<String?> readInstallId();

  Future<void> writeInstallId(String value);

  Future<List<StoredStroke>> readStrokes();

  Future<void> writeStroke(StoredStroke stroke);
}

/// Runs each pending step, then writes [currentSchemaVersion].
Future<void> runStorageMigrations(MigrationHost host) async {
  final version = await host.readSchemaVersion();
  if (version == 0) {
    await host.writeSchemaVersion(currentSchemaVersion);
    final existing = await host.readInstallId();
    if (existing == null || existing.isEmpty) {
      await host.writeInstallId(newId());
    }
    return;
  }
  if (version == 1) {
    await _packLegacyStrokes(host);
    await host.writeSchemaVersion(currentSchemaVersion);
  }
  final installId = await host.readInstallId();
  if (installId == null || installId.isEmpty) {
    await host.writeInstallId(newId());
  }
}

/// Version 1 stored each point as its own object. Version 2 packs them.
Future<void> _packLegacyStrokes(MigrationHost host) async {
  final strokes = await host.readStrokes();
  for (final stroke in strokes) {
    final legacy = stroke.legacyPoints;
    if (legacy == null || legacy.isEmpty) continue;
    final packedBytes = stroke.packedPoints;
    if (packedBytes != null && packedBytes.isNotEmpty) continue;
    final packed = packPoints([
      for (final point in legacy) _legacyPoint(point),
    ]);
    await host.writeStroke(
      stroke.copyWith(
        packedPoints: packed.bytes,
        timeOriginMs: packed.timeOriginMs,
        clearLegacy: true,
      ),
    );
  }
}

StrokePoint _legacyPoint(StoredPoint point) {
  return StrokePoint(
    xMm: point.xMm,
    yMm: point.yMm,
    pressure: point.pressure,
    touching: point.flags & pointFlagTouching != 0,
    tMs: point.tMs,
    approximateTime: point.flags & pointFlagApproximate != 0,
  );
}
