// The architecture audit ships its metrics script inside a reference file,
// between two marker lines, because skill bundles install references on
// every target but no script directory. Steps 1 and 2 cut the script out by
// those markers, and the script refuses to run when its own digest does not
// match SELF_DIGEST. These tests keep the markers, the fence and the digest
// line in the shape the extraction command expects.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _begin = '<!-- graph_metrics.py:begin -->';
const _end = '<!-- graph_metrics.py:end -->';

String _repoRoot() {
  var dir = Directory.current;
  while (true) {
    if (Directory(p.join(dir.path, 'skills')).existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('Could not locate repo root from ${Directory.current}');
    }
    dir = parent;
  }
}

void main() {
  final references = p.join(
    _repoRoot(),
    'skills',
    'architecture-audit',
    'references',
  );
  final script = File(p.join(references, 'graph-metrics-script.md'));

  test('the script reference exists', () {
    expect(script.existsSync(), isTrue);
  });

  test('holds exactly one marked python block', () {
    final text = script.readAsStringSync();
    expect(_begin.allMatches(text), hasLength(1));
    expect(_end.allMatches(text), hasLength(1));

    final body = text.split(_begin)[1].split(_end)[0];
    expect(
      RegExp(r'^```python$', multiLine: true).allMatches(body),
      hasLength(1),
    );
    expect(body.trimRight(), endsWith('```'));
  });

  test('the block carries a SELF_DIGEST line', () {
    final body = script.readAsStringSync().split(_begin)[1].split(_end)[0];
    expect(
      RegExp(r"^SELF_DIGEST = '[0-9a-f]{64}'$", multiLine: true)
          .allMatches(body),
      hasLength(1),
    );
  });

  test('the module-map step extracts by the same markers', () {
    final step = File(p.join(references, 'module-map.md')).readAsStringSync();
    expect(step, contains(_begin));
    expect(step, contains(_end));
    expect(step, contains('graph-metrics-script.md'));
  });
}
