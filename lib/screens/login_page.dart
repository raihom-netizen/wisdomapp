import 'package:flutter/material.dart';
import '../widgets/fast_text_field.dart';
import '../widgets/premium_button.dart';
import '../widgets/premium_text_field.dart';
import '../services/auth_service.dart';

/* * VERSÃO: 1.1.1
 * PROJETO: CONTROLE TOTAL
 * DESIGN: PREMIUM CLEAN / DARK MODE SUPPORT
 * MODIFICAÇÃO: Ajuste de constraints e padronização de cores via Theme
 */

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  static Future<void> _showRecuperarSenha(BuildContext context, ColorScheme colorScheme) async {
    final ctrl = TextEditingController();
    final sent = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Recuperar senha'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Informe seu CPF ou e-mail cadastrado. Enviaremos um link para redefinir sua senha.'),
                const SizedBox(height: 16),
                FastTextField(
                  controller: ctrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'CPF ou E-mail',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                final v = ctrl.text.trim();
                if (v.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Informe CPF ou e-mail.')));
                  return;
                }
                try {
                  await AuthService().sendPasswordResetEmail(v);
                  if (!ctx.mounted) return;
                  Navigator.of(ctx).pop(true);
                } catch (e) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Erro: ${e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '')}')),
                  );
                }
              },
              child: const Text('Enviar link'),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
    if (sent == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enviamos um e-mail para redefinir sua senha. Verifique sua caixa de entrada.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    
    // Pega a cor do card do seu PremiumTheme ou usa a cor de superfície padrão
    final panelColor = theme.cardTheme.color ?? colorScheme.surface;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 40.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 40.0),
              decoration: BoxDecoration(
                color: panelColor,
                borderRadius: BorderRadius.circular(28.0), // Bordas premium arredondadas
                border: Border.all(
                  color: theme.dividerColor.withOpacity(isDark ? 0.1 : 0.08),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.4 : 0.06),
                    blurRadius: 40,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cabeçalho de Boas-vindas
                    Text(
                      "Bem-vindo ao\nWISDOMAPP",
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "Faça login para gerenciar seus dados com segurança.",
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Campo de Login (Padronizado CPF/E-mail)
                    PremiumTextField(
                      label: "CPF ou E-mail",
                      controller: _loginController,
                      hintText: "digite seu cpf ou e-mail",
                      prefixIcon: Icons.person_outline,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: 24),

                    // Campo de Senha
                    PremiumTextField(
                      label: "Senha",
                      controller: _passwordController,
                      hintText: "••••••••",
                      prefixIcon: Icons.lock_outline,
                      obscureText: true,
                      textInputAction: TextInputAction.done,
                    ),
                    
                    // Link de Recuperação
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => _showRecuperarSenha(context, colorScheme),
                        style: TextButton.styleFrom(
                          foregroundColor: colorScheme.primary,
                        ),
                        child: const Text("Esqueceu a senha?"),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Botão Principal (Componente do seu Core)
                    PremiumPrimaryButton(
                      label: "ACESSAR SISTEMA",
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          // Lógica de Autenticação
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}