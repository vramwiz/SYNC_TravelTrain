# SYNC_TravelTrain 作業ノート

## プロジェクトの前提

- 作業フォルダーは `D:\DelphiProg\MyApp\SYNC_TravelTrain`。本番は `SYNC_TravelTrain.dproj` / `SYNC_TravelTrain.auf2`。登録名は「旅行列車」、グループは `SYNC`。
- プロジェクト設定と共通基盤は `D:\DelphiProg\MyApp\SYNC_WeatherFX` から継承。走行風景の遠近・高さと Direct2D の描画基盤は `SYNC_Elevator` を参考にした。
- 仕様は `docs/SPECIFICATION.md`、操作方法は `README.md` を参照する。
- `setup` は依頼どおりコピー元の全ファイルを保持しており、カタログ・スクリプト・既存 ZIP は WeatherFX 用。

## ビルド

- Delphi 37.0 / Win64。IDE では `SYNC_TravelTrain.dproj` を直接開く。
- Debug / Release の順にビルドする。両構成の出力先は `C:\ProgramData\aviutl2\Plugin\SYNC_TravelTrain\`。デバッガーホストは `D:\aviutl2_v2.1.16\aviutl2.exe`。

~~~powershell
New-Item -ItemType Directory -Force -Path 'Win64\BuildLogs','C:\ProgramData\aviutl2\Plugin\SYNC_TravelTrain' | Out-Null
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_TravelTrain.dproj /t:Rebuild /p:Config=Debug /p:Platform=Win64 /fl /flp:"logfile=Win64\BuildLogs\Debug.log;verbosity=normal;encoding=UTF-8"'
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_TravelTrain.dproj /t:Rebuild /p:Config=Release /p:Platform=Win64 /fl /flp:"logfile=Win64\BuildLogs\Release.log;verbosity=normal;encoding=UTF-8"'
~~~

- ビルド後イベントは `copy ... && del ...` の構成を引き継ぐ。DLL を AUF2 にコピーしてから DLL を削除し、Release は RSM も削除する。DCU は `Win64\Debug\DCU` / `Win64\Release\DCU`。警告とエラー、AUF2 の更新を確認する。
- ユニット追加時は `.dpr` の `in` と `.dproj` の `DCCReference` を更新し、必要なフォルダーを検索パスに追加する。外部変更したプロジェクトファイルは IDE で開き直す。

## コメント・分割・文字コード

- ユニット先頭に目的と責務を書く。公開処理には入出力、重要な副作用、必要に応じて値の単位や所有権を書く。
- 日本語を含む `.pas`、`.dpr`、`.ps1` は UTF-8 BOM 付き CRLF にする。約1,500行を目安に責務で分ける。フォームを追加する場合は `.pas` と `.dfm` を同じフォルダーに置く。
- SDK 型配置は公式定義と照合する。ホスト所有のポインターはコールバックの期間だけ借用し、Delphi 例外は DLL の外へ送出しない。

## 検査とアプリ操作

- `.\Tests\run_tests.ps1 -ImageDirectory Win64\Verification\Images` で本番 AUF2 を読み込む。`-PluginPath` で Debug / Release の検証対象を指定できる。
- 検査は登録、プリセット、5シーンの描画、シーク、単体レイヤーの再合成、扉のゼロ秒処理、描画サイズ、走行風景の高さ・ズームを確認する。1080p の走行はテストハーネスの画像受け取りも含めて計測する。
- 通常はコマンドラインでビルド・検査する。IDE・AviUtl2 内の確認は実施した場合に記録する。コピー元プロジェクト、ユーザーの AUP2、他のプラグインは変更しない。

## 初回実装の検証（2026-11-26）

- Delphi 37.0 の MSBuild で Win64 Debug / Release とも警告0・エラー0。本番 AUF2 を両構成で読み込み、5シーンと21枚の検証画像を照合した。両構成の画像は同一だった。配置先は Release の AUF2。
- 全レイヤーを有効にした画像と分離したレイヤーの再合成を比較した。全5シーンで8ビットRGB各チャンネルの差は最大3階調以内。走行の窓越しと乗車後の足元は仮の立ち絵を挟んで確認した。検証画像は `Win64\Verification\TravelTrain_Preview.png`。
- 1080pの市街地走行60フレームは Release で平均11.56 ms/フレーム。対向列車を手前に重ねると立ち絵を覆い、車体だけを揺らすと座席と窓枠の相対位置がずれた。風景の5サンプルブラー試作は風景の描画だけで平均55.48 ms/フレーム。この版は固定車体、遠近別の背景スクロール、通過電柱、ズーム、3種の風景を採用した。
- `setup` の5ファイルはコピー元とSHA-256が一致。AviUtl2 と Delphi IDE での画面確認は未実施。

## 到着・発車の車体と線路（2026-11-26）

- 添付の側面図を比率と床下の参考に、引き画の車体を論理寸法 820×182 へ変更。レールの頭頂へ車輪を接地させ、台車・床下機器・前後のスカート・前照灯と尾灯を追加した。到着は線路の奥にホーム、発車は線路の手前にもホームが見える。
- 車両長と編成数から画面内へ入る位置と画面外へ抜ける位置を計算する。設定項目やレイヤーの役割は従来どおり。
- Win64 Debug / Release は警告・エラーとも0件。AUF2 の描画検査は両構成で通過し、22枚の検証画像が一致。乗車・走行・降車の既存画像は前回の画像と一致した。配置先の Release 本体 SHA-256 は `DF3CD288FA0254BBCEDA16B6E7A4C6DF88DB8D2AECC86698608F7C7BBD636C02`。
- 描画見本とビルドログは `Win64\WideTrainVerification`。プロジェクトの出力先設定は維持し、検証時のみ MSBuild の `DCC_ExeOutput` を指定した。


## 引き画の列車の拡大と運転席窓（2026-11-26）

- 到着・発車の列車をレール上の接地点と先頭位置を基準に縦横1.5倍にした。拡大後の編成長から発車の終端位置を計算する。先頭・最後尾の運転席窓は縦長とし、流線型は上縁を車体の斜面に沿わせた。
- 到着・発車の駅だけの画像は前版と一致。Debug / Release の描画検査は22枚が一致し、両構成とも警告・エラー0件。配置した AUF2 も描画検査を通過した。配置時に退避した旧版の拡張子は `.previous`。
- 前後比較は `Win64\WideTrainScaleVerification\WideTrain_ScaleReview.png`。


- 運転席窓の高さを保ち、通勤車と箱型特急は窓の横幅を44から30へ、流線型は外形の横幅を60から40へ変更した。Debug / Release の描画検査と配置後の AUF2 検査が通過。比較画像は `Win64\CabWindowVerification\CabWindow_Review.png`。


## 乗車シーンの車内（2026-11-26）

- 参照写真をもとに乗車用の開口と扉を描き直した。閉扉時は縦長の扉窓と側窓からホームが見える。車内側に吊り革、手すり、ロングシート、袖仕切り、案内表示と敷居を描画する。
- ホーム背景、開閉する扉、手前の車内は独立した3レイヤー。開口が全開になるまでの描画と、床に立ち絵を配置できることを検査した。
- Win64 Debug / Release は警告・エラー0件で、23枚の画像が一致。配置後の AUF2 も描画検査を通過した。確認画像は `Win64\BoardCabinVerification\Boarding_Review.png`。


## 走行シーンの側窓（2026-11-26）

- 中央窓を論理寸法550×302から336×206へ縮めた。両脇の側窓も縮め、窓間に車体色と帯色に連動する閉扉を追加した。車内の座席とガラスの反射を新しい窓に合わせた。
- Debug / Release の描画検査は23枚が一致し、両構成とも警告・エラー0件。中央の立ち絵と窓の周囲の遮蔽を確認し、配置後の AUF2 も検査した。比較画像は `Win64\RunWindowVerification\RunWindow_Review.png`。


- 側面写真を参考に、走行用の扉を228×352、中央の客席窓を336×178に調整。扉窓と客席窓の上端を揃えた。両構成と配置後の AUF2 で描画検査を実施。前後比較は `Win64\RunDoorRatioVerification\RunDoorRatio_Review.png`。


- 走行時の車体前景へ床下機器箱、通風口、空気溜め、台車周辺の覆いを追加。標準ズームのレール頭頂をY=640から690へ下げ、ズーム時も車体の中心を基準に位置を追従させる。両構成と配置後の AUF2 で描画検査を実施。前後比較は `Win64\RunUnderframeVerification\RunUnderframe_Review.png`。


- 走行シーンで車体と窓から見える車内を標準ズーム時に36論理ピクセル上へ移した。レール頭頂はY=690。台車側の覆いはレール位置に合わせて調整。両構成と配置後の AUF2 で描画検査を実施。前後比較は `Win64\RunTrainPositionVerification\RunTrainPosition_Review.png`。


## AviUtl2カタログ登録時の共通ルール

1. **概要は35文字以内。** `Setup/*.catalog.json` の `summary` は、JSONのエスケープ表記ではなく実際の表示文字列を数える。機能の詳細や補足は概要に詰め込まず、説明・READMEに記載する。
2. **既存タグを優先する。** [公開カタログの `index.json`](https://github.com/Neosku/aviutl2-catalog-data/blob/main/index.json) で、同じ製品や近い用途に使われているタグの表記を確認し、用途を表すものだけを選ぶ。同義語を重ねたり、製品ごとに新しいタグを量産したりしない。
3. **配布専用フォルダー単位で導入・削除する。** ZIP内を製品専用フォルダーにまとめ、ダウンロード・展開後の配置はフォルダーの `copy` 1件、アンインストールはその専用フォルダーだけを指定する `delete` 1件を基本とする。共有フォルダーや、ユーザー素材・設定を含むフォルダーは一括削除しない。既存パッケージで変更する際は、配布ZIPの配置とセットアップスクリプトの検証条件も確認し、整合しない場合は既存の手順を維持する。
