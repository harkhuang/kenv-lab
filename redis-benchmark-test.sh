#!/bin/bash

# Redis性能测试脚本
# 使用redis-benchmark进行全面性能测试

set -e

# 配置参数
REDIS_HOST="127.0.0.1"
REDIS_PORTS=(7001 7002 7003)
TEST_CLIENTS=(1 10 50 100)
TEST_REQUESTS=100000
DATA_SIZE=64
RESULT_DIR="/home/k/kenv-lab/benchmark-results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

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
    mkdir -p "${RESULT_DIR}/${TIMESTAMP}"
    log_info "结果目录: ${RESULT_DIR}/${TIMESTAMP}"
}

# 检查Redis连接
check_redis_connection() {
    log_info "检查Redis集群连接..."
    
    for port in "${REDIS_PORTS[@]}"; do
        if redis-cli -h ${REDIS_HOST} -p ${port} ping &>/dev/null; then
            log_success "节点 ${port} 连接正常"
        else
            log_error "节点 ${port} 连接失败"
            return 1
        fi
    done
    
    # 检查集群状态
    if redis-cli -h ${REDIS_HOST} -p 7001 cluster info | grep -q "cluster_state:ok"; then
        log_success "集群状态正常"
    else
        log_warning "集群状态异常，将使用单节点模式测试"
    fi
}

# 清理测试数据
clean_test_data() {
    log_info "清理测试数据..."
    for port in "${REDIS_PORTS[@]}"; do
        redis-cli -h ${REDIS_HOST} -p ${port} flushall &>/dev/null || true
    done
    log_success "测试数据清理完成"
}

# 单节点性能测试（修复版）
# 在single_node_benchmark函数中添加集群重定向处理
single_node_benchmark() {
    local port=$1
    local clients=$2
    local test_name=$3
    local output_file="${RESULT_DIR}/${TIMESTAMP}/single_${port}_${clients}c_${test_name}.txt"
    
    log_info "测试节点 ${port} - ${clients} 客户端 - ${test_name}"
    
    # 检查是否为集群模式
    local is_cluster=$(redis-cli -h ${REDIS_HOST} -p ${port} cluster info 2>/dev/null | grep -q "cluster_enabled:1" && echo "true" || echo "false")
    
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        local benchmark_cmd="redis-benchmark -h ${REDIS_HOST} -p ${port} -c ${clients} -n ${TEST_REQUESTS}"
        
        # 如果是集群模式，添加--cluster参数
        if [[ "$is_cluster" == "true" ]]; then
            benchmark_cmd="$benchmark_cmd --cluster"
        fi
        
        case $test_name in
            "set")
                if $benchmark_cmd -d ${DATA_SIZE} -t set --csv > "${output_file}" 2>/dev/null; then
                    break
                fi
                ;;
            "get")
                # 先在所有节点预填充数据
                for p in "${REDIS_PORTS[@]}"; do
                    redis-cli -h ${REDIS_HOST} -p ${p} set "benchmark:test:${p}" "value" &>/dev/null || true
                done
                if $benchmark_cmd -d ${DATA_SIZE} -t get --csv > "${output_file}" 2>/dev/null; then
                    break
                fi
                ;;
        esac
        
        retry_count=$((retry_count + 1))
        if [ $retry_count -lt $max_retries ]; then
            log_warning "测试失败，重试 $retry_count/$max_retries..."
            sleep 1
        else
            log_error "测试 ${test_name} 在节点 ${port} 失败"
            echo "ERROR: Test failed after $max_retries retries" > "${output_file}"
        fi
    done
}

# 集群性能测试（修复版）
cluster_benchmark() {
    local clients=$1
    local test_name=$2
    local output_file="${RESULT_DIR}/${TIMESTAMP}/cluster_${clients}c_${test_name}.txt"
    
    log_info "集群测试 - ${clients} 客户端 - ${test_name}"
    
    # 检查是否支持集群模式
    if ! redis-benchmark --help | grep -q "cluster"; then
        log_warning "redis-benchmark 不支持 --cluster 参数，使用轮询模式"
        cluster_benchmark_fallback $clients $test_name
        return
    fi
    
    case $test_name in
        "set")
            redis-benchmark -h ${REDIS_HOST} -p 7001 \
                -c ${clients} -n ${TEST_REQUESTS} -d ${DATA_SIZE} \
                -t set --cluster --csv > "${output_file}" 2>/dev/null || \
            cluster_benchmark_fallback $clients $test_name
            ;;
        "get")
            # 先在集群中写入一些数据
            for port in "${REDIS_PORTS[@]}"; do
                redis-cli -h ${REDIS_HOST} -p ${port} set "cluster:test:${port}" "value" &>/dev/null || true
            done
            
            redis-benchmark -h ${REDIS_HOST} -p 7001 \
                -c ${clients} -n ${TEST_REQUESTS} -d ${DATA_SIZE} \
                -t get --cluster --csv > "${output_file}" 2>/dev/null || \
            cluster_benchmark_fallback $clients $test_name
            ;;
        "mixed")
            redis-benchmark -h ${REDIS_HOST} -p 7001 \
                -c ${clients} -n ${TEST_REQUESTS} -d ${DATA_SIZE} \
                -t set,get,incr --cluster --csv > "${output_file}" 2>/dev/null || \
            cluster_benchmark_fallback $clients $test_name
            ;;
    esac
}

