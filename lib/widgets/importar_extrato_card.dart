import 'package:flutter/material.dart';

import '../models/finance_account.dart';
import '../screens/extrato_preview_page.dart';
import '../services/extrato_import_service.dart';
import '../services/finance_accounts_service.dart';
import '../services/finance_advanced_settings_service.dart';
import '../theme/theme_context.dart';
import '../utils/extrato_import.dart';
import 'importar_rapido_card.dart';

/// Card «Importar extrato ou fatura» com Câmera / Galeria / Arquivo à vista.
///
/// Porte do card do Controle Total. Ler, classificar e achar duplicata
/// acontecem ANTES de abrir a pré-visualização; nada é gravado sem o usuário
/// tocar em «Gravar».
class ImportarExtratoCard extends StatefulWidget {
  const ImportarExtratoCard({
    super.key,
    required this.uid,
    this.titulo = 'Importar extrato ou fatura',
    this.subtitulo = 'OFX, CSV, PDF ou print do banco',
    this.onImportado,
    this.origem = 'extrato_import',
    this.conta,
  });

  final String uid;

  /// Conta de destino fixa. Nula = a conta padrão do usuário (ou ele escolhe).
  final FinanceAccount? conta;
  final String titulo;
  final String subtitulo;

  /// Quantos lançamentos entraram — para a tela recarregar a lista.
  final void Function(int quantidade)? onImportado;

  /// Marca a origem no lançamento (campo `source`).
  final String origem;

  @override
  State<ImportarExtratoCard> createState() => _ImportarExtratoCardState();
}

class _ImportarExtratoCardState extends State<ImportarExtratoCard> {
  bool _ocupado = false;

  @override
  Widget build(BuildContext context) {
    return ImportarRapidoCard(
      titulo: widget.titulo,
      subtitulo: widget.subtitulo,
      rotuloArquivo: 'OFX · CSV · PDF',
      iconeArquivo: Icons.insert_drive_file_rounded,
      ocupado: _ocupado,
      onEscolher: _importar,
    );
  }

  Future<void> _importar(ImportarRapidoOrigem origem) async {
    if (!mounted) return;
    await importarExtrato(
      context: context,
      uid: widget.uid,
      origem: widget.origem,
      conta: widget.conta,
      de: switch (origem) {
        ImportarRapidoOrigem.camera => ExtratoOrigemArquivo.camera,
        ImportarRapidoOrigem.galeria => ExtratoOrigemArquivo.galeria,
        ImportarRapidoOrigem.arquivo => ExtratoOrigemArquivo.arquivo,
      },
      onOcupado: (v) {
        if (mounted) setState(() => _ocupado = v);
      },
      onImportado: widget.onImportado,
    );
  }
}

/// Escolhe o arquivo e segue para [importarExtratoDeArquivo].
Future<void> importarExtrato({
  required BuildContext context,
  required String uid,
  ExtratoOrigemArquivo de = ExtratoOrigemArquivo.arquivo,
  String origem = 'extrato_import',
  FinanceAccount? conta,
  void Function(bool ocupado)? onOcupado,
  void Function(int quantidade)? onImportado,
}) async {
  ExtratoArquivo? arquivo;
  try {
    arquivo = switch (de) {
      ExtratoOrigemArquivo.camera => await ExtratoImportService.fotografar(),
      ExtratoOrigemArquivo.galeria => await ExtratoImportService.escolherImagem(),
      ExtratoOrigemArquivo.arquivo => await ExtratoImportService.escolherArquivo(),
    };
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não consegui abrir o arquivo: $e')),
      );
    }
    return;
  }
  if (arquivo == null || !context.mounted) return;
  await importarExtratoDeArquivo(
    context: context,
    uid: uid,
    arquivo: arquivo,
    origem: origem,
    conta: conta,
    onOcupado: onOcupado,
    onImportado: onImportado,
  );
}

