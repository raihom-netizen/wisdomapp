import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_colors.dart';
import '../widgets/app_logo.dart';

const String _kOnboardingDone = 'onboarding_done';

class OnboardingScreen extends StatelessWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  static Future<bool> shouldShow() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_kOnboardingDone) ?? false);
  }

  static Future<void> markDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboardingDone, true);
  }

  @override
  Widget build(BuildContext context) {
    return _OnboardingPageView(onComplete: onComplete);
  }
}

class _OnboardingPageView extends StatefulWidget {
  final VoidCallback onComplete;

  const _OnboardingPageView({required this.onComplete});

  @override
  State<_OnboardingPageView> createState() => _OnboardingPageViewState();
}

class _OnboardingPageViewState extends State<_OnboardingPageView> {
  final _controller = PageController();
  int _current = 0;

  static const _pages = [
    (
      Icons.account_balance_wallet_rounded,
      'Gestão financeira pessoal',
      'Controle despesas, receitas, metas e relatórios em um só lugar.',
    ),
    (
      Icons.calendar_month_rounded,
      'Agenda e lembretes',
      'Organize compromissos no calendário com avisos no celular e por e-mail.',
    ),
    (
      Icons.menu_book_rounded,
      'Sabedoria bíblica',
      'Dicas financeiras com base na Bíblia, cursos e app limpo — sem propagandas indesejáveis.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await OnboardingScreen.markDone();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.deepBlueDark, AppColors.deepBlue, AppColors.accent],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 24),
              const AppLogo(height: 56),
              const SizedBox(height: 8),
              Text(
                'WISDOMAPP',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withOpacity(0.95),
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _current = i),
                  itemCount: _pages.length,
                  itemBuilder: (context, i) {
                    final (icon, title, subtitle) = _pages[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white.withOpacity(0.2)),
                            ),
                            child: Icon(icon, size: 64, color: Colors.white),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            subtitle,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              height: 1.4,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  final sel = _current == i;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: sel ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: sel ? Colors.white : Colors.white.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      if (_current < _pages.length - 1) {
                        _controller.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        );
                      } else {
                        _finish();
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.deepBlueDark,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(_current < _pages.length - 1 ? 'Próximo' : 'Começar'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _finish,
                child: Text('Pular', style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
