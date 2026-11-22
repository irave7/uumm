# uumm

网易 UU Remote で遠隔操作する Mac 向けの仮想ディスプレイ、タッチ操作、スマートフォン接続時の自動切り替え、縦スクロール同期をまとめたアプリです。[Snug](https://github.com/zephyr4123/snug) をベースにした MIT ライセンスのフォークです。

[简体中文](README.md) · [English](README.en.md) · [DMG をダウンロード](https://github.com/irave7/uumm/releases/latest)

## インストール

1. macOS 14 以降の被操作 Mac に网易 UU Remote をインストールして設定します。
2. [GitHub Releases](https://github.com/irave7/uumm/releases/latest) の DMG を開き、**uumm** を「アプリケーション」へドラッグします。
3. uumm を起動し、アクセシビリティのアクセスを許可します。macOS 27 では「システム設定 → プライバシーとセキュリティ → デバイス制御とデータアクセス」にあります。uumm の任意のスクリーンショット機能には画面収録の許可も必要です。

このリリースは ad-hoc 署名済みで、Apple の公証は受けていません。初回起動がブロックされた場合は、入手先を確認してから [Apple の案内](https://support.apple.com/ja-jp/102445) に沿って uumm を個別に許可できます。

## 使い方

- **メニューバーアイコン。** 設定の「通用」で「在菜单栏显示」をオフにするとアイコンを隠せます。機能はバックグラウンドで動作します。「アプリケーション」または Spotlight から uumm を開くと設定に戻れます。
- **仮想ディスプレイとジェスチャ。** uumm の画面設定で仮想ディスプレイを有効にし、接続後に UU Remote の画面一覧から選びます。アプリライブラリ、ウインドウ配置、スマートフォンやタブレット向けのタッチ操作を利用できます。
- **スマートフォン接続時の自動切り替え。** 設定の「UU 优化」で「自动切屏」を有効にし、UU Remote の被操作ページに表示されるスマートフォン名を入力して保存します。画面設定で縦向きのスマートフォン用仮想ディスプレイを 1 台だけ有効にし、メインディスプレイは既存の設定を保持します。指定端末だけが接続中で、内蔵ディスプレイが配信され、対象の仮想ディスプレイがオンラインのとき、uumm が内蔵ディスプレイを一時停止して切り替えを促し、その後内蔵ディスプレイを復元します。他の端末や特定できない端末からの接続では切り替えは行いません。
- **縦スクロール同期。** 設定の「UU 优化」で「同步纵向滚轮」を有効にします。macOS のナチュラルスクロールと LinearMouse の縦方向反転を UU Remote の入力に反映します。対応する設定からはスクロールの行数も取得します。ローカルのマウスとトラックパッドは自身の設定を使います。[LinearMouse](https://linearmouse.app/)

自動切り替えとスクロール同期は初期状態では無効です。自動切り替えは、内蔵ディスプレイがメインで、内蔵画面と対象の仮想画面の 2 台だけがオンラインの場合に対応します。切り替え中は内蔵画面が短時間消え、ウインドウが移動することがあります。直後に別の端末が操作を引き継ぐと仮想画面が選ばれる場合があります。スマートフォン名を識別できない場合は、UU Remote の画面一覧から手動で選べます。

## Snug から移行する

uumm を使う前に Snug、UUyc-companion、個別に動作している UU 用のスクロールや画面切り替えツールを終了します。既存のアプリと設定を残したまま uumm を設定できます。動作を確認後、不要になったツールをログイン項目から外してください。

## ソースコードとライセンス

Swift 6 と macOS SDK を含む Xcode を用意し、`scripts/uumm check` でビルドとテストを行います。`scripts/uumm dmg` でアプリとディスクイメージを作成できます。出力先は `build/` と `dist/` です。

Snug の履歴と [MIT ライセンス](LICENSE) を継承しています。[Snug](https://github.com/zephyr4123/snug) の zephyr4123、[UUyc-companion](https://github.com/aoyamashou/UUyc-companion) の AoyamaShou、[PermissionFlow](https://github.com/jaywcjlove/PermissionFlow)、[Better Remote](https://github.com/pincc-debug/better-remote)、[FreeDisplay](https://github.com/huberdf/FreeDisplay) の開発者に感謝します。

uumm は网易から独立したコミュニティプロジェクトです。仮想画面と自動切り替えは macOS の非公開ディスプレイインターフェースと UU Remote の接続動作に依存するため、更新によって影響を受けることがあります。
