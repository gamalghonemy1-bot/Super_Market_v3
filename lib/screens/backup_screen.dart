import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../backup.dart';
import '../db.dart';
import '../export.dart';
import '../session.dart';
import 'auth.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupState();
}

class _BackupState extends State<BackupScreen> {
  List<File> files = [];
  final url = TextEditingController();
  final token = TextEditingController();
  String lastSync = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    files = await BackupService.list();
    url.text = await AppDb.I.getSetting('sync_url');
    token.text = await AppDb.I.getSetting('sync_token');
    lastSync = await AppDb.I.getSetting('last_sync');
    if (mounted) setState(() {});
  }

  String _name(File f) => f.uri.pathSegments.last;

  Future<void> _now() async {
    try {
      final f = await BackupService.manual();
      if (mounted) toast(context, 'تم إنشاء النسخة: ${_name(f)}');
      _load();
    } catch (e) {
      if (mounted) toast(context, 'فشل النسخ: ${errText(e)}');
    }
  }

  Future<void> _share(File f) async {
    try {
      await shareFile(_name(f), await f.readAsBytes());
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
  }

  Future<void> _restore(File f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استعادة نسخة احتياطية'),
        content: const Text('سيتم استبدال كل بيانات التطبيق الحالية بهذه النسخة (مع حفظ نسخة من الوضع الحالي قبل الاستعادة). هل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('استعادة')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await BackupService.restore(f, await BackupService.dir());
      Session.user = null;
      if (!mounted) return;
      toast(context, 'تمت الاستعادة بنجاح، سجّل الدخول من جديد');
      Navigator.pushAndRemoveUntil(
          context, MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles();
    final p = r?.files.single.path;
    if (p == null) return;
    await _restore(File(p));
  }

  Future<void> _saveSync() async {
    await AppDb.I.setSetting('sync_url', url.text.trim());
    await AppDb.I.setSetting('sync_token', token.text.trim());
    if (mounted) toast(context, 'تم حفظ إعدادات السيرفر');
  }

  Future<void> _syncNow() async {
    await _saveSync();
    final m = await SyncService.syncNow();
    if (mounted) {
      toast(context, m);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('النسخ الاحتياطي والاستعادة')),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          const Text('يتم إنشاء نسخة تلقائية مرة يومياً عند أول فتح للتطبيق (آخر 14 نسخة). '
              'النسخ الداخلية تُحذف إذا حُذف التطبيق، لذلك شارك نسخة بانتظام إلى Google Drive أو ذاكرة الهاتف.'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            FilledButton.icon(onPressed: _now, icon: const Icon(Icons.backup), label: const Text('نسخ احتياطي الآن')),
            FilledButton.tonalIcon(onPressed: _pick, icon: const Icon(Icons.folder_open), label: const Text('استعادة من ملف')),
          ]),
          const Divider(height: 28),
          const Text('النسخ المحفوظة', style: TextStyle(fontWeight: FontWeight.bold)),
          if (files.isEmpty) const ListTile(title: Text('لا توجد نسخ بعد')),
          for (final f in files)
            ListTile(
              dense: true,
              title: Text(_name(f)),
              subtitle: Text('${(f.lengthSync() / 1024).toStringAsFixed(0)} KB'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.share), tooltip: 'حفظ/مشاركة', onPressed: () => _share(f)),
                IconButton(icon: const Icon(Icons.restore), tooltip: 'استعادة', onPressed: () => _restore(f)),
              ]),
            ),
          const Divider(height: 28),
          const Text('رفع نسخة إلى سيرفر (اختياري)', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('كل ساعتين والتطبيق مفتوح وبه إنترنت. استخدم عنوان https. التطبيق لا يحتاج السيرفر أبداً للعمل.'),
          TextField(controller: url, decoration: const InputDecoration(labelText: 'عنوان السيرفر (PUT)')),
          TextField(controller: token, decoration: const InputDecoration(labelText: 'مفتاح الدخول (اختياري)')),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton(onPressed: _saveSync, child: const Text('حفظ')),
            const SizedBox(width: 8),
            FilledButton.tonal(onPressed: _syncNow, child: const Text('رفع الآن')),
          ]),
          if (lastSync.isNotEmpty) Text('آخر رفع ناجح: $lastSync'),
        ]),
      );
}
