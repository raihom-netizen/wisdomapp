/// Política de visualização — conteúdo só dentro do módulo (sem baixar/compartilhar).
class CourseMediaViewPolicy {
  CourseMediaViewPolicy._();

  /// Atributo HTML5 `controlsList` — oculta «Baixar» no menu nativo do vídeo.
  static const videoControlsList = 'nodownload noremoteplayback';

  static const videoContextMenuBlockJs = '''
document.addEventListener('contextmenu', function(e) {
  var t = e.target;
  if (t && (t.tagName === 'VIDEO' || t.tagName === 'IMG')) e.preventDefault();
}, true);
''';
}
