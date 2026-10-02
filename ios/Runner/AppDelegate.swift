import Flutter
import UIKit
import UserNotifications

// Despertador (soneca): mesmos ids do app (notification_soneca_service.dart) e
// do servidor (functions/agenda_soneca.js) — padrão do Controle Total.
private let sonecaCategoriaId = "CT_SONECA"
private let sonecaAcaoAdiar3 = "ct_adiar_3"
private let sonecaAcaoAdiar5 = "ct_adiar_5"
private let sonecaAcaoEncerrar = "ct_encerrar"

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
      registrarCategoriaSoneca()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  /// Banner/som na tela com app aberto (FCM + flutter_local_notifications).
  @available(iOS 10.0, *)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  // MARK: - Despertador (soneca) dos avisos

  /// Botões do push com `aps.category = CT_SONECA` (enviado pelo servidor).
  /// Soma à lista existente — não apaga categorias de outros plugins.
  @available(iOS 10.0, *)
  private func registrarCategoriaSoneca() {
    let adiar3 = UNNotificationAction(identifier: sonecaAcaoAdiar3, title: "⏰ Adiar 3 min", options: [])
    let adiar5 = UNNotificationAction(identifier: sonecaAcaoAdiar5, title: "⏰ Adiar 5 min", options: [])
    let encerrar = UNNotificationAction(identifier: sonecaAcaoEncerrar, title: "✔️ Encerrar", options: [.destructive])
    let categoria = UNNotificationCategory(
      identifier: sonecaCategoriaId,
      actions: [adiar3, adiar5, encerrar],
      intentIdentifiers: [],
      options: []
    )
    let center = UNUserNotificationCenter.current()
    center.getNotificationCategories { atuais in
      var todas = atuais.filter { $0.identifier != sonecaCategoriaId }
      todas.insert(categoria)
      center.setNotificationCategories(todas)
    }
  }

  /// Monta a chamada a `ctSonecaAcao` com o token que veio no push.
  private func pedidoSoneca(info: [AnyHashable: Any], acao: String) -> URLRequest? {
    guard (info["soneca"] as? String) == "1",
          let urlStr = info["sonecaUrl"] as? String, urlStr.hasPrefix("https://"),
          let url = URL(string: urlStr),
          let uid = info["sonecaUid"] as? String,
          let aviso = info["sonecaAvisoId"] as? String,
          let token = info["sonecaToken"] as? String else { return nil }
    var corpo: [String: Any] = ["u": uid, "a": aviso, "t": token]
    switch acao {
    case sonecaAcaoAdiar3: corpo["acao"] = "adiar"; corpo["min"] = 3
    case sonecaAcaoAdiar5: corpo["acao"] = "adiar"; corpo["min"] = 5
    default: corpo["acao"] = "encerrar"
    }
    var req = URLRequest(url: url, timeoutInterval: 15)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: corpo)
    return req
  }

  /// Botão do despertador: resolve aqui (o app pode estar fechado) e só
  /// devolve o controle ao iOS quando a chamada termina. Toque no corpo do
  /// aviso também encerra as repetições e segue para o Flutter abrir a tela.
  @available(iOS 10.0, *)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let info = response.notification.request.content.userInfo
    let acao = response.actionIdentifier
    let ehBotao = [sonecaAcaoAdiar3, sonecaAcaoAdiar5, sonecaAcaoEncerrar].contains(acao)
    if ehBotao, let pedido = pedidoSoneca(info: info, acao: acao) {
      URLSession.shared.dataTask(with: pedido) { _, _, _ in
        DispatchQueue.main.async { completionHandler() }
      }.resume()
      return
    }
    if acao == UNNotificationDefaultActionIdentifier,
       let pedido = pedidoSoneca(info: info, acao: sonecaAcaoEncerrar) {
      URLSession.shared.dataTask(with: pedido).resume()
    }
    super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
  }
}
