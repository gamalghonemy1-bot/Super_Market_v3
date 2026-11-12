import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'db.dart';

class BackupService {
  static Future<Directory> dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/backups');
    await d.create(recursive: true);
    return d;
  }

  static String stamp() => nowStr().replaceAll(RegExp('[: ]'), '-');

  /// ينشئ نسخة متسقة من قاعدة البيانات داخل [target] باسم [name].
  static Future<File> create(Directory target, String name) async {
    await target.create(recursive: true);
    final out = File('${target.path}/$name');
    if (await out.exists()) await out.delete();
    final d = await AppDb.I.db;
    try {
      await d.execute("VACUUM INTO '${out.path.replaceAll("'", "''")}'");
    } catch (_) {
      try {
        await d.rawQuery('PRAGMA wal_checkpoint(FULL)');
      } catch (_) {}
      if (await out.exists()) await out.delete();
      await File(d.path).copy(out.path);
    }
    return out;
  }

  static Future<File> manual() async => create(await dir(), 'manual_${stamp()}.db');

  /// نسخة تلقائية يومية (تُنشأ عند أول فتح للتطبيق في اليوم) مع الاحتفاظ بآخر 14 نسخة.
  static Future<void> autoDaily() async {
    try {
      final d = await dir();
      final today = nowStr().substring(0, 10);
      final f = File('${d.path}/auto_$today.db');
      if (!await f.exists()) await create(d, 'auto_$today.db');
      final autos = (await d.list().toList())
          .whereType<File>()
          .where((e) => e.uri.pathSegments.last.startsWith('auto_'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final old in autos.skip(14)) {
        await old.delete();
      }
    } catch (_) {}
  }

  static Future<List<File>> list() async {
    final d = await dir();
    final files = (await d.list().toList())
        .whereType<File>()
        .where((e) => e.path.endsWith('.db'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  static Future<bool> _isSqlite(File f) async {
    final bytes = <int>[];
    await for (final c in f.openRead(0, 16)) {
      bytes.addAll(c);
    }
    return bytes.length == 16 && String.fromCharCodes(bytes) == 'SQLite format 3\u0000';
  }

  /// يستعيد نسخة احتياطية. يحفظ نسخة من الوضع الحالي أولاً ويتراجع عند الفشل.
  static Future<void> restore(File src, Directory safeDir) async {
    if (!await src.exists() || !await _isSqlite(src)) {
      throw Exception('الملف ليس نسخة احتياطية صالحة');
    }
    final pre = await create(safeDir, 'pre_restore_${stamp()}.db');
    final path = (await AppDb.I.db).path;
    await AppDb.I.reset();
    Future<void> clean() async {
      for (final s in ['-wal', '-shm', '-journal']) {
        final f = File('$path$s');
        if (await f.exists()) await f.delete();
      }
    }

    try {
      await clean();
      await src.copy(path);
      final d = await AppDb.I.db;
      await d.rawQuery('SELECT COUNT(*) FROM users');
      await d.rawQuery('SELECT COUNT(*) FROM products');
    } catch (_) {
      await AppDb.I.reset();
      await clean();
      await pre.copy(path);
      throw Exception('فشلت الاستعادة، تمت إعادة البيانات السابقة');
    }
  }
}

/// رفع نسخة كاملة إلى سيرفر خارجي اختياري كل ساعتين (والتطبيق يعمل بدونه تماماً).
class SyncService {
  static Timer? _t;

  static void start() {
    _t?.cancel();
    _t = Timer.periodic(const Duration(hours: 2), (_) => syncNow());
  }

  static Future<String> syncNow() async {
    final url = (await AppDb.I.getSetting('sync_url')).trim();
    if (url.isEmpty) return 'لم يتم ضبط عنوان السيرفر';
    try {
      final tmp = await getTemporaryDirectory();
      final f = await BackupService.create(tmp, 'sync.db');
      final c = HttpClient()..connectionTimeout = const Duration(seconds: 15);
      final req = await c.putUrl(Uri.parse(url));
      req.headers.set('Content-Type', 'application/octet-stream');
      final tok = (await AppDb.I.getSetting('sync_token')).trim();
      if (tok.isNotEmpty) req.headers.set('Authorization', 'Bearer $tok');
      req.add(await f.readAsBytes());
      final res = await req.close();
      await res.drain<void>();
      c.close();
      if (res.statusCode < 300) {
        await AppDb.I.setSetting('last_sync', nowStr());
        return 'تم الرفع إلى السيرفر';
      }
      return 'رفض السيرفر العملية (${res.statusCode})';
    } catch (_) {
      return 'تعذر الاتصال بالسيرفر (التطبيق يعمل بشكل طبيعي بدونه)';
    }
  }
}
