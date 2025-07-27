#!/bin/bash

# Redis集群修复版性能测试脚本
# 解决参数兼容性问题

set -e

# 配置参数
RESULT_DIR="/home/k/kenv-lab/cluster-comparison-results"
TEST_TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
RESULT_FILE="${RESULT_DIR}/fixed_cluster_test_${TEST_TIMESTAMP}.md"

# 简化的测试参数
TEST_OPERATIONS=("set" "get" "incr")
CONCURRENCY_LEVELS=(50 100)
REQUEST_COUNTS=(10000 50000)
DATA_SIZE=64

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
    
    log_success "${cluster_name}集群连接正常"
    return 0
}

# 执行基准测试（修复版）
run_benchmark_fixed() {
    local cluster_name=$1
    local port=$2
    local operation=$3
    local concurrency=$4
    local requests=$5
    
    log_info "测试 ${cluster_name} - $operation (并发:$concurrency, 请求:$requests)"
    
    local temp_file="/tmp/redis_benchmark_$$_${operation}_${concurrency}_${requests}.txt"
    
    # 使用兼容的参数格式
    timeout 60 redis-benchmark -h ${HOST} -p ${port} \
        -t ${operation} -n ${requests} -c ${concurrency} -d ${DATA_SIZE} \
        -q > "$temp_file" 2>&1
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ] && [ -s "$temp_file" ]; then
        # 提取QPS数值
        local qps=$(cat "$temp_file" | grep -E "[0-9]+\.[0-9]+" | tail -1 | awk '{print $1}' | cut -d'.' -f1)
        if [ -z "$qps" ] || [ "$qps" = "0" ]; then
            # 尝试其他格式
            qps=$(cat "$temp_file" | grep -oE "[0-9]+" | tail -1)
        fi
        echo "${qps:-0}"
        log_success "$operation 测试完成: ${qps:-0} QPS"
    else
        log_error "测试失败: $operation (并发:$concurrency, 请求:$requests)"
        if [ -f "$temp_file" ]; then
            echo "错误输出:"
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
    
    # 生成测试结果表头
    echo "" >> "$RESULT_FILE"
    echo "## ${cluster_name}集群测试结果" >> "$RESULT_FILE"
    echo "" >> "$RESULT_FILE"
    
    for operation in "${TEST_OPERATIONS[@]}"; do
        echo "### $operation 操作性能" >> "$RESULT_FILE"
        echo "| 并发数 | 请求数 | QPS |" >> "$RESULT_FILE"
        echo "|--------|--------|-----|" >> "$RESULT_FILE"
        
        local max_qps=0
        local best_config=""
        
        for concurrency in "${CONCURRENCY_LEVELS[@]}"; do
            for requests in "${REQUEST_COUNTS[@]}"; do
                local qps=$(run_benchmark_fixed "$cluster_name" "$port" "$operation" "$concurrency" "$requests")
                
                echo "| $concurrency | $requests | $qps |" >> "$RESULT_FILE"
                
                # 记录最大QPS
                if (( qps > max_qps )); then
                    max_qps=$qps
                    best_config="并发:$concurrency, 请求:$requests"
                fi
                
                # 测试间隔
                sleep 2
            done
        done
        
        echo "" >> "$RESULT_FILE"
        echo "**$operation 最大QPS:** $max_qps ($best_config)" >> "$RESULT_FILE"
        echo "" >> "$RESULT_FILE"
    done
    
    log_success "${cluster_name}集群测试完成"
}

# 生成报告头部
generate_report_header() {
    cat > "$RESULT_FILE" << EOF
# Redis集群修复版性能测试报告

**测试目标:** 3节点 vs 6节点集群性能对比（修复版）
**测试时间:** $(date '+%Y-%m-%d %H:%M:%S')
**数据大小:** ${DATA_SIZE} bytes
**测试操作:** ${TEST_OPERATIONS[*]}
**并发级别:** ${CONCURRENCY_LEVELS[*]}
**请求数量:** ${REQUEST_COUNTS[*]}

> 🔧 **修复说明**: 解决了redis-benchmark参数兼容性问题

---
EOF
}

# 主函数
main() {
    log_info "开始Redis集群修复版性能测试..."
    
    # 检查依赖
    if ! command -v redis-benchmark &> /dev/null; then
        log_error "redis-benchmark 命令未找到，请安装Redis工具"
        exit 1
    fi
    
    if ! command -v redis-cli &> /dev/null; then
        log_error "redis-cli 命令未找到，请安装Redis工具"
        exit 1
    fi
    
    # 创建结果目录
    mkdir -p "$RESULT_DIR"
    
    # 生成报告头部
    generate_report_header
    
    # 测试3节点集群
    test_cluster "3节点" $CLUSTER_3_PORT
    
    # 等待系统稳定
    sleep 5
    
    # 测试6节点集群
    test_cluster "6节点" $CLUSTER_6_PORT
    
    # 生成总结
    echo "" >> "$RESULT_FILE"
    echo "## 测试总结" >> "$RESULT_FILE"
    echo "" >> "$RESULT_FILE"
    echo "- ✅ 修复了redis-benchmark参数兼容性问题" >> "$RESULT_FILE"
    echo "- ✅ 使用简化的测试参数避免资源竞争" >> "$RESULT_FILE"
    echo "- ✅ 增加了超时保护和错误处理" >> "$RESULT_FILE"
    echo "" >> "$RESULT_FILE"
    
    log_success "修复版性能测试完成！结果保存在: $RESULT_FILE"
    log_info "使用以下命令查看结果: cat $RESULT_FILE"
}

# 运行主函数
main "$@"