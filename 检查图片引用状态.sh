#!/bin/bash

echo "检查所有图片引用状态..."
echo "=========================================="

# 创建缺失图片清单
MISSING_IMAGES_FILE="./学习中心/资源/缺失图片详细清单.md"
echo "# 缺失图片详细清单" > "$MISSING_IMAGES_FILE"
echo "> 记录所有引用但实际不存在的图片文件" >> "$MISSING_IMAGES_FILE"
echo "> 生成时间：$(date '+%Y-%m-%d %H:%M:%S')" >> "$MISSING_IMAGES_FILE"
echo "" >> "$MISSING_IMAGES_FILE"

# 统计变量
TOTAL_REFERENCES=0
EXISTING_IMAGES=0
MISSING_IMAGES=0
FILES_WITH_IMAGES=0

# 查找所有有图片引用的文件
find ./学习中心 -name "*.md" -type f | while read -r file; do
    # 提取文件中的所有图片引用
    IMAGE_REFS=$(grep -o "!\[\[.*\.\(png\|jpg\|jpeg\|gif\)\]\]" "$file" | sed 's/!\[\[//' | sed 's/\]\]//')

    if [ -n "$IMAGE_REFS" ]; then
        FILES_WITH_IMAGES=$((FILES_WITH_IMAGES + 1))
        HAS_MISSING=false

        for img_name in $IMAGE_REFS; do
            TOTAL_REFERENCES=$((TOTAL_REFERENCES + 1))

            # 检查图片是否存在（在资源目录或文件所在目录）
            IMG_FOUND=false

            # 1. 检查资源/图片目录
            if [ -f "./学习中心/资源/图片/$img_name" ]; then
                IMG_FOUND=true
                EXISTING_IMAGES=$((EXISTING_IMAGES + 1))
            fi

            # 2. 检查文件所在目录
            FILE_DIR=$(dirname "$file")
            if [ -f "$FILE_DIR/$img_name" ]; then
                IMG_FOUND=true
                EXISTING_IMAGES=$((EXISTING_IMAGES + 1))
            fi

            # 3. 检查文件所在目录的assets子目录
            if [ -f "$FILE_DIR/assets/$img_name" ]; then
                IMG_FOUND=true
                EXISTING_IMAGES=$((EXISTING_IMAGES + 1))
            fi

            if [ "$IMG_FOUND" = false ]; then
                MISSING_IMAGES=$((MISSING_IMAGES + 1))
                HAS_MISSING=true

                # 记录缺失图片
                echo "## $img_name" >> "$MISSING_IMAGES_FILE"
                echo "" >> "$MISSING_IMAGES_FILE"
                echo "- **引用文件**: \`$file\`" >> "$MISSING_IMAGES_FILE"
                echo "- **状态**: ❌ 文件不存在" >> "$MISSING_IMAGES_FILE"
                echo "- **上下文**: " >> "$MISSING_IMAGES_FILE"

                # 获取引用上下文
                grep -n "!\[\[$img_name\]\]" "$file" | while read -r line_info; do
                    line_num=$(echo "$line_info" | cut -d: -f1)
                    context=$(echo "$line_info" | cut -d: -f2-)
                    echo "  - 第${line_num}行: \`$context\`" >> "$MISSING_IMAGES_FILE"
                done

                echo "" >> "$MISSING_IMAGES_FILE"
            fi
        done

        if [ "$HAS_MISSING" = true ]; then
            echo "⚠️  $file - 有缺失图片"
        else
            echo "✅  $file - 所有图片正常"
        fi
    fi
done

