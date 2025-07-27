#!/bin/bash

# Redis集群吞吐瓶颈测试脚本
# 基于redis-benchmark命令进行性能测试

# 配置参数
REDIS_HOST="127.0.0.1"
REDIS_PORT="7001"
TEST_OPERATIONS=("set" "get" "incr" "lpush" "rpush" "lpop" "rpop" "sadd" "hset" "spop" "zadd" "zpopmin" "lrange" "mset")
TEST_OPERATIONS=("set")
# TEST_OPERATIONS=("set" "get" )
CONCURRENCY_LEVELS=(10 25 50 100 200 300 500 1000)
REQUEST_COUNTS=(1000 5000 10000 50000 100000)
DATA_SIZE=2000
RESULT_DIR="./throughput-test-results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
RESULT_FILE="${RESULT_DIR}/throughput_bottleneck_${TIMESTAMP}.md"

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

# 创建结果目录
create_result_dir() {
    if [ ! -d "$RESULT_DIR" ]; then
        mkdir -p "$RESULT_DIR"
        log_info "创建结果目录: $RESULT_DIR"
    fi
}

# 检查Redis集群连接
check_redis_cluster() {
    log_info "检查Redis集群连接..."
    if ! redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} ping &>/dev/null; then
        log_error "无法连接到Redis集群 ${REDIS_HOST}:${REDIS_PORT}"
        exit 1
    fi
    
    # 检查集群状态
    cluster_state=$(redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} cluster info | grep cluster_state | cut -d: -f2 | tr -d '\r')
    if [ "$cluster_state" != "ok" ]; then
        log_error "Redis集群状态异常: $cluster_state"
        exit 1
    fi
    
    log_success "Redis集群连接正常"
}

# 执行单个基准测试（改进版）
run_benchmark() {
    local operation=$1
    local concurrency=$2
    local requests=$3
    
    log_info "测试 $operation - 并发:$concurrency, 请求:$requests"
    
    # 创建临时文件存储详细输出
    local temp_file="/tmp/redis_benchmark_$$_${operation}_${concurrency}_${requests}.txt"
    
    # 执行redis-benchmark并保存完整输出
    redis-benchmark -h ${REDIS_HOST} -p ${REDIS_PORT} --cluster \
        -t ${operation} -n ${requests} -c ${concurrency} -d ${DATA_SIZE} \
        > "$temp_file" 2>&1
    
    if [ ! -s "$temp_file" ]; then
        log_warning "测试失败: $operation (并发:$concurrency, 请求:$requests)"
        rm -f "$temp_file"
        echo "0,0,0,0,0,0,0,0"
        return
    fi
    
    # 解析结果
    local qps=$(grep "requests per second" "$temp_file" | tail -1 | awk '{print $(NF-3)}' | tr -d ',')
    local avg_latency=$(grep "latency" "$temp_file" | grep "average" | awk '{print $NF}' | tr -d 'ms')
    local min_latency=$(grep "latency" "$temp_file" | grep "min" | awk '{print $NF}' | tr -d 'ms')
    local max_latency=$(grep "latency" "$temp_file" | grep "max" | awk '{print $NF}' | tr -d 'ms')
    
    # 解析百分位延迟
    local p50_latency=$(grep "50.00%" "$temp_file" | awk '{print $NF}' | tr -d 'ms')
    local p95_latency=$(grep "95.00%" "$temp_file" | awk '{print $NF}' | tr -d 'ms')
    local p99_latency=$(grep "99.00%" "$temp_file" | awk '{print $NF}' | tr -d 'ms')
    
    # 设置默认值
    qps=${qps:-0}
    avg_latency=${avg_latency:-0}
    min_latency=${min_latency:-0}
    max_latency=${max_latency:-0}
    p50_latency=${p50_latency:-0}
    p95_latency=${p95_latency:-0}
    p99_latency=${p99_latency:-0}
    
    # 清理临时文件
    rm -f "$temp_file"
    
    echo "$operation,$qps,$avg_latency,$min_latency,$p50_latency,$p95_latency,$p99_latency,$max_latency"
}

