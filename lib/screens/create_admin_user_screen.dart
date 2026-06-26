import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../constants/team_role_config.dart';
import '../theme/app_colors.dart';
import '../services/logs_service.dart';
import '../widgets/fast_text_field.dart';

class CreateAdminUserScreen extends StatefulWidget {
  const CreateAdminUserScreen({
    super.key,
    this.initialRole = TeamRole.admin,
  });

  final TeamRole initialRole;

  @override
  State<CreateAdminUserScreen> createState() => _CreateAdminUserScreenState();
}

class _CreateAdminUserScreenState extends State<CreateAdminUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _cpfController = TextEditingController();
  bool _isLoading = false;
  late TeamRole _selectedRole;

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.initialRole;
  }

  Future<void> _createMember() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final payload = <String, dynamic>{
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'cpf': _cpfController.text.trim(),
        'role': TeamRoleConfig.firestoreRoleFor(_selectedRole),
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'active',
      };
      final lvl = TeamRoleConfig.adminLevelFor(_selectedRole);
      if (lvl != null) payload['adminLevel'] = lvl;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .set(payload);

      await LogsService().saveLog(
        modulo: 'Admin',
        acao: 'Criou membro da equipe',
        detalhes: '${_emailController.text.trim()} · ${TeamRoleConfig.label(_selectedRole)}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${TeamRoleConfig.label(_selectedRole)} criado com sucesso!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      var message = 'Erro ao criar usuário';
      if (e.code == 'email-already-in-use') {
        message = 'E-mail já existe. Use «Promover existente» na equipe.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _cpfController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roleColor = TeamRoleConfig.color(_selectedRole);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F8),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Novo ${TeamRoleConfig.label(_selectedRole)}'),
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      colors: [roleColor, Color.lerp(roleColor, Colors.black, 0.15)!],
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(TeamRoleConfig.icon(_selectedRole), color: Colors.white, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          TeamRoleConfig.description(_selectedRole),
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.95), height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                DropdownButtonFormField<TeamRole>(
                  value: _selectedRole,
                  decoration: InputDecoration(
                    labelText: 'Papel na equipe',
                    prefixIcon: Icon(TeamRoleConfig.icon(_selectedRole), color: roleColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  items: TeamRoleConfig.creatableRoles
                      .map(
                        (r) => DropdownMenuItem(
                          value: r,
                          child: Text(TeamRoleConfig.label(r)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedRole = v ?? TeamRole.admin),
                ),
                const SizedBox(height: 16),
                _field('Nome completo', _nameController, Icons.person_outline_rounded),
                const SizedBox(height: 12),
                _field('E-mail', _emailController, Icons.email_outlined, kind: FastTextFieldKind.email),
                const SizedBox(height: 12),
                _field('CPF', _cpfController, Icons.badge_outlined),
                const SizedBox(height: 12),
                _field('Senha temporária', _passwordController, Icons.lock_outline_rounded, obscure: true),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _isLoading ? null : _createMember,
                  style: FilledButton.styleFrom(
                    backgroundColor: roleColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          'CRIAR ${TeamRoleConfig.label(_selectedRole).toUpperCase()}',
                          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller,
    IconData icon, {
    bool obscure = false,
    FastTextFieldKind kind = FastTextFieldKind.standard,
  }) {
    return FastTextField(
      controller: controller,
      obscureText: obscure,
      kind: kind,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      validator: (v) => v == null || v.trim().isEmpty ? 'Campo obrigatório' : null,
    );
  }
}
