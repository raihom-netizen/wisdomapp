/// Não aplica (sem dart:html).
bool startPluggyConnectInWebPopup(
  String connectToken,
  bool includeSandbox, {
  required void Function(Map<String, dynamic>?) onDone,
}) {
  onDone(null);
  return false;
}
