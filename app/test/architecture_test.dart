import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('domain and protocol import neither Flutter nor other layers', () {
    final violations = <String>[];
    for (final layer in ['domain', 'protocol']) {
      final dir = Directory('lib/$layer');
      expect(dir.existsSync(), isTrue, reason: 'missing lib/$layer');
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        for (final uri in _importUris(entity.readAsStringSync())) {
          if (_forbidden(uri)) {
            violations.add('${entity.path} imports $uri');
          }
        }
      }
    }
    expect(violations, isEmpty);
  });
}

final _importUri = RegExp('(?:import|export)\\s+[\'"]([^\'"]+)[\'"]');

Iterable<String> _importUris(String source) sync* {
  for (final line in source.split('\n')) {
    final code = line.split('//').first;
    final match = _importUri.firstMatch(code);
    if (match != null) yield match.group(1)!;
  }
}

bool _forbidden(String uri) {
  if (uri.startsWith('dart:')) return false;
  if (uri.startsWith('package:uuid/')) return false;
  if (uri.contains('..')) return true;
  if (uri.startsWith('package:')) return true;
  return false;
}
