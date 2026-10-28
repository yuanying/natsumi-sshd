# natsumi-sshd

なつみ（[yuanying/natsumi](https://github.com/yuanying/natsumi)）の Pod で、本人が作業環境と記憶の領域を ssh で直接見て直すための sshd の image。Ubuntu 24.04 に OpenSSH と、ファイルを見て直す道具を入れただけのものである。

```
ghcr.io/yuanying/natsumi-sshd:<版>
```

## 入っているもの

| 用途 | パッケージ |
|---|---|
| ssh | `openssh-server`・`openssh-client`（`ssh-keygen`・`sftp`） |
| 鍵の取得 | `curl`・`ca-certificates` |
| 見る・直す | `bash`・`vim`・`less`・`git`・`jq`・`ripgrep`・`rsync`・`procps` |

`sudo` は入れていない。ロケールのパッケージも入れていない。日本語は glibc に入っている `C.UTF-8`（`LANG=C.UTF-8`）で扱える。

## 設定は使う側が渡す

image には道具だけを入れ、設定を持たない。entrypoint も無い。次のものは使う側（なつみでは fleet-infra のマニフェスト）が ConfigMap や Secret のマウントで渡す。

- `sshd_config`（`sshd -f` で指定する）
- ログインのシェル
- `/etc/passwd`・`/etc/group`（ログインするユーザーを含める）
- ホスト鍵。**image にはホスト鍵が無い**（パッケージが作ったものは消してある）ので、既定の `CMD`（`sshd -D -e`）のままでは起動しない
- 入れる公開鍵（`authorized_keys`）

root でなく、ログインするユーザーそのもので sshd を動かす前提である。この形では特権の分離を使わないので、`/run/sshd` などのディレクトリは要らず、ルートのファイルシステムを読み取り専用にしても起動する。sshd_config では `UsePAM no`・`PidFile none` とし、鍵のマウントが root の持ち物になるなら `StrictModes no` とする。

## 確かめ方

`test/run.sh` は、この image を上の形（UID 1001・読み取り専用のルート・capability なし・設定はマウント）で動かし、鍵の取得、ログイン、道具が使えることを確かめる。設定の例は `test/fixture/` にある。

```sh
docker build -t natsumi-sshd:test .
test/run.sh natsumi-sshd:test
```

- `CONFIG_DIR` に、実際に使う設定のディレクトリ（`sshd_config`・`shell`・`passwd`・`group`・`fetch-keys.sh`）を渡すと、それで確かめる。
- `FETCH_URL`（たとえば `https://github.com/<ユーザー>.keys`）を渡すと、そこから鍵を取れることも確かめる。
- docker のデーモンから見えない `/tmp` で動かしている場合は、`TMPDIR` を見える場所にする。

pull request と main への push では、GitHub Actions（`.github/workflows/image.yml`）が build と `test/run.sh` を行う。pull request では push しない。

main への push では、確かめたあと `ghcr.io/yuanying/natsumi-sshd:main` を push する。脆弱性の集計役がこれをスキャンし、main で直ったがリリースされていないものを見分ける。どの image にも `org.opencontainers.image.source` と、build したコミットの `org.opencontainers.image.revision` のラベルが付く。`:main` を上書きして tag の外れた古い image は、続くジョブ（`cleanup`、[dataaxiom/ghcr-cleanup-action](https://github.com/dataaxiom/ghcr-cleanup-action)）が消す。tag の付いた image は消さない。

## リリース

`v` で始まる版の tag を push すると、同じ workflow が確かめたあと `ghcr.io/yuanying/natsumi-sshd:<版>`（tag から `v` を除いたもの）と `latest` を push する。プラットフォームは amd64 だけである。

```sh
git tag v0.1.0
git push origin v0.1.0
```

### 週に一度のリリース

`.github/workflows/release.yml` が毎週月曜 09:00 JST に動く。最新の `vX.Y.Z` の tag から main の HEAD までに `Dockerfile` が変わっていれば、パッチ版を一つ上げた版（`v0.1.0` の次は `v0.1.1`）で image を確かめて push し、そのあとで tag を打つ。image の中身は `Dockerfile` だけで決まるので、workflow・`renovate.json`・`test/`・`README.md` だけの変更ではリリースしない。変わっていなければ何もしない。Actions の画面から `workflow_dispatch` で手でも動かせる。

### 脆弱性の直しのすぐのリリース

脆弱性対応の係（vuln-responder）が出した直しの PR（ブランチ名が `vuln-responder/` で始まる）を main にマージすると、同じ `release.yml` がすぐに動き、週を待たずに次のパッチ版を出す。出し方は週次と同じで、main の HEAD から image を確かめて push し、最後に tag を打つ。係は tag を打たない。

すぐに出すのは、最新の `vX.Y.Z` 以降に `Dockerfile` を変えたコミット（マージコミットを除く）の作者が、すべて `renovate[bot]` か `fraction-vuln-responder[bot]` のときだけである（`.github/release/blocking-commits.sh`）。人のコミットが一つでもあれば出さず、その run の job summary に止めたコミットの一覧と、手で出すコマンド（`gh workflow run release.yml --ref main`）を書く。`Dockerfile` を変えないコミット（workflow や README）は image に入らないので数えない。`Dockerfile` が変わっていなければ何もしない。

週次のリリースは作者を見ずに `Dockerfile` の変更で出すので、すぐのリリースが失敗しても、直しは次の月曜に出る。

スクリプトのテストは次で動かす。

```sh
.github/release/next-version_test.sh
.github/release/blocking-commits_test.sh
```

依存の更新は Renovate（`renovate.json`）が PR にする。パッチ版とダイジェストの更新は、PR の確かめが通れば Renovate がマージする。

### package を public にする

ghcr の package は、最初の push で private になることがある。package の公開範囲は REST API では変えられないので、最初のリリースのあとに GitHub の画面で変える。

1. `https://github.com/users/yuanying/packages/container/natsumi-sshd/settings` を開く
2. 「Danger Zone」の「Change visibility」で Public を選ぶ

