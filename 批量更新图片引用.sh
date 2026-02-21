#!/bin/bash

echo "开始批量更新图片引用为Wiki链接格式..."
echo "=========================================="

# 创建图片丢失记录文件
LOST_IMAGES_FILE="./学习中心/资源/丢失图片记录.md"
echo "# 丢失图片记录" > "$LOST_IMAGES_FILE"
echo "> 记录迁移过程中丢失的图片文件" >> "$LOST_IMAGES_FILE"
echo "> 生成时间：$(date '+%Y-%m-%d %H:%M:%S')" >> "$LOST_IMAGES_FILE"
echo "" >> "$LOST_IMAGES_FILE"
echo "## 丢失图片列表" >> "$LOST_IMAGES_FILE"
echo "" >> "$LOST_IMAGES_FILE"

# 计数器
TOTAL_FILES=0
UPDATED_FILES=0
LOST_IMAGES=0

# 查找所有有图片引用的Markdown文件
while IFS= read -r file; do
    TOTAL_FILES=$((TOTAL_FILES + 1))
    echo "处理文件: $file"

    # 备份原文件
    cp "$file" "$file.bak"

    # 提取文件中的所有图片引用
    IMAGE_REFS=$(grep -o "!\[.*\]([^)]*\.png)" "$file" | sed 's/.*(\(.*\))/\1/' | sed 's/%20/ /g')

    UPDATED=false

    # 处理每个图片引用
    for img_ref in $IMAGE_REFS; do
        # 检查图片文件是否存在（在当前目录或上级目录）
        IMG_FOUND=false
        DIR=$(dirname "$file")

        # 在当前文件目录查找
        if [ -f "$DIR/$img_ref" ]; then
            # 图片存在，迁移到统一目录
            IMG_NAME=$(basename "$img_ref" | sed 's/ /_/g')
            cp "$DIR/$img_ref" "./学习中心/资源/图片/$IMG_NAME"
            # 更新引用为Wiki链接
            sed -i '' "s|!\[.*\](.*$img_ref)|![[$IMG_NAME]]|g" "$file"
            IMG_FOUND=true
        fi

        if [ "$IMG_FOUND" = false ]; then
            # 图片不存在，记录丢失
            LOST_IMAGES=$((LOST_IMAGES + 1))
            echo "- **$img_ref**" >> "$LOST_IMAGES_FILE"
            echo "  - 引用文件: $file" >> "$LOST_IMAGES_FILE"
            echo "  - 状态: ❌ 文件不存在" >> "$LOST_IMAGES_FILE"
            echo "" >> "$LOST_IMAGES_FILE"

            # 仍然更新引用为Wiki链接格式（即使图片丢失）
            IMG_NAME=$(basename "$img_ref" | sed 's/ /_/g')
            sed -i '' "s|!\[.*\](.*$img_ref)|![[$IMG_NAME]]|g" "$file"
        fi

        UPDATED=true
    done

    if [ "$UPDATED" = true ]; then
        UPDATED_FILES=$((UPDATED_FILES + 1))
        echo "  ✅ 已更新图片引用"
    else
        echo "  ℹ️  无图片引用需要更新"
    fi

    # 清理备份文件（如果内容相同）
    if diff -q "$file" "$file.bak" > /dev/null; then
        rm "$file.bak"
    fi

    echo ""
done < <(find ./学习中心 -name "*.md" -type f -exec grep -l "!\[.*\](.*\.png)" {} \;)

# 更新丢失图片记录文件
echo "## 统计信息" >> "$LOST_IMAGES_FILE"
echo "" >> "$LOST_IMAGES_FILE"
echo "- 检查文件数: $TOTAL_FILES" >> "$LOST_IMAGES_FILE"
echo "- 更新文件数: $UPDATED_FILES" >> "$LOST_IMAGES_FILE"
echo "- 丢失图片数: $LOST_IMAGES" >> "$LOST_IMAGES_FILE"
echo "- 处理时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOST_IMAGES_FILE"
echo "" >> "$LOST_IMAGES_FILE"
echo "## 解决方案建议" >> "$LOST_IMAGES_FILE"
echo "" >> "$LOST_IMAGES_FILE"
echo "1. 如果这些图片有备份，请将它们复制到 \`学习中心/资源/图片/\` 目录" >> "$LOST_IMAGES_FILE"
echo "2. 图片文件名中的空格已被替换为下划线" >> "$LOST_IMAGES_FILE"
echo "3. 所有图片引用已更新为Wiki链接格式 \`![[图片名.png]]\`" >> "$LOST_IMAGES_FILE"
echo "4. 如果不需要这些图片，可以忽略此记录" >> "$LOST_IMAGES_FILE"

echo "=========================================="
echo "批量更新完成！"
echo "处理文件数: $TOTAL_FILES"
echo "更新文件数: $UPDATED_FILES"
echo "丢失图片数: $LOST_IMAGES"
echo ""
echo "详细记录请查看: $LOST_IMAGES_FILE"
echo "图片资源目录: ./学习中心/资源/图片/"