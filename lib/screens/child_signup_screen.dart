import 'package:flutter/material.dart';

import '../navigation/app_router.dart';
import '../services/auth_service.dart';
import '../utils/email_field.dart';

class ChildSignupScreen extends StatefulWidget {
  const ChildSignupScreen({super.key});

  @override
  State<ChildSignupScreen> createState() => _ChildSignupScreenState();
}

class _ChildSignupScreenState extends State<ChildSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auth = AuthService();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String _message = '';

  Future<void> _signup() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() {
      _loading = true;
      _message = '';
    });
    final result = await _auth.signup(
      email: _email.text.trim().toLowerCase(),
      password: _password.text,
      name: _name.text.trim(),
    );
    if (!mounted) return;
    setState(() => _loading = false);
    final msg = (result['message'] ?? 'Signup sent').toString();
    setState(() => _message = msg);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Child Signup')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
          children: [
            TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                inputFormatters: const [LowercaseTextInputFormatter()],
                validator: validateChildEmail,
                decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 16),
            if (_message.isNotEmpty) Text(_message),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _signup,
                child: Text(_loading ? 'Sending...' : 'Sign up'),
              ),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pushReplacementNamed(AppRouter.login),
              child: const Text('Back to login'),
            ),
          ],
          ),
        ),
      ),
    );
  }
}
