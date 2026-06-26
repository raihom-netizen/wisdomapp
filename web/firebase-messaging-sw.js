// Service Worker para Web Push (FCM) — WISDOMAPP
importScripts('https://www.gstatic.com/firebasejs/9.0.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.0.0/firebase-messaging-compat.js');

const firebaseConfig = {
  apiKey: "AIzaSyDLm_BNjBptj5ribo0YGHQ9Nqd4l_Inl-4",
  authDomain: "wisdomapp-b9e98.firebaseapp.com",
  projectId: "wisdomapp-b9e98",
  storageBucket: "wisdomapp-b9e98.firebasestorage.app",
  messagingSenderId: "766524666378",
  appId: "1:766524666378:web:13900906f683df187f25f3"
};

firebase.initializeApp(firebaseConfig);

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Notificação recebida em background:', payload);

  const notificationTitle = payload?.notification?.title || "WISDOMAPP";
  const data = payload?.data || {};
  const channelKind = (data.channelKind || "").toString().toLowerCase();
  const iconUrl = "/icons/Icon-192.png";
  const bannerByKind = ["audiencia", "compromisso", "escala"].includes(channelKind)
    ? `/icons/push-banner-${channelKind}.png`
    : null;
  const richImage =
    bannerByKind ||
    payload?.notification?.image ||
    payload?.fcmOptions?.image ||
    null;

  const notificationOptions = {
    body: payload?.notification?.body || "",
    icon: iconUrl,
    badge: iconUrl,
    data: data,
    ...(richImage ? { image: richImage } : {}),
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});

self.addEventListener("notificationclick", function (event) {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) ? event.notification.data.url : "/";
  event.waitUntil(clients.openWindow(url));
});
