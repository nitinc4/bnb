// lib/api/firebase_api.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'magento_api.dart'; // To send token to server

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("Handling a background message: ${message.messageId}");
}

class FirebaseApi {
  final _firebaseMessaging = FirebaseMessaging.instance;
  final MagentoAPI _magentoApi = MagentoAPI();

  // Initialize Notifications
  Future<void> initNotifications() async {
    // 1. Request Permission
    await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 2. Fetch Token
    final fcmToken = await _firebaseMessaging.getToken();
    debugPrint('FCM Token: $fcmToken');

    // 3. Handle Background Messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 4. Handle Foreground Messages (Optional: Show local notification)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      debugPrint('Message data: ${message.data}');

      if (message.notification != null) {
        debugPrint('Message also contained a notification: ${message.notification}');
        // You can use flutter_local_notifications here to show a banner if needed
      }
    });
  }

  // Send Token to Backend (Call this after Login)
  Future<void> syncTokenWithServer(String email) async {
    final token = await _firebaseMessaging.getToken();
    if (token != null) {
      await _magentoApi.registerDeviceToken(email, token);
    }
  }
}