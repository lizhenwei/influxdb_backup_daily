#!/bin/sh
set -e

# ===================================================
# InfluxDB 今日数据备份脚本
# ===================================================
# 功能说明:
#   该脚本用于备份InfluxDB中指定日期或当天的数据到单独的bucket并创建备份文件
#   与influx_backup_archive.sh类似，但可以灵活指定备份日期
#   适用于需要在当天内进行数据备份或补备份历史数据的场景
#
# 数据流程:
#   1. 创建以目标日期命名的归档bucket
#   2. 将主bucket中目标日期的数据复制到归档bucket
#   3. 备份归档bucket到文件系统
#   4. 压缩备份文件
#
# 环境变量配置:
#   - ORG_NAME: InfluxDB组织名称，默认值为"my-org"
#   - MAIN_BUCKET_NAME: 主bucket名称，默认值为"my-bucket"
#   - INFLUX_TOKEN: InfluxDB访问令牌(必填)
#   - INFLUX_HOST: InfluxDB服务器地址，默认值为"http://localhost:8086"
#   - BACKUP_DAY: 指定要备份的日期，格式为YYYY-MM-DD，未设置则备份当天
# ===================================================

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
# 固定备份目录为/backup，与其他脚本保持一致
BASE_BACKUP_DIR="/backup"



# -----------------------
# 日期相关
# -----------------------
# 获取目标备份日期 - 优先使用BACKUP_DAY环境变量，否则使用当天日期
if [ -n "$BACKUP_DAY" ]; then
  # 验证日期格式是否正确
  if ! date -d "$BACKUP_DAY" +%F >/dev/null 2>&1; then
    echo "错误: BACKUP_DAY环境变量格式不正确，请使用YYYY-MM-DD格式" >&2
    exit 1
  fi
  TARGET_DATE="$BACKUP_DAY"
else
  TARGET_DATE=$(date +%F)
fi

BUCKET="archive_${TARGET_DATE}"
# 创建备份目录
BACKUP_DIR="$BASE_BACKUP_DIR"
# 设置备份文件名格式为archive_日期.tar.gz
BACKUP_FILE="${BACKUP_DIR}/archive_${TARGET_DATE}"

# 如果备份目录不存在，创建备份目录
if [ ! -d "$BACKUP_DIR" ]; then
  mkdir -p "$BACKUP_DIR"
fi

# 检查INFLUX_TOKEN是否设置
if [ -z "$TOKEN" ]; then
  echo "错误: INFLUX_TOKEN环境变量未设置" >&2
  exit 1
fi

echo "==== 开始数据备份流程 ===="
echo "备份日期: $TARGET_DATE"
# -----------------------
# 检查 bucket 是否存在
# -----------------------
if influx bucket list --org "$ORG" --host "$HOST" --token "$TOKEN" --json | jq -e ".[] | select(.name==\"$BUCKET\")" >/dev/null; then
  echo "Bucket $BUCKET 已存在，跳过创建"
else
  echo "创建归档bucket: $BUCKET"
  influx bucket create \
    --name "$BUCKET" \
    --org "$ORG" \
    --host "$HOST" \
    --token "$TOKEN"
fi

# -----------------------
# 复制指定日期的数据到归档 bucket
# -----------------------
echo "正在复制${TARGET_DATE}的数据到归档bucket..."

# 计算目标日期的开始时间和结束时间（UTC时间）
TARGET_START="${TARGET_DATE}T00:00:00Z"
TARGET_END="${TARGET_DATE}T23:59:59Z"

# 如果备份的是当天，使用当前时间作为结束时间
if [ "$TARGET_DATE" = "$(date +%F)" ]; then
  TARGET_END=$(date -u +%FT%TZ)
fi

echo "时间范围: $TARGET_START 到 $TARGET_END"

influx query \
  --org "$ORG" \
  --host "$HOST" \
  --token "$TOKEN" \
  "from(bucket:\"$SOURCE_BUCKET\")
    |> range(start: $TARGET_START, stop: $TARGET_END)
    |> to(bucket:\"$BUCKET\")"

# -----------------------
# 备份 bucket
# -----------------------
echo "正在备份归档bucket到文件系统..."

# 创建批次备份目录
mkdir -p "$BACKUP_FILE"

influx backup \
  "$BACKUP_FILE" \
  --bucket "$BUCKET" \
  --org "$ORG" \
  --host "$HOST" \
  --token "$TOKEN"

# -----------------------
# 压缩备份
# -----------------------
echo "正在压缩备份文件..."

# 压缩备份
tar -czf "${BACKUP_FILE}.tar.gz" -C "$BACKUP_DIR" "archive_${TARGET_DATE}"
# 清理未压缩的备份目录
rm -rf "$BACKUP_FILE"

echo "备份文件已创建: ${BACKUP_FILE}.tar.gz"

echo "==== 数据备份完成 ($TARGET_DATE) ===="
