import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../db.dart';
import '../session.dart';
import '../voice_parser.dart';

class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});
  @override
  State<VoiceScreen> createState() => _VoiceState();
}

class _VoiceState extends State<VoiceScreen> {
  final speech = stt.SpeechToText();
  final text = TextEditingController();
  bool available = false;
  bool listening = false;
  String status = 'اضغط على الميكروفون وانطق الأصناف، أو اكتب الجملة يدوياً.';
  List<VoiceItem> items = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      available = await speech.initialize(
        onError: (e) {
          if (mounted) setState(() => status = 'تعذر التعرف الصوتي (قد يحتاج إنترنت). اكتب الجملة يدوياً.');
        },
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') {
            if (mounted) setState(() => listening = false);
            if (text.text.trim().isNotEmpty) _analyze();
          }
        },
      );
    } catch (_) {
      available = false;
    }
    if (!available && mounted) {
      setState(() => status = 'التعرف الصوتي غير متاح الآن. اكتب الجملة يدوياً أو أضف الأصناف من الكاشير.');
    }
  }

  Future<void> _listen() async {
    if (!available) {
      toast(context, 'التعرف الصوتي غير متاح، استخدم الإدخال اليدوي');
      return;
    }
    if (listening) {
      await speech.stop();
      return;
    }
    String? locale;
    try {
      final ls = await speech.locales();
      for (final l in ls) {
        if (l.localeId == 'ar_EG') locale = l.localeId;
      }
      locale ??= ls.where((l) => l.localeId.startsWith('ar')).map((l) => l.localeId).firstOrNull;
    } catch (_) {}
    setState(() => listening = true);
    await speech.listen(
      localeId: locale ?? 'ar_EG',
      onResult: (r) => setState(() => text.text = r.recognizedWords),
    );
  }

  Future<void> _analyze() async {
    final products = await AppDb.I.products();
    if (!mounted) return;
    setState(() => items = parseVoice(text.text, products));
  }

  @override
  Widget build(BuildContext context) {
    final good = items.where((i) => i.product != null).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('البيع الصوتي')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Text(status),
        const SizedBox(height: 8),
        TextField(
          controller: text,
          maxLines: 2,
          decoration: const InputDecoration(
              hintText: 'مثال: أضف 2 كيلو سكر و3 زجاجات زيت وعلبة شاي', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        Row(children: [
          FilledButton.icon(
              onPressed: _listen,
              icon: Icon(listening ? Icons.stop : Icons.mic),
              label: Text(listening ? 'إيقاف' : 'تحدّث')),
          const SizedBox(width: 8),
          FilledButton.tonal(onPressed: _analyze, child: const Text('تحليل النص')),
        ]),
        const Divider(height: 24),
        if (items.isEmpty) const Text('لن تُضاف أي أصناف قبل مراجعتها وتأكيدها.'),
        for (final i in items)
          Card(
            color: i.product == null ? Colors.red.withOpacity(0.12) : null,
            child: ListTile(
              title: Text(i.product == null ? 'لم يتم التعرف على صنف: «${i.text}»' : '${i.product!['name']}'),
              subtitle: i.product == null
                  ? const Text('أضفه يدوياً من الكاشير')
                  : Text('المتاح: ${fmt(i.product!['qty'] as num)}  |  السعر: ${fmt(i.product!['sell_price'] as num)}'),
              trailing: i.product == null
                  ? null
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => setState(() {
                                if (i.qty > 1) i.qty -= 1;
                              })),
                      InkWell(
                        onTap: () async {
                          final v = await askText(context, 'الكمية', initial: fmt(i.qty));
                          if (v != null && toD(v) > 0) setState(() => i.qty = toD(v));
                        },
                        child: Text(fmt(i.qty), style: const TextStyle(fontSize: 16)),
                      ),
                      IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => setState(() => i.qty += 1)),
                    ]),
            ),
          ),
        if (good.isNotEmpty) ...[
          const SizedBox(height: 8),
          FilledButton(
              onPressed: () => Navigator.pop(context, good),
              child: Text('تأكيد وإضافة ${good.length} صنف للفاتورة')),
        ],
      ]),
    );
  }
}
