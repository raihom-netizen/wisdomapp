import 'package:flutter/widgets.dart';

/// [StreamBuilder] que só recria a escuta quando [streamKey] muda.
///
/// `StreamBuilder(stream: ref.snapshots())` direto no `build` cria uma escuta
/// NOVA no Firestore a cada rebuild do pai (cancela a anterior e reabre):
/// leituras extras, «piscar» do conteúdo e, na Web, o assert
/// «Target ID already exists». Aqui o stream é criado uma vez e guardado no
/// estado; use o caminho do documento/consulta como [streamKey].
class KeyedStreamBuilder<T> extends StatefulWidget {
  const KeyedStreamBuilder({
    super.key,
    required this.streamKey,
    required this.create,
    required this.builder,
    this.initialData,
  });

  /// Identidade da consulta (ex.: `ref.path`). Mudou → nova escuta.
  final Object? streamKey;

  /// Cria o stream (chamado só na montagem e quando [streamKey] muda).
  final Stream<T> Function() create;

  final AsyncWidgetBuilder<T> builder;
  final T? initialData;

  @override
  State<KeyedStreamBuilder<T>> createState() => _KeyedStreamBuilderState<T>();
}

class _KeyedStreamBuilderState<T> extends State<KeyedStreamBuilder<T>> {
  late Stream<T> _stream;

  @override
  void initState() {
    super.initState();
    _stream = widget.create();
  }

  @override
  void didUpdateWidget(covariant KeyedStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamKey != widget.streamKey) {
      _stream = widget.create();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<T>(
      stream: _stream,
      initialData: widget.initialData,
      builder: widget.builder,
    );
  }
}
