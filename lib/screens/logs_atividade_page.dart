import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../utils/admin_responsive.dart';
import '../widgets/admin/admin_page_shell.dart';
import '../widgets/module_header_premium.dart';

class LogsAtividadePage extends StatelessWidget {
  final bool isMaster;

  /// Dentro do [AdminScreen]: sem Scaffold/AppBar próprios — full screen no painel.
  final bool embeddedInAdmin;

  const LogsAtividadePage({
    super.key,
    this.isMaster = false,
    this.embeddedInAdmin = false,
  });

  @override
  Widget build(BuildContext context) {
    final body = _LogsBody(isMaster: isMaster);
    if (embeddedInAdmin) {
      return body;
    }
    return Scaffold(
      backgroundColor: AdminPageShell.background,
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Voltar',
              )
            : null,
        title: const Text('Auditoria do Sistema'),
        elevation: 0,
      ),
      body: SafeArea(child: body),
    );
  }
}

class _LogsBody extends StatelessWidget {
  final bool isMaster;

  const _LogsBody({required this.isMaster});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('activity_logs')
          .orderBy('timestamp', descending: true)
          .limit(80)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: AdminPageShell.pagePadding(context, top: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline_rounded,
                      size: 48, color: Colors.orange.shade700),
                  const SizedBox(height: 12),
                  Text(
                    'Erro ao carregar logs: ${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final logs = snapshot.data!.docs;

        return ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: AdminPageShell.listPadding(context, top: 8),
          itemCount: logs.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ModuleHeaderPremium(
                  title: 'Logs de atividade',
                  icon: Icons.history_rounded,
                  subtitle: isMaster
                      ? 'Auditoria do sistema (últimos 80 registos).'
                      : 'Registos recentes de ações no painel.',
                ),
              );
            }
            final log = logs[index - 1].data() as Map<String, dynamic>;
            final date = (log['timestamp'] as Timestamp?)?.toDate() ??
                DateTime.now();
            return _LogCard(log: log, date: date);
          },
        );
      },
    );
  }
}

class _LogCard extends StatelessWidget {
  final Map<String, dynamic> log;
  final DateTime date;

  const _LogCard({required this.log, required this.date});

  @override
  Widget build(BuildContext context) {
    final modulo = (log['modulo'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AdminResponsive.cardRadius),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LogIcon(modulo: modulo),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (log['acao'] ?? '').toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Por: ${log['adminEmail'] ?? '—'}',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
                if ((log['detalhes'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    log['detalhes'].toString(),
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            DateFormat('dd/MM HH:mm').format(date),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogIcon extends StatelessWidget {
  final String modulo;

  const _LogIcon({required this.modulo});

  @override
  Widget build(BuildContext context) {
    IconData iconData = Icons.history_rounded;
    Color color = Colors.blue;
    if (modulo == 'Financeiro') {
      iconData = Icons.attach_money_rounded;
      color = Colors.green;
    } else if (modulo == 'Escalas') {
      iconData = Icons.calendar_month_rounded;
      color = Colors.orange;
    } else if (modulo == 'Admin') {
      iconData = Icons.admin_panel_settings_rounded;
      color = Colors.purple;
    }
    return CircleAvatar(
      radius: 22,
      backgroundColor: color.withValues(alpha: 0.12),
      child: Icon(iconData, color: color, size: 22),
    );
  }
}