# 集群测试回退方案
cluster_benchmark_fallback() {
    local clients=$1
    local test_name=$2
    local output_file="${RESULT_DIR}/${TIMESTAMP}/cluster_${clients}c_${test_name}.txt"
    
    log_info "使用轮询模式进行集群测试..."
    
    {
        echo "\"Test\",\"QPS\",\"Latency(ms)\",\"Node\""
        
        local total_qps=0
        local total_latency=0
        local node_count=0
        
        for port in "${REDIS_PORTS[@]}"; do
            local temp_file="/tmp/cluster_temp_${port}.csv"
            
            case $test_name in
                "set")
                    redis-benchmark -h ${REDIS_HOST} -p ${port} \
                        -c $((clients / 3)) -n $((TEST_REQUESTS / 3)) -d ${DATA_SIZE} \
                        -t set --csv > "${temp_file}" 2>/dev/null || continue
                    ;;
                "get")
                    redis-cli -h ${REDIS_HOST} -p ${port} set "test:${port}" "value" &>/dev/null
                    redis-benchmark -h ${REDIS_HOST} -p ${port} \
                        -c $((clients / 3)) -n $((TEST_REQUESTS / 3)) -d ${DATA_SIZE} \
                        -t get --csv > "${temp_file}" 2>/dev/null || continue
                    ;;
                "mixed")
                    redis-benchmark -h ${REDIS_HOST} -p ${port} \
                        -c $((clients / 3)) -n $((TEST_REQUESTS / 3)) -d ${DATA_SIZE} \
                        -t set,get,incr --csv > "${temp_file}" 2>/dev/null || continue
                    ;;
            esac
            
            if [[ -f "${temp_file}" && -s "${temp_file}" ]]; then
                local qps=$(tail -1 "${temp_file}" | cut -d',' -f2 | tr -d '"' | grep -o '[0-9.]*' || echo "0")
                local latency=$(tail -1 "${temp_file}" | cut -d',' -f3 | tr -d '"' | grep -o '[0-9.]*' || echo "0")
                
                if [[ -n "$qps" && "$qps" != "0" ]]; then
                    echo "\"${test_name}\",\"${qps}\",\"${latency}\",\"${port}\""
                    # 在cluster_benchmark_fallback函数中计算总QPS
                    total_qps=$(echo "$total_qps + $qps" | bc -l 2>/dev/null || echo "$total_qps")
                    total_latency=$(echo "$total_latency + $latency" | bc -l 2>/dev/null || echo "$total_latency")
                    node_count=$((node_count + 1))
                fi
                
                rm -f "${temp_file}"
            fi
        done
        
        if [[ $node_count -gt 0 ]]; then
            local avg_latency=$(echo "$total_latency / $node_count" | bc -l 2>/dev/null || echo "0")
            echo "\"${test_name}_total\",\"${total_qps}\",\"${avg_latency}\",\"cluster\""
        fi
        
    } > "${output_file}"
}

# 延迟测试
latency_test() {
    local port=$1
    local output_file="${RESULT_DIR}/${TIMESTAMP}/latency_${port}.txt"
    
    log_info "延迟测试 - 节点 ${port}"
    
    {
        echo "=== Redis延迟测试报告 ==="
        echo "节点: ${REDIS_HOST}:${port}"
        echo "时间: $(date)"
        echo
        
        echo "--- 基本延迟测试 ---"
        redis-cli -h ${REDIS_HOST} -p ${port} --latency -i 1 | head -5 2>/dev/null || echo "延迟测试失败"
        
        echo
        echo "--- 内存使用情况 ---"
        redis-cli -h ${REDIS_HOST} -p ${port} info memory | grep -E "used_memory_human|used_memory_peak_human|mem_fragmentation_ratio" || echo "内存信息获取失败"
        
        echo
        echo "--- 连接信息 ---"
        redis-cli -h ${REDIS_HOST} -p ${port} info clients | grep -E "connected_clients|client_recent_max_input_buffer" || echo "连接信息获取失败"
        
    } > "${output_file}"
}

