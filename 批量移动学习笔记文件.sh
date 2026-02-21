#!/bin/bash

# 批量移动学习笔记目录文件到学习中心

echo "开始批量移动学习笔记文件..."

# 1. 学习/Go修仙之路 → 01-技术栈/Go语言
echo "移动Go修仙之路文件..."
# Go基础
find ./学习笔记/学习/Go修仙之路 -name "*基础*" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        mv "$file" "学习中心/01-技术栈/Go语言/基础语法/$newname" 2>/dev/null && echo "移动Go基础: $filename"
    fi
done

# GoWeb开发
find ./学习笔记/学习/Go修仙之路 -path "*/GoWeb*" -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        mv "$file" "学习中心/01-技术栈/Go语言/框架生态/$newname" 2>/dev/null && echo "移动GoWeb: $filename"
    fi
done

# 微服务和分布式
find ./学习笔记/学习/Go修仙之路 -path "*/微服务*" -o -path "*/分布式*" -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        mv "$file" "学习中心/01-技术栈/系统设计/微服务/$newname" 2>/dev/null && echo "移动微服务: $filename"
    fi
done

# 数据库
find ./学习笔记/学习/Go修仙之路 -path "*/mysql*" -o -path "*/redis*" -o -path "*/Mysql*" -o -path "*/Redis*" -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        if [[ "$file" =~ [Mm]ysql ]]; then
            mv "$file" "学习中心/01-技术栈/数据库/MySQL/$newname" 2>/dev/null && echo "移动MySQL: $filename"
        elif [[ "$file" =~ [Rr]edis ]]; then
            mv "$file" "学习中心/01-技术栈/数据库/Redis/$newname" 2>/dev/null && echo "移动Redis: $filename"
        fi
    fi
done

# 其他Go修仙之路文件
find ./学习笔记/学习/Go修仙之路 -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        # 检查是否已经移动
        if [[ ! "$file" =~ "基础" ]] && [[ ! "$file" =~ "GoWeb" ]] && [[ ! "$file" =~ "微服务" ]] && [[ ! "$file" =~ "分布式" ]] && [[ ! "$file" =~ "mysql" ]] && [[ ! "$file" =~ "redis" ]] && [[ ! "$file" =~ "Mysql" ]] && [[ ! "$file" =~ "Redis" ]]; then
            mv "$file" "学习中心/01-技术栈/Go语言/框架生态/$newname" 2>/dev/null && echo "移动Go其他: $filename"
        fi
    fi
done

# 2. 学习/算法修仙之路 → 01-技术栈/算法与数据结构
echo "移动算法修仙之路文件..."
# 基础算法
find ./学习笔记/学习/算法修仙之路/基础算法 -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        mv "$file" "学习中心/01-技术栈/算法与数据结构/基础算法/$newname" 2>/dev/null && echo "移动基础算法: $filename"
    fi
done

# 动态规划
find ./学习笔记/学习/算法修仙之路/动态规划 -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        mv "$file" "学习中心/01-技术栈/算法与数据结构/动态规划/$newname" 2>/dev/null && echo "移动动态规划: $filename"
    fi
done

# 图论
find ./学习笔记/学习/算法修仙之路/图论 -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        mv "$file" "学习中心/01-技术栈/算法与数据结构/图论/$newname" 2>/dev/null && echo "移动图论: $filename"
    fi
done

# 数学
find ./学习笔记/学习/算法修仙之路/数学 -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        mv "$file" "学习中心/01-技术栈/算法与数据结构/数学/$newname" 2>/dev/null && echo "移动算法数学: $filename"
    fi
done

# 数据结构
find ./学习笔记/学习/算法修仙之路/数据结构 -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        mv "$file" "学习中心/01-技术栈/算法与数据结构/数据结构/$newname" 2>/dev/null && echo "移动数据结构: $filename"
    fi
done

# 其他算法文件
find ./学习笔记/学习/算法修仙之路 -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        # 检查是否已经移动
        if [[ ! "$file" =~ "基础算法" ]] && [[ ! "$file" =~ "动态规划" ]] && [[ ! "$file" =~ "图论" ]] && [[ ! "$file" =~ "数学" ]] && [[ ! "$file" =~ "数据结构" ]]; then
            mv "$file" "学习中心/01-技术栈/算法与数据结构/其他/$newname" 2>/dev/null && echo "移动算法其他: $filename"
        fi
    fi
