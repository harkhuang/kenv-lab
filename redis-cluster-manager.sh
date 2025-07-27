#!/bin/bash

# Redis集群管理脚本
# 用法: ./redis-cluster-manager.sh [start|stop|status|create|reset]

set -e

# 配置参数
REDIS_HOME="/usr/local/bin"
CLUSTER_DIR="/home/k/kenv-lab/redis-cluster"
NODES=(7001 7002 7003)
HOST="127.0.0.1"
REDIS_VERSION="7.2.10"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查Redis是否已安装
check_redis() {
    if ! command -v redis-server &> /dev/null; then
        log_error "Redis未安装，请先安装Redis"
        exit 1
    fi
    log_info "Redis版本: $(redis-server --version)"
}

# 创建目录结构
create_directories() {
    log_info "创建集群目录结构..."
    for port in "${NODES[@]}"; do
        mkdir -p "${CLUSTER_DIR}/${port}"
        mkdir -p "${CLUSTER_DIR}/${port}/data"
        mkdir -p "${CLUSTER_DIR}/${port}/logs"
    done
    log_success "目录结构创建完成"
}

# 生成配置文件
generate_configs() {
    log_info "生成Redis配置文件..."
    
    for port in "${NODES[@]}"; do
        cat > "${CLUSTER_DIR}/${port}/redis.conf" << EOF
# Redis ${port} 配置文件
port ${port}
bind 127.0.0.1
protected-mode yes
tcp-backlog 511
timeout 0
tcp-keepalive 300

# 集群配置
cluster-enabled yes
cluster-config-file nodes-${port}.conf
cluster-node-timeout 15000
cluster-announce-ip 127.0.0.1
cluster-announce-port ${port}
cluster-announce-bus-port $((port + 10000))

# 数据持久化
dir ${CLUSTER_DIR}/${port}/data
dbfilename dump-${port}.rdb
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes

# AOF配置
appendonly yes
appendfilename "appendonly-${port}.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb

# 日志配置
logfile ${CLUSTER_DIR}/${port}/logs/redis-${port}.log
loglevel notice

# 内存配置
maxmemory 256mb
maxmemory-policy allkeys-lru

# 网络配置
maxclients 10000

# 安全配置
# requirepass your_password_here
# masterauth your_password_here
EOF
        log_success "节点 ${port} 配置文件生成完成"
    done
}

# 启动集群节点
start_nodes() {
    log_info "启动Redis集群节点..."
    
    for port in "${NODES[@]}"; do
        if pgrep -f "redis-server.*${port}" > /dev/null; then
            log_warning "节点 ${port} 已在运行"
            continue
        fi
        
        log_info "启动节点 ${port}..."
        redis-server "${CLUSTER_DIR}/${port}/redis.conf" --daemonize yes
        
        # 等待节点启动
        sleep 2
        
        if pgrep -f "redis-server.*${port}" > /dev/null; then
            log_success "节点 ${port} 启动成功"
        else
            log_error "节点 ${port} 启动失败"
            return 1
        fi
    done
}

# 创建集群
create_cluster() {
    log_info "创建Redis集群..."
    
    # 构建节点列表
    node_list=""
    for port in "${NODES[@]}"; do
        node_list="${node_list} ${HOST}:${port}"
    done
    
    log_info "节点列表: ${node_list}"
    
    # 创建集群
    echo "yes" | redis-cli --cluster create ${node_list} --cluster-replicas 0
    
    if [ $? -eq 0 ]; then
        log_success "Redis集群创建成功"
        show_cluster_info
    else
        log_error "Redis集群创建失败"
        return 1
    fi
}

