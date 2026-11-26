# ライセンスと共通基盤の由来

旅行列車（SYNC_TravelTrain） Copyright (c) 2026 VRAMの魔術師

本体は GNU General Public License v3.0（GPL-3.0-only）です。全文は [LICENSE](LICENSE) を参照してください。

## AviUtl ExEdit2 Plugin SDK

Copyright (c) 2025 Kenkun、MIT ライセンス。SDK 型定義と編集 API の ABI は `Source/Lib/AviUtl2FilterTypes.pas` にあります。ライセンス全文は [ThirdParty/LICENSE.AviUtl2-SDK.txt](ThirdParty/LICENSE.AviUtl2-SDK.txt) を参照してください。

## 継承元

- **SYNC_WeatherFX** から Delphi プロジェクト設定、DLL の公開関数、SDK 型定義、フィルターテーブル登録処理を継承しました。登録処理は SYNC_AquaFX、SYNC_ParticleFX、SYNC_Mine を経由した Syncroh2 / SYNC_Lyrics 由来です。
- **SYNC_Elevator** から `TravelTrain_Canvas.pas` の Direct2D 描画プリミティブと WIC 描画先の扱いを継承しました。走行風景では視点高と遠近の計算を参考にしました。
