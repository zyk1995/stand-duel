# 仓库结构 / Layout

竖切做到 W4：进场提示词出卡、六维结算、开阔掩体、锁定对轰、2 人主机权威房间，以及最多 3 张的胜者保留库。缩圈、排位、6 人压测、完整三视图流水线不在这里。

`docs/stand_card.schema.json` 是卡面契约。`stand/stand_validator.gd` 是运行时镜像，两边要一起改。校验器不内嵌完整 JSON Schema 引擎，因此 schema 新增字段时必须同步改 GDScript，否则会漂移。

```
.
├── project.godot             功能标签保持 4.3
├── icon.svg
├── scenes/main.tscn          主场景：地面、模板人形、掩体、锁定相机、进场 UI、HUD
├── gameplay/
│   ├── player.gd             WASD；进局后 Q / E / R 放技能
│   ├── lock_on_camera.gd     默认锁最近 / 受伤目标。人数仍少，每帧扫描
│   ├── combat_rules.gd       六维公式（无头测试直接打这里）
│   ├── combat_stub.gd        场景节点，转给 combat_rules
│   ├── cover_query.gd        线段对半掩 / 全掩
│   ├── arena_setup.gd        摆掩体和成长拾取
│   ├── match_director.gd     进局、对轰、结算到保留库
│   └── training_ai.gd        离线训练桩
├── stand/
│   ├── stand_card.gd         JSON 装载
│   ├── stand_validator.gd    总分、短板、全 3、黑名单、身高、大招代价、三连吃
│   ├── stand_library.gd      胜者保留，上限 3；对局结算满了先弃最旧
│   └── fixtures/             合法镜步旅人、合法柱卫、非法灭世巨神
├── net/
│   ├── room_authority.gd     同进程主机权威：位置、生命、施法、胜负
│   └── net_room.gd           ENet 主机 / 加入，RPC 转发快照
├── ai/
│   ├── stand_generator.gd    有 key 走 LLM，否则确定性假卡；失败会弱化重试
│   ├── costume.gd            模板人形换色 + 占位贴图
│   └── llm_config.example.cfg
├── ui/
│   ├── hud.gd                锁定、生命、技能 CD、成长层
│   └── entry_ui.gd           提示词、校验结果、确认进匹配
├── tests/                    run_w0_checks.gd … run_w4_checks.gd
└── docs/                     策划书、schema、生成提示词、本文件
```

保留库是进程内的。胜者入库前会再校验，并剥掉本局成长层；败者卡不入库。没有 `STAND_LLM_API_KEY` / `OPENAI_API_KEY`（或设置了 `STAND_LLM_DISABLE=1`）时，出卡使用夹具派生的假数据，不访问网络。
