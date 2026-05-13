import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/item_image_upload_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = AuthService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _profilePicController = TextEditingController();
  final _roleController = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _profilePicController.dispose();
    _roleController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await _auth.getCurrentProfile();
    if (!mounted) return;
    setState(() {
      _nameController.text = profile['name'] ?? '';
      _emailController.text = profile['email'] ?? '';
      _profilePicController.text = profile['profilePic'] ?? '';
      _roleController.text = (profile['role'] ?? 'ADMIN').toString();
      _loading = false;
    });
  }

  Future<void> _uploadProfilePhoto() async {
    if (_uploadingPhoto || _saving) return;
    setState(() => _uploadingPhoto = true);
    try {
      final url = await ItemImageUploadService.instance.pickCompressAndUpload();
      if (!mounted) return;
      setState(() => _profilePicController.text = url);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile photo uploaded.')));
    } catch (e) {
      if (!mounted) return;
      final message = '$e'.contains('_UserCancelledException')
          ? 'Image selection cancelled.'
          : 'Photo upload failed: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _uploadingPhoto = false);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final result = await _auth.updateProfile(
      name: _nameController.text,
      email: _emailController.text,
      newPassword: _passwordController.text.trim().isEmpty
          ? null
          : _passwordController.text.trim(),
      profilePic: _profilePicController.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.$2)),
    );
    if (result.$1) {
      _passwordController.clear();
      _confirmPasswordController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final picUrl = _profilePicController.text.trim();
    final initials = (_nameController.text.trim().isEmpty
            ? 'U'
            : _nameController.text.trim().split(' ').where((e) => e.isNotEmpty).take(2).map((e) => e[0].toUpperCase()).join())
        .padRight(1, 'U');

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 42,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      backgroundImage: picUrl.isNotEmpty ? NetworkImage(picUrl) : null,
                      child: picUrl.isEmpty
                          ? Text(
                              initials,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _uploadingPhoto ? null : _uploadProfilePhoto,
                      icon: _uploadingPhoto
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_camera_outlined),
                      label: Text(_uploadingPhoto ? 'Uploading...' : 'Edit photo'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _profilePicController,
                    decoration: const InputDecoration(
                      labelText: 'Profile picture URL (optional)',
                      hintText: 'https://example.com/photo.jpg',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      hintText: 'Enter your name',
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _roleController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'Enter email',
                    ),
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.isEmpty) return 'Email is required';
                      final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                      if (!emailRegex.hasMatch(value)) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'New password (optional)',
                      hintText: 'Leave blank to keep current password',
                    ),
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.isNotEmpty && value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirm new password',
                    ),
                    validator: (v) {
                      final pass = _passwordController.text.trim();
                      final confirm = (v ?? '').trim();
                      if (pass.isEmpty && confirm.isEmpty) return null;
                      if (confirm != pass) return 'Passwords do not match';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'Saving...' : 'Save profile'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

