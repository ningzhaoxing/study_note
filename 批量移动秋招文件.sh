#!/bin/bash

# 批量移动秋招目录文件到学习中心

echo "开始批量移动秋招文件..."

# 1. 简历文件 → 03-面试准备/简历材料
echo "移动简历文件..."
find ./秋招/简历 -name "*.md" -type f | while read file; do
    filename=$(basename "$file")
    # 简化文件名，移除空格和特殊字符
    newname=$(echo "$filename" | sed 's/ /_/g')
    mv "$file" "学习中心/03-面试准备/简历材料/$newname" 2>/dev/null && echo "移动: $filename"
done

# 2. Go语言文件 → 01-技术栈/Go语言
echo "移动Go语言文件..."
# 内存管理相关
find ./秋招/go -name "*内存*" -o -name "*map*" -o -name "*源码*" | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        mv "$file" "学习中心/01-技术栈/Go语言/内存管理/$newname" 2>/dev/null && echo "移动Go内存: $filename"
    fi
done

# 并发编程相关
find ./秋招/go -name "*进程*" -o -name "*线程*" -o -name "*协程*" -o -name "*gmp*" -o -name "*channel*" | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        mv "$file" "学习中心/01-技术栈/Go语言/并发编程/$newname" 2>/dev/null && echo "移动Go并发: $filename"
    fi
done

# 其他Go文件
find ./秋招/go -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        # 检查是否已经移动
        if [[ ! "$file" =~ "内存" ]] && [[ ! "$file" =~ "进程" ]] && [[ ! "$file" =~ "线程" ]] && [[ ! "$file" =~ "协程" ]] && [[ ! "$file" =~ "gmp" ]] && [[ ! "$file" =~ "channel" ]] && [[ ! "$file" =~ "map" ]] && [[ ! "$file" =~ "源码" ]]; then
            mv "$file" "学习中心/01-技术栈/Go语言/基础语法/$newname" 2>/dev/null && echo "移动Go基础: $filename"
        fi
    fi
done

# 3. 算法文件 → 01-技术栈/算法与数据结构
echo "移动算法文件..."
find ./秋招/手撕算法 -name "*.md" -type f | while read file; do
    filename=$(basename "$file")
    newname=$(echo "$filename" | sed 's/^[0-9.]* //' | sed 's/ /_/g')  # 移除开头的编号
    mv "$file" "学习中心/01-技术栈/算法与数据结构/面试算法/$newname" 2>/dev/null && echo "移动算法: $filename"
done

# 4. 计算机网络文件 → 01-技术栈/计算机网络
echo "移动计算机网络文件..."
# HTTP相关
find ./秋招/计网面经/HTTP篇 -name "*.md" -type f | while read file; do
    filename=$(basename "$file")
    newname=$(echo "$filename" | sed 's/ /_/g')
    mv "$file" "学习中心/01-技术栈/计算机网络/HTTP-HTTPS/$newname" 2>/dev/null && echo "移动HTTP: $filename"
done

# TCP/UDP相关
find ./秋招/计网面经/传输层 -name "*.md" -type f | while read file; do
    filename=$(basename "$file")
    newname=$(echo "$filename" | sed 's/ /_/g')
    mv "$file" "学习中心/01-技术栈/计算机网络/TCP-UDP/$newname" 2>/dev/null && echo "移动TCP: $filename"
done

# 基础篇
find ./秋招/计网面经/基础篇 -name "*.md" -type f | while read file; do
    filename=$(basename "$file")
    newname=$(echo "$filename" | sed 's/ /_/g')
    mv "$file" "学习中心/01-技术栈/计算机网络/基础概念/$newname" 2>/dev/null && echo "移动网络基础: $filename"
done

# 5. 中间件和数据库文件 → 01-技术栈/数据库和系统设计
echo "移动中间件和数据库文件..."
# MySQL相关
find ./秋招/中间件/数据库 -name "*.md" -type f | while read file; do
    filename=$(basename "$file")
    newname=$(echo "$filename" | sed 's/ /_/g')
    mv "$file" "学习中心/01-技术栈/数据库/MySQL/$newname" 2>/dev/null && echo "移动MySQL: $filename"
done

# Redis相关
find ./秋招/中间件/缓存 -name "*.md" -type f | while read file; do
    filename=$(basename "$file")
    newname=$(echo "$filename" | sed 's/ /_/g')
    mv "$file" "学习中心/01-技术栈/数据库/Redis/$newname" 2>/dev/null && echo "移动Redis: $filename"
done

# 消息队列
find ./秋招/中间件/mq -name "*.md" -type f | while read file; do
    filename=$(basename "$file")
    newname=$(echo "$filename" | sed 's/ /_/g')
    mv "$file" "学习中心/01-技术栈/系统设计/中间件/$newname" 2>/dev/null && echo "移动MQ: $filename"
done

# 6. 面经文件 → 03-面试准备
echo "移动面经文件..."
find ./秋招/面经 -name "*.md" -type f | while read file; do
    filename=$(basename "$file")
    newname=$(echo "$filename" | sed 's/（/ /' | sed 's/）//' | sed 's/ /_/g')  # 清理括号
    mv "$file" "学习中心/03-面试准备/面试经验/$newname" 2>/dev/null && echo "移动面经: $filename"
done

# 7. 其他文件（设计模式等）
echo "移动其他文件..."
find ./秋招 -name "*.md" -type f | while read file; do
    # 跳过已经处理的目录
    if [[ "$file" =~ ./秋招/简历 ]] || [[ "$file" =~ ./秋招/go ]] || [[ "$file" =~ ./秋招/手撕算法 ]] || [[ "$file" =~ ./秋招/计网面经 ]] || [[ "$file" =~ ./秋招/中间件 ]] || [[ "$file" =~ ./秋招/面经 ]]; then
        continue
    fi
    filename=$(basename "$file")
    newname=$(echo "$filename" | sed 's/ /_/g')
    mv "$file" "学习中心/01-技术栈/系统设计/设计模式/$newname" 2>/dev/null && echo "移动其他: $filename"
done

echo "秋招文件批量移动完成！"