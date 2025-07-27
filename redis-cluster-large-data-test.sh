#!/bin/bash

# Redis集群大数据量性能测试脚本
# 专门测试大数据集下的分片效果

set -e

# 配置参数
RESULT_DIR="/home/k/kenv-lab/cluster-comparison-results"
TEST_TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
RESULT_FILE="${RESULT_DIR}/large_data_test_${TEST_TIMESTAMP}.md"

# 大数据测试参数
LARGE_DATA_SIZES=(1024 4096 16384)  # 1KB, 4KB, 16KB
KEY_SPACE_SIZES=(100000 500000 1000000)  # 10万, 50万, 100万键
TEST_OPERATIONS=("set" "get" "incr")
CONCURRENCY=200
REQUESTS=100000

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

# 预填充大量数据
prefill_large_dataset() {
    local port=$1
    local cluster_name=$2
    local keyspace_size=$3
    local data_size=$4
    
    log_info "为${cluster_name}集群预填充数据 (键空间:${keyspace_size}, 数据大小:${data_size}字节)"
    
    # 分批填充，避免内存溢出
    local batch_size=10000
    local batches=$((keyspace_size / batch_size))
    
    for ((i=0; i<batches; i++)); do
        local start_key=$((i * batch_size))
        redis-benchmark -h ${HOST} -p ${port} --cluster \
            -t set -n ${batch_size} -c 50 -d ${data_size} \
            -r ${keyspace_size} --quiet > /dev/null 2>&1
        
        if (( i % 10 == 0 )); then
            log_info "已填充 $((i * batch_size)) / ${keyspace_size} 条数据"
        fi
    done
    
    log_success "${cluster_name}集群数据预填充完成"
}

# 测试大数据场景
test_large_data_scenario() {
    local cluster_name=$1
    local port=$2
    local keyspace_size=$3
    local data_size=$4
    
    echo "\n### ${cluster_name}集群 - 键空间:${keyspace_size}, 数据大小:${data_size}字节\n" >> "$RESULT_FILE"
    echo "| 操作 | QPS | 平均延迟(ms) | 内存使用(MB) |" >> "$RESULT_FILE"
    echo "|------|-----|-------------|-------------|" >> "$RESULT_FILE"
    
    # 预填充数据
    prefill_large_dataset "$port" "$cluster_name" "$keyspace_size" "$data_size"
    
    for operation in "${TEST_OPERATIONS[@]}"; do
        # 获取测试前内存使用
        local mem_before=$(redis-cli -h ${HOST} -p ${port} info memory | grep used_memory_human | cut -d: -f2 | tr -d '\r')
        
        # 执行测试
        local temp_file="/tmp/large_data_test_$$_${operation}.txt"
        redis-benchmark -h ${HOST} -p ${port} --cluster \
            -t ${operation} -n ${REQUESTS} -c ${CONCURRENCY} -d ${data_size} \
            -r ${keyspace_size} > "$temp_file" 2>&1
        
        # 解析结果
        local qps=$(grep "requests per second" "$temp_file" | tail -1 | awk '{print $(NF-3)}' | tr -d ',')
        local avg_latency=$(grep "latency" "$temp_file" | grep "average" | awk '{print $NF}' | tr -d 'ms')
        
        # 获取测试后内存使用
        local mem_after=$(redis-cli -h ${HOST} -p ${port} info memory | grep used_memory_human | cut -d: -f2 | tr -d '\r')
        
        echo "| $operation | $qps | $avg_latency | $mem_after |" >> "$RESULT_FILE"
        
        rm -f "$temp_file"
        sleep 2
    done
    
    echo "" >> "$RESULT_FILE"
}

# 主函数
main() {
    log_info "开始Redis集群大数据量性能测试..."
    
    # 创建结果目录
    mkdir -p "$RESULT_DIR"
    
    # 生成报告头部
    cat > "$RESULT_FILE" << EOF
# Redis集群大数据量性能测试报告

**测试目标:** 大数据集下的集群分片效果对比
**测试时间:** $(date '+%Y-%m-%d %H:%M:%S')
**数据大小:** ${LARGE_DATA_SIZES[*]} bytes
**键空间大小:** ${KEY_SPACE_SIZES[*]}
**并发数:** ${CONCURRENCY}
**请求数:** ${REQUESTS}

> 🎯 **测试重点**: 验证6节点集群在大数据集下的分片优势

---

EOF
    
    # 测试不同数据大小和键空间组合
    for data_size in "${LARGE_DATA_SIZES[@]}"; do
        for keyspace_size in "${KEY_SPACE_SIZES[@]}"; do
            echo "\n## 数据大小: ${data_size}字节, 键空间: ${keyspace_size}\n" >> "$RESULT_FILE"
            
            # 测试3节点集群
            test_large_data_scenario "3节点" $CLUSTER_3_PORT "$keyspace_size" "$data_size"
            
            # 清理数据
            redis-cli -h ${HOST} -p $CLUSTER_3_PORT flushall > /dev/null 2>&1
            sleep 5
            
            # 测试6节点集群
            test_large_data_scenario "6节点" $CLUSTER_6_PORT "$keyspace_size" "$data_size"
            
            # 清理数据
            redis-cli -h ${HOST} -p $CLUSTER_6_PORT flushall > /dev/null 2>&1
            sleep 5
        done
    done
    
    log_success "大数据量性能测试完成！结果保存在: $RESULT_FILE"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi