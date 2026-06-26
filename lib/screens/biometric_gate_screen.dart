import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/biometric_auth_service.dart';
import '../constants/app_business_rules.dart';

/// Tela de bloqueio por biometria: exibe ao abrir o app quando biometria está ativa (mobile).
class BiometricGateScreen extends StatefulWidget {
  final String uid;
  final Widget child;
  /// Chamado quando o usuário escolhe desativar o acesso por digital e entrar mesmo assim (evita ficar travado no APK).
  final VoidCallback? onDisableAndContinue;

  const BiometricGateScreen({super.key, required this.uid, required this.child, this.onDisableAndContinue});

  @override
  State<BiometricGateScreen> createState() => _BiometricGateScreenState();
}

class _BiometricGateScreenState extends State<BiometricGateScreen> with WidgetsBindingObserver {
  bool _authenticated = false;
  bool _loading = true;
  String? _error;
  DateTime? _lastBackgroundTime;
  bool _resuming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) {
      setState(() {
        _authenticated = true;
        _loading = false;
      });
      return;
    }
    // Abertura a frio: sessão Firebase já no disco — painel imediato (também offline).
    // Digital/rosto só ao voltar do background (multitarefa / ícone), ver [didChangeAppLifecycleState].
    setState(() {
      _authenticated = true;
      _loading = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
    if (state == AppLifecycleState.paused) {
      _lastBackgroundTime = DateTime.now();
      // Ao sair do app (Home / multitarefa), exige digital de novo ao voltar — alinhado a “abrir o ícone”.
      if (!_loading) {
        if (mounted) setState(() => _authenticated = false);
      }
      _resuming = false;
    } else if (state == AppLifecycleState.resumed) {
      if (!_authenticated && !_loading) {
        if (mounted) setState(() => _resuming = true);
        _tryAuthenticate();
      } else if (_authenticated &&
          _lastBackgroundTime != null &&
          DateTime.now().difference(_lastBackgroundTime!).inMinutes >= AppBusinessRules.inactivityTimeoutMinutes) {
        if (mounted) {
          setState(() {
            _authenticated = false;
            _resuming = true;
          });
          _tryAuthenticate();
        }
      } else {
        if (mounted) setState(() {});
      }
    }
  }

  Future<void> _tryAuthenticate() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ok = await authenticateWithBiometric();
      if (!mounted) return;
      setState(() {
        _authenticated = ok;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Fallback para senha. **NÃO** desloga: a sessão Firebase Auth fica
  /// preservada para que o usuário continue logado mesmo offline. Apenas
  /// entra direto no app quando o user prefere pular a biometria.
  ///
  /// Antes esse método chamava `AuthService().signOut()` e enviava pra
  /// tela de login — o que zerava a sessão e exigia internet pra entrar
  /// de novo. Pioneirismo off→on: uma vez logado, segue logado.
  Future<void> _usePassword() async {
    if (!mounted) return;
    setState(() {
      _authenticated = true;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_authenticated) return widget.child;

    if (_resuming && _loading) {
      const bg = Color(0xFF1A237E);
      return Scaffold(
        backgroundColor: bg,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          color: bg,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1A237E), Color(0xFF2D5BFF), Color(0xFF0D9488)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 20),
                    Text(
                      'Verificando acesso...',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    const gateBg = Color(0xFFE0EAFC);
    return Scaffold(
      backgroundColor: gateBg,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: gateBg,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFE0EAFC), Color(0xFFCFDEF3)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.fingerprint_rounded,
                  size: 100,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Acesso por digital ou facial',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A237E),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Toque no ícone ou use sua senha para acessar o WISDOMAPP.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, fontSize: 16),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 40),
                if (_loading)
                  const CircularProgressIndicator()
                else
                  FilledButton.icon(
                    onPressed: _tryAuthenticate,
                    icon: const Icon(Icons.fingerprint_rounded, size: 28),
                    label: const Text('Usar digital ou facial'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2962FF),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                const SizedBox(height: 20),
                TextButton.icon(
                  onPressed: _usePassword,
                  icon: const Icon(Icons.lock_outline_rounded, size: 20),
                  label: const Text('Entrar com senha'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF1A237E),
                  ),
                ),
                if (widget.onDisableAndContinue != null) ...[
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    onPressed: _disableAndContinue,
                    icon: const Icon(Icons.fingerprint_rounded, size: 20),
                    label: const Text('Desativar digital e entrar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white70,
                      foregroundColor: const Color(0xFF1A237E),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }

  Future<void> _disableAndContinue() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desativar digital'),
        content: const Text(
          'Desativar acesso por digital nas próximas aberturas? Você pode reativar em Configurações.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Desativar e entrar')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await BiometricPreferences.setEnabled(false);
    if (!mounted) return;
    widget.onDisableAndContinue?.call();
  }
}
