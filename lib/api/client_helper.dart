import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:http/http.dart' as http;

// The fixed verification phrase (Must match server)
const String _verificationPhrase = "BNB_SECURE_ACCESS";

String _getCurrentDateString() {
  final now = DateTime.now();
  final year = now.year.toString();
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  return '$year$month$day';
}

String generateSecureHeader() {
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

Future<Map<String, dynamic>> fetchApiKeys(String serverUrl) async {
  // No shared secret passed here anymore
  final secureHeader = generateSecureHeader();

  try {
    final response = await http.get(
      Uri.parse('$serverUrl/api/get-keys'),
      headers: {
        'x-secure-date': secureHeader,
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      final errorData = jsonDecode(response.body);
      throw Exception(errorData['message'] ?? 'Failed to fetch API keys');
    }

    final data = jsonDecode(response.body);
    return data['keys'];
  } catch (error) {
    print('Error fetching API keys: $error');
    rethrow;
  }
}

void main() async {
  const serverUrl = 'http://localhost:3000';

  try {
    print('Fetching keys using Date-Derived Encryption...');
    final keys = await fetchApiKeys(serverUrl);
    print('Successfully retrieved API keys: $keys');
  } catch (error) {
    print('Failed to retrieve API keys: $error');
  }
}