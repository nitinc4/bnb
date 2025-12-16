import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class MagentoOAuthClient {
  final String baseUrl;
  final String consumerKey;
  final String consumerSecret;
  final String token;
  final String tokenSecret;

  MagentoOAuthClient({
    required this.baseUrl,
    required this.consumerKey,
    required this.consumerSecret,
    required this.token,
    required this.tokenSecret,
  });

  String _generateNonce([int length = 16]) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    return List.generate(length, (_) => chars[rand.nextInt(chars.length)])
        .join();
  }

  String _encode(String input) {
    return Uri.encodeQueryComponent(input)
        .replaceAll('%20', '+')
        .replaceAll('%7E', '~');
  }

  String _buildAuthHeader({
    required String method,
    required String url,
    Map<String, String>? queryParams,
  }) {
    final nonce = _generateNonce();
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

    final oauthParams = {
      'oauth_consumer_key': consumerKey,
      'oauth_token': token,
      'oauth_nonce': nonce,
      'oauth_timestamp': timestamp,
      'oauth_signature_method': 'HMAC-SHA256',
      'oauth_version': '1.0',
    };

    final sigParams = {...oauthParams};
    if (queryParams != null) sigParams.addAll(queryParams);

    final sortedKeys = sigParams.keys.toList()..sort();
    final paramStr = sortedKeys
        .map((k) => '${_encode(k)}=${_encode(sigParams[k]!)}')
        .join('&');

    final methodUpper = method.toUpperCase();
    final baseUri = Uri.parse(url);
    final normUrl = '${baseUri.scheme}://${baseUri.host}${baseUri.path}';

    final baseString = '$methodUpper&${_encode(normUrl)}&${_encode(paramStr)}';
    final signingKey = '${_encode(consumerSecret)}&${_encode(tokenSecret)}';

    final hmacSha256 = Hmac(sha256, utf8.encode(signingKey));
    final signatureBytes = hmacSha256.convert(utf8.encode(baseString)).bytes;
    final signature = base64Encode(signatureBytes);

    final headerParams = {
      ...oauthParams,
      'oauth_signature': signature,
    };

    final headerString = headerParams.entries
        .map((e) => '${e.key}="${_encode(e.value)}"')
        .join(', ');

    return 'OAuth $headerString';
  }

  Future<http.Response> get(String endpoint, {Map<String, String>? params}) async {
    final url = Uri.parse('$baseUrl$endpoint').replace(queryParameters: params);
    final authHeader = _buildAuthHeader(
      method: 'GET',
      url: url.toString(),
      queryParams: params,
    );
    return http.get(url, headers: {'Authorization': authHeader, 'Content-Type': 'application/json'});
  }

  Future<http.Response> post(String endpoint, {Map<String, String>? params, Object? body}) async {
    final url = Uri.parse('$baseUrl$endpoint').replace(queryParameters: params);
    final authHeader = _buildAuthHeader(
      method: 'POST',
      url: url.toString(),
      queryParams: params,
    );
    return http.post(
      url,
      headers: {'Authorization': authHeader, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
  }

  Future<http.Response> put(String endpoint, {Map<String, String>? params, Object? body}) async {
    final url = Uri.parse('$baseUrl$endpoint').replace(queryParameters: params);
    final authHeader = _buildAuthHeader(
      method: 'PUT',
      url: url.toString(),
      queryParams: params,
    );
    return http.put(
      url,
      headers: {'Authorization': authHeader, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
  }
}