# 内存效率测试
memory_efficiency_test() {
    local port=$1
    local output_file="${RESULT_DIR}/${TIMESTAMP}/memory_${port}.txt"
    
    log_info "内存效率测试 - 节点 ${port}"
    
    {
        echo "=== Redis内存效率测试 ==="
        echo "节点: ${REDIS_HOST}:${port}"
        echo "时间: $(date)"
        echo
        
        echo "--- 基准内存使用 ---"
        redis-cli -h ${REDIS_HOST} -p ${port} info memory | grep used_memory_human || echo "内存信息获取失败"
        
        # 写入不同大小的数据
        for size in 64 256 1024; do
            echo
            echo "--- 写入 1000 个 ${size} 字节的键值对 ---"
            
            # 使用更小的数据量避免集群重定向问题
            for i in $(seq 1 1000); do
                redis-cli -h ${REDIS_HOST} -p ${port} set "mem:${size}:${i}" "$(head -c ${size} /dev/zero | tr '\0' 'x')" &>/dev/null || true
            done
            
            redis-cli -h ${REDIS_HOST} -p ${port} info memory | grep -E "used_memory_human|mem_fragmentation_ratio" || echo "内存信息获取失败"
        done
        
    } > "${output_file}"
}

# 生成性能报告
generate_report() {
    local report_file="${RESULT_DIR}/${TIMESTAMP}/performance_report.md"
    
    log_info "生成性能测试报告..."
    
    {
        echo "# Redis集群性能测试报告"
        echo
        echo "**测试时间:** $(date)"
        echo "**集群节点:** ${REDIS_PORTS[*]}"
        echo "**测试请求数:** ${TEST_REQUESTS}"
        echo "**数据大小:** ${DATA_SIZE} bytes"
        echo
        
        echo "## 测试环境"
        echo "- CPU: $(nproc) 核心"
        echo "- 内存: $(free -h | awk '/^Mem:/ {print $2}')"
        echo "- Redis版本: $(redis-server --version | cut -d' ' -f3)"
        echo
        
        echo "## 单节点性能测试结果"
        echo
        echo "| 节点 | 客户端数 | 操作类型 | QPS | 平均延迟(ms) |"
        echo "|------|----------|----------|-----|-------------|"
        
        # 解析CSV结果
        for port in "${REDIS_PORTS[@]}"; do
            for clients in "${TEST_CLIENTS[@]}"; do
                for test in set get incr; do
                    local csv_file="${RESULT_DIR}/${TIMESTAMP}/single_${port}_${clients}c_${test}.txt"
                    if [[ -f "$csv_file" && -s "$csv_file" ]]; then
                        local last_line=$(tail -1 "$csv_file")
                        if [[ "$last_line" != *"ERROR"* ]]; then
                            local qps=$(echo "$last_line" | cut -d',' -f2 | tr -d '"' | grep -o '[0-9.]*' || echo "N/A")
                            local latency=$(echo "$last_line" | cut -d',' -f3 | tr -d '"' | grep -o '[0-9.]*' || echo "N/A")
                            echo "| ${port} | ${clients} | ${test} | ${qps} | ${latency} |"
                        else
                            echo "| ${port} | ${clients} | ${test} | ERROR | ERROR |"
                        fi
                    fi
                done
            done
        done
        
        echo
        echo "## 集群性能测试结果"
        echo
        echo "| 客户端数 | 操作类型 | 总QPS | 平均延迟(ms) | 备注 |"
        echo "|----------|----------|-------|-------------|------|"
        
        for clients in "${TEST_CLIENTS[@]}"; do
            for test in set get mixed; do
                local csv_file="${RESULT_DIR}/${TIMESTAMP}/cluster_${clients}c_${test}.txt"
                if [[ -f "$csv_file" && -s "$csv_file" ]]; then
                    local total_line=$(grep "_total" "$csv_file" 2>/dev/null || tail -1 "$csv_file")
                    if [[ -n "$total_line" && "$total_line" != *"ERROR"* ]]; then
                        local qps=$(echo "$total_line" | cut -d',' -f2 | tr -d '"' | grep -o '[0-9.]*' || echo "N/A")
                        local latency=$(echo "$total_line" | cut -d',' -f3 | tr -d '"' | grep -o '[0-9.]*' || echo "N/A")
                        echo "| ${clients} | ${test} | ${qps} | ${latency} | 集群模式 |"
                    else
                        echo "| ${clients} | ${test} | ERROR | ERROR | 测试失败 |"
                    fi
                fi
            done
        done
        
        echo
        echo "## 性能优化建议"
        echo
        echo "### C++客户端优化建议"
        echo "1. **连接池管理**: 使用连接池避免频繁建立连接"
        echo "2. **集群感知**: 使用支持集群的客户端库(如redis-plus-plus)"
        echo "3. **异步操作**: 使用异步I/O提升并发性能"
        echo "4. **批量操作**: 使用pipeline和批量命令"
        echo "5. **错误处理**: 正确处理MOVED/ASK重定向"
        echo
        
        echo "### 集群优化建议"
        echo "1. **分片策略**: 优化key分布避免热点"
        echo "2. **网络优化**: 确保节点间低延迟"
        echo "3. **监控告警**: 监控集群状态和性能指标"
        echo "4. **故障恢复**: 建立完善的故障恢复机制"
        echo
        
    } > "$report_file"
    
    log_success "性能报告生成完成: $report_file"
}

