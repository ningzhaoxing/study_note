---
name: git
description: Git 版本控制工具集
version: 1.0.0
author: Claudian
category: git
tags: [git, version-control, vcs]
---

# Git Skill

Git 版本控制工具集。

## 描述

提供一系列 git 相关命令，包括提交、状态查看等功能。

## 命令

### commit
提交本地更改到 git 仓库。

**用法：**
```
commit [选项] [提交信息]
```

**选项：**
- `-h, --help` - 显示帮助信息
- `-s, --status` - 显示当前 git 状态
- `-m, --message` - 指定提交信息
- `-a, --all` - 添加所有更改的文件
- `-p, --push` - 提交后推送到远程

**示例：**
```bash
# 提交所有更改并推送
commit -a -m "更新文档" -p

# 查看状态
commit -s

# 显示帮助
commit --help
```

## 脚本

使用 `git-commit.skill.sh` 脚本实现 commit 功能。

## 安装

脚本已位于 `.claude/skills/` 目录中，Claude 会自动加载。

## 标签

git, version-control, vcs