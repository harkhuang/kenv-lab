#!/bin/bash

# Redis集群诊断脚本

set -e

# 配置参数
CLUSTER_3_PORT=7001
CLUSTER_6_PORT=7011
HOST="127.0.0.1"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# 检查Redis集群连接
check_cluster_connection() {
    local port=$1
    local cluster_name=$2
    
    log_info "检查${cluster_name}集群连接 (端口: $port)..."
    
    # 检查Redis进程
    if ! pgrep -f "redis-server.*:$port" > /dev/null; then
        log_error "${cluster_name}集群进程未运行 (端口: $port)"
        return 1
    fi
    
    # 检查连接
    if ! redis-cli -h ${HOST} -p ${port} ping &>/dev/null; then
        log_error "无法连接到${cluster_name}集群 ${HOST}:${port}"
        return 1
    fi
    
    # 检查集群状态
    local cluster_state=$(redis-cli -h ${HOST} -p ${port} cluster info 2>/dev/null | grep cluster_state | cut -d: -f2 | tr -d '\r')
    if [ "$cluster_state" != "ok" ]; then
        log_error "${cluster_name}集群状态异常: $cluster_state"
        return 1
    fi
    
    # 检查集群节点
    local node_count=$(redis-cli -h ${HOST} -p ${port} cluster nodes 2>/dev/null | wc -l)
    log_success "${cluster_name}集群连接正常，节点数: $node_count"
    
    return 0
}

# 检查redis-benchmark支持
check_redis_benchmark() {
    log_info "检查redis-benchmark工具..."
    
    if ! command -v redis-benchmark &> /dev/null; then
        log_error "redis-benchmark 命令未找到"
        return 1
    fi
    
    # 检查是否支持--cluster参数
    if redis-benchmark --help 2>&1 | grep -q "cluster"; then
        log_success "redis-benchmark 支持 --cluster 参数"
    else
        log_warning "redis-benchmark 不支持 --cluster 参数，将使用替代方案"
    fi
    
    return 0
}

# 简单性能测试
simple_performance_test() {
    local port=$1
    local cluster_name=$2
    
    log_info "执行${cluster_name}集群简单性能测试..."
    
    # 测试基本连接
    local temp_file="/tmp/simple_test_$$_${cluster_name}.txt"
    
    # 尝试使用--cluster参数
    if redis-benchmark --help 2>&1 | grep -q "cluster"; then
        redis-benchmark -h ${HOST} -p ${port} --cluster \
            -t set -n 1000 -c 10 -d 64 --quiet > "$temp_file" 2>&1
    else
        # 不支持--cluster参数，使用普通模式
        redis-benchmark -h ${HOST} -p ${port} \
            -t set -n 1000 -c 10 -d 64 --quiet > "$temp_file" 2>&1
    fi
    
    if [ $? -eq 0 ]; then
        local qps=$(grep "requests per second" "$temp_file" | tail -1 | awk '{print $(NF-3)}' | tr -d ',')
        log_success "${cluster_name}集群测试成功，QPS: $qps"
    else
        log_error "${cluster_name}集群测试失败"
        cat "$temp_file"
    fi
    
    rm -f "$temp_file"
}

# 检查系统资源
check_system_resources() {
    log_info "检查系统资源..."
    
    # 检查内存
    local mem_info=$(free -h | grep "Mem:")
    local mem_used=$(echo $mem_info | awk '{print $3}')
    local mem_total=$(echo $mem_info | awk '{print $2}')
    log_info "内存使用: ${mem_used}/${mem_total}"
    
    # 检查CPU负载
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    log_info "负载平均值: ${load_avg}"
    
    # 检查Redis进程
    local redis_processes=$(ps aux | grep redis-server | grep -v grep | wc -l)
    log_info "Redis进程数: ${redis_processes}"
    
    # 显示Redis进程详情
    log_info "Redis进程详情:"
    ps aux | grep redis-server | grep -v grep | while read line; do
        echo "  $line"
    done
}

# 主函数
main() {
    echo "==========================================="
    echo "Redis集群诊断工具"
    echo "==========================================="
    
    # 检查系统资源
    check_system_resources
    echo
    
    # 检查redis-benchmark
    check_redis_benchmark
    echo
    
    # 检查3节点集群
    if check_cluster_connection $CLUSTER_3_PORT "3节点"; then
        simple_performance_test $CLUSTER_3_PORT "3节点"
    fi
    echo
    
    # 检查6节点集群
    if check_cluster_connection $CLUSTER_6_PORT "6节点"; then
        simple_performance_test $CLUSTER_6_PORT "6节点"
    fi
    echo
    
    log_info "诊断完成"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi