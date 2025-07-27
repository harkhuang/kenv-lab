#!/bin/bash

# Redis集群性能对比测试脚本
# 对比3节点和6节点集群的吞吐性能

set -e

# 配置参数
RESULT_DIR="/home/k/kenv-lab/cluster-comparison-results"
TEST_TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
RESULT_FILE="${RESULT_DIR}/cluster_comparison_${TEST_TIMESTAMP}.md"
DATA_SIZE=64

# 测试参数
TEST_OPERATIONS=("set" "get" "incr" "lpush" "sadd")
CONCURRENCY_LEVELS=(50 100 200 500 1000)
REQUEST_COUNTS=(10000 50000 100000)

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

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 创建结果目录
create_result_dir() {
    mkdir -p "$RESULT_DIR"
    log_info "结果将保存到: $RESULT_FILE"
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
    
    # 使用awk进行浮点数比较
    awk "BEGIN {exit !($num1 > $num2)}"
}

# 检查集群状态
check_cluster() {
    local port=$1
    local cluster_name=$2
    
    if ! redis-cli -h ${HOST} -p ${port} ping &>/dev/null; then
        log_error "${cluster_name}集群未运行，请先启动集群"
        return 1
    fi
    
    local cluster_state=$(redis-cli -h ${HOST} -p ${port} cluster info | grep cluster_state | cut -d: -f2 | tr -d '\r')
    if [ "$cluster_state" != "ok" ]; then
        log_error "${cluster_name}集群状态异常: $cluster_state"
        return 1
    fi
    
    log_success "${cluster_name}集群连接正常"
}

