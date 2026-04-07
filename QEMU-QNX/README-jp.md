# wolfBoot セキュアブート + OTA デモ (QEMU/QNX)

このサンプルは、**QNX 8.0** を **QEMU x86_64** 上で UEFI ブートさせ、
[wolfBoot](https://github.com/wolfSSL/wolfBoot) によるセキュアブートと
OTA (Over-The-Air) ファームウェアアップデートを実演します。

## デモシナリオ

| シナリオ | 操作 | 結果 |
|---|---|---|
| セキュアアップデート v1→v2 | v1 起動 → `update` → `reboot` | wolfBoot が v2 署名を検証・コミットし v2 が起動 |
| 改ざん検知 | v1 起動 → `update` → `attack` → `reboot` | wolfBoot がハッシュ不一致を検出し更新を拒否、v1 継続 |
| バージョンチェック | v2 起動 → `update` → `reboot` | wolfBoot が同バージョンを拒否、v2 継続 |
| 単純再起動 | 任意 → `reboot` | 同バージョンで起動継続 |

## 動作の仕組み

```
OVMF (UEFI ファームウェア)
  └─▶ wolfBoot.efi  (ESP 上の EFI アプリケーション)
       ├─ ESP FAT パーティションから kernel.img と update.img を読み込む
       ├─ ED25519 署名を検証 (SHA256 ハッシュ)
       ├─ update.img のバージョン > kernel.img のバージョンの場合:
       │    コミット (kernel.img を上書き)、update.img を削除
       └─▶ QNX startup (PE32+、0x1400000 にロード)
            └─▶ app_v1  または  app_v2
                 └─ ユーザーが "update" を入力:
                      /proc/boot/ifs_v2_signed.bin を
                      FAT マウント経由で /fs/esp/update.img に書き込む
```

## 前提条件

### プラットフォーム

- **Ubuntu 22.04 または 24.04** (x86_64、ネイティブまたは VM)
- 空きディスク容量 約 2 GB、RAM 約 4 GB

### パッケージ

```bash
sudo apt install \
    qemu-system-x86_64 \
    dosfstools mtools gdisk \
    ovmf gnu-efi \
    git make autoconf automake libtool
```

### QNX SDP 8.0

QNX SDP (Software Development Platform) は QNX イメージのビルドおよびデモアプリの
クロスコンパイルに必要な商用ソフトウェアです。

1. [BlackBerry QNX](https://www.qnx.com/) からインストーラーを入手します
   (myQNX アカウントと有効なライセンスが必要です)
2. デフォルトの場所にインストールします:
   ```bash
   chmod +x qnx-setup-2.0.x-linux.run
   ./qnx-setup-2.0.x-linux.run
   # デフォルトのまま進める → ~/qnx800/ にインストールされる
   ```
3. クロスコンパイラを確認します:
   ```bash
   source ~/qnx800/qnxsdp-env.sh
   qcc --version   # Toolchain: gcc  Version: 12.2.0
   ```

## クイックスタート

```bash
# 1. リポジトリをクローン
git clone https://github.com/wolfSSL/wolfboot-examples.git
cd wolfboot-examples/QEMU-QNX

# 2. QNX 環境を読み込む
source ~/qnx800/qnxsdp-env.sh

# 3. ビルド (初回は約 10 分)
./scripts/build.sh

# 4. デモを実行
./scripts/run.sh
```

> **ヒント:** KVM を有効にすると起動が大幅に速くなります (約 5 秒 vs 約 90 秒):
> ```bash
> sudo usermod -aG kvm $USER   # ログアウト→ログインし直す
> ```

## デモの実行例

### v1 起動時

QNX が起動すると次のプロンプトが表示されます:

```
************************************
*  wolfBoot Demo: QNX v1 booted    *
************************************

Commands:
  reboot  -- reboot (stay on v1)
  update  -- write update.img, reboot to upgrade to v2
  attack  -- corrupt update.img then reboot (tamper demo)
```

### シナリオ 1 — セキュアアップデート (v1 → v2)

```
> update
Writing update.img to ESP...
ESP mounted: /dev/hd0.efi.0 -> /fs/esp
update.img written: 32127232 bytes
Done. Type 'reboot' to boot v2.
> reboot
```

次の起動時の wolfBoot 出力:

```
Opening file: kernel.img, size: 42838272
Opening file: update.img, size: 32127232
Trying partition 1 at ...
Checking integrity...done
Verifying signature...done
Successfully selected image in part: 1
[WB] Update accepted (version newer), committing
[WB] Committing update.img -> kernel.img
[WB] commit: done
Firmware Valid
```

QNX v2 が起動し、次のバナーが表示されます:

```
*********************************************
*  wolfBoot Demo: QNX v2 booted            *
*  Secure OTA update complete!             *
*  wolfBoot verified the v2 signature.     *
*********************************************
```

### シナリオ 2 — 改ざん検知

```
> update          # update.img を書き込む
> attack          # offset 512 の 1 バイトを破壊
> reboot
```

wolfBoot 出力:

```
Checking integrity...FAILED
Failure -1: Part 1, Hdr 1, Hash 0, Sig 0
Active is now: 0
Trying partition 0 at ...
Checking integrity...done
Verifying signature...done
[WB] Update REJECTED: signature verification FAILED (update tampered!)
Firmware Valid
```

改ざんされた update.img は無視され、QNX v1 が再び起動します。

### シナリオ 3 — バージョンチェック (v2 から)

```
> update          # 同バージョン (v2) の update.img を書き込む
> reboot
```

wolfBoot 出力:

```
[WB] Update rejected: version not newer (update=2, kernel=2)
Firmware Valid
```

QNX v2 がそのまま起動し続けます。

## ディレクトリ構成

```
QEMU-QNX/
├── README.md                  英語ドキュメント
├── README-jp.md               日本語ドキュメント (本ファイル)
├── Makefile                   QNX x86_64 クロスコンパイル設定
├── app_v1.c                   デモアプリ v1 (update トリガー + 改ざんシミュ)
├── app_v2.c                   デモアプリ v2 (アップデート完了バナー)
├── update_helper.c/h          ESP FAT ヘルパー (マウント/書き込み/アンマウント)
├── wolfboot.config            wolfBoot ビルド設定 (ED25519, x86_64_efi)
├── snippets/
│   ├── v1/ifs_files.custom    v1 IFS に組み込むファイル (/proc/boot/)
│   ├── v1/post_start.custom   QNX v1 起動コマンド (app_v1 自動起動)
│   ├── v2/ifs_files.custom    v2 IFS に組み込むファイル
│   └── v2/post_start.custom   QNX v2 起動コマンド (app_v2 自動起動)
└── scripts/
    ├── build.sh               全自動ビルドスクリプト
    └── run.sh                 QEMU 起動スクリプト (KVM 自動検出)

build/                         build.sh が生成 (git 管理外)
├── wolfboot/                  wolfBoot クローン (qemu-qnx ブランチ)
├── app_v1, app_v2             コンパイル済みデモアプリ
├── qnx-image-base/            ベース QNX イメージ (local/ 雛形)
├── qnx-image-v1/              QNX v1 作業ディレクトリ
├── qnx-image-v2/              QNX v2 作業ディレクトリ
├── keys/                      ED25519 鍵と署名済みイメージ
├── esp.img                    ESP FAT32 イメージ (作業用)
├── wolfboot-demo.img          最終 QEMU GPT ディスクイメージ (640 MB)
└── OVMF_VARS.fd               UEFI 変数ストア (--reset でリセット可)
```


## ライセンス

- デモアプリケーションコード (`app_v1.c`, `app_v2.c`, `update_helper.*`):
  GPLv2 — Copyright (C) 2025 wolfSSL Inc.

詳細は [wolfBoot LICENSE](https://github.com/wolfSSL/wolfBoot/blob/master/LICENSE)
および [wolfboot-examples LICENSE](../LICENSE) を参照してください。
