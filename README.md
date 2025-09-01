# InfluxDB 备份与恢复方案

这是一个完整的 InfluxDB 增量备份与恢复方案，通过 Docker 容器实现自动化的每日备份和恢复，并管理数据保留周期。

## 功能特点

- **每日增量备份**：自动备份前一天的增量数据
- **自动恢复**：每日恢复备份数据到临时 bucket
- **数据保留管理**：最多保留 14 天的日备份数据
- **数据归档**：超过 14 天的数据自动归档回主 bucket
- **环境变量配置**：支持通过环境变量灵活配置
- **Docker 容器化**：使用 Alpine 基础镜像，体积小，资源占用低
- **一次性备份**：支持执行单次备份操作，适用于临时备份或指定日期备份

## 备份流程

1. 每天凌晨 2 点执行备份任务
2. 创建日期格式的临时 bucket（如 `archive_2023-05-20`）
3. 从主 bucket 复制前一天的数据到临时 bucket
4. 备份临时 bucket 数据到压缩文件
5. 备份文件存储在 `/backup` 目录

## 恢复流程

1. 每天凌晨 3 点执行恢复任务（在备份完成后）
2. 从备份文件恢复前一天的数据到临时 bucket
3. 检查并管理所有临时 bucket 的保留时间
4. 对于超过 14 天的临时 bucket：
   - 将数据插回主 bucket
   - 删除过期的临时 bucket

## 环境变量配置

以下环境变量可以在运行 Docker 容器时配置：

| 环境变量 | 默认值 | 描述 |
|---------|-------|------|
| `ORG_NAME` | `my-org` | InfluxDB 组织名称 |
| `MAIN_BUCKET_NAME` | `my-bucket` | 主 bucket 名称 |
| `INFLUX_TOKEN` | 无默认值（必须提供） | InfluxDB 访问令牌 |
| `INFLUX_HOST` | `http://localhost:8086` | InfluxDB 服务器地址 |
| `BACKUP_DAY` | 无默认值（未设置则备份当天） | 指定要备份的日期，格式为YYYY-MM-DD（仅适用于一次性备份） |

## Docker 运行命令

### 备份容器

```bash
# 运行备份容器
docker run -d \
  --name influxdb-backup \
  -e INFLUX_TOKEN=your_token_here \
  -e INFLUX_HOST=http://influxdb:8086 \
  -e ORG_NAME=your_org \
  -e MAIN_BUCKET_NAME=your_main_bucket \
  -v /path/to/backup:/backup \
  --network=your_influxdb_network \
  docker.sfere.local/influxdb-backup:latest
```

### 一次性备份容器

```bash
# 运行一次性备份容器（备份当天数据）
docker run \
  -e INFLUX_TOKEN=your_token_here \
  -e INFLUX_HOST=http://influxdb:8086 \
  -e ORG_NAME=your_org \
  -e MAIN_BUCKET_NAME=your_main_bucket \
  -v /path/to/backup:/backup \
  --network=your_influxdb_network \
  docker.sfere.local/influxdb-once:latest

# 运行一次性备份容器（备份指定日期数据）
docker run \
  -e INFLUX_TOKEN=your_token_here \
  -e INFLUX_HOST=http://influxdb:8086 \
  -e ORG_NAME=your_org \
  -e MAIN_BUCKET_NAME=your_main_bucket \
  -e BACKUP_DAY=2023-05-20 \
  -v /path/to/backup:/backup \
  --network=your_influxdb_network \
  docker.sfere.local/influxdb-once:latest
```

### 恢复容器

```bash
# 运行恢复容器
docker run -d \
  --name influxdb-restore \
  -e INFLUX_TOKEN=your_token_here \
  -e INFLUX_HOST=http://influxdb:8086 \
  -e ORG_NAME=your_org \
  -e MAIN_BUCKET_NAME=your_main_bucket \
  -v /path/to/backup:/backup \
  --network=your_influxdb_network \
  docker.sfere.local/influxdb-restore:latest
```

## 快速开始指南

### 1. 准备工作

- 确保已安装 Docker
- 确保可以访问 InfluxDB 服务器
- 获取具有足够权限的 InfluxDB 访问令牌

### 2. 构建 Docker 镜像

