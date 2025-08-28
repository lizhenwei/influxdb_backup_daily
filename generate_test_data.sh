#!/bin/bash

# 设置环境变量默认值（与备份脚本保持一致）
ORG_NAME="${ORG_NAME:-my-org}"
MAIN_BUCKET_NAME="${MAIN_BUCKET_NAME:-my-bucket}"
INFLUX_HOST="${INFLUX_HOST:-http://localhost:8086}"

# 检查INFLUX_TOKEN是否设置
if [ -z "$INFLUX_TOKEN" ]; then
  echo "错误: INFLUX_TOKEN环境变量未设置" >&2
  exit 1
fi

# 生成随机测试数据
# 模拟传感器数据：温度、湿度、压力
current_unix_time=$(date -u +%s)
timestamp_ns="$current_unix_time"000000000 # 转换为纳秒时间戳
temperature=$(echo "scale=2; 20 + $RANDOM * 10 / 32767" | bc)
humidity=$(echo "scale=2; 40 + $RANDOM * 40 / 32767" | bc)
pressure=$(echo "scale=2; 980 + $RANDOM * 40 / 32767" | bc)

# 随机选择设备ID（模拟多个设备）
device_ids=("device_1" "device_2" "device_3" "device_4" "device_5")
random_index=$(( RANDOM % ${#device_ids[@]} ))
device_id=${device_ids[$random_index]}

# 构建InfluxDB数据点
# 格式: measurement,tag1=value1,tag2=value2 field1=value1,field2=value2 timestamp
# 测量值类型说明:
# - field使用数值类型（无需引号）
# - tag使用字符串类型（需要引号）
data_point="sensor_data,device_id=${device_id},location=test_location temperature=${temperature},humidity=${humidity},pressure=${pressure} ${timestamp_ns}"

# 输出数据点信息（用于调试）
echo "[$(date)] 生成数据: $data_point"

# 写入数据到InfluxDB
echo "$data_point" | influx write \
  --host "$INFLUX_HOST" \
  --token "$INFLUX_TOKEN" \
  --org "$ORG_NAME" \
  --bucket "$MAIN_BUCKET_NAME"

# 检查写入是否成功
if [ $? -eq 0 ]; then
  echo "[$(date)] 数据成功写入InfluxDB"
else
  echo "[$(date)] 数据写入失败，请检查InfluxDB连接和配置" >&2
  exit 1
fi

# 额外生成一些不同类型的测试数据以丰富测试场景
# 模拟系统指标数据：CPU使用率、内存使用率、磁盘使用率
cpu_usage=$(echo "scale=2; $RANDOM * 100 / 32767" | bc)
memory_usage=$(echo "scale=2; 50 + $RANDOM * 50 / 32767" | bc)
disk_usage=$(echo "scale=2; 30 + $RANDOM * 70 / 32767" | bc)

# 构建系统指标数据点
system_metrics_point="system_metrics,host=test_host cpu_usage=${cpu_usage},memory_usage=${memory_usage},disk_usage=${disk_usage} ${timestamp_ns}"

# 写入系统指标数据
echo "$system_metrics_point" | influx write \
  --host "$INFLUX_HOST" \
  --token "$INFLUX_TOKEN" \
  --org "$ORG_NAME" \
  --bucket "$MAIN_BUCKET_NAME"

if [ $? -eq 0 ]; then
  echo "[$(date)] 系统指标数据成功写入InfluxDB"
else
  echo "[$(date)] 系统指标数据写入失败" >&2
fi

exit 0