# 快速性能测试
quick_test() {
    log_info "执行快速性能测试..."
    
    create_result_dir
    check_redis_connection
    clean_test_data
    
    # 只测试主要操作和较少的客户端数
    for port in "${REDIS_PORTS[@]}"; do
        for clients in 1 50; do
            single_node_benchmark $port $clients "set"
            single_node_benchmark $port $clients "get"
        done
        latency_test $port
    done
    
    # 集群测试
    cluster_benchmark 50 "set"
    cluster_benchmark 50 "get"
    
    generate_report
    log_success "快速测试完成"
}

# 完整性能测试
full_test() {
    log_info "执行完整性能测试..."
    
    create_result_dir
    check_redis_connection
    clean_test_data
    
    # 单节点测试
    for port in "${REDIS_PORTS[@]}"; do
        for clients in "${TEST_CLIENTS[@]}"; do
            for test in set get incr lpush lpop sadd hset zadd pipeline; do
                single_node_benchmark $port $clients $test
            done
        done
        latency_test $port
        memory_efficiency_test $port
    done
    
    # 集群测试
    for clients in "${TEST_CLIENTS[@]}"; do
        cluster_benchmark $clients "set"
        cluster_benchmark $clients "get"
        cluster_benchmark $clients "mixed"
    done
    
    generate_report
    log_success "完整测试完成"
}

# 自定义测试
custom_test() {
    local port=${1:-7001}
    local clients=${2:-50}
    local requests=${3:-10000}
    local operation=${4:-"set"}
    
    log_info "自定义测试: 节点${port}, ${clients}客户端, ${requests}请求, ${operation}操作"
    
    create_result_dir
    
    redis-benchmark -h ${REDIS_HOST} -p ${port} \
        -c ${clients} -n ${requests} -d ${DATA_SIZE} \
        -t ${operation} --csv 2>/dev/null || \
    log_error "自定义测试失败"
}

# 压力测试
stress_test() {
    log_info "执行压力测试..."
    
    create_result_dir
    check_redis_connection
    
    local stress_clients=200
    local stress_requests=1000000
    
    log_warning "压力测试将使用 ${stress_clients} 个客户端执行 ${stress_requests} 个请求"
    
    for port in "${REDIS_PORTS[@]}"; do
        log_info "压力测试节点 ${port}..."
        
        redis-benchmark -h ${REDIS_HOST} -p ${port} \
            -c ${stress_clients} -n ${stress_requests} -d ${DATA_SIZE} \
            -t set,get --csv > "${RESULT_DIR}/${TIMESTAMP}/stress_${port}.txt" 2>/dev/null || \
        log_error "节点 ${port} 压力测试失败"
    done
    
    log_success "压力测试完成"
}

# 主函数
main() {
    case "$1" in
        "quick")
            quick_test
            ;;
        "full")
            full_test
            ;;
        "stress")
            stress_test
            ;;
        "custom")
            custom_test "$2" "$3" "$4" "$5"
            ;;
        "clean")
            clean_test_data
            ;;
        *)
            echo "用法: $0 {quick|full|stress|custom|clean}"
            echo
            echo "命令说明:"
            echo "  quick   - 快速性能测试 (推荐)"
            echo "  full    - 完整性能测试 (耗时较长)"
            echo "  stress  - 压力测试"
            echo "  custom  - 自定义测试 [port] [clients] [requests] [operation]"
            echo "  clean   - 清理测试数据"
            echo
            echo "示例:"
            echo "  $0 quick                    # 快速测试"
            echo "  $0 custom 7001 100 50000 set # 自定义测试"
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
