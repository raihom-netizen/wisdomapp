// Service Worker: recebe push (Escala/Agenda) e mostra notificação na tela do celular (app fechado ou aberto)
self.addEventListener('push', function(event) {
  var data = { title: 'WISDOMAPP', body: '', url: '/' };
  if (event.data) {
    try {
      var parsed = event.data.json();
      if (parsed.title) data.title = parsed.title;
      if (parsed.body) data.body = parsed.body;
      if (parsed.url) data.url = parsed.url;
    } catch (e) {
      data.body = event.data.text();
    }
  }

  var options = {
    body: data.body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    vibrate: [200, 100, 200],
    data: { url: data.url }
  };

  event.waitUntil(
    self.registration.showNotification(data.title, options)
  );
});

// Abre o app na escala ou agenda quando o usuário toca na notificação
self.addEventListener('notificationclick', function(event) {
  event.notification.close();
  var url = event.notification.data && event.notification.data.url ? event.notification.data.url : '/';
  event.waitUntil(
    clients.openWindow(url)
  );
});