done

# 3. 学习/专业课 → 01-技术栈
echo "移动专业课文件..."
# 计算机网络
find ./学习笔记/学习/专业课/计算机网络 -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        if [[ "$file" =~ "HTTP" ]]; then
            mv "$file" "学习中心/01-技术栈/计算机网络/HTTP-HTTPS/$newname" 2>/dev/null && echo "移动专业课HTTP: $filename"
        elif [[ "$file" =~ "传输层" ]]; then
            mv "$file" "学习中心/01-技术栈/计算机网络/TCP-UDP/$newname" 2>/dev/null && echo "移动专业课传输层: $filename"
        else
            mv "$file" "学习中心/01-技术栈/计算机网络/基础概念/$newname" 2>/dev/null && echo "移动专业课网络: $filename"
        fi
    fi
done

# 数据库原理
find ./学习笔记/学习/专业课/数据库原理 -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        mv "$file" "学习中心/01-技术栈/数据库/数据库原理/$newname" 2>/dev/null && echo "移动数据库原理: $filename"
    fi
done

# 4. 学习/AI → 04-学习资源/AI与机器学习
echo "移动AI学习文件..."
find ./学习笔记/学习/AI -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        mv "$file" "学习中心/04-学习资源/AI与机器学习/$newname" 2>/dev/null && echo "移动AI: $filename"
    fi
done

# 5. 学习/面试积淀 → 03-面试准备
echo "移动面试积淀文件..."
# 技术面
find ./学习笔记/学习/面试积淀/技术面 -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        if [[ "$file" =~ "go面经" ]] || [[ "$file" =~ "Go面经" ]]; then
            mv "$file" "学习中心/03-面试准备/面经整理/Go面经/$newname" 2>/dev/null && echo "移动Go面经: $filename"
        elif [[ "$file" =~ "计网面经" ]]; then
            mv "$file" "学习中心/03-面试准备/面经整理/网络面经/$newname" 2>/dev/null && echo "移动网络面经: $filename"
        elif [[ "$file" =~ "算法" ]]; then
            mv "$file" "学习中心/03-面试准备/面经整理/算法面经/$newname" 2>/dev/null && echo "移动算法面经: $filename"
        elif [[ "$file" =~ "中间件" ]] || [[ "$file" =~ "mysql" ]] || [[ "$file" =~ "redis" ]] || [[ "$file" =~ "分布式" ]]; then
            mv "$file" "学习中心/03-面试准备/面经整理/系统设计面经/$newname" 2>/dev/null && echo "移动系统设计面经: $filename"
        else
            mv "$file" "学习中心/03-面试准备/面经整理/技术面经/$newname" 2>/dev/null && echo "移动技术面经: $filename"
        fi
    fi
done

# 非技术面
find ./学习笔记/学习/面试积淀/非技术面 -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        mv "$file" "学习中心/03-面试准备/面经整理/行为面试/$newname" 2>/dev/null && echo "移动行为面试: $filename"
    fi
done

# 模拟面
find ./学习笔记/学习/面试积淀/模拟面 -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        mv "$file" "学习中心/03-面试准备/模拟面试/$newname" 2>/dev/null && echo "移动模拟面试: $filename"
    fi
done

# 面试经验
find ./学习笔记/学习/面试积淀/面试经验 -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        mv "$file" "学习中心/03-面试准备/面试经验/$newname" 2>/dev/null && echo "移动面试经验: $filename"
    fi
done

# 6. 学习/项目 → 02-项目实践
echo "移动项目文件..."
find ./学习笔记/学习/项目 -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        mv "$file" "学习中心/02-项目实践/开源项目/$newname" 2>/dev/null && echo "移动项目: $filename"
    fi
done

# 7. 实习 → 05-成长记录/实习日志
echo "移动实习文件..."
find ./学习笔记/实习 -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        mv "$file" "学习中心/05-成长记录/实习日志/字节实习/$newname" 2>/dev/null && echo "移动实习: $filename"
    fi
