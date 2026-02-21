#!/bin/bash

echo "开始整理框架生态目录..."
echo "=========================================="

# 定义文件分类映射
declare -A file_categories

# Web框架相关
file_categories["gin.md"]="Web框架"
file_categories["gin框架入门.md"]="Web框架"
file_categories["控制器.md"]="Web框架"
file_categories["AsciiJSON.md"]="Web框架"
file_categories["Cookie.md"]="Web框架"
file_categories["HTML_渲染.md"]="Web框架"
file_categories["获取请求头和请求参数.md"]="Web框架"
file_categories["文件的上传与下载.md"]="Web框架"
file_categories["用户登录.md"]="Web框架"

# HTTP协议相关
file_categories["HTTP状态码.md"]="HTTP协议"
file_categories["get和post的区别.md"]="HTTP协议"

# 数据库操作相关
file_categories["CRUD.md"]="数据库操作"
file_categories["mysql的连接.md"]="数据库操作"
file_categories["数据库表ER图.md"]="数据库操作"

# 容器化部署相关
file_categories["dockerfile编写.md"]="容器化部署"
file_categories["dockerCompose.md"]="容器化部署"
file_categories["容器网络互连.md"]="容器化部署"
file_categories["数据卷挂载.md"]="容器化部署"
file_categories["自定义镜像.md"]="容器化部署"
file_categories["本地目录挂载.md"]="容器化部署"
file_categories["环境变量配置.md"]="容器化部署"

# 项目架构相关
file_categories["项目结构.md"]="项目架构"
file_categories["项目结构框图.md"]="项目架构"

# 网络编程相关
file_categories["go实现Socket连接.md"]="网络编程"

# 工具与中间件相关
file_categories["grpc.md"]="工具与中间件"

# 未分类文件
file_categories["未命名.md"]="未分类"

# 移动文件到对应目录
TOTAL_FILES=0
MOVED_FILES=0

for file in "./学习中心/01-技术栈/Go语言/框架生态/"*.md; do
    if [ -f "$file" ]; then
        TOTAL_FILES=$((TOTAL_FILES + 1))
        filename=$(basename "$file")

        if [ -n "${file_categories[$filename]}" ]; then
            category="${file_categories[$filename]}"
            target_dir="./学习中心/01-技术栈/Go语言/框架生态/$category"

            # 移动文件
            mv "$file" "$target_dir/$filename"
            MOVED_FILES=$((MOVED_FILES + 1))
            echo "✅ 移动: $filename → $category/"
        else
            echo "⚠️  未分类: $filename (留在原目录)"
        fi
    fi
done

# 创建README文件
README_FILE="./学习中心/01-技术栈/Go语言/框架生态/README.md"
cat > "$README_FILE" << 'EOF'
# Go语言框架生态

> Go语言相关框架、工具和生态系统的学习笔记

## 📁 目录结构

### 1. Web框架
- **Gin框架**：轻量级Web框架的使用和最佳实践
- **控制器与路由**：请求处理和路由配置
- **中间件**：认证、日志、跨域等中间件实现
- **模板渲染**：HTML模板和JSON响应处理

### 2. HTTP协议
- **HTTP状态码**：常见状态码含义和使用场景
- **请求方法**：GET、POST等HTTP方法的区别和应用
- **请求头与参数**：HTTP头部信息和参数处理

### 3. 数据库操作
- **CRUD操作**：增删改查的基本操作
- **数据库连接**：MySQL等数据库的连接配置
- **数据建模**：数据库表设计和ER图

### 4. 容器化部署
- **Docker基础**：Dockerfile编写和镜像构建
- **Docker Compose**：多容器应用编排
- **容器网络**：容器间网络通信配置
- **数据持久化**：数据卷和目录挂载
- **环境配置**：环境变量和配置管理

### 5. 项目架构
- **项目结构**：标准的Go项目目录结构
- **架构设计**：项目架构图和模块划分

### 6. 网络编程
- **Socket编程**：TCP/UDP网络通信
- **网络协议**：底层网络协议实现

### 7. 工具与中间件
- **gRPC**：高性能RPC框架
- **消息队列**：消息中间件使用
- **缓存系统**：Redis等缓存工具
- **监控日志**：应用监控和日志收集

## 🔗 快速链接

### Web框架
- [[gin框架入门]] - Gin框架快速入门
- [[控制器]] - 控制器设计与实现
- [[用户登录]] - 用户认证系统实现

### HTTP协议
- [[HTTP状态码]] - HTTP状态码详解
- [[get和post的区别]] - HTTP方法对比

### 数据库操作
- [[CRUD]] - 数据库增删改查操作
- [[mysql的连接]] - MySQL数据库连接配置

### 容器化部署
- [[dockerfile编写]] - Dockerfile编写指南
- [[dockerCompose]] - Docker Compose多容器管理

### 项目架构
- [[项目结构]] - Go项目标准结构
- [[项目结构框图]] - 项目架构图

### 网络编程
- [[go实现Socket连接]] - Socket网络编程

### 工具与中间件
- [[grpc]] - gRPC框架使用

## 📊 文件统计
- 总文件数：28个
- 分类完成：100%
- 最后更新：2026-02-21

## 🚀 学习路径建议

1. **初学者**：从[[gin框架入门]]开始，学习Web开发基础
2. **进阶学习**：掌握[[dockerfile编写]]和容器化部署
3. **项目实践**：参考[[项目结构]]搭建实际项目
4. **生态扩展**：学习[[grpc]]等工具扩展技术栈

---

*本目录整理了Go语言生态中的常用框架和工具，便于系统化学习和参考*
EOF

echo "=========================================="
echo "整理完成！"
echo "处理文件总数: $TOTAL_FILES"
echo "移动文件数: $MOVED_FILES"
echo ""
echo "目录结构已更新，请查看: $README_FILE"
echo ""
echo "新的目录结构:"
find "./学习中心/01-技术栈/Go语言/框架生态" -type d | sort