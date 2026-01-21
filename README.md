
---

# BuyNutBolts (BNB) Technical Reference Manual

**Version:** 1.0.0
**Framework:** Flutter (Dart 3.7.0+)
**Backend:** Magento 2 (REST API) & Vercel Middleware
**Architecture:** Layered (MVVM-style with Providers)

---

## 1. Security Architecture (Deep Dive)

The application employs a "Zero-Trust" configuration model. Sensitive credentials are never stored in the binary. Instead, a custom cryptographic handshake is used to retrieve them at runtime.

### 1.1. Dynamic Configuration Injection

**Source:** `lib/api/client_helper.dart`

* **Trigger:** The `fetchAndSetConfig()` function is awaited in `main.dart` before `runApp()` executes, ensuring no network calls fail due to missing keys.
* **Handshake Protocol:**
1. **Key Derivation:** A symmetric key is derived from the current date (`yyyyMMdd`), padded to 32 bytes to satisfy AES-256 requirements.
2. **Encryption:** The app encrypts a static verification phrase (`BNB_SECURE_ACCESS`) using **AES-CBC** (Cipher Block Chaining) with a random 16-byte Initialization Vector (IV).
3. **Header Construction:** The request includes a custom header `x-secure-date` formatted as `base64(IV):base64(Ciphertext)`.
4. **Verification:** The Vercel middleware decrypts the header. If the phrase matches, it returns the `consumerKey`, `accessToken`, and `geminiApiKey`.



### 1.2. Client-Side Data Protection

* **Token Storage:** User authentication tokens (`customer_token`) are stored in `FlutterSecureStorage` (EncryptedSharedPreferences on Android / Keychain on iOS), not in plain text `SharedPreferences`.
* **Email Privacy:** Transactional emails (OTPs, support tickets) are routed through the secure middleware (`/api/send-email`) rather than using a direct SMTP client, preventing the exposure of email server credentials on the client device.

---

## 2. API & Networking Layer

**Source:** `lib/api/magento_api.dart`

The `MagentoAPI` class acts as the central service layer, wrapping HTTP calls with OAuth 1.0a (via `MagentoOAuthClient`) and handling business logic.

### 2.1. "Smart" Search Algorithm

The search functionality implements a fallback strategy to maximize result relevance:

1. **Strict Mode (AND Logic):**
* Splits the query into individual words.
* Creates separate **Filter Groups** for each word.
* **Logic:** Magento requires *all* filter groups to be true. (e.g., "M6 Bolt" -> Product must contain "M6" AND "Bolt").


2. **Loose Mode (Fallback / OR Logic):**
* Triggered only if Strict Mode returns 0 results.
* Places all words into a **single Filter Group**.
* **Logic:** Magento treats filters within a group as OR conditions. (e.g., "M6 Bolt" -> Product contains "M6" OR "Bolt").
* *Constraint:* Both modes search against `name` and `sku` attributes.



### 2.2. Advanced Caching & Warm-up

To mitigate Magento's API latency, the app implements aggressive caching:

* **Attribute Filtering:** The app explicitly filters out over 20 backend-specific attributes (e.g., `tax_class_id`, `custom_design`) to reduce memory footprint.
* **Warm-Up Routine:** The `warmUpHomeData()` method runs in the background on launch:
1. Fetches the full Category Tree.
2. Iterates through the top 5 categories.
3. Pre-fetches the first 10 products for each category into memory (`categoryProductsCache`).


* **Persistence:**
* **Category Tree:** Serialized and saved to `SharedPreferences` (`cached_categories_data`).
* **Product Data:** Cached items are saved to `cached_products_data` to allow offline product viewing on subsequent launches.



---

## 3. Cart & State Management

**Source:** `lib/providers/cart_provider.dart`

The `CartProvider` manages the complex state between the local device and the server.

### 3.1. Hybrid Cart System

* **Guest Mode:** Items are assigned a placeholder quote ID (`guest_local`) and stored in local JSON.
* **Debounced Persistence:** To prevent disk thrashing, updates to the local cart are debounced. The `_saveLocalCart` function only executes after 500ms of inactivity.

### 3.2. Synchronization Logic (The Merge)

When `fetchCart()` is called (e.g., after login):

1. **Token Validation:** It attempts to fetch server items. If the server returns 401 (Unauthorized), the app automatically wipes local user data and reverts to Guest Mode.
2. **Merge Process:**
* It identifies local items with `quoteId == 'guest_local'`.
* It iterates through them, calling `addToCart` on the server for each.
* Finally, it re-fetches the server cart to ensure the local state mirrors the backend 1:1.



---

## 4. Feature Modules

### 4.1. Push Notifications

**Source:** `lib/api/firebase_api.dart`

* **Architecture:** Uses a detached background handler (`_firebaseMessagingBackgroundHandler`) marked with `@pragma('vm:entry-point')` to ensure execution even when the app is terminated.
* **Sync-After-Login:** The FCM token is not just generated but explicitly registered with Magento via `registerDeviceToken` whenever a user logs in. This links the device token to the specific Customer ID in Magento.

### 4.2. Tier Pricing (B2B Feature)

**Source:** `lib/models/magento_models.dart` & `lib/api/magento_api.dart`

* **Parsing:** The `Product` model contains specific logic to parse the `tier_prices` array.
* **Discrepancy Handling:** It handles Magento's API inconsistency where price is sometimes returned as `price` and other times as `value`.
* **Display:** These parsed values allow the UI to show bulk quantity discounts (e.g., "Buy 10 for ₹50 each").

### 4.3. Image Handling

**Source:** `lib/models/magento_models.dart`

* **Path Reconstruction:** Magento returns relative image paths (e.g., `/a/b/image.jpg`). The `Product` model detects this and prepends the full media URL (`https://buynutbolts.com/media/catalog/product`).
* **Fallbacks:** If no image is defined in the `custom_attributes`, it defaults to a placeholder.

---

## 5. UI/UX Implementation Details

**Source:** `lib/main.dart`

* **Routing:** Uses a named route system (`/home`, `/cart`, etc.) defined in `MaterialApp`.
* **Theme Engine:**
* **Primary Color:** `#00599c` (Industrial Blue).
* **Secondary Color:** `#F54336` (Alert Red).
* **Design Standard:** Material 3 is explicitly enabled (`useMaterial3: true`).


* **Route Guards:** The `onGenerateRoute` logic intercepts navigation to `/productDetail` and `/orderSuccess` to securely pass complex arguments (`Product` objects) that cannot be passed via standard string routes.

---

## 6. Request for Quote (RFQ) & AI Fallback

**Source:** `lib/api/magento_api.dart`

This module provides a safety net for failed interactions:

* **Trigger:** If live support fails to initialize or a product is out of stock.
* **Payload:** The app constructs a JSON payload containing the user's contact info and product interest.
* **Endpoint:** Sends data to a separate microservice (`AppConfig.rfqUrl`), bypassing the main Magento order flow. This is tagged with `source: 'app_ai_assistant'` or `source: 'app_support_fallback'`, indicating future plans for AI-driven response handling.
