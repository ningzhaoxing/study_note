#!/bin/bash

echo "修复丢失图片记录..."
echo "=========================================="

# 重新创建图片丢失记录文件
LOST_IMAGES_FILE="./学习中心/资源/丢失图片记录.md"
echo "# 丢失图片记录" > "$LOST_IMAGES_FILE"
echo "> 记录迁移过程中丢失的图片文件" >> "$LOST_IMAGES_FILE"
echo "> 生成时间：$(date '+%Y-%m-%d %H:%M:%S')" >> "$LOST_IMAGES_FILE"
echo "" >> "$LOST_IMAGES_FILE"
echo "## 丢失图片列表" >> "$LOST_IMAGES_FILE"
echo "" >> "$LOST_IMAGES_FILE"

# 计数器
TOTAL_IMAGES=0

# 查找所有Wiki链接格式的图片引用，并记录丢失的图片
find ./学习中心 -name "*.md" -type f | while read -r file; do
    # 提取文件中的所有Wiki链接格式图片引用
    IMAGE_REFS=$(grep -o "!\[\[.*\.png\]\]" "$file" | sed 's/!\[\[//' | sed 's/\]\]//')

    for img_name in $IMAGE_REFS; do
        # 检查图片文件是否存在
        if [ ! -f "./学习中心/资源/图片/$img_name" ]; then
            TOTAL_IMAGES=$((TOTAL_IMAGES + 1))
            echo "- **$img_name**" >> "$LOST_IMAGES_FILE"
            echo "  - 引用文件: $file" >> "$LOST_IMAGES_FILE"
            echo "  - 状态: ❌ 文件不存在" >> "$LOST_IMAGES_FILE"
            echo "" >> "$LOST_IMAGES_FILE"
        fi
    done
done

# 更新丢失图片记录文件
echo "## 统计信息" >> "$LOST_IMAGES_FILE"
echo "" >> "$LOST_IMAGES_FILE"
echo "- 丢失图片总数: $TOTAL_IMAGES" >> "$LOST_IMAGES_FILE"
echo "- 处理时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOST_IMAGES_FILE"
echo "" >> "$LOST_IMAGES_FILE"
echo "## 解决方案建议" >> "$LOST_IMAGES_FILE"
echo "" >> "$LOST_IMAGES_FILE"
echo "1. 所有图片引用已更新为Wiki链接格式: \`![[图片名.png]]\`" >> "$LOST_IMAGES_FILE"
echo "2. 图片文件名中的空格已被替换为下划线" >> "$LOST_IMAGES_FILE"
echo "3. 如果这些图片有备份，请将它们复制到 \`学习中心/资源/图片/\` 目录" >> "$LOST_IMAGES_FILE"
echo "4. 复制时请注意文件名匹配（已移除空格）" >> "$LOST_IMAGES_FILE"
echo "5. 如果不需要这些图片，可以忽略此记录" >> "$LOST_IMAGES_FILE"
echo "" >> "$LOST_IMAGES_FILE"
echo "## 常见原文件名与现文件名对应" >> "$LOST_IMAGES_FILE"
echo "" >> "$LOST_IMAGES_FILE"
echo "| 原文件名 | 现文件名 |" >> "$LOST_IMAGES_FILE"
echo "|----------|----------|" >> "$LOST_IMAGES_FILE"
echo "| \`Pasted image 20250118082336.png\` | \`20250118082336.png\` |" >> "$LOST_IMAGES_FILE"
echo "| \`Pasted image 20241123095049.png\` | \`20241123095049.png\` |" >> "$LOST_IMAGES_FILE"
echo "| \`Pasted image 20241123200044.png\` | \`20241123200044.png\` |" >> "$LOST_IMAGES_FILE"
echo "| \`Pasted image 20250302105329.png\` | \`20250302105329.png\` |" >> "$LOST_IMAGES_FILE"

echo "=========================================="
echo "修复完成！"
echo "丢失图片总数: $TOTAL_IMAGES"
echo ""
echo "详细记录请查看: $LOST_IMAGES_FILE"