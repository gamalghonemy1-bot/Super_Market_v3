import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../db.dart';
import '../main.dart';
import '../session.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsState();
}

class _SettingsState extends State<SettingsScreen> {
  final store = TextEditingController();
  final branch = TextEditingController();
  final manager = TextEditingController();
  final footer = TextEditingController();
  String paper = 'A4';
  List<Map<String, Object?>> users = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    store.text = await AppDb.I.getSetting('store_name');
    branch.text = await AppDb.I.getSetting('branch');
    manager.text = await AppDb.I.getSetting('manager');
    footer.text = await AppDb.I.getSetting('invoice_footer');
    paper = (await AppDb.I.getSetting('paper')) == '80mm' ? '80mm' : 'A4';
    if (Session.isAdmin) users = await AppDb.I.users();
    if (mounted) setState(() {});
  }

  Future<void> _saveBrand() async {
    await AppDb.I.setSetting('store_name', store.text.trim());
    await AppDb.I.setSetting('branch', branch.text.trim());
    await AppDb.I.setSetting('manager', manager.text.trim());
    await AppDb.I.setSetting('invoice_footer', footer.text.trim());
    await AppDb.I.setSetting('paper', paper);
    if (mounted) toast(context, 'تم حفظ الإعدادات');
  }

  Future<void> _changeOwnPassword() async {
    final v = await askText(context, 'كلمة المرور الجديدة', obscure: true);
    if (v == null) return;
    try {
      await AppDb.I.setPassword(Session.id, v);
      if (mounted) toast(context, 'تم تغيير كلمة المرور');
    } catch (e) {
      if (mounted) toast(context, errText(e));
    }
  }

  Future<void> _addSeller() async {
    final u = TextEditingController();
    final p = TextEditingController();
    final n = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إضافة مستخدم (بائع)'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: n, decoration: const InputDecoration(labelText: 'الاسم')),
          TextField(controller: u, decoration: const InputDecoration(labelText: 'اسم المستخدم')),
          TextField(controller: p, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () async {
              try {
                await AppDb.I.addUser(u.text, p.text, n.text, 'seller');
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                if (ctx.mounted) toast(ctx, errText(e));
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final admin = Session.isAdmin;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        if (admin) ...[
          const Text('بيانات المتجر', style: TextStyle(fontWeight: FontWeight.bold)),
          TextField(controller: store, decoration: const InputDecoration(labelText: 'اسم السوبر ماركت')),
          TextField(controller: branch, decoration: const InputDecoration(labelText: 'اسم الفرع')),
          TextField(controller: manager, decoration: const InputDecoration(labelText: 'اسم الإدارة')),
          TextField(controller: footer, decoration: const InputDecoration(labelText: 'نص أسفل الفاتورة (شكراً لزيارتكم...)')),
          DropdownButtonFormField<String>(
            value: paper,
            decoration: const InputDecoration(labelText: 'مقاس ورق الطباعة'),
            items: const [
              DropdownMenuItem(value: 'A4', child: Text('A4')),
              DropdownMenuItem(value: '80mm', child: Text('إيصال 80 مم')),
            ],
            onChanged: (v) => setState(() => paper = v!),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.image),
            title: const Text('اختيار شعار المتجر'),
            onTap: () async {
              final r = await FilePicker.platform.pickFiles(type: FileType.image);
              final path = r?.files.single.path;
              if (path == null) return;
              final dir = await getApplicationDocumentsDirectory();
              final ext = path.contains('.') ? path.substring(path.lastIndexOf('.')) : '.png';
              final dest = '${dir.path}/logo$ext';
              await File(path).copy(dest);
              await AppDb.I.setSetting('logo_path', dest);
              if (mounted) toast(context, 'تم حفظ الشعار');
            },
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _saveBrand, child: const Text('حفظ')),
          const Divider(height: 32),
        ],
        SwitchListTile(
          title: const Text('الوضع الليلي'),
          value: themeMode.value == ThemeMode.dark,
          onChanged: (v) async {
            themeMode.value = v ? ThemeMode.dark : ThemeMode.light;
            await AppDb.I.setSetting('dark', v ? '1' : '0');
            setState(() {});
          },
        ),
        ListTile(
            leading: const Icon(Icons.lock_reset),
            title: const Text('تغيير كلمة المرور الخاصة بي'),
            onTap: _changeOwnPassword),
        if (admin) ...[
          const Divider(height: 32),
          Row(children: [
            const Text('المستخدمون', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(onPressed: _addSeller, icon: const Icon(Icons.person_add), label: const Text('إضافة بائع')),
          ]),
          for (final u in users)
            ListTile(
              title: Text('${u['full_name'] ?? ''} (${u['username']})'),
              subtitle: Text(u['role'] == 'admin' ? 'مدير' : 'بائع'),
              trailing: u['role'] == 'admin'
                  ? null
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.key),
                        onPressed: () async {
                          final v = await askText(context, 'كلمة مرور جديدة', obscure: true);
                          if (v == null) return;
                          try {
                            await AppDb.I.setPassword(u['id'] as int, v);
                            if (mounted) toast(context, 'تم التغيير');
                          } catch (e) {
                            if (mounted) toast(context, errText(e));
                          }
                        },
                      ),
                      Switch(
                        value: u['active'] == 1,
                        onChanged: (v) async {
                          await AppDb.I.setActive(u['id'] as int, v);
                          _load();
                        },
                      ),
                    ]),
            ),
        ],
      ]),
    );
  }
}
