# 替身对决 / Stand Duel

Godot 4.x 3D 竖切的 W0 骨架：占位人形、锁定第三人称相机、替身卡校验，以及最多 3 张的胜者保留库。这一版不能完成一局对轰。

## 中文

玩家用提示词生成人形替身，在开阔掩体图里技能对轰；只有活到最后的人能带走本局替身。策划口径以 `docs/GDD.md` 为准。生成模型的护栏在 `docs/stand_generator_system_prompt.md`，卡面契约在 `docs/stand_card.schema.json`。

W0 已经做的：

- 主场景里有地面、约 1.8 米的胶囊占位人、锁定相机和一只训练桩
- WASD / 方向键移动，Tab 开关锁定。默认锁最近目标；节点 meta `hurt_priority` 越高越优先（同距离下的受伤目标）
- 校验器：六维之和必须为 18；至多一个 5，有 5 则至少一个 ≤ 2；拒绝六维全 3；黑名单词；必须人形且身高 1.5–2.0 米；大招必须带代价；拒绝单个技能同时绑定力量、速度、射程
- 保留库最多 3 张，满了必须先弃旧。入库前会再跑一遍校验
- `net/`、`ai/`、`gameplay/combat_stub.gd` 只返回「尚未实现」

用 Godot 4.3–4.7 打开项目根目录，F5 运行 `scenes/main.tscn`。`project.godot` 的功能标签写成 4.3，是为了老编辑器也能打开；本仓库在 Godot 4.7.2 上跑过无头自检。

```bash
godot --headless --path . --script res://tests/run_w0_checks.gd
```

通过时进程退出码为 0，并打印 `W0 checks passed`。

## English

W0 is a Godot 4.x 3D scaffold: a placeholder humanoid, a lock-on third-person camera, a stand-card validator, and a winner library capped at 3 cards. It is not a finished match.

Rules live in `docs/GDD.md`. The generator guardrail is `docs/stand_generator_system_prompt.md`. The card contract is `docs/stand_card.schema.json`. Directory map: `docs/REPO_STRUCTURE.md`.

The validator requires stats to sum to 18, enforces the short-stat rule, rejects an all-3 spread, rejects blacklist phrases, requires a humanoid between 1.5 m and 2.0 m, requires an ultimate cost, and rejects a skill bound to power, speed, and range together. `stand/fixtures/valid_mirror_walker.json` must pass. `stand/fixtures/invalid_overpowered.json` must fail. Networking, card generation, and hit resolution are stubs.

Open the repo in Godot 4.3–4.7 and run the main scene. The feature tag stays on 4.3 so older 4.x editors can still load the project. Headless checks were run on Godot 4.7.2:

```bash
godot --headless --path . --script res://tests/run_w0_checks.gd
```

Exit code 0 and the line `W0 checks passed` mean the scaffold is intact.

## License

MIT. See `LICENSE`.
