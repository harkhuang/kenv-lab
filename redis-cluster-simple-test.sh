#!/bin/bash

# Redis集群简化性能测试脚本
# 针对单机环境优化，避免大数据量导致的问题

set -e

# 配置参数
RESULT_DIR="/home/k/kenv-lab/cluster-comparison-results"
TEST_TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
RESULT_FILE="${RESULT_DIR}/simple_cluster_test_${TEST_TIMESTAMP}.md"

# 简化的测试参数
TEST_OPERATIONS=("set" "get" "incr")
CONCURRENCY_LEVELS=(50 100 200)
REQUEST_COUNTS=(10000 50000)  # 减少请求数
DATA_SIZE=64  # 使用较小的数据大小

# 集群配置
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

# 检查集群状态
check_cluster() {
    local port=$1
    local cluster_name=$2
    
    log_info "检查${cluster_name}集群状态..."
    
    if ! redis-cli -h ${HOST} -p ${port} ping &>/dev/null; then
        log_error "${cluster_name}集群未运行，请先启动集群"
        return 1
    fi
    
    local cluster_state=$(redis-cli -h ${HOST} -p ${port} cluster info 2>/dev/null | grep cluster_state | cut -d: -f2 | tr -d '\r')
    if [ "$cluster_state" != "ok" ]; then
        log_error "${cluster_name}集群状态异常: $cluster_state"
        return 1
    fi
    
    log_success "${cluster_name}集群状态正常"
    return 0
}

# 执行基准测试（兼容版）
run_benchmark_compatible() {
    local cluster_name=$1
    local port=$2
    local operation=$3
    local concurrency=$4
    local requests=$5
    
    log_info "测试 ${cluster_name} - $operation (并发:$concurrency, 请求:$requests)"
    
    local temp_file="/tmp/redis_benchmark_$$_${operation}_${concurrency}_${requests}.txt"
    
    # 检查是否支持--cluster参数
    if redis-benchmark --help 2>&1 | grep -q "cluster"; then
        # 支持集群模式
        redis-benchmark -h ${HOST} -p ${port} --cluster \
            -t ${operation} -n ${requests} -c ${concurrency} -d ${DATA_SIZE} \
            --quiet > "$temp_file" 2>&1
    else
        # 不支持集群模式，使用普通模式
        redis-benchmark -h ${HOST} -p ${port} \
            -t ${operation} -n ${requests} -c ${concurrency} -d ${DATA_SIZE} \
            --quiet > "$temp_file" 2>&1
    fi
    
    if [ $? -eq 0 ] && [ -s "$temp_file" ]; then
        local qps=$(grep "requests per second" "$temp_file" | tail -1 | awk '{print $(NF-3)}' | tr -d ',')
        echo "$qps"
    else
        log_error "测试失败: $operation (并发:$concurrency, 请求:$requests)"
        if [ -f "$temp_file" ]; then
            cat "$temp_file"
        fi
        echo "0"
    fi
    
    rm -f "$temp_file"
}

# 测试单个集群
test_cluster() {
    local cluster_name=$1
    local port=$2
    
    log_info "开始测试${cluster_name}集群..."
    
    # 检查集群状态
    if ! check_cluster $port "$cluster_name"; then
        return 1
    fi
    
    # 清理数据
    redis-cli -h ${HOST} -p ${port} flushall > /dev/null 2>&1
    
    # 生成测试结果表头
    echo "\n## ${cluster_name}集群测试结果\n" >> "$RESULT_FILE"
    
    for operation in "${TEST_OPERATIONS[@]}"; do
        echo "\n### $operation 操作性能\n" >> "$RESULT_FILE"
        echo "| 并发数 | 请求数 | QPS |" >> "$RESULT_FILE"
        echo "|--------|--------|-----|" >> "$RESULT_FILE"
        
        local max_qps=0
        local best_config=""
        
        for concurrency in "${CONCURRENCY_LEVELS[@]}"; do
            for requests in "${REQUEST_COUNTS[@]}"; do
                local qps=$(run_benchmark_compatible "$cluster_name" "$port" "$operation" "$concurrency" "$requests")
                
                echo "|    $concurrency |  $requests | $qps |" >> "$RESULT_FILE"
                
                # 记录最大QPS
                if (( qps > max_qps )); then
                    max_qps=$qps
                    best_config="并发:$concurrency, 请求:$requests"
                fi
                
                # 测试间隔
                sleep 1
            done
        done
        
        echo "\n**$operation 最大QPS:** $max_qps ($best_config)\n" >> "$RESULT_FILE"
    done
    
    log_success "${cluster_name}集群测试完成"
}

# 生成报告头部
generate_report_header() {
    cat > "$RESULT_FILE" << EOF
# Redis集群简化性能测试报告

**测试目标:** 3节点 vs 6节点集群性能对比（简化版）
**测试时间:** $(date '+%Y-%m-%d %H:%M:%S')
**数据大小:** ${DATA_SIZE} bytes
**测试操作:** ${TEST_OPERATIONS[*]}
**并发级别:** ${CONCURRENCY_LEVELS[*]}
**请求数量:** ${REQUEST_COUNTS[*]}

> 📝 **说明**: 简化版测试，避免大数据量导致的资源问题

---

EOF
}

# 主函数
main() {
    log_info "开始Redis集群简化性能测试..."
    
    # 检查依赖
    if ! command -v redis-benchmark &> /dev/null; then
        log_error "redis-benchmark 命令未找到，请安装Redis工具"
        exit 1
    fi
    
    # 创建结果目录
    mkdir -p "$RESULT_DIR"
    
    # 生成报告头部
    generate_report_header
    
    # 测试3节点集群
    test_cluster "3节点" $CLUSTER_3_PORT
    
    # 等待系统稳定
    sleep 3
    
    # 测试6节点集群
    test_cluster "6节点" $CLUSTER_6_PORT
    
    log_success "简化性能测试完成！结果保存在: $RESULT_FILE"
    log_info "使用以下命令查看结果: cat $RESULT_FILE"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi