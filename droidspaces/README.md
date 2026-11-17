# DeepSeek Harness on Droidspaces

English | [中文](README.zh.md)

This directory builds a [Droidspaces](https://www.droidspaces.org/) root filesystem that carries the complete DeepSeek Harness repository, its dependencies, and the published `dsh` command. The container hosts the repository and publishes it: the Web UI serves the agent, and the working tree is published over git and HTTP.

## The feed

Droidspaces reads a feed of downloadable root files. Subscribe to this one in the app with **Containers → + → Repository → Manage Repositories**, and add the address:

```text
https://github.com/camillanapoles/deepseek-harness/releases/download/droidspaces-rootfs-v20261117-014202/rootfs.json
```

That address is the feed of the published release, and it stays valid as long as the release does. The same file lives in the repository, where every later build replaces it:

```text
https://github.com/camillanapoles/deepseek-harness/raw/refs/heads/master/droidspaces/rootfs.json
```

The app filters the entries by the device architecture, so a phone sees the `aarch64` entry and a desktop sees the `x86_64` one.

## What the container publishes

| Service | Port | Address |
|---|---|---|
| DeepSeek Harness Web UI | 3080 | `http://<container-ip>:3080/` |
| Repository over git | 9418 | `git://<container-ip>:9418/deepseek-harness` |
| Repository over HTTP | 8080 | `http://<container-ip>:8080/` |

The container address is the one Droidspaces assigns in NAT mode (`172.28.x.x`). Port forwarding (`--port=3080:3080`) makes the Web UI reachable at `http://127.0.0.1:3080/` on the phone.

The harness prints its launch URL, token included, in the container log. The app shows that log while the container starts, and the token is what opens the session in a browser.

## Inside the container

The repository lives in `/opt/deepseek-harness`, with its workspace dependencies installed and the commit it was built from recorded in `/opt/deepseek-harness/.dsh-commit`. The harness home is `/var/lib/dsh`, which keeps the sessions, the credentials, and the settings between container restarts.

```sh
droidspaces enter <container>            # a shell in the container
dsh --profile headless "summarize this repository"
```

A model is configured in the Web UI under **Settings → Models**, or through the `DEEPSEEK_API_KEY` environment variable the container inherits.

## Building the images

The build runs in GitHub Actions (`.github/workflows/droidspaces-rootfs.yml`): one job per architecture, then a publish job that creates the release and regenerates the feed.

To build one image locally:

```sh
./droidspaces/build.sh -a x86_64 -i DeepSeek-Harness -v dev
```

The script needs Docker with Buildx. It writes `DeepSeek-Harness-Droidspaces-rootfs-<arch>-<date>-<version>.tar.xz`, the file the app installs.

## Layout

```text
archs.json                    architectures -> platform and CI runner
build.sh                      build one template for one architecture
rootfs.json                   the generated feed; do not edit by hand
scripts/generate_rootfs_json.py  write the feed from the templates and the release
scripts/publish-release.sh    publish the release, regenerate the feed, commit it
scripts/dsh-init.sh           the container init Droidspaces runs as PID 1
scripts/dsh-entrypoint.sh     the services the container publishes
scripts/serve-repo.mjs        the read-only HTTP publisher for the repository
scripts/udhcpc.script         address configuration for the runtime's DHCP server
templates/<arch>/             one Dockerfile per architecture
```
