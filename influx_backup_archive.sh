#!/bin/bash
set -e

# -----------------------
# InfluxDB 配置
# -----------------------
ORG="${ORG_NAME:-my-org}"
SOURCE_BUCKET="${MAIN_BUCKET_NAME:-my-bucket}"
TOKEN="${INFLUX_TOKEN}"
HOST="${INFLUX_HOST:-http://localhost:8086}"

# -----------------------
# 归档和备份目录
# -----------------------
BASE_BACKUP_DIR="/backup"

# -----------------------
# 保留天数配置
# -----------------------
# 从环境变量读取保留天数，如果未设置则默认14天
MAX_RETENTION_DAYS=${MAX_RETENTION_DAYS:-14}

# -----------------------
# 日期相关
# -----------------------
# 使用兼容BusyBox的方式计算昨天的日期
# 计算方式: 当前时间戳减去86400秒(一天)
# 注意: 由于Docker容器默认使用UTC时区，如果要按照本地时区计算日期，
# 请确保在docker run命令中添加时区文件挂载: -v /etc/localtime:/etc/localtime:ro -v /etc/timezone:/etc/timezone:ro
YESTERDAY=$(date -d @$(($(date +%s) - 86400)) +%F)
BUCKET="archive_${YESTERDAY}"
BACKUP_DIR="$BASE_BACKUP_DIR/$BUCKET"

echo "==== Start daily archive for $YESTERDAY ===="

# -----------------------
# 检查 bucket 是否存在
# -----------------------
if influx bucket list --org "$ORG" --host "$HOST" --token "$TOKEN" --json | jq -e ".[] | select(.name==\"$BUCKET\")" >/dev/null; then
  echo "Bucket $BUCKET already exists, skip creating."
else
  influx bucket create \
    --name "$BUCKET" \
    --org "$ORG" \
    --host "$HOST" \
    --token "$TOKEN"
fi

# -----------------------
# 复制昨天的数据到新 bucket
# -----------------------
influx query \
  --org "$ORG" \
  --host "$HOST" \
  --token "$TOKEN" \
  "from(bucket:\"$SOURCE_BUCKET\")
    |> range(start: ${YESTERDAY}T00:00:00Z, stop: ${YESTERDAY}T23:59:59Z)
    |> to(bucket:\"$BUCKET\")"

# -----------------------
# 备份 bucket
# -----------------------
mkdir -p "$BACKUP_DIR"
influx backup \
  "$BACKUP_DIR" \
  --bucket "$BUCKET" \
  --org "$ORG" \
  --host "$HOST" \
  --token "$TOKEN"

# -----------------------
# 压缩备份并清理
# -----------------------
tar -czf "${BACKUP_DIR}.tar.gz" -C "$(dirname "$BACKUP_DIR")" "$(basename "$BACKUP_DIR")"
rm -rf "$BACKUP_DIR"

echo "==== Done daily archive for $YESTERDAY ===="

# -----------------------
# 清理超过保留天数的归档 bucket
# -----------------------
echo "==== 开始清理超过 $MAX_RETENTION_DAYS 天的归档 bucket ===="

# 获取所有归档 bucket 列表
# 注意：这里使用startswith("archive_")条件严格过滤，只会选择名称以archive_开头的归档bucket
# 不会包含任何业务bucket（如ess等），因此不会影响正常业务数据
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
    echo "处理过期的归档 bucket: $BUCKET ($BUCKET_DATE)"
    
    # 删除过期的 bucket
    influx bucket delete \
      --name "$BUCKET" \
      --org "$ORG" \
      --host "$HOST" \
      --token "$TOKEN"
  fi
done

echo "==== 清理完成 ===="

