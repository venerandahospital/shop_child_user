import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../navigation/app_router.dart';
import '../services/auth_service.dart';
import '../utils/email_field.dart';

class ChildLoginScreen extends StatefulWidget {
  const ChildLoginScreen({super.key});

  @override
  State<ChildLoginScreen> createState() => _ChildLoginScreenState();
}

class _ChildLoginScreenState extends State<ChildLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auth = AuthService();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _rememberPassword = false;
  String _error = '';
  String _baseUrl = '';

  @override
  void initState() {
    super.initState();
    _loadBaseUrl();
    _loadCachedLoginCredentials();
  }

  Future<void> _loadBaseUrl() async {
    final value = await _auth.getBaseUrl();
    if (!mounted) return;
    setState(() => _baseUrl = value);
  }

  Future<void> _loadCachedLoginCredentials() async {
    final cached = await _auth.getCachedLoginCredentials();
    final rememberPassword = await _auth.getRememberLoginPassword();
    if (!mounted) return;
    setState(() {
      _rememberPassword = rememberPassword;
      _email.text = (cached['email'] ?? '').trim().toLowerCase();
      _password.text = rememberPassword ? (cached['password'] ?? '') : '';
    });
  }

  Future<void> _login() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    await _auth.setRememberLoginPassword(_rememberPassword);
    final email = _email.text.trim().toLowerCase();
    final result = await _auth.login(email, _password.text);
    if (!mounted) return;
    setState(() => _loading = false);
    if (result['success'] == true) {
      Navigator.of(context)
          .pushNamedAndRemoveUntil(AppRouter.main, (_) => false);
      return;
    }
    setState(() {
      _error = (result['message'] ?? 'Login failed').toString();
    });
  }

  Future<bool> _confirmCloseApp() async {
    final shouldClose = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Close app'),
        content: const Text('Are you sure you want to close app?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (shouldClose == true) {
      await SystemNavigator.pop();
      return true;
    }
    return false;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _confirmCloseApp,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Child Login'),
        ),
        resizeToAvoidBottomInset: true,
        body: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              inputFormatters: const [LowercaseTextInputFormatter()],
              validator: validateChildEmail,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _rememberPassword,
              contentPadding: EdgeInsets.zero,
              title: const Text('Remember password'),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (value) async {
                final remember = value ?? false;
                await _auth.setRememberLoginPassword(remember);
                if (!mounted) return;
                setState(() {
                  _rememberPassword = remember;
                  if (!remember) {
                    _password.clear();
                  }
                });
              },
            ),
            const SizedBox(height: 16),
            if (_baseUrl.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Current mother endpoint: $_baseUrl',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            if (_baseUrl.isNotEmpty) const SizedBox(height: 8),
            if (_error.isNotEmpty)
              Text(_error, style: const TextStyle(color: Colors.red)),
            ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                onPressed: _loading ? null : _login,
                child: Text(_loading ? 'Signing in...' : 'Sign in'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRouter.signup),
              child: const Text('Create account'),
            ),
            TextButton(
              onPressed: () async {
                await Navigator.of(context).pushNamed(AppRouter.connect);
                await _loadBaseUrl();
              },
              child: const Text('Configure mother endpoint'),
            ),
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
            ],
            ),
          ),
        ),
      ),
    );
  }
}
