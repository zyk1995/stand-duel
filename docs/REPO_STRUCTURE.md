# 仓库结构 / Layout

W0 只放工程骨架、锁定相机、占位人形，以及替身卡的 schema、校验器和最多 3 张的保留库。战斗数值、房间同步、LLM 出卡都是占位。

`docs/stand_card.schema.json` 是卡面契约。`stand/stand_validator.gd` 是运行时镜像，两边要一起改。校验器不内嵌完整 JSON Schema 引擎，因此 schema 新增字段时必须同步改 GDScript，否则会漂移。

```
.
├── project.godot
├── icon.svg
├── scenes/main.tscn          主场景：地面、占位人、锁定相机、桩、HUD
├── gameplay/
│   ├── player.gd             WASD 占位移动
│   ├── lock_on_camera.gd     默认锁最近 / 受伤目标
│   └── combat_stub.gd        结算顺序占位，伤害留到 W1
├── stand/
│   ├── stand_card.gd         JSON 装载
│   ├── stand_validator.gd    总分、短板、全 3、黑名单、身高、大招代价、三连吃
│   ├── stand_library.gd      胜者保留，上限 3，超限须先弃旧
│   └── fixtures/             合法镜步旅人、非法灭世巨神
├── net/net_room.gd           主机权威房间占位（W2）
├── ai/stand_generator.gd     提示词出卡占位（W3）
├── ui/hud.gd                 锁定状态一行字
├── tests/run_w0_checks.gd    无头自检
└── docs/                     策划书、schema、生成提示词、本文件
```

竖切之后的落点：W1 在 `gameplay/combat_stub.gd` 接六维结算和掩体；W2 在 `net/` 与 `stand_library.gd` 接 2 人房间和胜负保留；W3 在 `ai/` 与 `ui/` 接 LLM 与进场提示词。缩圈、排位、6 人压测不在这套目录里展开。
