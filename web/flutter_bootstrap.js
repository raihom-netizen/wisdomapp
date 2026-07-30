{{flutter_js}}
{{flutter_build_config}}

// Boot único do Flutter (evita load duplicado → initializeFirestore chamado 2x).
// CanvasKit "full" local: renderização estável em Safari iOS/PWA sem CDN.
_flutter.loader.load({
  serviceWorkerSettings: null,
  config: {
    canvasKitVariant: "full",
    canvasKitBaseUrl: "/canvaskit/"
  }
});
