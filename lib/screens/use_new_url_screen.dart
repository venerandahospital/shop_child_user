import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class UseNewUrlScreen extends StatefulWidget {
  const UseNewUrlScreen({super.key});

  @override
  State<UseNewUrlScreen> createState() => _UseNewUrlScreenState();
}

class _UseNewUrlScreenState extends State<UseNewUrlScreen> {
  final _auth = AuthService();
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final entered = _controller.text.trim();
    if (entered.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paste a mother URL first.')),
      );
      return;
    }

    setState(() => _saving = true);
    await _auth.setBaseUrl(entered);
    if (!mounted) return;
    Navigator.of(context).pop<String>(entered);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Use New URL')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: 'Mother Base URL',
                ),
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _saving ? null : _save(),
              ),
              const SizedBox(height: 10),
              const Text(
                'Paste the URL shared by mother (for example from WhatsApp), then save.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(_saving ? 'Saving...' : 'Save & Use URL'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
