#!/bin/bash

# Git Commit Skill
# 用于将本地更改提交到远程仓库

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 帮助函数
show_help() {
    echo -e "${BLUE}Git Commit Skill - 帮助${NC}"
    echo "用法: git-commit [选项] [提交信息]"
    echo ""
    echo "选项:"
    echo "  -h, --help          显示此帮助信息"
    echo "  -s, --status        显示当前 git 状态"
    echo "  -m, --message       指定提交信息"
    echo "  -a, --all           添加所有更改的文件"
    echo "  -p, --push          提交后推送到远程"
    echo "  -f, --files         交互式选择要添加的文件"
    echo "  -b, --branch        指定要推送到的分支名称"
    echo "  -d, --dry-run       只显示将要执行的操作，不实际执行"
    echo "  -v, --verbose       显示详细输出"
    echo ""
    echo "示例:"
    echo "  git-commit -m \"修复bug\" -p          # 提交并推送（交互式选择分支）"
    echo "  git-commit -m \"修复bug\" -p -b main  # 提交并推送到 main 分支"
    echo "  git-commit -s                       # 只显示状态"
    echo "  git-commit -a -m \"更新文档\"         # 添加所有更改并提交"
    echo "  git-commit -f                       # 交互式选择文件"
    echo ""
    echo "注意："
    echo "  使用 -p 选项时，如果没有指定 -b 选项，"
    echo "  脚本会交互式询问要推送到哪个分支。"
}

# 显示 git 状态
show_status() {
    echo -e "${BLUE}=== Git 状态 ===${NC}"
    git status

    echo -e "\n${BLUE}=== 未暂存的更改 ===${NC}"
    git diff --name-only

    if [ -n "$(git diff --cached --name-only)" ]; then
        echo -e "\n${BLUE}=== 已暂存的更改 ===${NC}"
        git diff --cached --name-only
    fi
}

# 交互式选择文件
select_files() {
    local changed_files=$(git status --porcelain | awk '{print $2}')

    if [ -z "$changed_files" ]; then
        echo -e "${YELLOW}没有发现更改的文件${NC}"
        return 1
    fi

    echo -e "${BLUE}请选择要添加的文件 (输入数字，多个用空格分隔):${NC}"

    local i=1
    local file_array=()

    while IFS= read -r file; do
        if [ -n "$file" ]; then
            local status=$(git status --porcelain "$file" | cut -c1-2)
            echo "  $i) $status $file"
            file_array[$i]="$file"
            ((i++))
        fi
    done <<< "$changed_files"

    echo -e "${BLUE}选择:${NC} "
    read -r selection

    if [ -z "$selection" ]; then
        echo -e "${YELLOW}未选择任何文件${NC}"
        return 1
    fi

    for num in $selection; do
        if [ -n "${file_array[$num]}" ]; then
            echo -e "${GREEN}添加文件: ${file_array[$num]}${NC}"
            git add "${file_array[$num]}"
        fi
    done
}

# 获取远程默认分支
get_default_remote_branch() {
    # 尝试获取远程默认分支
    local default_branch=$(git remote show origin | grep "HEAD branch" | cut -d ":" -f 2 | tr -d ' ')

    if [ -n "$default_branch" ]; then
        echo "$default_branch"
    else
        # 如果无法获取，尝试常见的默认分支
        if git show-ref --verify --quiet refs/heads/main; then
            echo "main"
        elif git show-ref --verify --quiet refs/heads/master; then
            echo "master"
        else
            echo ""
        fi
    fi
}

# 交互式选择分支
select_branch() {
    local current_branch=$(git branch --show-current)
    local default_branch=$(get_default_remote_branch)

    # 显示当前分支信息
    echo -e "${BLUE}当前分支: ${GREEN}$current_branch${NC}"

    # 获取所有远程分支
    local remote_branches=$(git branch -r | grep -v "HEAD" | sed 's/origin\///' | sort | uniq)

    if [ -n "$remote_branches" ]; then
        echo -e "${BLUE}可用的远程分支:${NC}"
        local i=1
        local branch_array=()

        while IFS= read -r branch; do
            if [ -n "$branch" ]; then
                local display_name="$branch"
                if [ "$branch" = "$default_branch" ]; then
                    display_name="$branch (默认)"
                fi
                echo "  $i) $display_name"
                branch_array[$i]="$branch"
                ((i++))
            fi
        done <<< "$remote_branches"

        echo -e "${BLUE}选择要推送到的分支 (输入数字，默认为 $default_branch):${NC} "
        read -r selection

        local selected_branch=""

        if [ -z "$selection" ]; then
            if [ -n "$default_branch" ]; then
                selected_branch="$default_branch"
                echo -e "${GREEN}使用默认分支: $default_branch${NC}"
            else
                selected_branch="$current_branch"
                echo -e "${YELLOW}未选择分支，使用当前分支: $current_branch${NC}"
            fi
        elif [ -n "${branch_array[$selection]}" ]; then
            selected_branch="${branch_array[$selection]}"
            echo -e "${GREEN}选择分支: $selected_branch${NC}"
        else
            if [ -n "$default_branch" ]; then
                selected_branch="$default_branch"
                echo -e "${YELLOW}无效的选择，使用默认分支: $default_branch${NC}"
            else
                selected_branch="$current_branch"
                echo -e "${YELLOW}无效的选择，使用当前分支: $current_branch${NC}"
            fi
        fi

        # 返回纯净的分支名称（不带颜色代码）
        echo "$selected_branch"
        return 0
    else
        echo -e "${YELLOW}没有找到远程分支，使用当前分支: $current_branch${NC}"
        echo "$current_branch"
        return 0
    fi
}

