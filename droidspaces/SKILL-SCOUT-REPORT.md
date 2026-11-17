# Skill Scout report: skills for the Droidspaces rootfs

The container in this directory is built, published, and described by a root
filesystem feed. Before writing any of it, the existing skills were searched
and their quality was checked with [skill-scout](https://pypi.org/project/skill-scout/)
(`scan`, `asm` and `cisco` engines, `skill-scout 0.1.0`).

## Intent

| Field | Value |
|---|---|
| Task | Build a Droidspaces rootfs that hosts the complete repository, publish it as a release, and publish the `rootfs.json` feed the app reads. |
| Trigger | The container assets did not exist yet, and a reusable skill could have covered part of the work. |
| Domain | Container images, multi-architecture builds, GitHub releases, Android container runtimes. |
| Keywords | droidspaces, rootfs.json, rootfs, container image, docker buildx, multi-arch, github release, android, termux, agent skill. |

## Search

`skill-scout find` needs the skills.sh index, which this environment cannot
reach (`skills.sh` and `api.skills.sh` answer with connection errors). The
search therefore ran over the sources that are reachable, and every candidate
was scored by `skill-scout scan`, which fetches from GitHub and runs both
engines:

- GitHub code search for `SKILL.md` files matching the keywords above.
- The skills already installed in this repository (`.agents/skills/`).
- The registries named by the candidates themselves.

No purpose-built skill for Droidspaces rootfs feeds exists: a GitHub code
search for `droidspaces` in `SKILL.md` files returns one unrelated result.

## Verdicts

| Skill | Verdict | Highest severity | Finding |
|---|---|---|---|
| `rohitg00/awesome-claude-code-toolkit@docker-best-practices` | SAFE | info | no license declared |
| `H410M-H/h470skills@termux-android-poweruser` | SAFE | info | no license declared |
| `thst71/agent-skills@release` | RISKY | medium | tainted data flows into a shell sink (`setup-repository.sh:28`), executable file mode |
| `sickn33/agentic-awesome-skills@docker-expert` | RISKY | medium | code execution primitive inside `SKILL.md` |
| `diegosouzapw/awesome-omni-skill@devops/docker-buildx` | DANGEROUS | critical | command injection signature matched by YARA (`SKILL.md:299`) |
| `Ming00777/skill-scout` | DANGEROUS | high | pipeline taint flow, network script piped into a shell |
| `.agents/skills/` (this repository, 22 skills) | NOT_SCANNED | medium | code execution primitives in the macOS signing and GIF helper scripts |

## Decision

Nothing was installed.

- The two SAFE skills are documentation-only, and everything they say about
  Docker layering and Android paths is already covered by the upstream
  Droidspaces builder conventions this repository follows.
- The RISKY skills cover the release and Docker steps that this repository
  implements in reviewable scripts instead.
- The DANGEROUS ones would have been the most convenient to install, and are
  exactly the ones that must not be trusted: a skill that pipes a downloaded
  script into a shell, or whose instructions match a command-injection
  signature, is a supply-chain risk in an agent's own context.

The container assets were therefore written directly, and the risk they carry
was reduced by other means: the build is reproducible from a pinned
repository commit, the feed is generated from the published release rather
than written by hand, and every script in `scripts/` is plain shell or plain
Python that runs in the CI job with no extra credential.
