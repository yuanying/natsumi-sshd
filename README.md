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

pull request と main への push では、GitHub Actions（`.github/workflows/image.yml`）が build と `test/run.sh` を行う。push はしない。

## リリース

`v` で始まる版の tag を push すると、同じ workflow が確かめたあと `ghcr.io/yuanying/natsumi-sshd:<版>`（tag から `v` を除いたもの）と `latest` を push する。プラットフォームは amd64 だけである。

```sh
git tag v0.1.0
git push origin v0.1.0
```

### package を public にする

ghcr の package は、最初の push で private になることがある。package の公開範囲は REST API では変えられないので、最初のリリースのあとに GitHub の画面で変える。

1. `https://github.com/users/yuanying/packages/container/natsumi-sshd/settings` を開く
2. 「Danger Zone」の「Change visibility」で Public を選ぶ