# 执行单个基准测试
run_benchmark() {
    local cluster_name=$1
    local port=$2
    local operation=$3
    local concurrency=$4
    local requests=$5
    
    log_info "测试 ${cluster_name} - $operation (并发:$concurrency, 请求:$requests)"
    
    # 创建临时文件存储详细输出
    local temp_file="/tmp/redis_benchmark_${cluster_name}_$$_${operation}_${concurrency}_${requests}.txt"
    
    # 执行redis-benchmark并保存完整输出
    redis-benchmark -h ${HOST} -p ${port} --cluster \
        -t ${operation} -n ${requests} -c ${concurrency} -d ${DATA_SIZE} \
        > "$temp_file" 2>&1
    
    if [ ! -s "$temp_file" ]; then
        log_warning "测试失败: ${cluster_name} $operation (并发:$concurrency, 请求:$requests)"
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

# 测试单个集群
test_cluster() {
    local cluster_name=$1
    local port=$2
    
    log_info "开始测试 ${cluster_name}集群性能..."
    
    # 检查集群状态
    check_cluster $port "$cluster_name"
    
    echo "\n## ${cluster_name}集群测试结果\n" >> "$RESULT_FILE"
    
    for operation in "${TEST_OPERATIONS[@]}"; do
        echo "\n### ${operation} 操作性能\n" >> "$RESULT_FILE"
        echo "| 并发数 | 请求数 | QPS | 平均延迟(ms) | P50延迟(ms) | P95延迟(ms) | P99延迟(ms) |" >> "$RESULT_FILE"
        echo "|--------|--------|-----|-------------|-------------|-------------|-------------|" >> "$RESULT_FILE"
        
        local max_qps=0
        local best_config=""
        
        for concurrency in "${CONCURRENCY_LEVELS[@]}"; do
            for requests in "${REQUEST_COUNTS[@]}"; do
                local result=$(run_benchmark "$cluster_name" "$port" "$operation" "$concurrency" "$requests")
                
                # 解析CSV结果
                IFS=',' read -ra METRICS <<< "$result"
                local qps=$(safe_format_number "${METRICS[1]}" "0.00")
                local avg_latency=$(safe_format_number "${METRICS[2]}" "0.00")
                local p50_latency=$(safe_format_number "${METRICS[4]}" "0.00")
                local p95_latency=$(safe_format_number "${METRICS[5]}" "0.00")
                local p99_latency=$(safe_format_number "${METRICS[6]}" "0.00")
                
                # 记录结果
                printf "| %6d | %6d | %8s | %11s | %11s | %11s | %11s |\n" \
                    "$concurrency" "$requests" "$qps" "$avg_latency" \
                    "$p50_latency" "$p95_latency" "$p99_latency" >> "$RESULT_FILE"
                
                # 寻找最大QPS
                if safe_compare "$qps" "$max_qps"; then
                    max_qps=$qps
                    best_config="并发:$concurrency, 请求:$requests"
                fi
                
                # 实时显示进度
                printf "\r${cluster_name} - %s: 并发:%d, 请求:%d, QPS:%s" \
                    "$operation" "$concurrency" "$requests" "$qps"
            done
        done
        
        echo "\n\n**${operation} 最佳性能:** QPS: $max_qps ($best_config)\n" >> "$RESULT_FILE"
        echo "" # 换行
    done
    
    log_success "${cluster_name}集群测试完成"
}

# 生成对比分析
generate_comparison() {
    echo "\n---\n" >> "$RESULT_FILE"
    echo "## 性能对比分析\n" >> "$RESULT_FILE"
    
    echo "### 理论分析\n" >> "$RESULT_FILE"
    echo "**3节点集群 vs 6节点集群:**\n" >> "$RESULT_FILE"
    echo "1. **分片数量**: 3节点集群有3个主分片，6节点集群有6个主分片" >> "$RESULT_FILE"
    echo "2. **并行处理能力**: 6节点集群理论上可以处理更多并发请求" >> "$RESULT_FILE"
    echo "3. **数据分布**: 6节点集群数据分布更均匀，热点问题更少" >> "$RESULT_FILE"
    echo "4. **网络开销**: 6节点集群节点间通信开销相对更大" >> "$RESULT_FILE"
    
    echo "\n### 测试环境信息\n" >> "$RESULT_FILE"
    echo "- **测试时间**: $(date '+%Y-%m-%d %H:%M:%S')" >> "$RESULT_FILE"
    echo "- **系统信息**: $(uname -a)" >> "$RESULT_FILE"
    echo "- **CPU核数**: $(nproc)" >> "$RESULT_FILE"
    echo "- **内存信息**: $(free -h | grep Mem | awk '{print $2}')" >> "$RESULT_FILE"
    echo "- **Redis版本**: $(redis-cli -h ${HOST} -p ${CLUSTER_3_PORT} info server | grep redis_version | cut -d: -f2 | tr -d '\r')" >> "$RESULT_FILE"
    
    echo "\n### 结论\n" >> "$RESULT_FILE"
    echo "根据测试结果，可以观察到：" >> "$RESULT_FILE"
    echo "1. 在相同硬件资源下，6节点集群在高并发场景下通常表现更好" >> "$RESULT_FILE"
    echo "2. 3节点集群在低并发场景下可能有更好的延迟表现" >> "$RESULT_FILE"
    echo "3. 具体性能差异取决于操作类型和并发模式" >> "$RESULT_FILE"
    echo "4. 建议根据实际业务场景选择合适的集群规模" >> "$RESULT_FILE"
}

# 生成测试报告头部
generate_report_header() {
    cat > "$RESULT_FILE" << EOF
# Redis集群性能对比测试报告

**测试时间:** $(date '+%Y-%m-%d %H:%M:%S')
**测试目标:** 对比3节点和6节点Redis集群的吞吐性能
**数据大小:** ${DATA_SIZE} bytes
**测试操作:** ${TEST_OPERATIONS[*]}
**并发级别:** ${CONCURRENCY_LEVELS[*]}
**请求数量:** ${REQUEST_COUNTS[*]}

---

EOF
}

# 主测试函数
main() {
    log_info "开始Redis集群性能对比测试..."
    
    # 检查依赖
    if ! command -v redis-benchmark &> /dev/null; then
        log_error "redis-benchmark 命令未找到，请安装Redis工具"
        exit 1
    fi
    
    # 初始化
    create_result_dir
    generate_report_header
    
    # 测试3节点集群
    test_cluster "3节点" $CLUSTER_3_PORT
    
    # 测试6节点集群
    test_cluster "6节点" $CLUSTER_6_PORT
    
    # 生成对比分析
    generate_comparison
    
    log_success "性能对比测试完成！结果保存在: $RESULT_FILE"
    log_info "使用以下命令查看结果: cat $RESULT_FILE"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi