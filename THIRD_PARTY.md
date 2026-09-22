# 来源

- 冷却字段、Windows 适配与初始化逻辑从本地 EATAirburst 0.2.1 拆分，去除所有武器表处理。
- `scripts/lua_host.py` 来自本地 RoverFireSpread 的构建工具。
- `scripts/archive.py` 的资源 hash / archive 编码实现来自本地 CowboyBingus/SentryAimRetention 工作副本。
  上游地址：https://github.com/CowboyBingus/SentryAimRetention 。该工作副本未声明仓库级许可证。
- v14 启动包装与 v15 发现集成测试参考本地 RoverFireSpread 的多渠道构建约定，已在本仓库独立实现。
- Bingus Shared Loader：https://github.com/CowboyBingus/BingusSharedLoader 。
  v14 包封装完整官方 v14 Wwise 回调字节码；v15 包不含加载器，需另行安装官方 v15 或更新版。
  固定输入及 SHA-256：
  - v14：https://github.com/CowboyBingus/BingusSharedLoader/releases/download/v14/Bingus-Shared-Loader-v14.zip
    `7FA8AF328AC2C98F68DD5946D94444315DD61B2B3504B0788301700CC9C023B2`
  - v15（仅用于测试）：https://github.com/CowboyBingus/BingusSharedLoader/releases/download/v15/Bingus-Shared-Loader-v15.zip
    `FA766634DFF3F7D1FD9C5C0EBA72B1FBABAD8721710491CAAA4E12A598028CDA`

安装包不包含游戏 DLL、完整游戏配置表或进程内存记录。

- 0.2.0 在原版燃烧弹丸上增加近炸参数；字段结构参考 Filediver projectile_settings.go，并以本机 build 25327279 运行时记录核对。保留原生燃烧爆炸 ID，不移植空爆载荷。
