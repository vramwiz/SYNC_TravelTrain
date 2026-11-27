# 旅行列車の配布ファイル

`make_release_zip.bat` で、`SYNC_TravelTrain.zip` と `SYNC_TravelTrain.catalog.json` をそろえます。カタログの末尾バージョンには、同梱する本体のXXH3-128を記録します。

- `-ReleaseDirectory` は配布する `SYNC_TravelTrain.auf2` が入っているフォルダーです。省略時は `C:\ProgramData\aviutl2\Plugin\SYNC_TravelTrain` を使います。
- `-XxhsumPath` は [xxHash公式配布](https://github.com/Cyan4973/xxHash/releases/tag/v0.8.4)の `xxhsum.exe` へのパスです。省略時は `Win64\Dependencies\xxHash-0.8.4` とPATHから探します。

~~~bat
setup\make_release_zip.bat -ReleaseDirectory "D:\Release\SYNC_TravelTrain" -XxhsumPath "D:\Tools\xxhsum.exe"
~~~

ZIPには本体、README、描画例、ライセンス文書が入ります。カタログは `SYNC_TravelTrain` フォルダー単位で導入・削除します。GitHubリリースのタグとカタログのバージョンを合わせ、ZIPとJSONを添付します。