# 安全的数字格式化函数
safe_format_number() {
    local value="$1"
    local default="${2:-0.00}"
    
    # 移除非数字字符（保留小数点和负号）
    value=$(echo "$value" | sed 's/[^0-9.-]//g')
    
    # 检查是否为有效数字
    if [[ "$value" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then
        printf "%.2f" "$value" 2>/dev/null || echo "$default"
    else
        echo "$default"
    fi
}

# 安全的数字比较函数
safe_compare() {
    local num1="$1"
    local num2="$2"
    
    # 确保输入是有效数字
    num1=$(safe_format_number "$num1" "0")
    num2=$(safe_format_number "$num2" "0")
    
    # 使用awk进行浮点数比较（避免bc依赖）
    awk "BEGIN {exit !($num1 > $num2)}"
}

# 修复后的分析瓶颈函数
analyze_bottleneck() {
    local operation=$1
    local max_qps=0
    local bottleneck_concurrency=0
    local bottleneck_requests=0
    
    echo "\n### $operation 操作瓶颈分析\n" >> "$RESULT_FILE"
    echo "| 并发数 | 请求数 | QPS | 平均延迟(ms) | 最小延迟(ms) | P50延迟(ms) | P95延迟(ms) | P99延迟(ms) | 最大延迟(ms) |" >> "$RESULT_FILE"
    echo "|--------|--------|-----|-------------|-------------|-------------|-------------|-------------|-------------|" >> "$RESULT_FILE"
    
    for concurrency in "${CONCURRENCY_LEVELS[@]}"; do
        for requests in "${REQUEST_COUNTS[@]}"; do
            local result=$(run_benchmark "$operation" "$concurrency" "$requests")
            
            # 解析CSV结果（安全版）
            IFS=',' read -ra METRICS <<< "$result"
            local op_name=${METRICS[0]:-$operation}
            local qps=${METRICS[1]:-0}
            local avg_latency=${METRICS[2]:-0}
            local min_latency=${METRICS[3]:-0}
            local p50_latency=${METRICS[4]:-0}
            local p95_latency=${METRICS[5]:-0}
            local p99_latency=${METRICS[6]:-0}
            local max_latency=${METRICS[7]:-0}
            
            # 安全格式化数值
            qps=$(safe_format_number "$qps" "0.00")
            avg_latency=$(safe_format_number "$avg_latency" "0.00")
            min_latency=$(safe_format_number "$min_latency" "0.00")
            p50_latency=$(safe_format_number "$p50_latency" "0.00")
            p95_latency=$(safe_format_number "$p95_latency" "0.00")
            p99_latency=$(safe_format_number "$p99_latency" "0.00")
            max_latency=$(safe_format_number "$max_latency" "0.00")
            
            # 记录结果
            printf "| %6d | %6d | %8s | %11s | %11s | %11s | %11s | %11s | %11s |\n" \
                "$concurrency" "$requests" "$qps" "$avg_latency" "$min_latency" \
                "$p50_latency" "$p95_latency" "$p99_latency" "$max_latency" >> "$RESULT_FILE"
            
            # 安全的QPS比较
            if safe_compare "$qps" "$max_qps"; then
                max_qps=$qps
                bottleneck_concurrency=$concurrency
                bottleneck_requests=$requests
            fi
            
            # 实时显示进度
            printf "\r测试进度: %s - 并发:%d, 请求:%d, QPS:%s, 延迟:%sms" \
                "$operation" "$concurrency" "$requests" "$qps" "$avg_latency"
        done
    done
    
    echo "\n\n**$operation 最佳性能点:**" >> "$RESULT_FILE"
    echo "- 最大QPS: $max_qps" >> "$RESULT_FILE"
    echo "- 最佳并发数: $bottleneck_concurrency" >> "$RESULT_FILE"
    echo "- 最佳请求数: $bottleneck_requests" >> "$RESULT_FILE"
    echo "" >> "$RESULT_FILE"
    
    log_success "$operation 测试完成 - 最大QPS: $max_qps (并发:$bottleneck_concurrency)"
}

# 生成测试报告头部
generate_report_header() {
    cat > "$RESULT_FILE" << EOF
# Redis集群吞吐瓶颈测试报告

**测试时间:** $(date '+%Y-%m-%d %H:%M:%S')
**Redis主机:** ${REDIS_HOST}:${REDIS_PORT}
**数据大小:** ${DATA_SIZE} bytes
**测试操作:** ${TEST_OPERATIONS[*]}
**并发级别:** ${CONCURRENCY_LEVELS[*]}
**请求数量:** ${REQUEST_COUNTS[*]}

---

## 测试结果详情

EOF
}

# 生成性能总结
generate_performance_summary() {
    echo "\n---\n" >> "$RESULT_FILE"
    echo "## 性能总结与建议\n" >> "$RESULT_FILE"
    
    echo "### 关键发现\n" >> "$RESULT_FILE"
    echo "1. **吞吐瓶颈识别**: 通过测试不同并发数和请求数的组合，识别出各操作的性能瓶颈点" >> "$RESULT_FILE"
    echo "2. **最佳配置**: 每个操作都有其最佳的并发数配置，超过此值性能可能下降" >> "$RESULT_FILE"
    echo "3. **延迟分析**: P95和P99延迟指标帮助识别系统在高负载下的稳定性" >> "$RESULT_FILE"
    
    echo "\n### 优化建议\n" >> "$RESULT_FILE"
    echo "1. **连接池优化**: 根据测试结果调整客户端连接池大小" >> "$RESULT_FILE"
    echo "2. **批量操作**: 对于高频操作，考虑使用pipeline或批量命令" >> "$RESULT_FILE"
    echo "3. **监控告警**: 基于测试结果设置QPS和延迟的监控阈值" >> "$RESULT_FILE"
    echo "4. **容量规划**: 使用瓶颈数据进行系统容量规划" >> "$RESULT_FILE"
    
    echo "\n### 测试环境信息\n" >> "$RESULT_FILE"
    echo "- **系统信息**: $(uname -a)" >> "$RESULT_FILE"
    echo "- **CPU核数**: $(nproc)" >> "$RESULT_FILE"
    echo "- **内存信息**: $(free -h | grep Mem | awk '{print $2}')" >> "$RESULT_FILE"
    echo "- **Redis版本**: $(redis-cli -h ${REDIS_HOST} -p ${REDIS_PORT} info server | grep redis_version | cut -d: -f2 | tr -d '\r')" >> "$RESULT_FILE"
}

# 主测试函数
main() {
    log_info "开始Redis集群吞吐瓶颈测试..."
    
    # 检查依赖
    if ! command -v redis-benchmark &> /dev/null; then
        log_error "redis-benchmark 命令未找到，请安装Redis工具"
        exit 1
    fi
    
    if ! command -v bc &> /dev/null; then
        log_error "bc 命令未找到，请安装bc工具: sudo apt-get install bc"
        exit 1
    fi
    
    # 初始化
    create_result_dir
    check_redis_cluster
    generate_report_header
    
    # 执行测试
    local total_operations=${#TEST_OPERATIONS[@]}
    local current_operation=0
    
    for operation in "${TEST_OPERATIONS[@]}"; do
        current_operation=$((current_operation + 1))
        log_info "[$current_operation/$total_operations] 开始测试 $operation 操作"
        analyze_bottleneck "$operation"
        echo "" # 换行
    done
    
    # 生成总结
    generate_performance_summary
    
    log_success "测试完成！结果保存在: $RESULT_FILE"
    log_info "使用以下命令查看结果: cat $RESULT_FILE"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi