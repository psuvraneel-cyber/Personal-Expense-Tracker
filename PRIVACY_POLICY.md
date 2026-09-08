# Privacy Policy — Personal Expense Tracker (P.E.T)

**Last updated:** July 26, 2026

## Overview

Personal Expense Tracker ("P.E.T", "the App") is an offline-first personal finance management application. This privacy policy explains how the App processes, stores, protects, and deletes your personal and financial data.

---

## SMS Data Access & Parsing

The App requests **READ_SMS** and **RECEIVE_SMS** permissions to automatically detect financial transactions from bank SMS alerts.

### Processing & Redaction Architecture:
- **On-Device Processing:** All SMS parsing and transaction classification are performed locally on your device using background Isolates. Raw SMS content is not transmitted to external servers.
- **PII Redaction:** Account numbers, card numbers, and phone numbers contained in SMS messages are automatically redacted prior to local database storage (e.g., masked as `XX****1234`).
- **Targeted Filtering:** The App filters incoming SMS by verified bank sender IDs (e.g., `AD-HDFCBK`, `AD-SBIINB`). Personal, social, promotional, and non-financial SMS messages are ignored.

---

## Notification Access

The App requests notification access via Android's **NotificationListenerService** to detect transaction alerts from financial and payment applications (such as Google Pay, PhonePe, Paytm, and BHIM) that do not send traditional SMS alerts.

### Processing & Caching Security:
- **On-Device Filtering:** Notification content is parsed locally on-device. Only notifications originating from verified Indian UPI and banking package names are processed. Notifications from messaging, social media, or other non-financial apps are ignored.
- **Encrypted Notification Caching:** If notification data is received while the main application process is inactive, notification payloads are temporarily cached using hardware-backed **AES-256-GCM encryption** (via Android Jetpack Security EncryptedSharedPreferences) until processed, after which they are flushed.
- **Non-Transmission:** Notification text is not transmitted to external servers.

---

## Data Storage & Encryption at Rest

### 1. Local Database Storage (Encrypted at Rest)
- Your transaction records, custom categories, budgets, and application settings are stored locally in an on-device SQLite database.
- **SQLCipher Encryption:** On supported Android devices, the local SQLite database is encrypted at rest using **256-bit AES encryption via SQLCipher**. Encryption keys are generated using cryptographically secure random number generators (`Random.secure()`) and stored in the hardware-backed Android Keystore via encrypted secure storage.
- **Backup Exclusion:** The local database file is explicitly excluded from Android cloud backups and device-to-device transfers (`backup_rules.xml`) to prevent unauthorized extraction.

### 2. Guest Mode (Offline Operation)
- The App supports full offline operation ("Guest Mode") without requiring account creation or internet connectivity. In Guest Mode, all financial data remains exclusively on your physical device.

### 3. Cloud Synchronization (Optional)
- If you choose to sign in with Google, your transaction metadata, custom categories, and budget targets are synchronized to **Google Cloud Firestore**.
- **Multi-Account Isolation:** Cloud data is strictly segregated per user using Firebase Authentication. Security rules enforce that database paths are readable and writable solely by the authenticated owner (`request.auth.uid == uid`).

---

## Third-Party Services & Optional AI Insights

The App integrates with selected third-party services to provide authentication, cloud sync, analytics, and optional AI features:

| Service | Purpose | Transmitted Data | Privacy Policy |
| :--- | :--- | :--- | :--- |
| **Firebase Authentication** | User sign-in & identity | Email address, Google Account ID | [Google Privacy Policy](https://policies.google.com/privacy) |
| **Google Cloud Firestore** | Optional cloud synchronization | Redacted transaction metadata, categories, budgets, recurring rules, goals | [Google Cloud Privacy](https://cloud.google.com/terms) |
| **Firebase Crashlytics** | Stability & crash diagnostics | Anonymous stack traces, device OS version (zero financial PII) | [Firebase Privacy](https://firebase.google.com/support/privacy) |
| **Cloudflare Workers** | Secure proxy for optional AI Copilot | Anonymized monthly category totals, budget utilization percentages, and sanitized recent transaction labels (No PII, no account numbers, no raw SMS) | [Cloudflare Privacy Policy](https://www.cloudflare.com/privacypolicy/) |
| **Groq API** | LLM processing for AI Copilot insights | Anonymized financial context summaries and user chat turns | [Groq Privacy Policy](https://groq.com/privacy-policy/) |
| **RevenueCat** | Premium subscription management | App store purchase receipts, anonymous subscriber ID | [RevenueCat Privacy Policy](https://www.revenuecat.com/privacy/) |

---

## Data Retention & Automatic Expiration

1. **Financial Transactions & Budgets:** Your saved transactions, categories, and budgets are retained locally and in cloud storage until you manually delete individual entries or execute an account deletion.
2. **Diagnostic Unparsed SMS Logs (`UnknownFormatLog`):** To improve parsing accuracy for unrepresented bank formats, unparseable financial SMS structures are logged locally in your encrypted database. These diagnostic entries **automatically expire and are deleted after 30 days**, and total log volume is capped at 500 rows maximum.
3. **Exported Reports:** When you export financial records (CSV or PDF), temporary files are written to the operating system's temporary directory for sharing. These files are subject to automatic OS temporary directory cleanup.

---

## Account Deletion & Data Erasure

You can permanently delete your data at any time:

1. **In-App Account Deletion:** Navigating to `Settings > Account > Delete Account` executes a multi-layer deletion protocol:
   - Permanently deletes all user documents, subcollections, and sync logs from Google Cloud Firestore.
   - Deletes the Firebase Authentication user profile.
   - Wipes all local SQLite tables, encrypted shared preferences, and cached notifications on your device.
   - Cancels RevenueCat subscriber association.
2. **Local Data Reset:** Signing out or clearing application storage immediately deletes local database files and cached credentials.

---

## Children's Privacy

The App is not directed to individuals under the age of 18. We do not knowingly collect personal information from children.

---

## Changes to This Privacy Policy

We may update this Privacy Policy periodically. Changes become effective upon publishing the updated policy in the App and repository.

---

## Contact & Privacy Inquiries

For questions, data protection requests, or privacy inquiries:

**Data Protection Contact:** Suvraneel Paul  
**Email:** psuvraneel@gmail.com  
**Repository:** [psuvraneel-cyber/Personal-Expense-Tracker](https://github.com/psuvraneel-cyber/Personal-Expense-Tracker)
