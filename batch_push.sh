#!/bin/bash
set -euo pipefail

MAX_BATCH_MB=40
MAX_BATCH_BYTES=$(( MAX_BATCH_MB * 1024 * 1024 ))

# 列出所有未跟踪/修改文件，按从小到大排序（避免大文件卡在第一批）
mapfile -t file_list < <(git ls-files --others --modified --exclude-standard | while read -r f; do
    if [ -f "$f" ]; then
        size=$(stat -c %s "$f")
        echo "$size $f"
    fi
done | sort -n | cut -d' ' -f2-)

total_files=${#file_list[@]}
if [ "$total_files" -eq 0 ]; then
    echo "✅ 没有待提交文件"
    exit 0
fi

echo "🔍 待处理文件总数：$total_files，单批上限 ${MAX_BATCH_MB}MB"

batch=1
current_sum=0
batch_files=()

for f in "${file_list[@]}"; do
    size=$(stat -c %s "$f")
    # 单个文件超过阈值直接告警跳过
    if (( size > MAX_BATCH_BYTES )); then
        echo "⚠️ 单个文件超限（> ${MAX_BATCH_MB}MB）跳过：$f ($size bytes)"
        continue
    fi

    # 加上这个文件会超，则先提交当前批次
    if (( current_sum + size > MAX_BATCH_BYTES )) && (( ${#batch_files[@]} > 0 )); then
        echo -e "\n==== 📦 第 $batch 批，总大小 $((current_sum/1024/1024)) MB ===="
        printf "%s\n" "${batch_files[@]}"
        git add "${batch_files[@]}"
        git commit -m "batch $batch"
        git push origin main
        echo "✅ 第 $batch 批推送完成"

        batch=$((batch + 1))
        current_sum=0
        batch_files=()
    fi

    batch_files+=("$f")
    current_sum=$((current_sum + size))
done

# 最后剩余一批
if (( ${#batch_files[@]} > 0 )); then
    echo -e "\n==== 📦 第 $batch 批，总大小 $((current_sum/1024/1024)) MB ===="
    printf "%s\n" "${batch_files[@]}"
    git add "${batch_files[@]}"
    git commit -m "batch $batch"
    git push origin main
    echo "✅ 第 $batch 批推送完成"
fi

echo -e "\n🎉 全部批次推送完毕"

