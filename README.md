# Bar RAGNOISE - AI Integrated Bar Support App

**「洗練された空間を、最先端の技術でサポートする」**
Bar RAGNOISE（ラグノイズ）のブランドイメージを損なうことなく、店舗運営をDX化し、顧客体験を最大化するためのFlutterアプリケーションです。

## 📱 アプリケーションの概要
単なる予約やポイント付与のアプリではなく、店主と顧客の双方向にメリットをもたらす機能を統合しています。

## 🌟 主要機能
* **AI ビジネスインサイト**: 蓄積された来店データ（年代・性別・時間帯）をGemini 1.5 Flashが分析。店舗の強みや次の一手を提案する経営診断機能を搭載。
* **スタイリッシュなポイントシステム**: Firebase Authによる匿名認証を採用し、個人情報を守りつつ来店実績を管理。累積来店数に応じたランクアップ機能を実装。
* **インテリジェント予約システム**: 店舗の定休日や貸切状況とリアルタイムに同期し、ユーザーの利便性を高めた予約フォーム。
* **モーメント（店舗掲示板）**: 管理者が投稿したカクテルの写真や最新情報を、美しいカードデザインで表示。
* **プロ仕様のUX**: 各アクションにHaptic Feedback（触覚フィードバック）を実装し、高級感を演出。

## 🛠 使用技術
### Frontend
* **Framework**: Flutter (Dart)
* **Design**: Custom Dark Theme / Glassmorphism
* **UX**: Haptic Feedback Integration

### Backend / AI
* **Database**: Cloud Firestore (Real-time DB)
* **Authentication**: Firebase Anonymous Auth
* **Generative AI**: Google Gemini API (gemini-1.5-flash)

## 🏗 セキュリティと設計へのこだわり
* **機密情報の保護**: APIキーはソースコードに直接記述せず、`--dart-define` を用いた環境変数分離を行っています。
* **プライバシー配慮**: 匿名認証を活用することで、ユーザーの過度な個人情報入力を省きつつ、パーソナライズされた体験を提供。
* **保守性**: 各機能（分析、予約、ポイント等）を別ファイルに分割し、可読性の高いコード構成を維持。

## 🚀 実行方法
1. `flutter pub get` を実行して依存関係をインストール。
2. 以下のコマンドでGemini APIキーを注入して実行。
```bash
flutter run --dart-define=GEMINI_API_KEY=YOUR_API_KEY
