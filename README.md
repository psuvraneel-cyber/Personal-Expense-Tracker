# P.E.T - Personal Expense Tracker

![Flutter Version](https://img.shields.io/badge/Flutter-3.10.8+-blue.svg)
![Dart Version](https://img.shields.io/badge/Dart-3.1.0+-blue.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

**P.E.T (Personal Expense Tracker)** is a secure, feature-rich, and automated finance companion specifically designed for Indian users. The application simplifies personal finance by automatically tracking UPI and bank transactions via SMS, intelligently categorized budgeting, and providing personalized financial advice powered by an AI Copilot.

---

## ✨ Key Features

- **💸 Automated UPI & Bank Tracking:** Uses secure, on-device SMS parsing to automatically detect and log UPI transactions and bank alerts without requiring bank login credentials. 
- **🤖 AI Financial Copilot:** Get personalized financial advice, budget reviews, and spending insights. Powered by Groq's `llama-3.3-70b-versatile` LLM.
- **☁️ Cloud Backup & Sync:** Secure realtime synchronization across devices via Firebase (Auth & Firestore).
- **📊 Intuitive Analytics:** Beautiful, interactive charts and dashboard breakdowns for income, expenses, and savings via `fl_chart`.
- **🔐 Enterprise-grade Security:** 
  - Biometric App Lock (`local_auth`).
  - No hardcoded API keys: AI requests are securely proxied through a Cloudflare Worker backend to protect the Groq API key.
- **📄 Export & Reports:** Generate comprehensive PDF financial reports for tax seasons or personal archiving.

---

## 🛠️ Architecture & Tech Stack

- **Frontend:** Flutter & Dart
- **State Management:** Provider
- **Local Storage:** SQLite (`sqflite`) for lightning-fast offline access
- **Cloud Backend:** Firebase (Authentication, Cloud Firestore)
- **AI Proxy:** Cloudflare Workers (JavaScript/Node.js environment verifying Firebase JWTs and proxying Groq LLM requests)

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (v3.10.8 or higher)
- [Firebase CLI](https://firebase.google.com/docs/cli)
- [Wrangler CLI](https://developers.cloudflare.com/workers/wrangler/install-and-update/) (For Cloudflare Worker)

### 1. Clone the repository
```bash
git clone https://github.com/your-username/pet-expense-tracker.git
cd pet-expense-tracker
```

### 2. Install dependencies
```bash
flutter pub get
```

### 3. Setup Firebase & Credentials
Configure Firebase for this project using FlutterFire CLI locally:
```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=<your-firebase-project-id>
```
* **Gitignored Configuration Files**: The local output configuration files (`android/app/google-services.json`, `lib/firebase_options.dart`, `ios/Runner/GoogleService-Info.plist`) are strictly gitignored and must never be committed to source control.
* **CI/CD Pipeline Setup**: For automated CI builds, inject the required credential files from your CI secret store during a pre-build step before compilation.
* **⚠️ Warning on Repository Export / Audit Tools (e.g., Repomix)**: If you use repo-flattening or export tools such as `repomix` to create code snapshot files (`repomix-output.txt`) for reviews or AI prompts, **NEVER commit the generated output file**. Repomix inlines full file contents from your workspace, which will expose locally-present gitignored secret files if committed.

### 4. Setup Environment Variables
Create a `.env` file in the root of the project. **Do not commit this file to version control.**
```env
SUPABASE_URL=your_supabase_url
SUPABASE_ANON_KEY=your_supabase_key
GROQ_MODEL=llama-3.3-70b-versatile
```
*Note: P.E.T uses compile-time variables. You'll run the app using `--dart-define-from-file=.env`.*

### 5. Setup AI Copilot Proxy (Cloudflare Worker)
To secure the Groq API Key from malicious actors, we route AI requests through a Cloudflare Worker.
```bash
cd cloudflare_worker
npm install
```
Add your Groq API key securely using Wrangler:
```bash
npx wrangler secret put GROQ_API_KEY
```
Deploy the worker:
```bash
npx wrangler deploy
```
Update the `_baseUrl` in `lib/premium/services/ai_copilot_service.dart` with your deployed worker URL.

### 6. Run the App
```bash
flutter run --dart-define-from-file=.env
```

---

## 🔒 Security & Privacy First

Privacy is a core pillar of P.E.T. 
- **SMS Parsing** happens strictly *on-device*. We do not upload your messages to the cloud.
- **Copilot Data:** Only aggregated numbers (top categories, overall budget, total income) are sent to the AI Copilot to deliver tailored advice.
- **API Security:** Private LLM API calls are securely authenticated via Short-Lived Firebase IdTokens via the custom Cloudflare server setup.

## 🤝 Contributing
Contributions are always welcome! 
1. Fork the project.
2. Create your feature branch (`git checkout -b feature/AmazingFeature`).
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`).
4. Push to the branch (`git push origin feature/AmazingFeature`).
5. Open a Pull Request.

## 📝 License
Distributed under the MIT License. See `LICENSE` for more information.
