<div align="center">
  <img src="https://cliptate.github.io/assets/app-icon.png" width="120" alt="Cliptate アイコン" />
  <h1>Cliptate</h1>
  <p><strong>Mac 向け映像・音声クリエイターのためのオンデバイス AI ワークスペース</strong></p>

  <p>
    <a href="https://apps.apple.com/cn/app/%E5%89%AA%E8%A8%80-cliptate/id6754441004?mt=12"><img alt="App Store からダウンロード" src="https://img.shields.io/badge/App%20Store-ダウンロード-0066cc?logo=apple&logoColor=white&style=flat-square" /></a>
    <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white&style=flat-square" />
    <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-MLX-ff6900?style=flat-square" />
    <img alt="Swift" src="https://img.shields.io/badge/Swift-5.10-f05138?logo=swift&logoColor=white&style=flat-square" />
    <img alt="100% オンデバイス" src="https://img.shields.io/badge/処理-100%25%20ローカル-22c55e?style=flat-square" />
  </p>

  <p>
    <a href="https://cliptate.github.io">ウェブサイト</a> ·
    <a href="https://cliptate.github.io#features">機能</a> ·
    <a href="https://cliptate.github.io#voice">音声・TTS</a> ·
    <a href="https://apps.apple.com/cn/app/%E5%89%AA%E8%A8%80-cliptate/id6754441004?mt=12">ダウンロード</a>
  </p>

  <p>
    <a href="README.md">English</a> ·
    <a href="README.zh.md">中文</a> ·
    <a href="README.ja.md">日本語</a> ·
    <a href="README.ko.md">한국어</a> ·
    <a href="README.de.md">Deutsch</a>
  </p>
</div>

---

Cliptate は、映像・音声制作で最も時間のかかる作業を、完全にローカルで動作する一連のワークフローにまとめたネイティブ macOS アプリです。クラウドへのアップロード不要、API キー不要、ネットワーク待機不要。すべてのモデルは Mac 上で動作します。

---

## 機能

### 🎙 音声入力 — 話すだけで文字に

リアルタイムストリーミングの音声テキスト変換をインプットメソッドとして利用できます。グローバルキーボードショートカットでどのアプリからでも呼び出し、話すだけで編集可能なテキストが生成されます。

- 最小遅延のストリーミング文字起こし
- 複数話者の自動識別とラベリング
- ドメイン固有の精度向上のためのカスタム語彙辞書
- いつでも呼び出し・一時停止できるグローバルショートカット

### 📝 オフライン文字起こし

音声・動画ファイルをすべてオンデバイスでバッチ文字起こし。複数の ASR エンジン（Parakeet、Qwen3、FireRed ASR）と Apple Silicon 最適化 MLX 推論により、高精度な字幕をサーバーへの送信なしで生成します。

### ✂️ スマート無音カット

VAD ベースの無音検出が、ポッドキャスト・インタビュー・講座録音の不要な間を自動識別・一括削除。ラフカットが納品に近い状態で完成します。

### 👥 話者識別

録音内の複数話者を自動識別してラベリング。Sortformer と Silero VAD モデルがオンデバイスで動作し、インタビューやパネル、会議録に話者情報付きの構造化トランスクリプトを生成します。

### 🔊 TTS 音声合成 — 4 つのモード

| モード | 説明 |
|---|---|
| **プリセット音声** | 内蔵多言語音声ライブラリからすぐに利用可能 |
| **音声クローン** | 参照音声をアップロードして話者の音色とリズムを再現 |
| **感情コントロール** | テキストプロンプトで指定した話者の感情とスタイルを制御 |
| **音声デザイン** | テキストで音声特性を記述し、完全オリジナルのペルソナを合成 |

すべての TTS 推論は MLX でオンデバイスに実行されます。音声データはクラウドに送信されません。

### 🌐 AI 校正・翻訳

文脈を考慮したトランスクリプト校正と、オンデバイスまたは Apple 翻訳を利用した多言語出力。ツールを切り替えることなく、グローバルな視聴者向けコンテンツを制作できます。

### ⭐ ハイライト検出

録音から最も重要な文や注目すべき瞬間を自動的に抽出し、タイムラインにマーク。編集・公開作業のスピードが向上します。

---

## 出力フォーマット

Cliptate はすでに使用しているツールへ直接出力します：

| フォーマット | 用途 |
|---|---|
| **FCPXML** | Final Cut Pro タイムラインプロジェクト交換 |
| **SRT** | 汎用字幕配信 |
| **ASS** | スタイルと位置情報付き字幕 |
| **VTT** | ブラウザ・ストリーミングプラットフォーム向け Web 字幕 |

**Final Cut Pro**、**DaVinci Resolve**、**Adobe Premiere Pro** に対応。

---

## プライバシーとセキュリティ

- **クラウドアップロードなし** — 音声・動画・トランスクリプトは Mac の外に出ません
- **API キー不要** — すべてのモデルはアプリに同梱、または初回起動時にダウンロード
- **ネットワーク依存なし** — モデルをキャッシュすれば完全オフラインで動作
- 機密性の高いコンテンツやコンプライアンス対応が求められる用途に適しています

---

## 動作環境

| | |
|---|---|
| **プラットフォーム** | macOS 14 Sonoma 以降 |
| **アーキテクチャ** | Apple Silicon（M1 以降）を推奨 |
| **ストレージ** | モデル選択により異なります（フルモデルセット: 2〜8 GB） |

---

## 技術スタック

Cliptate は Swift で構築された Apple ネイティブフレームワーク使用のアプリです：

---

## 活用シーン

**ポッドキャスター・インタビュアー** — 無音カット、字幕生成、公開可能な場面の特定をアプリ内で完結。

**Vlog・ショート動画クリエイター** — トーキングヘッド編集をスムーズにし、ペースや表現に集中。

**講座制作者・会議記録者** — 音声入力またはバッチ文字起こしで、長時間の録音を検索・翻訳・納品可能なテキスト資産に変換。

**多言語コンテンツチーム** — 音声をクローンし、トランスクリプトを翻訳し、吹き替えバージョンを作成——すべて 1 台の Mac で。

---

## リンク

- **ウェブサイト：** [cliptate.github.io](https://cliptate.github.io)
- **App Store：** [Cliptate をダウンロード](https://apps.apple.com/cn/app/%E5%89%AA%E8%A8%80-cliptate/id6754441004?mt=12)
- **問題・フィードバック：** [GitHub Issues](https://github.com/cliptate/cliptate.github.io/issues)

---

<div align="center">
  <sub>プライバシー、スピード、プロフェッショナルな出力を重視するクリエイターのために。</sub>
</div>