# 停止集群
stop_cluster() {
    log_info "停止Redis集群..."
    
    for port in "${NODES[@]}"; do
        if pgrep -f "redis-server.*${port}" > /dev/null; then
            log_info "停止节点 ${port}..."
            redis-cli -p ${port} shutdown nosave 2>/dev/null || true
            sleep 1
            
            # 强制杀死进程（如果还在运行）
            pkill -f "redis-server.*${port}" 2>/dev/null || true
            
            log_success "节点 ${port} 已停止"
        else
            log_warning "节点 ${port} 未在运行"
        fi
    done
}

# 显示集群状态
show_cluster_status() {
    log_info "Redis集群状态:"
    
    for port in "${NODES[@]}"; do
        if pgrep -f "redis-server.*${port}" > /dev/null; then
            echo -e "  节点 ${port}: ${GREEN}运行中${NC}"
        else
            echo -e "  节点 ${port}: ${RED}已停止${NC}"
        fi
    done
    
    # 检查集群状态
    if redis-cli -p 7001 ping &>/dev/null; then
        echo
        log_info "集群信息:"
        redis-cli -p 7001 cluster info | grep -E "cluster_state|cluster_slots_assigned|cluster_known_nodes"
        
        echo
        log_info "节点信息:"
        redis-cli -p 7001 cluster nodes
    fi
}

# 显示集群详细信息
show_cluster_info() {
    echo
    log_info "=== Redis集群信息 ==="
    redis-cli -p 7001 cluster info
    
    echo
    log_info "=== 节点分布 ==="
    redis-cli -p 7001 cluster nodes
    
    echo
    log_info "=== 连接测试 ==="
    for port in "${NODES[@]}"; do
        result=$(redis-cli -p ${port} ping 2>/dev/null || echo "FAILED")
        echo "  节点 ${port}: ${result}"
    done
}

# 重置集群
reset_cluster() {
    log_warning "重置集群将删除所有数据，确认继续？(y/N)"
    read -r confirm
    if [[ $confirm != [yY] ]]; then
        log_info "操作已取消"
        return 0
    fi
    
    log_info "重置Redis集群..."
    
    # 停止集群
    stop_cluster
    
    # 清理数据文件
    for port in "${NODES[@]}"; do
        rm -rf "${CLUSTER_DIR}/${port}/data/*"
        rm -f "${CLUSTER_DIR}/${port}/nodes-${port}.conf"
        log_info "清理节点 ${port} 数据"
    done
    
    log_success "集群重置完成"
}

# 性能测试
performance_test() {
    log_info "执行性能测试..."
    
    if ! redis-cli -p 7001 ping &>/dev/null; then
        log_error "集群未运行，请先启动集群"
        return 1
    fi
    
    log_info "写入测试 (10000 keys)..."
    redis-cli -p 7001 --cluster call 127.0.0.1:7001 eval "for i=1,10000 do redis.call('set', 'test:key:' .. i, 'value' .. i) end" 0
    
    log_info "读取测试..."
    redis-cli -p 7001 --cluster call 127.0.0.1:7001 eval "for i=1,1000 do redis.call('get', 'test:key:' .. i) end" 0
    
    log_success "性能测试完成"
}

# 主函数
main() {
    case "$1" in
        "start")
            check_redis
            create_directories
            generate_configs
            start_nodes
            ;;
        "create")
            check_redis
            create_directories
            generate_configs
            start_nodes
            sleep 3
            create_cluster
            ;;
        "stop")
            stop_cluster
            ;;
        "status")
            show_cluster_status
            ;;
        "info")
            show_cluster_info
            ;;
        "reset")
            reset_cluster
            ;;
        "test")
            performance_test
            ;;
        *)
            echo "用法: $0 {start|create|stop|status|info|reset|test}"
            echo
            echo "命令说明:"
            echo "  start   - 启动集群节点（不创建集群）"
            echo "  create  - 完整创建并启动集群"
            echo "  stop    - 停止集群"
            echo "  status  - 显示集群状态"
            echo "  info    - 显示详细集群信息"
            echo "  reset   - 重置集群（删除所有数据）"
            echo "  test    - 执行性能测试"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"