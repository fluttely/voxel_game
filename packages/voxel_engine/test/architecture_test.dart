// The five subjects of this package were five packages until 2026-09-19, and
// pub itself refused an import that would have made a cycle between them. This
// test is what bought that back: it is the same rule, read off the import
// lines instead of off the dependency graph.
//
// See docs/VOXEL_CONSOLIDATION_PLAN_2026-09-19.md, step VC3.1.
import 'dart:io';

import 'package:test/test.dart';

/// Every subject folder under `lib/src/`, and the subjects each one may import.
/// `core` is the base and depends on nothing; `net` is the transport and is
/// alone on purpose, so it can go back to being its own package any day.
const Map<String, Set<String>> allowed = {
  'core': {},
  'worldgen': {'core'},
  'content': {'core'},
  'signals': {'core'},
  'net': {},
};

/// The subject a file under `lib/src/` belongs to: `lib/src/<subject>/...`.
String subjectOf(String path) => path.split('/')[2];

void main() {
  final lib = Directory('lib/src');
  final files = [
    if (lib.existsSync())
      for (final f in lib.listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart')) f,
  ];

  test('the source tree is the subjects this test knows about', () {
    expect(lib.existsSync(), isTrue, reason: 'run this from the package root, where lib/src is');
    expect(files, isNotEmpty);
    final found = {for (final f in files) subjectOf(f.path)};
    expect(found, equals(allowed.keys.toSet()), reason: 'a new subject folder needs its edges declared here');
  });

  test('a subject imports only the subjects it is allowed to', () {
    // `package:voxel_engine/<subject>.dart` is how one subject reaches another;
    // within a subject, files import each other by relative path.
    final importLine = RegExp(r"^import 'package:voxel_engine/([a-z_]+)\.dart'", multiLine: true);
    final climbing = RegExp(r"^import '(\.\./)+([a-z_]+)/", multiLine: true);
    final broken = <String>[];

    for (final file in files) {
      final from = subjectOf(file.path);
      final text = file.readAsStringSync();
      final into = <String>{
        for (final m in importLine.allMatches(text)) m.group(1)!,
        for (final m in climbing.allMatches(text))
          if (allowed.containsKey(m.group(2))) m.group(2)!,
      }..remove(from);
      for (final to in into.difference(allowed[from]!)) {
        broken.add('${file.path}: $from must not import $to');
      }
    }

    expect(broken, isEmpty, reason: 'the subjects would not have resolved as separate packages');
  });

  test('a subject library exports its own folder and nothing else', () {
    final export = RegExp(r"^export 'src/([a-z_]+)/", multiLine: true);
    for (final subject in allowed.keys) {
      final text = File('lib/$subject.dart').readAsStringSync();
      final folders = {for (final m in export.allMatches(text)) m.group(1)!};
      expect(folders, equals({subject}), reason: 'lib/$subject.dart exports $folders');
    }
  });

  test('the umbrella library exports every subject', () {
    final text = File('lib/voxel_engine.dart').readAsStringSync();
    for (final subject in allowed.keys) {
      expect(text, contains("export '$subject.dart';"));
    }
  });
}
