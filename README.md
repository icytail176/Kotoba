# Kotoba

Kotoba 是一款原生 macOS 日语词汇学习应用，面向以 JLPT 词汇为基础的日语学习与复习。

应用采用 Swift / SwiftUI / SwiftData 开发，学习数据保存在本地，不依赖在线账户或云端服务。

## 功能

### JLPT N5–N1 内置词书

Kotoba 当前内置 10,609 个词条：

| 词书 | 词条数 |
| --- | ---: |
| JLPT N5 | 802 |
| JLPT N4 | 755 |
| JLPT N3 | 1,817 |
| JLPT N2 | 3,206 |
| JLPT N1 | 4,029 |
| 总计 | 10,609 |

### SRS 学习与复习

根据每次学习结果自动安排后续复习时间。

支持：

- 忘记
- 模糊
- 认识
- 熟练

学习状态和复习记录均保存在本地。

### 卡片强化

完成正式卡片学习后，会对本组单词进行额外强化。

强化阶段不会重复修改正式复习记录或复习计划。

### 两阶段拼写训练

每组学习完成后进入拼写巩固。

第一轮：

中文释义 / 语境 → 日语词语

支持假名提示。

第二轮：

日语词语 → 假名

主要用于包含汉字的词汇。

拼写错误的词会重新进入当前轮次，直到正确完成。

### 日语活用

应用包含本地日语活用生成逻辑，可处理常见：

- 一段动词
- 五段动词
- する
- 来る
- い形容词
- な形容词

不依赖在线语言模型。

### 外来语词源

部分词汇包含外来语来源信息，可展示：

- 原词
- 来源语言
- 和制英语标记

当前内置 46 条词源数据。

### 单词与词书管理

支持：

- 浏览内置词书
- 创建和管理个人词汇
- 编辑词条
- 收藏
- 学习状态管理
- CSV 导入
- CSV 导出

### 学习统计

可查看学习和复习相关统计信息。

### Backup

支持 JSON Backup V3，可用于备份和恢复本地学习数据。

导入过程包含预检查与回滚机制，避免无效备份破坏现有数据。

## 数据与隐私

Kotoba 是一个 local-first 应用。

目前正式版本：

- 不需要登录
- 不上传学习数据
- 不依赖云端数据库
- 不调用在线 AI / LLM
- 不调用在线词典
- 不包含广告或追踪服务

学习记录保存在本机 SwiftData 数据库中。

## 系统要求

- macOS 26.5 或更高版本

## 下载

前往 GitHub Releases：

https://github.com/icytail176/Kotoba/releases

当前版本：

Kotoba 0.2.0

请下载：

`Kotoba-0.2.0-macOS-local-signed.zip`

不要下载 GitHub 自动生成的 `Source code (zip)`。

## 安装

1. 下载 `Kotoba-0.2.0-macOS-local-signed.zip`
2. 解压得到 `Kotoba.app`
3. 将 `Kotoba.app` 移动到“应用程序”文件夹
4. 打开应用

### Gatekeeper

当前提供的 GitHub binary 尚未完成 Apple Developer ID notarization。

因此在其他 Mac 上首次启动时，macOS 可能阻止直接打开应用。

可以使用 macOS 提供的官方方式：

1. 在 Finder 中右键 `Kotoba.app`
2. 选择“打开”
3. 在系统提示中再次确认

如果仍然被阻止，可前往：

系统设置 → 隐私与安全性

在系统明确提供相应选项时选择“仍要打开”。

不需要关闭 Gatekeeper 或修改系统级安全策略。

## 当前版本

### Kotoba 0.2.0

主要包含：

- JLPT N5–N1 内置词书
- SRS 学习与复习
- Card reinforcement
- 两阶段拼写训练
- 本地日语活用
- 外来语词源
- 单词管理
- 词书管理
- 学习统计
- CSV 导入导出
- JSON Backup V3
- 键盘操作
- Accessibility 支持
- Built-in vocabulary 增量初始化与修复
- canonical-equivalent duplicate 安全修复

## 开发环境

当前项目主要使用：

- Swift
- SwiftUI
- SwiftData
- Xcode 27
- macOS

项目没有第三方运行时依赖。

## 从源码构建

克隆仓库：

```bash
git clone git@github.com:icytail176/Kotoba.git
cd Kotoba
```

使用 Xcode 打开：

```text
Kotoba.xcodeproj
```

选择 `Kotoba` Scheme 后运行即可。

也可以通过命令行执行测试：

```bash
xcodebuild test \
  -project Kotoba.xcodeproj \
  -scheme Kotoba \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

Kotoba 0.2.0 发布前完整测试结果：

200 passed / 0 failed

## 第三方数据与 Attribution

项目包含 JMdict 相关 attribution 信息。

详见：

`Kotoba/Resources/JMdict_NOTICE.txt`

请保留相关 notice。

## License

当前仓库暂未附带独立的软件开源许可证文件。

除项目中明确标注的第三方内容外，代码及项目资源的使用、修改与再分发权限以仓库所有者授权为准。

---

Kotoba 目前仍处于早期版本阶段。

如果遇到词条、学习流程或应用行为方面的问题，可以通过 GitHub Issues 反馈。
