# Git Commit Skill

一个用于将本地更改提交到远程 git 仓库的 Claude skill。

## 功能特性

- ✅ 显示当前 git 状态
- ✅ 添加所有更改的文件
- ✅ 交互式选择要提交的文件
- ✅ 自定义提交信息
- ✅ 提交后自动推送
- ✅ 详细输出模式
- ✅ 干运行模式（只显示不执行）

## 安装

1. 确保脚本有执行权限：
   ```bash
   chmod +x .claude/skills/git-commit.skill.sh
   ```

2. Claude 会自动识别 `.claude/skills/` 目录下的 skill 文件。

## 使用方法

### 基本用法

```bash
# 显示帮助
git-commit --help

# 显示当前状态
git-commit --status

# 添加所有更改并提交
git-commit -a -m "提交信息"

# 提交并推送到远程
git-commit -a -m "提交信息" -p

# 交互式选择文件
git-commit -f

# 详细输出模式
git-commit -a -m "提交信息" -v

# 干运行模式（只显示不执行）
git-commit -a -m "提交信息" -p -d
```

### 在 Claude 中使用

在 Claude 对话中，你可以通过以下方式使用：

1. **直接调用脚本**：
   ```bash
   .claude/skills/git-commit.skill.sh -a -m "更新文档" -p
   ```

2. **在 Claude 中请求执行**：
   ```
   请使用 git-commit skill 提交我的更改，提交信息是"更新 Obsidian 配置"
   ```

## 文件结构

```
.claude/skills/
├── git-commit.skill.sh      # 主脚本文件
├── git-commit.skill.json    # skill 描述文件
└── README.md               # 说明文档
```

## 选项说明

| 选项 | 简写 | 描述 |
|------|------|------|
| `--help` | `-h` | 显示帮助信息 |
| `--status` | `-s` | 显示当前 git 状态 |
| `--message` | `-m` | 指定提交信息 |
| `--all` | `-a` | 添加所有更改的文件 |
| `--push` | `-p` | 提交后推送到远程 |
| `--files` | `-f` | 交互式选择要添加的文件 |
| `--dry-run` | `-d` | 只显示将要执行的操作，不实际执行 |
| `--verbose` | `-v` | 显示详细输出 |

## 示例场景

### 场景1：快速提交所有更改
```bash
git-commit -a -m "日常更新" -p
```

### 场景2：选择性提交文件
```bash
git-commit -f -m "只提交重要文件"
```

### 场景3：先查看状态再决定
```bash
git-commit -s
# 查看状态后决定如何提交
git-commit -a -m "根据状态更新"
```

## 注意事项

1. 确保在 git 仓库目录中运行
2. 交互式选择文件功能需要终端支持
3. 推送前确保有远程仓库权限
4. 使用 `-d` 选项可以先预览将要执行的操作