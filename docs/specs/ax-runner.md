# 通用 AXRunner

## Problem Statement / Solution

测试客户端在临时目录、硬编码具体项目，不利于长期授权。改为固定安装、稳定签名的通用客户端，项目独立维护场景。不建设远程服务或脚本执行平台。

## Functional Requirements

### ax-runner::REQ-001 固定身份（直接验收）
源码位于用户 Developer/ax-test-tools；App 固定安装于用户 Applications/AXTestTools/AXRunner.app，固定 bundle ID 并使用现有稳定代码签名身份。不能承诺系统永不要求重新授权。

### ax-runner::REQ-002 项目场景
- ax-runner::REQ-002/AC-01：通过启动参数读取项目自己的场景与结果路径，Runner 不含项目路径、Key 或特定按钮业务。
- ax-runner::REQ-002/AC-02：按 identifier/role/subrole/title/description 精确组合定位，匹配不唯一时失败，不选第一项。
- ax-runner::REQ-002/AC-03：支持安全属性读取、属性断言、等待属性、写入可写 AXValue、执行 AXPress；系统不支持时明确失败。
- ax-runner::REQ-002/AC-04：输出结构化结果和失败阶段；open 命令成功不等于测试成功。

## Constraints

### ax-runner::CON-001 后台边界
- ax-runner::CON-001/AC-01：不申请或修改辅助功能权限；缺授权返回 blocked，不启动目标。
- ax-runner::CON-001/AC-02：不主动激活目标、不发送桌面鼠标键盘事件；前台身份变化时停止后续步骤并报告失败。
- ax-runner::CON-001/AC-03：只对明确目标 App 的 AX 树操作；启动前拒绝已运行同 bundle ID；只正常终止本次拥有的实例，不强杀或关闭其他 App。
- ax-runner::CON-001/AC-04：结果不记录字段值、期望值或第三方窗口内容；read 只导出安全元数据，敏感内容可参与断言而不写日志。

## 失败模式与边界

非法 JSON/未知字段/版本/空步骤/空 selector/不支持操作/相对目标路径：启动前拒绝。节点遍历有边界，截断不当作未找到；多个匹配失败。AX 未暴露的控件、密码属性不可写、未触发业务变化都算失败而不是偷偷回退。异步更新需等待可观察终态。目标启动失败、退出、拒绝终止和前台变化单独记录，结果写失败不报成功。用户运行未审查场景可能触发目标 App 的业务副作用，场景应仅用隔离 App/假数据。

## Implementation Decisions

JSON v1 为配置而非任意代码；只暴露窄 AX 操作。客户端仅本机单次运行，不监听端口。稳定签名不等于公证发行，本机工具不自动发布。

具体 bundle ID 为 `com.aloong.AXTestTools.AXRunner`。正常清理只处理已验证路径、bundle ID 且不在启动前进程集合中的新实例。启动超时无法确认归属时报告人工检查，不误杀；同一目标场景不支持并发调度，运行前检查不冒充互斥锁。前台 PID/事件监测是失败检测而非操作系统级焦点隔离，瞬时事件负对照仍需实测。

## Testing Decisions

LaunchServices回调显式切换主队列，不假定系统回调就在主线程。只读wait在既有期限内可重试AX cannotComplete（-25204）与 invalidUIElement（-25202，按下关闭预览后的等待中实测出现）；写入/动作不自动重试。

纯配置验证与执行语义使用单元测试；AX 系统边界可用测试替身验证错误处理，但不能替代真实 App/前台监测验收。真实交互需用户授予 AXRunner 权限。失败负对照与成功结果分开记录。

## Out of Scope

不承诺所有 Swift App 支持全部动作；无 XCUITest 等价点击保证；不做坐标点击、全桌面扫描、AXRaise、焦点强设、远程控制或自动授权。
