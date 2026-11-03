# AXTestTools

固定安装的本机 macOS Accessibility 测试客户端。面向暴露标准 AX 接口的 App（不限 Swift），不保证每个 SwiftUI/AppKit 控件都能后台控制。项目负责场景与结果断言，工具不包含项目按钮、API Key 或服务逻辑。

## 安装与授权

- 源码：`~/Developer/ax-test-tools`
- App：`~/Applications/AXTestTools/AXRunner.app`
- 固定 bundle ID：`com.aloong.AXTestTools.AXRunner`
- 依赖：macOS 14+、Xcode 的 Swift 6 工具链；无第三方包。

```bash
bash Scripts/install.sh 'Developer ID Application: Your Name (TEAMID)'
bash Scripts/run.sh --preflight
```

安装先运行全量测试与 release 构建，再签名与验签。已有安装的 designated requirement 必须一致，正在运行时拒绝替换。不使用临时/ad-hoc 身份作为永久客户端，也不自动发布或公证。

首次需要用户在系统设置 → 隐私与安全性 → 辅助功能，手工添加并启用上述 **AXRunner.app**。不要再授权临时目录的旧 Runner。权限属于测试客户端，不是目标 App。固定位置和同一签名身份减少身份变化，但不保证系统永不要求重新授权；撤销权限、签名变化或系统策略变化后重新预检。

工具不调用权限弹窗、不改 TCC、不自动打开设置。

## 使用

```bash
bash Scripts/run.sh --help
bash Scripts/run.sh --check /absolute/project/scenario.json
bash Scripts/run.sh --scenario /absolute/project/scenario.json
```

`run.sh` 通过 `open -g -W -n` 启动已安装的 App，每次创建新的私有结果目录，从 `report.json` 读取真正的 `exitCode`。不能把 open 的成功当成用例成功。`--check` 只校验结构；`--preflight` 只查权限，均不执行场景。

结果含 status、exitCode、reason、stage、已完成步骤与 cleanup。0=本模式通过，77=缺授权，1/2/3=执行或清理失败，74=结果不可用。wrapper 自身输入/安装错误也非零。需看 stage 区分“schema 校验通过”与“实际交互通过”。

## JSON v1

```json
{
  "version": 1,
  "target": {
    "app": "/absolute/build/Fixture.app",
    "bundleID": "example.fixture",
    "arguments": []
  },
  "steps": [
    {"op":"wait","selector":{"AXIdentifier":"submit","AXRole":"AXButton"},"attribute":"AXEnabled","value":true,"timeout":3},
    {"op":"perform","selector":{"AXIdentifier":"submit","AXRole":"AXButton"},"action":"AXPress"},
    {"op":"wait","selector":{"AXIdentifier":"result"},"attribute":"AXValue","value":"Done","timeout":3}
  ]
}
```

- selector：AXIdentifier / AXRole / AXSubrole / AXTitle / AXDescription，组合精确匹配；0 或多项匹配失败，wait 可等待0项但不接受歧义。建议 identifier，标题选择器会受本地化影响。
- query：验证唯一存在，不证明可操作或业务成功。
- read：仅导出 AXRole、AXSubrole、AXEnabled 元数据。
- assert / wait：可比较上述选择器属性、AXValue、AXEnabled；省略 attribute/value 表示唯一存在。wait 默认3秒，可配置0–10秒。
- set：只写可写 AXValue，值为 string/bool/number。
- perform：只执行已支持且控件 enabled 的 AXPress。动作返回成功不代表业务完成，场景须额外等待结果。
- 未知字段、相对路径、空 selector、非法操作、超量步骤拒绝。单次查找最多1000节点、5秒，执行后端总限120秒，单次 AX messaging 超时1秒；这些是检查边界，不是硬实时保证。

## 安全与覆盖边界

只运行自己审查过的场景，优先使用隔离 fixture、假数据。AX 授权权限较广，场景可触发被测 App 的真实业务副作用；这不是不可信场景的安全沙箱。JSON 文件本身可能含敏感输入，不应填真实 Key 再提交仓库。

启动前校验 App 路径/bundle ID、拒绝已运行同 bundle ID；仅正常终止本次确认拥有的进程，不强杀。LaunchServices 超时无法确认归属时不误杀，报告要求手工检查可能迟到的目标启动。相同目标不要并发运行；check-before-launch 不能作为跨进程互斥锁。

不扫描其他 App 的 AX 树，不使用 AXRaise、激活目标、坐标、CGEvent、键盘或剪贴板回退。观察前台 PID/激活事件，检测变化即失败；目标自身仍可能抢焦点，这种情况报告失败，不能承诺操作完全无扰动。瞬时激活事件是否完整捕获需真实负对照验收。

报告不导出场景、输入、预期值或第三方窗口文本；敏感内容可在内存参与断言。read 元数据仅用于可信 fixture。

AX 测试不替代真实鼠标命中、键盘输入/焦点、视觉截图和窗口遮挡验收。10项单元测试验证解析与执行语义，不代表通用后台交互已经通过。授权后实测已能定位隔离Provider输入框和按钮，但AX设置值后Validate仍禁用，完整流程未通过，见验证记录。

## 开发

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

具体场景留在各项目 `Tests/AXScenarios/`；不要把项目流程塞进 Runner。安装包生成目录 `.build/package.*` 是构建产物，不是授权目标。旧临时 PoC 未自动删除，避免丢失实验记录。