done

# 8. 我的项目 → 02-项目实践/个人项目
echo "移动我的项目文件..."
find ./学习笔记/我的项目 -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        if [[ "$file" =~ "校园二手" ]]; then
            mv "$file" "学习中心/02-项目实践/个人项目/校园二手平台/$newname" 2>/dev/null && echo "移动校园二手: $filename"
        elif [[ "$file" =~ "校队 OJ" ]] || [[ "$file" =~ "校队OJ" ]]; then
            mv "$file" "学习中心/02-项目实践/个人项目/校队OJ系统/$newname" 2>/dev/null && echo "移动校队OJ: $filename"
        elif [[ "$file" =~ "算法钉钉" ]]; then
            mv "$file" "学习中心/02-项目实践/个人项目/算法钉钉机器人/$newname" 2>/dev/null && echo "移动算法钉钉: $filename"
        else
            mv "$file" "学习中心/02-项目实践/个人项目/其他/$newname" 2>/dev/null && echo "移动个人项目: $filename"
        fi
    fi
done

# 9. 生活/读书 → 04-学习资源/读书笔记
echo "移动读书笔记文件..."
find ./学习笔记/生活/读书 -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        if [[ "$file" =~ "王阳明" ]] || [[ "$file" =~ "道德经" ]] || [[ "$file" =~ "自我感悟" ]]; then
            mv "$file" "学习中心/04-学习资源/读书笔记/个人成长/$newname" 2>/dev/null && echo "移动个人成长: $filename"
        elif [[ "$file" =~ "小米创业" ]] || [[ "$file" =~ "张一鸣" ]] || [[ "$file" =~ "商业" ]]; then
            mv "$file" "学习中心/04-学习资源/读书笔记/商业思维/$newname" 2>/dev/null && echo "移动商业思维: $filename"
        else
            mv "$file" "学习中心/04-学习资源/读书笔记/技术书籍/$newname" 2>/dev/null && echo "移动技术书籍: $filename"
        fi
    fi
done

# 10. 临时目录 → 05-成长记录/问题记录
echo "移动临时目录文件..."
find ./学习笔记/临时目录 -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        # 提取日期或使用原文件名
        if [[ "$filename" =~ ^[0-9] ]]; then
            # 类似 "6.12问题.md" 的文件
            newname=$(echo "$filename" | sed 's/\./-/g' | sed 's/问题/.问题/')
            mv "$file" "学习中心/05-成长记录/问题记录/$newname" 2>/dev/null && echo "移动问题记录: $filename"
        elif [[ "$file" =~ "校园二手交易平台总体设计" ]]; then
            # 项目设计文件
            newname=$(echo "$filename" | sed 's/ /_/g')
            mv "$file" "学习中心/02-项目实践/个人项目/校园二手平台/$newname" 2>/dev/null && echo "移动项目设计: $filename"
        else
            newname=$(echo "$filename" | sed 's/ /_/g')
            mv "$file" "学习中心/05-成长记录/问题记录/$newname" 2>/dev/null && echo "移动临时文件: $filename"
        fi
    fi
done

# 11. 其他学习文件
echo "移动其他学习文件..."
# Go底层
find ./学习笔记/学习/Go\ 底层 -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        mv "$file" "学习中心/01-技术栈/Go语言/内存管理/$newname" 2>/dev/null && echo "移动Go底层: $filename"
    fi
done

# 后端其他知识点
find ./学习笔记/学习/后端其它知识点 -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        if [[ "$file" =~ "web安全" ]]; then
            mv "$file" "学习中心/01-技术栈/系统设计/网络安全/$newname" 2>/dev/null && echo "移动网络安全: $filename"
        else
            mv "$file" "学习中心/01-技术栈/系统设计/其他/$newname" 2>/dev/null && echo "移动后端其他: $filename"
        fi
    fi
done

# 课程笔记
find ./学习笔记/学习/email -name "*.md" -type f | while read file; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        newname=$(echo "$filename" | sed 's/ /_/g')
        mv "$file" "学习中心/04-学习资源/课程笔记/$newname" 2>/dev/null && echo "移动课程笔记: $filename"
    fi
done

echo "学习笔记文件批量移动完成！"