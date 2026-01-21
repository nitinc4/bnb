// lib/api/client_helper.dart
import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class AppConfig {
  static String magentoBaseUrl = "https://buynutbolts.com";
  static String consumerKey = "";
  static String consumerSecret = "";
  static String accessToken = "";
  static String accessTokenSecret = "";
  static String geminiApiKey = "";
  static String rfqUrl = "";
  static String rfqToken = "";

  static bool get isLoaded => consumerKey.isNotEmpty;
}

// verification phrase (Must match server)
const String _verificationPhrase = "BNB_SECURE_ACCESS";
// Vercel Server URL
const String _serverUrl = "https://secuserv-7w95.vercel.app";

String _getCurrentDateString() {
  final now = DateTime.now();
  final year = now.year.toString();
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  return '$year$month$day';
}

String _generateSecureHeader() {
  final currentDate = _getCurrentDateString();

  // 1. Use the Date itself as the Key (Padded to 32 bytes)
  final keyString = currentDate.padRight(32, ' ').substring(0, 32);
  final key = encrypt.Key.fromUtf8(keyString);

  // 2. Generate a random IV
  final iv = encrypt.IV.fromLength(16);

  // 3. Encrypt the Verification Phrase
  final encrypter = encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
  final encrypted = encrypter.encrypt(_verificationPhrase, iv: iv);

  // 4. Return "IV:Ciphertext"
  return '${iv.base64}:${encrypted.base64}';
}

Future<void> fetchAndSetConfig() async {
  try {
    final secureHeader = _generateSecureHeader();
    
    debugPrint("Fetching configuration from $_serverUrl...");

    final response = await http.get(
      Uri.parse('$_serverUrl/api/get-keys'),
      headers: {
        'x-secure-date': secureHeader,
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final keys = data['keys'];
        
        AppConfig.magentoBaseUrl = keys['magentoBaseUrl'] ?? "https://buynutbolts.com";
        AppConfig.consumerKey = keys['consumerKey'] ?? "";
        AppConfig.consumerSecret = keys['consumerSecret'] ?? "";
        AppConfig.accessToken = keys['accessToken'] ?? "";
        AppConfig.accessTokenSecret = keys['accessTokenSecret'] ?? "";
        AppConfig.geminiApiKey = keys['geminiApiKey'] ?? "";
        AppConfig.rfqUrl = keys['rfqUrl'] ?? "https://rfq.buynutbolts.com/api/rfq_ingest.php";
        AppConfig.rfqToken = keys['rfqToken'] ?? "";

        debugPrint("Configuration loaded successfully.");
      }
    } else {
      debugPrint("Failed to load config: ${response.statusCode} - ${response.body}");
    }
  } catch (e) {
    debugPrint("Error fetching config: $e");
    // Error handeler
  }
}

/// Sends a secure email via the server's nodemailer integration.
/// Used for OTP verification and Fallback support tickets.
Future<bool> sendSecureEmail({
  required String to,
  required String subject,
  required String text,
}) async {
  try {
    final secureHeader = _generateSecureHeader();
    debugPrint("Sending secure email to $to...");

    final body = {
      'to': to,
      'subject': subject,
      'text': text,
    };

    final response = await http.post(
      Uri.parse('$_serverUrl/api/send-email'),
      headers: {
        'x-secure-date': secureHeader,
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['success'] == true;
    } else {
      debugPrint("Email failed: ${response.statusCode} - ${response.body}");
      return false;
    }
  } catch (e) {
    debugPrint("Error sending email: $e");
    return false;
  }
}