#!/bin/bash
set -e

# -----------------------
# InfluxDB 配置
# -----------------------
ORG="${ORG_NAME:-my-org}"
MAIN_BUCKET="${MAIN_BUCKET_NAME:-my-bucket}"
TOKEN="${INFLUX_TOKEN}"
HOST="${INFLUX_HOST:-http://localhost:8086}"
BACKUP_DIR="${BACKUP_DIR:-/backup}"

# -----------------------
# 保留天数配置
# -----------------------
# 从环境变量读取保留天数，如果未设置则默认14天
MAX_RETENTION_DAYS=${MAX_RETENTION_DAYS:-14}

# -----------------------
# 每日恢复函数
# -----------------------
daily_restore() {
  # 获取昨天的日期
  # 使用兼容BusyBox的方式计算：当前时间戳减去86400秒(一天)
  YESTERDAY=$(date -d @$(($(date +%s) - 86400)) +%F)
  ARCHIVE_BUCKET="archive_${YESTERDAY}"
  BACKUP_FILE="${BACKUP_DIR}/${ARCHIVE_BUCKET}.tar.gz"
  
  echo "==== Start daily restore for $YESTERDAY ===="
  
  # 检查备份文件是否存在
  if [ ! -f "$BACKUP_FILE" ]; then
    echo "错误: 备份文件 $BACKUP_FILE 不存在"
    return 1
  fi
  
  # 临时解压目录
  TMP_DIR=$(mktemp -d)
  tar -xzf "$BACKUP_FILE" -C "$TMP_DIR"
  
  # 取解压后的目录
  RESTORE_DIR="$TMP_DIR/${ARCHIVE_BUCKET}"
  
  # 恢复数据
  echo "开始恢复数据到 bucket $ARCHIVE_BUCKET ..."
  influx restore \
    --bucket "$ARCHIVE_BUCKET" \
    --new-bucket "$ARCHIVE_BUCKET" \
    --org "$ORG" \
    --host "$HOST" \
    --token "$TOKEN" \
    "$RESTORE_DIR"
  
  echo "恢复完成 ✅"
  
  # 清理临时目录
  rm -rf "$TMP_DIR"
  
  # 调用清理旧数据函数
  cleanup_old_data
  
  echo "==== Done daily restore for $YESTERDAY ===="
}

# -----------------------
# 清理旧数据函数
# -----------------------
cleanup_old_data() {
  echo "==== 开始清理超过 $MAX_RETENTION_DAYS 天的数据 ===="
  
  # 获取所有归档 bucket 列表
  ARCHIVE_BUCKETS=$(influx bucket list --org "$ORG" --host "$HOST" --token "$TOKEN" --json | jq -r '.[] | select(.name | startswith("archive_")) | .name' | sort)
  
  # 计算超过保留天数的日期阈值
  # 使用兼容BusyBox的方式计算：当前时间戳减去保留天数×86400秒
  THRESHOLD_DATE=$(date -d @$(($(date +%s) - ${MAX_RETENTION_DAYS}*86400)) +%s)
  
  # 处理每个归档 bucket
  for BUCKET in $ARCHIVE_BUCKETS; do
    # 从 bucket 名称提取日期
    BUCKET_DATE=$(echo "$BUCKET" | sed 's/^archive_//')
    
    # 将日期转换为时间戳进行比较
    # 注意：BusyBox的date命令支持直接解析YYYY-MM-DD格式
    BUCKET_TIMESTAMP=$(date -d "$BUCKET_DATE" +%s 2>/dev/null)
    
    if [ $? -eq 0 ] && [ $BUCKET_TIMESTAMP -lt $THRESHOLD_DATE ]; then
      echo "处理过期数据: $BUCKET ($BUCKET_DATE)"
      
      # 将数据插回主 bucket
      echo "将 $BUCKET 的数据插回主 bucket $MAIN_BUCKET"
      influx query \
        --org "$ORG" \
        --host "$HOST" \
        --token "$TOKEN" \
        "from(bucket:\"$BUCKET\")
          |> range(start: 0)
          |> to(bucket:\"$MAIN_BUCKET\")"
      
      # 删除过期的 bucket
      echo "删除过期的 bucket: $BUCKET"
      influx bucket delete \
        --name "$BUCKET" \
        --org "$ORG" \
        --host "$HOST" \
        --token "$TOKEN"
    fi
  done
  
  echo "==== 清理完成 ===="
}

# -----------------------
# 主程序入口
# -----------------------
# 直接执行每日恢复流程
daily_restore

