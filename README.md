# 替身对决 / Stand Duel

Godot 4.x 3D 竖切（W0–W4）：提示词出卡、校验、模板人形、锁定对轰、胜者保留最多 3 张。这一版能打完一局，不做缩圈、排位、6 人压测，也不做完整三视图或图生模。

## 中文

玩家用提示词生成人形替身，在开阔掩体图里技能对轰；只有活到最后的人能带走本局替身。策划口径以 `docs/GDD.md` 为准。生成护栏在 `docs/stand_generator_system_prompt.md`，卡面契约在 `docs/stand_card.schema.json`。目录见 `docs/REPO_STRUCTURE.md`。

本机 F5：用 Godot 4.3–4.7 打开项目根目录，运行 `scenes/main.tscn`。`project.godot` 的功能标签写成 4.3，是为了老编辑器也能打开；脚本不使用 4.4+ 专属语法。

进场面板在右侧：

1. 写下提示词，按「生成并校验」。没有 API key 时用确定性假卡，界面会写明来源。
2. 校验通过后按「确认进匹配」。
3. WASD 移动，Tab 切换锁定。Q / E 是两个小技能，R 是大招。绿色球拾取成长，本局最多 3 层。
4. 击倒训练桩后，胜者卡写入保留库（最多 3 张，满了丢最旧的一张）。败者卡不入库。成长层不带走。

要接真实 LLM，任选一种（不要把 key 提交进仓库）：

- 环境变量 `STAND_LLM_API_KEY` 或 `OPENAI_API_KEY`
- 可选 `STAND_LLM_BASE_URL`（默认 `https://api.openai.com/v1`）、`STAND_LLM_MODEL`（默认 `gpt-4o-mini`）
- 或复制 `ai/llm_config.example.cfg` 为 `ai/llm_config.cfg` 再填 `api_key`
- `STAND_LLM_DISABLE=1` 时即使有 key 也走假数据

文生图仍是占位：按卡名涂色，并在 `user://stand_portrait_placeholder.png` 写一张纯色图。

双开 2 人（主机权威，客户端把出卡和操作交给主机）：

```bash
godot --path . -- --host 7777
godot --path . -- --join 127.0.0.1 7777
```

无头检查（通过时退出码 0）：

```bash
godot --headless --path . --script res://tests/run_w0_checks.gd
godot --headless --path . --script res://tests/run_w1_checks.gd
godot --headless --path . --script res://tests/run_w2_checks.gd
godot --headless --path . --script res://tests/run_w3_checks.gd
godot --headless --path . --script res://tests/run_w4_checks.gd
```

期望打印：

- `W0 checks passed`
- `W1 checks passed`
- `W2 checks passed`
- `W3 checks passed`
- `W4 checks passed`

本仓库在 Godot 4.3 stable 上跑过这些无头检查。

## English

The vertical slice covers prompt-to-card, validation, a tinted template humanoid, lock-on combat, and a winner library capped at 3 cards. It is not a battle royale with a shrinking circle, ranked matchmaking, a six-player soak test, or image-to-mesh.

Rules live in `docs/GDD.md`. The generator guardrail is `docs/stand_generator_system_prompt.md`. The card contract is `docs/stand_card.schema.json`. Directory map: `docs/REPO_STRUCTURE.md`.

Open the repo in Godot 4.3–4.7 and run `scenes/main.tscn` (F5). The feature tag stays on 4.3. Enter a prompt, generate, confirm, then fight with Q / E / R. Tab toggles lock-on. Without an API key the generator returns a deterministic fixture-backed card and says so in the UI. Set `STAND_LLM_API_KEY` or `OPENAI_API_KEY` for a real OpenAI-compatible chat completion. Image generation stays a flat placeholder color.

Two processes:

```bash
godot --path . -- --host 7777
godot --path . -- --join 127.0.0.1 7777
```

Headless checks, exit code 0:

```bash
godot --headless --path . --script res://tests/run_w0_checks.gd
godot --headless --path . --script res://tests/run_w1_checks.gd
godot --headless --path . --script res://tests/run_w2_checks.gd
godot --headless --path . --script res://tests/run_w3_checks.gd
godot --headless --path . --script res://tests/run_w4_checks.gd
```

Passing lines: `W0 checks passed`, `W1 checks passed`, `W2 checks passed`, `W3 checks passed`, `W4 checks passed`.

## License

MIT. See `LICENSE`.
