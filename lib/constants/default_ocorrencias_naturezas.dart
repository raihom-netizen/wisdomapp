/// Naturezas padrão para ocorrências (produtividade) — Anexo I da Portaria 24ª CIPM.
/// O usuário pode editar e adicionar conforme sua unidade.

class OcorrenciaNatureza {
  final String id;
  final String label;
  final int pontos;

  const OcorrenciaNatureza({
    required this.id,
    required this.label,
    required this.pontos,
  });

  Map<String, dynamic> toMap() => {'id': id, 'label': label, 'pontos': pontos};

  static OcorrenciaNatureza fromMap(Map<String, dynamic> m) => OcorrenciaNatureza(
        id: (m['id'] ?? '').toString(),
        label: (m['label'] ?? '').toString(),
        pontos: (m['pontos'] is int) ? m['pontos'] as int : int.tryParse((m['pontos'] ?? '0').toString()) ?? 0,
      );
}

const List<OcorrenciaNatureza> kDefaultOcorrenciasNaturezas = [
  OcorrenciaNatureza(
    id: '01',
    label: 'Estatuto do Desarmamento (Lei nº 10.826/2003)',
    pontos: 30,
  ),
  OcorrenciaNatureza(
    id: '02',
    label: 'Flagrante de Homicídio, Roubo e Extorsão',
    pontos: 12,
  ),
  OcorrenciaNatureza(
    id: '03',
    label: 'Lei de Entorpecentes – Tráfico (Art. 33)',
    pontos: 10,
  ),
  OcorrenciaNatureza(
    id: '04',
    label: 'Foragido Recapturado',
    pontos: 8,
  ),
  OcorrenciaNatureza(
    id: '05',
    label: 'Flagrante de Furto, Receptação e outros',
    pontos: 4,
  ),
  OcorrenciaNatureza(
    id: '06',
    label: 'Flagrante de Crimes de Trânsito',
    pontos: 2,
  ),
  OcorrenciaNatureza(
    id: '07',
    label: 'TCO/BOC (exceto desacato e Art. 28)',
    pontos: 2,
  ),
];