/// O fluxo a partir de um arquivo que já está em mãos.
Future<void> importarExtratoDeArquivo({
  required BuildContext context,
  required String uid,
  required ExtratoArquivo arquivo,
  String origem = 'extrato_import',
  FinanceAccount? conta,
  void Function(bool ocupado)? onOcupado,
  void Function(int quantidade)? onImportado,
}) async {
  final usaDialogo = onOcupado == null;
  var dialogoAberto = false;
  void ocupado(bool v) {
    if (!usaDialogo) {
      onOcupado(v);
      return;
    }
    if (v && !dialogoAberto && context.mounted) {
      dialogoAberto = true;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _LendoDialogo(),
      );
    } else if (!v && dialogoAberto && context.mounted) {
      dialogoAberto = false;
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  ocupado(true);
  ExtratoLote? lote;
  var texto = '';
  String? erro;
  try {
    texto = await ExtratoImportService.extrairTexto(arquivo);
    if (texto.trim().isNotEmpty) {
      lote = extratoInterpretar(texto, nomeArquivo: arquivo.nome);
      if (lote != null) {
        await ExtratoImportService.classificar(uid, lote);
        await ExtratoImportService.marcarDuplicatas(uid, lote);
      }
    }
  } catch (e) {
    erro = '$e';
  } finally {
    ocupado(false);
  }
  if (!context.mounted) return;

  void aviso(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  if (erro != null) {
    aviso('Não consegui ler o arquivo: $erro');
    return;
  }
  if (texto.trim().isEmpty) {
    aviso('Não saiu texto legível desse arquivo. Um print mais nítido, sem '
        'cortar os valores, costuma resolver.');
    return;
  }
  if (lote == null) {
    // No Controle Total este caso virava «comprovante único» (leitura por IA
    // no servidor). No WisdomApp essa função não existe: só extrato/fatura.
    aviso('Li o arquivo, mas não achei uma lista de lançamentos (extrato ou '
        'fatura). Para um recibo avulso, lance pelo «+» do Financeiro.');
    return;
  }

  // A conta do card aberto manda; fora dele, a padrão; sem padrão, escolher.
  FinanceAccount? alvo = conta;
  if (alvo == null) {
    final contas = await FinanceAccountsService().listOnce(uid);
    final padraoId =
        await FinanceAdvancedSettingsService().getDefaultFinanceAccountId(uid) ?? '';
    for (final c in contas) {
      if (c.id == padraoId) {
        alvo = c;
        break;
      }
    }
    if (alvo == null && contas.length == 1) alvo = contas.first;
    if (alvo == null && contas.isNotEmpty && context.mounted) {
      alvo = await _escolherConta(context, contas);
      if (alvo == null) return;
    }
  }
  if (!context.mounted) return;
  if (alvo == null) {
    aviso('Cadastre uma conta no Financeiro antes de importar o extrato.');
    return;
  }

  final categorias = await ExtratoImportService.categoriasParaEscolha(uid);
  if (!context.mounted) return;
  final destino = alvo;

  final confirmado = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ExtratoPreviewPage(
        lote: lote!,
        categoriasDespesa: categorias.despesa,
        categoriasReceita: categorias.receita,
        contaNome: destino.displayName,
        cartao: destino.isCardProduct,
        onConfirmar: (marcados, ehFatura) async {
          await ExtratoImportService.gravar(
            uid: uid,
            itens: marcados,
            contaId: destino.id,
            origem: origem,
            faturaDeCartao: ehFatura && destino.isCardProduct,
            diaFechamento: destino.statementClosingDay,
          );
          onImportado?.call(marcados.length);
        },
      ),
    ),
  );

  if (confirmado == true && context.mounted) {
    aviso('Lançamentos importados.');
  }
}

Future<FinanceAccount?> _escolherConta(
  BuildContext context,
  List<FinanceAccount> contas,
) {
  return showModalBottomSheet<FinanceAccount>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: ctx.appSheetDecoration(),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(
                'Para qual conta vai o extrato?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: ctx.appTextPrimary,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: contas
                    .map((c) => ListTile(
                          leading: Icon(
                            c.isCardProduct
                                ? Icons.credit_card_rounded
                                : Icons.account_balance_rounded,
                            color: ctx.appTextSecondary,
                          ),
                          title: Text(
                            c.displayName,
                            style: TextStyle(color: ctx.appTextPrimary),
                          ),
                          onTap: () => Navigator.pop(ctx, c),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

class _LendoDialogo extends StatelessWidget {
  const _LendoDialogo();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.appSurface,
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'Lendo o arquivo e separando os lançamentos…',
              style: TextStyle(fontSize: 14, color: context.appTextPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
