# Treescope 调研文档

> 一个开源的 SwiftUI + UIKit/AppKit **运行时视图检查器**（view inspector）。
> 目标：做 Lookin / LookInside 的开源替代，重点补齐它们**闭源的 SwiftUI 检查能力**。
> Slogan: *Put your SwiftUI tree under the scope.*
>
> 本文件是项目启动前的可行性调研存档（调研日期：2026-05-28）。后续在本目录重新开始时，以此为上下文起点。

---

## 0. 命名与包结构

- **`Treescope`** —— Mac 端客户端（查看器，对应 LookInside 那个 GPL 客户端的角色）。
- **`TreescopeServer`** —— 注入到被调试 App 里的 **debug-only** 运行时（SwiftUI/UIKit 抓取引擎），通过 SPM / CocoaPods 分发。
- 关键点：server 是 **Debug-only**（Release 构建排除），所以即便用到私有 API，**也不受 App Store 审核约束**。这正是 LookInside 敢用 `_viewDebugData`/AttributeGraph 的原因。
- GitHub Swift 生态零撞名（`Treescope`、`Glasswing`、`Heartwood` 当时均为 0 命中；`Loupe` 已被一个 SwiftUI 调试库占用，弃用）。

---

## 1. 背景：Lookin / LookInside 的开源现状

| 项目 | 仓库 | License | 范围 |
|---|---|---|---|
| **Lookin**（原版） | `QMUI/LookinServer` | MIT，**真开源** | **仅 UIKit/CALayer**，无 SwiftUI 树检查（源码搜 `SwiftUI`/`_ViewDebug` 零命中，只有 demo 里有） |
| **LookInside**（继任） | `LookInsideApp/LookInside` | GPL-3.0 | Mac **客户端**开源 |
| LookInside 运行时 | `LookInsideApp/LookInside-Release` | none（无 LICENSE 文件） | **闭源**：`.binaryTarget` 指向签名的 `LookInsideServer.xcframework.zip` |

- LookInside 的 SwiftUI 检查能力在运行时 server 里，而 server **只发布预编译签名二进制**，源码在私有上游仓库（CI 里 `UPSTREAM_SERVER_REPO_URL` 是 GitHub secret）编译。
- `LookInsideServerXcodeProj`、`LookInsidePrivateDiscriminator` 等公开仓库只是下载/集成那个二进制的"壳"。
- License 不一致：CocoaPods podspec 写 `license MIT`，但不给源码——MIT 声明在无源码下意义不大。
- **结论：SwiftUI 检查是 LookInside 相对原版 Lookin 新增、且闭源的增量。Treescope 要做的就是把这块开源化。**

---

## 2. 核心问题：SwiftUI 的 ViewTree / Modifier / Layout / 实时属性，能做出来吗？

**能。** Apple 自家的 Xcode "Debug View Hierarchy" 就是这么干的，且每条关键技术路径都有公开的开源实现可参考。没有原理上的拦路虎——难的是「把碎片拼成稳定产品」和「跨系统版本维护」。

---

## 3. 三条技术路径

| 路径 | 技术 | 能拿到 | 代价 / 局限 | 开源证据 |
|---|---|---|---|---|
| **A. 私有 `_viewDebugData()`** | 调 `_UIHostingView` / `NSHostingView` 的私有方法（新版 `makeViewDebugData()`），返回一大坨 JSON（以 `SwiftUI._ViewDebug.Property` 为 key） | **树 + modifier + 解析后真实 frame/size + 属性**，一次调用全有（Xcode 视图调试器同源） | 私有 API（上架被拒，但 debug-only 无所谓）；跨版本易碎；只有 hosting view 暴露（需把 root 包进 hosting controller）；输出巨大 | **`OpenSwiftUIProject/SwiftUIViewDebug`**（MIT）——已证明可导出 JSON，但只是导出器，无 UI |
| **B. Mirror 反射** | 纯公开 API，`Mirror(reflecting:)` 走 `body` 结构、`ModifiedContent<Content,Modifier>`、`_VariadicView.Tree` | 视图类型树、modifier 的**声明参数**、`@State`/`@Binding`（**渲染后**读才有值） | **拿不到解析后的布局几何**（只有 `.frame(width:)` 入参，不是屏幕坐标）；跨版本内部字段会变 | **`nalexn/ViewInspector`**（MIT，2.6k★，仅单测用）；`_VariadicView` 枚举子视图是 movingparts.io 记录的半官方手法 |
| **C. AttributeGraph (AGGraph)** | 直接调私有 `AttributeGraph.framework` 的 C 符号；`AGGraphArchiveJSON(path, graph)` 把整张依赖图 dump 成 JSON | **真正实时的 `@State`/属性值**——SwiftUI 的"树"本质就是这张图，结构体只是临时喂进去 | 最脆：SwiftUI 符号被 strip、靠寄存器/指针 hack、强绑系统版本 ABI | **`OpenSwiftUIProject/OpenAttributeGraph`**（@Kyle-Ye 重写 ABI）；Rens Breur《Untangling the AttributeGraph》 |

---

## 4. 各能力可达性小结

