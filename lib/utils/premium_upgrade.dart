import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../screens/escolha_plano_page.dart';
import '../services/ios_payments_gate.dart';

/// Exibe aviso de recurso Premium e oferece ir para a tela de planos.
void mostrarAvisoUpgrade(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      icon: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2962FF), Color(0xFF6D4DFF)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6D4DFF).withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(Icons.workspace_premium_rounded,
            color: Colors.white, size: 32),
      ),
      title: const Text('Recurso Premium', textAlign: TextAlign.center),
      content: const Text(
        'Assine o plano para ter acesso total: Financeiro, Agenda, Cursos, relatórios PDF, comprovantes e backup. App limpo, sem propagandas indesejáveis.',
        textAlign: TextAlign.center,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Depois'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2962FF),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () async {
            Navigator.of(ctx).pop();
            if (IosPaymentsGate.shouldHidePayments &&
                IosPaymentsGate.isIosNative) {
              await IosPaymentsGate.openReaderPlansInSafari(
                  source: 'premium_upgrade_dialog');
              return;
            }
            if (!context.mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const EscolhaPlanoPage(),
              ),
            );
          },
          icon: const Icon(Icons.rocket_launch_rounded, size: 18),
          label: const Text('Ver planos'),
        ),
      ],
    ),
  );
}

/// Exibe aviso de licença vencida: bloqueio total até renovar.
void mostrarAvisoLicencaVencida(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      icon: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEF4444), Color(0xFFF97316)],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFEF4444).withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(Icons.lock_clock_rounded,
            color: Colors.white, size: 32),
      ),
      title: const Text('Licença vencida',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.w800)),
      content: const Text(
        'Sua licença está vencida. Você pode visualizar os módulos, mas não pode lançar, editar ou remover dados em Financeiro, Agenda, Cursos, Relatórios, Anotações e Configurações.\n\nRenove agora para voltar a usar o WISDOMAPP por completo.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Depois'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFEF4444),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: () async {
            Navigator.of(ctx).pop();
            if (IosPaymentsGate.shouldHidePayments &&
                IosPaymentsGate.isIosNative) {
              await IosPaymentsGate.openReaderPlansInSafari(
                  source: 'premium_license_expired_dialog');
              return;
            }
            if (!context.mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const EscolhaPlanoPage(),
              ),
            );
          },
          icon: const Icon(Icons.autorenew_rounded, size: 18),
          label: const Text('Renovar licença'),
        ),
      ],
    ),
  );
}

/// Escolhe aviso conforme status da licença: vencida → renovar; inativa → plano premium.
void mostrarAvisoSeLicencaInativa(BuildContext context, UserProfile profile) {
  if (profile.isLicenseExpired) {
    mostrarAvisoLicencaVencida(context);
  } else {
    mostrarAvisoUpgrade(context);
  }
}
