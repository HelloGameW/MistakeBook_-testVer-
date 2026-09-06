# 版本规则

App 的用户可见版本号来自 `Config/Shared.xcconfig` 中的 `MARKETING_VERSION`，构建号来自 `CURRENT_PROJECT_VERSION`。

- 修复 bug：`主版本.次版本.修订号 + 1`，例如 `0.2.0` → `0.2.1`。
- 新增功能：次版本号 `+ 1`，修订号归零，例如 `0.2.1` → `0.3.0`。
- 每次版本变更同时将构建号递增 1。

使用仓库内脚本更新版本：

```sh
sh Scripts/bump-version.sh bugfix
sh Scripts/bump-version.sh feature
```

当前版本为 `0.5.0`，构建号为 `19`。`0.5.0` 应用错题量化体系：`课标量化体系/data` 的九科课标属性层（109 个考点）随包内置，`CurriculumQuantificationEngine` 按模型 W=Σwᵢfᵢ、I=100·W·F_repeat·F_error·F_target·F_prop、P=I·(1−掌握度)^γ·F_due 评估每道错题（六大维度映射见 docs/03 §6），`evaluateValue` 注入同考点重复次数/掌握度/复习时效等行为信号，未知考点自动回退原结果。
