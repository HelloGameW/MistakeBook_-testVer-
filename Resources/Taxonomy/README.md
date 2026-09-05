# 知识树资源

`seed.json` 是 App 内置知识分类种子。生产装配通过 `Bundle.main.url(forResource: "seed", withExtension: "json", subdirectory: "Taxonomy")` 加载，并注入 `IntelligenceFactory.makeTaxonomySeedProvider(resourceURL:)`。

测试中的 synthetic seed 仅用于验证树结构，不替代正式知识树内容。
