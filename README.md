
---

# BuyNutBolts (BNB) Mobile Application Documentation

**Version:** 1.0.0
**Framework:** Flutter (Dart SDK ^3.7.0)
**Backend:** Magento 2 (via REST API) & Vercel Middleware

---

## 1. Project Overview

The **BNB App** is a specialized B2B/B2C e-commerce mobile application designed for the sale of industrial fasteners. Built with Flutter, it interacts with a Magento 2 backend for commerce operations and a custom Vercel middleware for secure key management.

The app prioritizes **security** (via dynamic key injection), **performance** (smart caching), and **reliability** (offline-to-online cart synchronization).

---

## 2. Technical Stack

### Core Framework

* **Flutter & Dart:** Targeted for Android and iOS.
* **State Management:** `Provider` (ChangeNotifier).
* **Networking:** `http`, `dio`, and `socket_io_client`.

### Backend & Data

* **Commerce API:** Magento 2 REST API (OAuth 1.0a & Bearer Token).
* **Security Middleware:** Custom Vercel Node.js server (`secuserv`) for key distribution.
* **Local Storage:**
* `shared_preferences`: Non-sensitive cache.
* `flutter_secure_storage`: AES-encrypted token storage.



### Cloud & Services

* **Firebase:** Core, Analytics, and Cloud Messaging (FCM).
* **Google Generative AI:** Gemini integration for AI assistance.
* **Encryption:** `encrypt` package (AES-CBC) for secure middleware communication.

### UI & UX

* **Design System:** Material 3 (`useMaterial3: true`).
* **Components:** `flutter_spinkit` (loaders), `shimmer` (skeletons), `cached_network_image`.

---

## 3. Architecture & Data Flow

The application follows a **Layered Architecture** with a distinct "Secure Boot" phase.

### Key Workflows

#### A. Secure Boot & Configuration

Unlike standard apps that hardcode API keys, BNB uses a **Dynamic Configuration Injection** pattern:

1. **App Start:** `fetchAndSetConfig()` is called in `main.dart` before the UI renders.
2. **Handshake:** The app generates a time-based AES-encrypted header (`x-secure-date`) using a pre-shared verification phrase.
3. **Key Retrieval:** It requests configuration from the Vercel middleware.
4. **Injection:** Critical keys (Magento Consumer Key, OAuth Tokens, Gemini API Key) are injected into the static `AppConfig` class in memory.

#### B. The "Smart" Cart System

1. **Guest Mode:** Items are stored locally in JSON.
2. **Merge Logic:** Upon login, local "guest" items are merged into the server-side Magento cart.
3. **Debouncing:** Local cart persistence is debounced (500ms) to reduce disk I/O.

#### C. Notifications

The app uses a "Sync-after-Login" strategy for push notifications:

1. **Initialization:** Permissions are requested, and an FCM token is generated on startup.
2. **Sync:** When a user logs in, the `syncTokenWithServer` method sends the FCM token to Magento, linking the device to the customer account.

---

## 4. Key Modules

### 4.1. Security Manager (`client_helper.dart`)

This module handles the "Zero-Trust" configuration loading.

* **Time-Based Authentication:** Generates a secure header where the encryption key is derived from the current date (`yyyyMMdd`).
* **Header Format:** `IV:Ciphertext` (Base64 encoded).
* **Secure Email:** Provides a method `sendSecureEmail` to route transactional emails (OTPs, support tickets) through the middleware to avoid exposing SMTP credentials on the client.

### 4.2. Notification Manager (`firebase_api.dart`)

Manages the lifecycle of push notifications.

* **Background Handler:** A top-level `@pragma('vm:entry-point')` function handles messages when the app is terminated.
* **Magento Integration:** Contains logic to register the device token with Magento's notification endpoint (`/rest/V1/notifications/register`).

### 4.3. API Manager (`magento_api.dart`)

The core engine for commerce operations.

* **Dual-Strategy Search:** Implements "Strict" (AND) search with a fallback to "Loose" (OR) search if no results are found.
* **RFQ Integration:** Supports a "Request for Quote" fallback system if live support fails or for bulk orders.
* **Tier Pricing:** Parses complex B2B pricing structures from Magento.

---

## 5. Security Protocols

### Dynamic Key Management

The app does **not** store sensitive API keys in `git` or the compiled binary.

* **Mechanism:** Keys are fetched at runtime from `https://secuserv-7w95.vercel.app`.
* **Protection:** The request requires a custom `x-secure-date` header.
* **Encryption:** The header allows the server to verify the request originated from a valid app instance without exposing static secrets in simple text headers.

### Data Security

* **Token Storage:** Customer OAuth tokens are managed strictly by `flutter_secure_storage`.
* **Email Privacy:** User emails are never sent directly via SMTP from the phone; they are routed via the secure middleware API (`/api/send-email`).

---

## 6. Future Roadmap

* **Offline Mode:** Enhance `CartProvider` to support full offline browsing (currently partially cached).
* **Biometrics:** Integrate `local_auth` for login using the stored token in `flutter_secure_storage`.
* **In-App Chat:** Expand the `socket_io_client` usage (currently a dependency) for real-time customer support.
