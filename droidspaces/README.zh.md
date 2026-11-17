# Droidspaces 上的 DeepSeek Harness

[English](README.md) | 中文

本目录构建 [Droidspaces](https://www.droidspaces.org/) 根文件系统，其中包含完整的 DeepSeek Harness 仓库、它的依赖，以及已发布的 `dsh` 命令。容器托管该仓库并将其发布出来：Web UI 为智能体提供服务，工作树则通过 git 和 HTTP 发布。

## 订阅源

Droidspaces 读取一份可下载根文件的订阅源。在应用中选择 **Containers → + → Repository → Manage Repositories**，添加下面的地址即可订阅：

```text
https://github.com/camillanapoles/deepseek-harness/releases/download/droidspaces-rootfs-v20261117-014202/rootfs.json
```

该地址是已发布 release 的订阅源，只要 release 还在就始终有效。同一份文件也保存在仓库中，之后每次构建都会替换它：

```text
https://github.com/camillanapoles/deepseek-harness/raw/refs/heads/master/droidspaces/rootfs.json
```

应用会按设备架构过滤条目，因此手机看到 `aarch64` 条目，桌面设备看到 `x86_64` 条目。

## 容器发布什么

| 服务 | 端口 | 地址 |
|---|---|---|
| DeepSeek Harness Web UI | 3080 | `http://<container-ip>:3080/` |
| 仓库（git） | 9418 | `git://<container-ip>:9418/deepseek-harness` |
| 仓库（HTTP） | 8080 | `http://<container-ip>:8080/` |

容器地址是 Droidspaces 在 NAT 模式下分配的地址（`172.28.x.x`）。端口转发（`--port=3080:3080`）让 Web UI 在手机上可以通过 `http://127.0.0.1:3080/` 访问。

Harness 会在容器日志中打印带令牌的启动地址。应用在容器启动期间展示该日志，而令牌就是在浏览器中打开会话的凭据。

## 容器内部

仓库位于 `/opt/deepseek-harness`，其工作区依赖已安装，构建时使用的提交记录在 `/opt/deepseek-harness/.dsh-commit`。Harness 主目录是 `/var/lib/dsh`，它在容器重启之间保留会话、凭据与设置。

```sh
droidspaces enter <container>            # a shell in the container
dsh --profile headless "summarize this repository"
```

模型在 Web UI 的 **Settings → Models** 中配置，或者通过容器继承的 `DEEPSEEK_API_KEY` 环境变量配置。

## 构建镜像

构建在 GitHub Actions 中运行（`.github/workflows/droidspaces-rootfs.yml`）：每种架构一个作业，随后是创建 release 并重新生成订阅源的发布作业。

在本地构建一个镜像：

```sh
./droidspaces/build.sh -a x86_64 -i DeepSeek-Harness -v dev
```

该脚本需要带 Buildx 的 Docker。它写出 `DeepSeek-Harness-Droidspaces-rootfs-<arch>-<date>-<version>.tar.xz`，即应用安装的文件。

## 目录结构

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
