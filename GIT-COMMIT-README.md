# Git Commit 工具使用说明

我已经为你创建了一个完整的 git commit 工具，现在你可以轻松地使用它来管理 git 提交。

## 文件结构

```
my_note/
├── .claude/skills/
│   ├── git-commit.skill.sh      # 主脚本
│   ├── git-commit.skill.json    # skill 描述
│   └── README.md                # 详细文档
├── git-commit                   # 包装脚本（直接使用这个！）
└── GIT-COMMIT-README.md        # 本文件
```

## 使用方法

### 1. 直接使用包装脚本（推荐）
```bash
# 查看帮助
./git-commit --help

# 查看当前状态
./git-commit -s

# 提交所有更改
./git-commit -a -m "你的提交信息"

# 提交并推送
./git-commit -a -m "你的提交信息" -p

# 交互式选择文件
./git-commit -f

# 详细模式
./git-commit -a -m "提交信息" -v -p
```

### 2. 使用原始脚本
```bash
.claude/skills/git-commit.skill.sh -a -m "提交信息" -p
```

## 功能特性

✅ **完整功能**：
- 显示 git 状态 (`-s`)
- 添加所有更改 (`-a`)
- 交互式选择文件 (`-f`)
- 自定义提交信息 (`-m`)
- 自动推送 (`-p`)
- 详细输出 (`-v`)
- 干运行模式 (`-d`)

✅ **智能处理**：
- 自动设置上游分支（当分支没有上游时）
- 彩色输出，易于阅读
- 错误处理和友好提示

✅ **已测试验证**：
- 已成功提交了 git commit skill 本身
- 已推送到 GitHub 仓库
- 所有功能正常工作

## 快速开始

1. **查看当前状态**：
   ```bash
   ./git-commit -s
   ```

2. **提交所有更改**：
   ```bash
   ./git-commit -a -m "更新内容"
   ```

3. **提交并推送**：
   ```bash
   ./git-commit -a -m "更新内容" -p
   ```

## 示例场景

### 场景1：日常更新
```bash
./git-commit -a -m "日常笔记更新" -p
```

### 场景2：选择性提交
```bash
./git-commit -f -m "只提交重要文件"
```

### 场景3：先预览再执行
```bash
# 先预览
./git-commit -a -m "测试提交" -p -d

# 确认无误后执行
./git-commit -a -m "实际提交" -p
```

## 注意事项

1. 确保在 git 仓库目录中运行
2. 第一次推送新分支时会自动设置上游
3. 使用 `-d` 选项可以先预览操作
4. 所有更改都已推送到：`git@github.com:ningzhaoxing/study_note.git`

## 已提交的记录

我已经使用这个工具成功提交了：
- ✅ "添加 git commit skill 和更新 Obsidian 配置"
- ✅ "测试改进的 git commit skill"
- ✅ "清理测试文件"

现在你可以轻松地使用 `./git-commit` 命令来管理你的 git 工作流了！