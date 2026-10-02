import 'package:flutter/material.dart';

import '../theme/theme_context.dart';

/// De onde vem o arquivo: câmera, galeria (print) ou arquivo (PDF/OFX/CSV).
enum ImportarRapidoOrigem { camera, galeria, arquivo }

/// Card compacto «ler por imagem ou PDF» com os três atalhos à vista.
///
/// Antes era uma faixa que abria um menu para só então escolher câmera,
/// galeria ou arquivo — dois toques e uma tela a mais. Aqui o toque já vai
/// direto. Continua baixo (título + uma linha de botões) para não empurrar o
/// formulário ou a lista para fora da tela.
class ImportarRapidoCard extends StatelessWidget {
  const ImportarRapidoCard({
    super.key,
    required this.titulo,
    required this.subtitulo,
    required this.onEscolher,
    this.rotuloArquivo = 'PDF / arquivo',
    this.iconeArquivo = Icons.picture_as_pdf_rounded,
    this.cor,
    this.ocupado = false,
    this.textoOcupado = 'Lendo o arquivo…',
    this.margem = const EdgeInsets.fromLTRB(12, 8, 12, 4),
  });

  final String titulo;
  final String subtitulo;
  final void Function(ImportarRapidoOrigem origem) onEscolher;
  final String rotuloArquivo;
  final IconData iconeArquivo;

  /// Cor de destaque (padrão: o neón do app).
  final Color? cor;
  final bool ocupado;
  final String textoOcupado;
  final EdgeInsets margem;

  @override
  Widget build(BuildContext context) {
    final ctx = context;
    final c = cor ?? ctx.appNeon;
    return Padding(
      padding: margem,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: ctx.appSurface,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(c.withValues(alpha: 0.22), ctx.appSurface),
              Color.alphaBlend(const Color(0xFFDB2777).withValues(alpha: 0.08), ctx.appSurface),
            ],
          ),
          border: Border.all(color: c.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(color: c.withValues(alpha: 0.10), blurRadius: 14, offset: const Offset(0, 4)),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [c, Color.lerp(c, Colors.black, 0.25)!],
                  ),
                ),
                child: ocupado
                    ? const Padding(
                        padding: EdgeInsets.all(9),
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.document_scanner_rounded, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ocupado ? textoOcupado : titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: ctx.appTextPrimary),
                    ),
                    Text(
                      ocupado ? 'Isso leva um instante.' : subtitulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: ctx.appTextMuted),
                    ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 9),
            Row(children: [
              _botao(ctx, const Color(0xFFF97316), Icons.photo_camera_rounded, 'Câmera', ImportarRapidoOrigem.camera),
              const SizedBox(width: 6),
              _botao(ctx, const Color(0xFFDB2777), Icons.image_rounded, 'Galeria', ImportarRapidoOrigem.galeria),
              const SizedBox(width: 6),
              _botao(ctx, const Color(0xFF2563EB), iconeArquivo, rotuloArquivo, ImportarRapidoOrigem.arquivo),
            ]),
          ],
        ),
      ),
    );
  }

  /// Cada atalho tem a sua cor (câmera laranja, galeria rosa, arquivo azul)
  /// em degradê com texto branco — dá para achar pelo olho, sem ler.
  Widget _botao(BuildContext ctx, Color c, IconData icone, String rotulo, ImportarRapidoOrigem o) {
    return Expanded(
      child: Opacity(
        opacity: ocupado ? 0.5 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(colors: [c, Color.lerp(c, Colors.black, 0.22)!]),
            boxShadow: [BoxShadow(color: c.withValues(alpha: 0.30), blurRadius: 8, offset: const Offset(0, 3))],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: ocupado ? null : () => onEscolher(o),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icone, size: 17, color: Colors.white),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        rotulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
