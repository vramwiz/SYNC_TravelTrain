# ライセンスと共通基盤の由来

旅行列車（SYNC_TravelTrain） Copyright (c) 2026 VRAMの魔術師

本体は GNU General Public License v3.0（GPL-3.0-only）です。全文は [LICENSE](LICENSE) を参照してください。

## AviUtl ExEdit2 Plugin SDK

Copyright (c) 2025 Kenkun、MIT ライセンス。SDK 型定義と編集 API の ABI は `Source/Lib/AviUtl2FilterTypes.pas` にあります。MIT ライセンスの全文を以下に記載します。

~~~text
The MIT License

Copyright (c) 2025 Kenkun

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
~~~

## 継承元

- **SYNC_WeatherFX** から Delphi プロジェクト設定、DLL の公開関数、SDK 型定義、フィルターテーブル登録処理を継承しました。登録処理は SYNC_AquaFX、SYNC_ParticleFX、SYNC_Mine を経由した Syncroh2 / SYNC_Lyrics 由来です。
- **SYNC_Elevator** から `TravelTrain_Canvas.pas` の Direct2D 描画プリミティブと WIC 描画先の扱いを継承しました。走行風景では視点高と遠近の計算を参考にしました。
