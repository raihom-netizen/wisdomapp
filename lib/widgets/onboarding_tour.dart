import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';

const String _kOnboardingTourDone = 'onboarding_tour_done';

class OnboardingTour extends StatefulWidget {
  final Widget child;
  final VoidCallback? onComplete;

  const OnboardingTour({
    super.key,
    required this.child,
    this.onComplete,
  });

  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_kOnboardingTourDone) ?? false);
  }

  static Future<void> markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingTourDone, true);
  }

  @override
  State<OnboardingTour> createState() => _OnboardingTourState();
}

class _OnboardingTourState extends State<OnboardingTour> {
  int _step = 0;
  bool _visible = false;

  static const _steps = [
    (Icons.home_rounded, 'Início', 'Dica financeira do dia com base na Bíblia e resumo do seu financeiro.'),
    (Icons.account_balance_wallet_rounded, 'Financeiro', 'Lançamentos, contas, metas e relatórios em um só lugar.'),
    (Icons.calendar_month_rounded, 'Agenda', 'Compromissos no calendário com lembretes configuráveis.'),
    (Icons.ondemand_video_rounded, 'Cursos', 'Conteúdos de formação financeira com princípios bíblicos.'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndShow());
  }

  Future<void> _checkAndShow() async {
    final show = await OnboardingTour.shouldShow();
    if (mounted && show) {
      setState(() => _visible = true);
    }
  }

  Future<void> _next() async {
    HapticFeedback.lightImpact();
    if (_step < _steps.length - 1) {
      setState(() => _step++);
    } else {
      await OnboardingTour.markDone();
      if (mounted) {
        setState(() => _visible = false);
        widget.onComplete?.call();
      }
    }
  }

  Future<void> _skip() async {
    HapticFeedback.lightImpact();
    await OnboardingTour.markDone();
    if (mounted) {
      setState(() => _visible = false);
      widget.onComplete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_visible)
          Material(
            color: Colors.black54,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Card(
                      elevation: 8,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                _steps[_step].$1,
                                size: 56,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              _steps[_step].$2,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _steps[_step].$3,
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey.shade700,
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                _steps.length,
                                (i) => Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  width: i == _step ? 24 : 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: i == _step ? AppColors.primary : Colors.grey.shade300,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: _skip,
                                  child: const Text('Pular'),
                                ),
                                const SizedBox(width: 12),
                                FilledButton(
                                  onPressed: _next,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                  ),
                                  child: Text(_step < _steps.length - 1 ? 'Próximo' : 'Concluir'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