```bash
# 构建备份镜像
docker build -t docker.sfere.local/influxdb-backup:latest -f Dockerfile.backup .

# 构建恢复镜像
docker build -t docker.sfere.local/influxdb-restore:latest -f Dockerfile.restore .

# 构建一次性备份镜像
docker build -t docker.sfere.local/influxdb-once:latest -f Dockerfile.once .
```

### 3. 创建持久化备份目录

```bash
# 在主机上创建备份目录
mkdir -p /path/to/backup
chmod 777 /path/to/backup
```

### 4. 运行备份容器

```bash
# 运行备份容器
docker run -d \
  --name influxdb-backup \
  -e INFLUX_TOKEN=your_influxdb_token_here \
  -e INFLUX_HOST=http://influxdb_server:8086 \
  -e ORG_NAME=your_organization_name \
  -e MAIN_BUCKET_NAME=your_main_bucket_name \
  -v /path/to/backup:/backup \
  -v /etc/localtime:/etc/localtime:ro \
  -v /etc/timezone:/etc/timezone:ro \
  docker.sfere.local/influxdb-backup:latest
```

### 5. 运行恢复容器

### 6. 运行一次性备份（可选）

如果需要执行单次备份操作，可以使用一次性备份容器。这对于临时备份或补备份历史数据非常有用：

```bash
# 运行一次性备份容器（备份当天数据）
docker run \
  -e INFLUX_TOKEN=your_influxdb_token_here \
  -e INFLUX_HOST=http://influxdb_server:8086 \
  -e ORG_NAME=your_organization_name \
  -e MAIN_BUCKET_NAME=your_main_bucket_name \
  -v /path/to/backup:/backup \
  docker.sfere.local/influxdb-once:latest

# 运行一次性备份容器（备份指定日期数据）
docker run  \
  -e INFLUX_TOKEN=your_influxdb_token_here \
  -e INFLUX_HOST=http://influxdb_server:8086 \
  -e ORG_NAME=your_organization_name \
  -e MAIN_BUCKET_NAME=your_main_bucket_name \
  -e BACKUP_DAY=2023-05-20 \
  -v /path/to/backup:/backup \
  docker.sfere.local/influxdb-once:latest
```

```bash
# 运行恢复容器
docker run -d \
  --name influxdb-restore \
  -e INFLUX_TOKEN=your_influxdb_token_here \
  -e INFLUX_HOST=http://influxdb_server:8086 \
  -e ORG_NAME=your_organization_name \
  -e MAIN_BUCKET_NAME=your_main_bucket_name \
  -e MAX_RETENTION_DAYS=14 \
  -v /path/to/backup:/backup \
  -v /etc/localtime:/etc/localtime:ro \
  -v /etc/timezone:/etc/timezone:ro \
  docker.sfere.local/influxdb-restore:latest
```

### 运行说明

- **网络连接**：如果 InfluxDB 也在 Docker 中运行，请确保备份和恢复容器与 InfluxDB 容器在同一个 Docker 网络中
- **持久化存储**：`/path/to/backup` 是主机上的目录，用于持久化存储备份文件
- **必需参数**：`INFLUX_TOKEN` 是必需的，其他参数可以根据需要修改
- **自动执行**：容器启动后会自动按照 crontab 配置的时间执行备份和恢复任务

## 目录挂载

- `/backup` 目录：容器内的备份文件存储目录，所有备份和恢复脚本都使用此固定目录。为了持久化存储备份文件，必须通过 Docker 的 `-v` 参数将主机上的目录挂载到容器的 `/backup` 目录，例如 `-v /path/to/backup:/backup`。

## 日志查看

备份和恢复过程的日志可以通过以下命令查看：

```bash
# 查看备份日志
docker logs influxdb-backup

# 或直接查看日志文件
docker exec -it influxdb-backup cat /var/log/influx_backup.log

# 查看恢复日志
docker logs influxdb-restore

# 或直接查看日志文件
docker exec -it influxdb-restore cat /var/log/influx_restore.log
```

## 手动执行备份或恢复

您也可以手动执行备份或恢复操作：

```bash
# 手动执行备份
docker exec -it influxdb-backup /usr/local/bin/influx_backup_archive.sh

# 手动执行恢复
docker exec -it influxdb-restore /usr/local/bin/influx_restore_archive.sh
```
