# 火次抛减CD到标准次抛

只减少火焰次抛 EAT-700 的战备冷却。

基础 CD 从 **140 秒改为 70 秒**。当前 5% 和 10% 舰船升级后，
`70 × 0.95 × 0.9 = 59.85 秒`，菜单取整显示 **60 秒**。
保留原版火焰弹头、武器模式、伤害、弹匣、外观和呼叫数量，常规 EAT-17 不变。
不同舰船升级、任务修正仍按原生规则计算，已经开始的倒计时不会重算。

这是从本地 EATAirburst 项目拆出的独立仓库，可独立构建。
所有源码、构建工具与测试均在本仓库内，无需相邻项目或 research 目录。

## 安装

见 [INSTALL.txt](INSTALL.txt)。仅提供下面两种渠道，二选一：

| 渠道 | 加载器 | 安装目录 |
| --- | --- | --- |
| v14 内置加载器 | 内含完整发布版 v14 启动代码，本包必须赢得 Wwise 启动资源优先级 | `data/` |
| v15 需要额外安装加载器 | 另装官方 Bingus Shared Loader v15 或更新版，自动发现独立入口 | `Addon/` |

不再构建 v12 包。不要与同时修改该 CD 的空爆版一起启用。
独立版的离线测试已通过，重启自动加载仍待实机验证。

## 构建与验证

需要 Windows x64、Python 3 和本机游戏的 `bin/lua51.dll`，不分发游戏 DLL。
默认游戏路径为 `C:\Program Files (x86)\Steam\steamapps\common\Helldivers 2`；
其他位置可设置环境变量 `HD2_GAME_ROOT`。

```powershell
python scripts/test.py
python scripts/build.py
```

ZIP 输出到 `releases/`。本地手动部署工具仅在游戏关闭后运行：

```powershell
python scripts/deploy.py install --channel v15
python scripts/deploy.py uninstall
```

构建首次下载官方 v14/v15 ZIP 到 `build/` 并校验固定 SHA-256；
也可提前放入 `build/Bingus-Shared-Loader-v14.zip` 和 `build/Bingus-Shared-Loader-v15.zip`。
构建过程使用真实发布版加载器做离线启动测试，校验 v14 回调保留与故障隔离、
v15 两种 patch 顺序的自动发现，以及缺失模块的处理。两种包共用相同的冷却实现字节码。
输出摘要与哈希在 `build/package-matrix.json`。构建不会部署文件或访问游戏进程。
手动部署脚本默认 v15；遇到已有资源冲突会拒绝覆盖，v14 的优先级由模组管理器处理。

## 实现范围

仅写入 EAT-700 战备记录中的一个 4 字节冷却字段：原值 140.0，新值 70.0。
校验模块 SHA-256、原生读取签名、战备 ID、名称、原值和私有可写内存。
失败时停止；还原前确认记录身份和字段仍由本模组持有。
没有武器或弹丸配置表、空爆弹药、武器菜单修改、表指针替换或内存分配接口。

当前支持 Steam build 24826606 / EXE 1.8.45317.0，具体配置见 `profile.json`。
来源说明见 [THIRD_PARTY.md](THIRD_PARTY.md)。
