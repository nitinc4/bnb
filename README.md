---

# BuyNutBolts (BNB) Mobile Application Documentation

**Version:** 1.0.0
**Framework:** Flutter (Dart SDK ^3.7.0)
**Backend:** Magento 2 (via REST API)

---

## 1. Project Overview

The **BNB App** is a specialized B2B/B2C e-commerce mobile application designed for the sale of industrial fasteners (nuts, bolts, etc.). Built with Flutter, it interacts directly with a Magento 2 backend to manage products, categories, users, and orders.

The app places a heavy emphasis on **performance caching**, **offline-to-online cart synchronization**, and **tier-pricing** for bulk purchasers.

---

## 2. Technical Stack

### Core Framework

* **Flutter & Dart:** Targeted for Android and iOS.
* **State Management:** `Provider` (ChangeNotifier).
* **Networking:** `http` and `dio` for API requests.

### Backend & Data

* **API:** Magento 2 REST API (OAuth 1.0a & Bearer Token authentication).
* **Local Storage:**
* `shared_preferences`: Non-sensitive data (cached categories, product data).
* `flutter_secure_storage`: Sensitive data (Auth tokens).


* **Cloud & AI:**
* **Firebase:** Core, Messaging (FCM), and Analytics.
* **Google Generative AI:** Integrated for AI-assisted features (Gemini).



### UI & UX

* **Design System:** Material 3 (`useMaterial3: true`).
* **Theme:** Custom Blue (`#00599c`) and Red (`#F54336`) palette.
* **Components:** `flutter_spinkit` (loaders), `shimmer` (loading skeletons), `cached_network_image`.

---

## 3. Architecture & Data Flow

The application follows a **Layered Architecture**:

1. **Presentation Layer (Screens/Widgets):** Consumes data via Providers.
2. **Logic Layer (Providers):** Manages state (`CartProvider`) and business logic.
3. **Service Layer (API):** Handles HTTP requests, error handling, and data parsing (`MagentoAPI`).
4. **Model Layer:** Typed data objects (`Product`, `Order`, `TierPrice`).

### Key Workflows

#### A. Authentication

The app supports both **Guest** and **Registered** user flows.

* **Login/Register:** Uses Magento integration endpoints.
* **Token Management:** Customer tokens are encrypted and stored via `FlutterSecureStorage`.
* **Auto-Login:** The app attempts to fetch customer details on startup using the stored token.

#### B. The "Smart" Cart System

The `CartProvider` implements a complex synchronization strategy:

1. **Guest Mode:** Items are stored locally in JSON format.
2. **Merge Logic:** When a user logs in, the app detects local "guest" items and merges them into the server-side Magento cart automatically.
3. **Debouncing:** To prevent excessive disk I/O, local cart saving is debounced (500ms delay).

#### C. Search Logic

The `MagentoAPI` implements a **Dual-Strategy Search**:

1. **Strict Search:** Attempts to find products where *every* word in the query matches (AND logic).
2. **Loose Search (Fallback):** If strict search fails, it retries finding products matching *any* word (OR logic).

* *Note:* Search targets both `name` and `sku`.

---

## 4. Key Modules

### 4.1. API Manager (`magento_api.dart`)

This is the core engine of the application.

* **Caching Strategy:**
* **Memory Cache:** Static lists for categories and products to reduce network calls during a session.
* **Persistence:** Caches category trees and user details to `SharedPreferences` to speed up subsequent app launches.
* **Warm-Up:** The `warmUpHomeData()` method pre-fetches top categories and products in the background to ensure the Home Screen loads instantly.


* **RFQ (Request for Quote):** A custom endpoint integration allowing users to request bulk pricing. It allows the app to fallback to this system if live support fails.
* **Tier Pricing:** Specifically parses Magento's `tier_prices` to display bulk quantity discounts, essential for the B2B nature of the business.

### 4.2. Models (`magento_models.dart`)

Custom parsing logic is implemented to handle Magento's complex JSON structure.

* **Product Images:** Automatically constructs full URLs from Magento's relative paths (`/media/catalog/...`).
* **Custom Attributes:** filters out backend-specific attributes (like "tax_class_id") and focuses on user-facing specs.

### 4.3. Navigation & Routing (`main.dart`)

The app uses named routes for navigation:

* `/splash`: Initial data fetching and configuration.
* `/home`: Main dashboard.
* `/login`: Authentication gate.
* `/cart`: Shopping cart.
* `/support`: Customer service interface.

---

## 5. Security & Configuration

### Data Security

* **Token Storage:** Access tokens are **never** stored in plain text `SharedPreferences`. They are strictly managed by `flutter_secure_storage`.
* **Environment:** The app relies on an external configuration loader (`fetchAndSetConfig`) to retrieve sensitive API keys (Consumer Key/Secret) from secuserve rather than hardcoding them in the binary.

### Permissions

* **Android:**
* `Internet`: For API access.
* `Wake Lock`: To maintain processes during heavy syncs.
  
---