# 主函数
main() {
    local commit_message=""
    local do_push=false
    local do_all=false
    local do_select=false
    local dry_run=false
    local verbose=false
    local show_status_only=false
    local target_branch=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                return 0
                ;;
            -s|--status)
                show_status_only=true
                shift
                ;;
            -m|--message)
                if [ -n "$2" ]; then
                    commit_message="$2"
                    shift 2
                else
                    echo -e "${RED}错误: -m 选项需要提交信息${NC}"
                    return 1
                fi
                ;;
            -a|--all)
                do_all=true
                shift
                ;;
            -p|--push)
                do_push=true
                shift
                ;;
            -f|--files)
                do_select=true
                shift
                ;;
            -d|--dry-run)
                dry_run=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -b|--branch)
                if [ -n "$2" ]; then
                    target_branch="$2"
                    shift 2
                else
                    echo -e "${RED}错误: -b 选项需要分支名称${NC}"
                    return 1
                fi
                ;;
            *)
                # 如果没有选项，则视为提交信息
                if [ -z "$commit_message" ]; then
                    commit_message="$1"
                fi
                shift
                ;;
        esac
    done

    # 显示状态
    if [ "$show_status_only" = true ]; then
        show_status
        return 0
    fi

    # 检查是否有更改
    if [ -z "$(git status --porcelain)" ]; then
        echo -e "${YELLOW}没有发现更改${NC}"
        return 0
    fi

    echo -e "${BLUE}=== Git Commit Skill ===${NC}"

    # 显示当前状态
    if [ "$verbose" = true ]; then
        show_status
    fi

    # 添加文件
    if [ "$do_all" = true ]; then
        echo -e "${GREEN}添加所有更改的文件...${NC}"
        if [ "$dry_run" = false ]; then
            git add .
        else
            echo "[DRY RUN] git add ."
        fi
    elif [ "$do_select" = true ]; then
        if [ "$dry_run" = false ]; then
            select_files
        else
            echo "[DRY RUN] 交互式选择文件"
        fi
    fi

    # 检查是否有文件被暂存
    if [ -z "$(git diff --cached --name-only)" ] && [ "$do_all" = false ] && [ "$do_select" = false ]; then
        echo -e "${YELLOW}没有文件被暂存，使用 -a 或 -f 选项添加文件${NC}"
        return 1
    fi

    # 如果没有提交信息，提示输入
    if [ -z "$commit_message" ]; then
        echo -e "${BLUE}请输入提交信息:${NC} "
        read -r commit_message

        if [ -z "$commit_message" ]; then
            echo -e "${RED}错误: 提交信息不能为空${NC}"
            return 1
        fi
    fi

    # 创建提交
    echo -e "${GREEN}创建提交: $commit_message${NC}"
    if [ "$dry_run" = false ]; then
        git commit -m "$commit_message"

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ 提交成功${NC}"

            # 推送到远程
            if [ "$do_push" = true ]; then
                local current_branch=$(git branch --show-current)
                local push_branch="$current_branch"

                # 确定目标分支
                if [ -n "$target_branch" ]; then
                    push_branch="$target_branch"
                    echo -e "${GREEN}推送到指定分支: $push_branch${NC}"
                else
                    echo -e "${BLUE}确定推送目标分支...${NC}"
                    push_branch=$(select_branch)
                fi

                echo -e "${GREEN}推送到远程仓库 ($push_branch)...${NC}"

                # 尝试推送
                if [ "$push_branch" = "$current_branch" ]; then
                    # 推送到同名分支
                    git push
                else
                    # 推送到不同分支
                    git push origin "$current_branch:$push_branch"
                fi

                # 如果推送失败，尝试设置上游分支
                if [ $? -ne 0 ]; then
                    echo -e "${YELLOW}尝试设置上游分支并推送...${NC}"

                    if [ "$push_branch" = "$current_branch" ]; then
                        git push --set-upstream origin "$current_branch"
                    else
                        git push --set-upstream origin "$current_branch:$push_branch"
                    fi

                    if [ $? -eq 0 ]; then
                        echo -e "${GREEN}✓ 推送成功（已设置上游分支）${NC}"
                    else
                        echo -e "${RED}✗ 推送失败${NC}"
                        return 1
                    fi
                else
                    echo -e "${GREEN}✓ 推送成功${NC}"
                fi
            fi
        else
            echo -e "${RED}✗ 提交失败${NC}"
            return 1
        fi
    else
        echo "[DRY RUN] git commit -m \"$commit_message\""
        if [ "$do_push" = true ]; then
            local current_branch=$(git branch --show-current)
            local push_branch="$current_branch"

            if [ -n "$target_branch" ]; then
                push_branch="$target_branch"
                echo "[DRY RUN] 将推送到分支: $push_branch"
                echo "[DRY RUN] git push origin $current_branch:$push_branch"
            else
                echo "[DRY RUN] 将交互式选择分支"
                echo "[DRY RUN] git push"
            fi
        fi
    fi

    return 0
}

# 执行主函数
main "$@"