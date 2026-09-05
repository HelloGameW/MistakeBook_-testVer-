# 合成契约样例

本目录数据均为程序构造的测试样例，不包含真实学生数据或照片。

- `record-v1.json`：最小待分类草稿与校正文。
- `recognized-page-v1.json`：与草稿对应的图、区域、行引用。
- `taxonomy-seed-v1.json`：测试树结构的合成学科。
- `export-options-v1.json`：导出选项。
- `record-future-version.json`：用于验证未来 schema 拒绝。
- `clear-reference-patch.json`：验证显式清空与不修改的区别。

SwiftPM 测试资源副本位于 `Packages/MistakeKit/Tests/ContractsTests/Fixtures`。
