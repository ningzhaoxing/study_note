---
name: git-commit
description: 使用 git 将本地更改提交到远程仓库
version: 1.0.0
author: Claudian
script: git-commit.skill.sh
category: git
tags: [git, commit, version-control, vcs]
---

# Git Commit Skill

使用 git 将本地更改提交到远程仓库。

## 描述

这是一个用于简化 git 提交流程的工具，支持添加文件、创建提交、推送到远程仓库等完整功能。

## 命令

### git-commit
提交本地更改到 git 仓库。

**用法：**
```
git-commit [选项] [提交信息]
```

**选项：**
- `-h, --help` - 显示帮助信息
- `-s, --status` - 显示当前 git 状态
- `-m, --message` - 指定提交信息
- `-a, --all` - 添加所有更改的文件
- `-p, --push` - 提交后推送到远程
- `-f, --files` - 交互式选择要添加的文件
- `-b, --branch` - 指定要推送到的分支名称
- `-d, --dry-run` - 只显示将要执行的操作，不实际执行
- `-v, --verbose` - 显示详细输出

**示例：**
```bash
# 提交并推送（交互式选择分支）
git-commit -m "修复bug" -p

# 提交并推送到指定分支
git-commit -m "修复bug" -p -b main

# 只显示状态
git-commit -s

# 添加所有更改并提交
git-commit -a -m "更新文档"

# 交互式选择文件
git-commit -f
```

## 脚本

主脚本文件：`git-commit.skill.sh`

```bash
#!/bin/bash
# Git Commit Skill 主脚本
# 完整功能实现...
```

## 特性

1. **彩色输出**：易于阅读的彩色终端输出
2. **智能分支选择**：自动检测默认分支，支持交互式分支选择
3. **自动上游分支设置**：当分支没有上游时自动设置
4. **交互式文件选择**：可以选择性地添加文件
5. **分支指定支持**：可以通过 `-b` 选项指定目标分支
6. **干运行模式**：预览操作而不实际执行
7. **详细输出**：显示详细的操作信息
8. **错误处理**：友好的错误提示和恢复

## 安装

脚本已位于 `.claude/skills/` 目录中，Claude 会自动加载。

## 使用方式

### 在 Claude 中：
```
/git-commit -a -m "更新文档" -p
```

### 直接运行：
```bash
.claude/skills/git-commit.skill.sh -a -m "更新文档" -p
```

## 版本

1.1.0

## 作者

Claudian

## 标签

git, commit, version-control, vcs