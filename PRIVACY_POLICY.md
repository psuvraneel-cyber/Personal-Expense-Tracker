# Privacy Policy — Personal Expense Tracker (P.E.T)

**Last updated:** July 16, 2026

## Overview

Personal Expense Tracker ("P.E.T", "the App") is a personal finance management application. This privacy policy explains how the App handles your data.

## SMS Data Access

The App requests **READ_SMS** and **RECEIVE_SMS** permissions to automatically detect financial transactions from bank SMS messages. This is used solely for:

- Extracting transaction amounts, merchant names, and dates from bank alerts
- Categorising spending automatically
- Detecting recurring payments

### What we DO:

- **All SMS processing happens entirely on your device.** No SMS content is ever transmitted to external servers.
- Store only redacted transaction data (account numbers are masked, e.g., `XX****1234`)
- Allow you to delete any auto-detected transaction at any time

### What we DO NOT do:

- Read personal, promotional, or non-financial SMS messages
- Share, sell, or transmit raw SMS content to any third party
- Store the full, unredacted SMS body

## Notification Access

The App requests notification access (via Android's **NotificationListenerService**) to capture transaction alerts from financial and payment apps (such as Google Pay, PhonePe, and Paytm) that do not arrive via SMS. This is used solely for:
- Auto-detecting UPI transactions completed via payment apps.
- Extracting transaction amount, date, and merchant details.

### What we DO:
- **Notification reading is processed entirely on-device.** The app filters and parses notifications locally to identify transaction events. No notification content is ever transmitted to external servers.
- Read only notifications originating from verified Indian UPI and banking applications.

### What we DO NOT do:
- Read notifications from messaging, social media, or other non-financial apps.
- Share, sell, or transmit raw notification data to any third party.

## Data Storage

- **Local data** is stored in an on-device SQLite database
- **Cloud sync** (optional, via Google Sign-In) stores transaction metadata in Google Cloud Firestore, secured per-user with Firebase Authentication
- **AI Copilot** (optional) sends anonymised financial summaries via a secure Cloudflare Worker to Groq's API for generating insights — no raw SMS data is included

## Third-Party Services

| Service | Purpose | Privacy Policy |
|---------|---------|----------------|
| Firebase Authentication | User sign-in | [Google Privacy Policy](https://policies.google.com/privacy) |
| Cloud Firestore | Cloud sync | [Google Cloud Terms](https://cloud.google.com/terms) |
| Cloudflare Workers | Secure proxy for AI requests | [Cloudflare Privacy Policy](https://www.cloudflare.com/privacypolicy/) |
| Groq API | AI financial insights | [Groq Privacy Policy](https://groq.com/privacy-policy/) |
| RevenueCat | Premium subscription management | [RevenueCat Privacy Policy](https://www.revenuecat.com/privacy/) |

## Data Deletion

You can delete all your data at any time by:
1. Signing out (clears local cache and sign-in session)
2. Using the "Delete Account" option in Settings (permanently and irreversibly deletes your profile, transaction records, categories, and sync logs from our Cloud Firestore servers and your local device)

## Data Retention

Your data is retained until you choose to delete it. There is no automatic data expiration — your records persist as long as you keep your account active. Once you delete your account, all personal and financial data is deleted immediately and irreversibly.

## Contact

For questions about this privacy policy, contact:

**Email:** psuvraneel@gmail.com