# 更新缺失图片清单文件
echo "## 统计信息" >> "$MISSING_IMAGES_FILE"
echo "" >> "$MISSING_IMAGES_FILE"
echo "- 检查文件数: $FILES_WITH_IMAGES 个（有图片引用的文件）" >> "$MISSING_IMAGES_FILE"
echo "- 图片引用总数: $TOTAL_REFERENCES 个" >> "$MISSING_IMAGES_FILE"
echo "- 存在图片数: $EXISTING_IMAGES 个" >> "$MISSING_IMAGES_FILE"
echo "- 缺失图片数: $MISSING_IMAGES 个" >> "$MISSING_IMAGES_FILE"
echo "- 缺失比例: $((MISSING_IMAGES * 100 / TOTAL_REFERENCES))%" >> "$MISSING_IMAGES_FILE"
echo "" >> "$MISSING_IMAGES_FILE"

echo "## 解决方案" >> "$MISSING_IMAGES_FILE"
echo "" >> "$MISSING_IMAGES_FILE"
echo "### 方案一：忽略缺失图片" >> "$MISSING_IMAGES_FILE"
echo "如果这些图片不重要，可以忽略。文字内容仍然完整。" >> "$MISSING_IMAGES_FILE"
echo "" >> "$MISSING_IMAGES_FILE"
echo "### 方案二：逐步补充图片" >> "$MISSING_IMAGES_FILE"
echo "1. 找到原图片文件（可能需要从备份恢复）" >> "$MISSING_IMAGES_FILE"
echo "2. 将图片复制到对应位置：" >> "$MISSING_IMAGES_FILE"
echo "   - 统一位置: \`学习中心/资源/图片/\`" >> "$MISSING_IMAGES_FILE"
echo "   - 或文件所在目录" >> "$MISSING_IMAGES_FILE"
echo "3. 确保文件名完全匹配" >> "$MISSING_IMAGES_FILE"
echo "" >> "$MISSING_IMAGES_FILE"
echo "### 方案三：替换为占位符" >> "$MISSING_IMAGES_FILE"
echo "1. 创建统一的占位符图片" >> "$MISSING_IMAGES_FILE"
echo "2. 替换所有缺失图片引用" >> "$MISSING_IMAGES_FILE"
echo "" >> "$MISSING_IMAGES_FILE"
echo "## 常见缺失图片示例" >> "$MISSING_IMAGES_FILE"
echo "" >> "$MISSING_IMAGES_FILE"
echo "| 图片文件名 | 引用文件 | 说明 |" >> "$MISSING_IMAGES_FILE"
echo "|------------|----------|------|" >> "$MISSING_IMAGES_FILE"

# 添加一些示例
echo "| \`20241230095627.png\` | \`TCP-UDP/传输层笔记.md\` | TCP四次挥手示意图 |" >> "$MISSING_IMAGES_FILE"
echo "| \`20250118082336.png\` | \`读书笔记/商业思维/第三章._争议与挑战.md\` | 字节跳动声明图片 |" >> "$MISSING_IMAGES_FILE"
echo "| \`20241123095049.png\` | \`读书笔记/商业思维/梦想落地.md\` | 小米创业相关图片 |" >> "$MISSING_IMAGES_FILE"

echo "" >> "$MISSING_IMAGES_FILE"
echo "---" >> "$MISSING_IMAGES_FILE"
echo "*注：由于原目录已清理，大部分图片文件已丢失。建议根据重要性决定是否补充。*" >> "$MISSING_IMAGES_FILE"

echo "=========================================="
echo "检查完成！"
echo ""
echo "📊 统计结果："
echo "- 有图片引用的文件: $FILES_WITH_IMAGES 个"
echo "- 图片引用总数: $TOTAL_REFERENCES 个"
echo "- 存在图片数: $EXISTING_IMAGES 个"
echo "- 缺失图片数: $MISSING_IMAGES 个"
echo "- 缺失比例: $((MISSING_IMAGES * 100 / TOTAL_REFERENCES))%"
echo ""
echo "📋 详细清单: $MISSING_IMAGES_FILE"
echo ""
echo "💡 建议："
echo "1. 如果图片不重要，可以忽略"
echo "2. 如需补充，参考清单逐步恢复"
echo "3. 核心技术图片已迁移（TCP三次握手、HTTP状态码等）"