| 能力 | 可达性 |
|---|---|
| 视图树 + 视图类型 | ✅ Mirror（公开安全）；或 `_viewDebugData`（含真实结构） |
| Modifier 值 | ✅ 声明参数 via Mirror；**真实/计算后** via `_viewDebugData` |
| Layout / frame | requested 值 via Mirror；**resolved 屏幕几何** via `_viewDebugData` 或 UIKit backing（`siteline/swiftui-introspect`，覆盖不全） |
| 实时 `@State`/属性 | Mirror 渲染后能读部分；**真正实时**只有 AttributeGraph 路径（最难、最脆） |

---

## 5. 传输层

- 原版 Lookin 用 **Peertalk** 走 USB/loopback TCP，把 in-app server 抓到的数据传到 Mac 端。
- 现成参考：`QMUI/LookinServer` 里的 `Lookin_PTChannel` / `LKS_ConnectionManager`（监听 `127.0.0.1`，模拟器/USB 端口段）。
- Mac 客户端渲染逻辑可参考 `LookInsideApp/LookInside`（GPL-3.0，注意 license 传染性）。

---

## 6. 开源参考清单

| 仓库 | License | 作用 / 技术 |
|---|---|---|
| `OpenSwiftUIProject/SwiftUIViewDebug` | MIT | 封装私有 `_viewDebugData`/`_ViewDebug`，导出 JSON。**含一份 `Resources/example.json`，是设计数据模型的最佳起点** |
| `nalexn/ViewInspector` | MIT | Mirror 反射读视图/modifier/`@State`（仅单测，覆盖不全） |
| `siteline/swiftui-introspect` | MIT | 走 UIKit/AppKit backing 拿真实 frame/平台对象（不读 SwiftUI 树） |
| `OpenSwiftUIProject/OpenAttributeGraph` | — | AttributeGraph ABI 重写，研究 AGGraph 符号/结构 |
| `QMUI/LookinServer` | MIT | UIKit 树抓取 + Peertalk 传输的完整参考实现 |
| `DebugSwift/DebugSwift` | MIT | in-app overlay；SwiftUI 仅 re-render 追踪（beta） |
| `ipedro/Inspector` | MIT | in-app UIKit 层级/属性面板（UIKit only） |
| `ole/swiftui-layout-inspector` | 无 SPDX | 教学性 layout proposal 探测（仅被插桩视图） |

---

## 7. 推荐落地路线（Roadmap）

1. **MVP（路径 A）**：把要查的 root 包进 hosting controller，调 `makeViewDebugData()` 拿 JSON → 先在控制台 dump 出一棵 SwiftUI 树。性价比最高的起点。
   - 先拆 `OpenSwiftUIProject/SwiftUIViewDebug` 的 `example.json`，搞清 `_ViewDebug.Property` 结构，定下 `ViewNode` 数据模型。
2. **传输层**：接 Peertalk（参考 `Lookin_PTChannel`），把 JSON 传到 Mac。
3. **Mac 端面板**：树视图 + 属性面板 + 截图/frame 叠加。
4. **实时属性（路径 C）**：要做到运行时改属性即时反映，再接 AttributeGraph 读活节点（research-grade，最后做）。

---

## 8. 待定决策

- **License**：MIT vs GPL-3.0 vs MPL-2.0。
  - 想最大采用率 → MIT。
  - 想做开源替代品、防止被闭源 fork（LookInside 正是闭源化了 server）→ 可考虑 GPL-3.0 / MPL-2.0。
  - **尚未决定，开工时确认。**

---

## 9. 风险 / 注意

- **维护成本是核心**：私有 API + AttributeGraph 每个 iOS 大版本都可能 break。这块持续维护正是闭源收费的合理性所在，也是开源版要扛的主要负担。
- 方法名已变过：`_viewDebugData` → `makeViewDebugData`，需做多选择子兼容。
- **务必 Debug-only**：Release 构建排除 `TreescopeServer`（SPM 设 `Excluded Source File Names`，或 CocoaPods `:configurations => ["Debug"]`），把直接调用收在 Debug 代码路径里。

---

## 参考链接

- LookInside Mac 客户端：https://github.com/LookInsideApp/LookInside
- LookInside 运行时（闭源二进制）：https://github.com/LookInsideApp/LookInside-Release
- 原版 Lookin server：https://github.com/QMUI/LookinServer
- SwiftUIViewDebug（私有 `_viewDebugData` 封装 + example.json）：https://github.com/OpenSwiftUIProject/SwiftUIViewDebug
- ViewInspector（Mirror 反射）：https://github.com/nalexn/ViewInspector
- swiftui-introspect（UIKit backing）：https://github.com/siteline/swiftui-introspect
- OpenAttributeGraph：https://github.com/OpenSwiftUIProject/OpenAttributeGraph
- Rens Breur《Untangling the AttributeGraph》：https://rensbr.eu/blog/swiftui-attribute-graph/
- Moving Parts《Variadic Views in SwiftUI》：https://movingparts.io/variadic-views-in-swiftui
- EmergeTools《Calling Hidden Swift Functions》：https://www.emergetools.com/blog/posts/calling-hidden-swift-functions
- `_viewDebugData` 写法（apurin.me）：https://apurin.me/articles/swiftui-secrets/
