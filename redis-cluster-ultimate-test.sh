#!/bin/bash

# Redis集群终极性能测试脚本 - 高效版本
# 解决所有已知问题，专为单机环境优化

set -euo pipefail

# 配置参数
readonly RESULT_DIR="/home/k/kenv-lab/cluster-comparison-results"
readonly TEST_TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
readonly RESULT_FILE="${RESULT_DIR}/ultimate_cluster_test_${TEST_TIMESTAMP}.md"

# 优化的测试参数
readonly -a TEST_OPERATIONS=("set" "get" "incr")
readonly -a CONCURRENCY_LEVELS=(25 50)
readonly -a REQUEST_COUNTS=(5000 10000)
readonly DATA_SIZE=64
readonly TIMEOUT=30

# 集群配置
readonly CLUSTER_3_PORT=7001
readonly CLUSTER_6_PORT=7011
readonly HOST="127.0.0.1"

# 性能优化：预编译正则表达式
readonly QPS_REGEX='([0-9]+\.[0-9]+)'

# 日志函数 - 优化输出
log_info() { echo -e "\033[0;34m[INFO]\033[0m $*"; }
log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $*"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }
log_warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }

# 高效的集群状态检查
check_cluster_fast() {
    local -r port=$1
    local -r cluster_name=$2
    
    log_info "检查${cluster_name}集群状态..."
    
    # 快速连接测试
    if ! timeout 5 redis-cli -h "${HOST}" -p "${port}" ping >/dev/null 2>&1; then
        log_error "${cluster_name}集群连接失败"
        return 1
    fi
    
    # 检查集群状态（如果支持）
    local cluster_info
    if cluster_info=$(timeout 5 redis-cli -h "${HOST}" -p "${port}" cluster info 2>/dev/null); then
        if [[ $cluster_info == *"cluster_state:ok"* ]]; then
            log_success "${cluster_name}集群状态正常"
        else
            log_warn "${cluster_name}集群状态异常，但继续测试"
        fi
    else
        log_warn "${cluster_name}可能不是集群模式，使用单机模式测试"
    fi
    
    return 0
}

# 高性能基准测试函数
run_benchmark_optimized() {
    local -r cluster_name=$1
    local -r port=$2
    local -r operation=$3
    local -r concurrency=$4
    local -r requests=$5
    
    log_info "测试 ${cluster_name} - ${operation} (并发:${concurrency}, 请求:${requests})"
    
    local -r temp_file="/tmp/redis_bench_${BASHPID}_${operation}_${concurrency}_${requests}.out"
    local qps=0
    
    # 使用多种策略尝试测试
    local strategies=(
        "redis-benchmark -h ${HOST} -p ${port} -t ${operation} -n ${requests} -c ${concurrency} -d ${DATA_SIZE} -q --csv"
        "redis-benchmark -h ${HOST} -p ${port} -t ${operation} -n ${requests} -c ${concurrency} -d ${DATA_SIZE} -q"
        "redis-benchmark -h ${HOST} -p ${port} -t ${operation} -n ${requests} -c ${concurrency} -d ${DATA_SIZE}"
    )
    
    for strategy in "${strategies[@]}"; do
        log_info "尝试策略: ${strategy##* }"
        
        if timeout "${TIMEOUT}" bash -c "${strategy}" > "${temp_file}" 2>&1; then
            # 多种QPS提取方法
            if [[ -s "${temp_file}" ]]; then
                # 方法1: CSV格式
                qps=$(awk -F',' 'NR==2 {gsub(/"/, "", $2); print int($2)}' "${temp_file}" 2>/dev/null || echo "0")
                
                # 方法2: 标准格式
                if [[ $qps -eq 0 ]]; then
                    qps=$(grep -oE '[0-9]+\.[0-9]+' "${temp_file}" | tail -1 | cut -d'.' -f1 2>/dev/null || echo "0")
                fi
                
                # 方法3: 简单数字提取
                if [[ $qps -eq 0 ]]; then
                    qps=$(grep -oE '[0-9]+' "${temp_file}" | tail -1 2>/dev/null || echo "0")
                fi
                
                # 验证QPS有效性
                if [[ $qps =~ ^[0-9]+$ ]] && [[ $qps -gt 0 ]]; then
                    log_success "${operation} 测试成功: ${qps} QPS"
                    break
                fi
            fi
        fi
        
        log_warn "策略失败，尝试下一个..."
        qps=0
    done
    
    # 清理临时文件
    [[ -f "${temp_file}" ]] && rm -f "${temp_file}"
    
    # 确保返回有效数值
    echo "${qps:-0}"
}

# 高效的集群测试函数
test_cluster_optimized() {
    local -r cluster_name=$1
    local -r port=$2
    
    log_info "开始测试${cluster_name}集群..."
    
    # 检查集群状态
    if ! check_cluster_fast "${port}" "${cluster_name}"; then
        log_error "${cluster_name}集群检查失败，跳过测试"
        return 1
    fi
    
    # 预热集群
    log_info "预热${cluster_name}集群..."
    timeout 10 redis-benchmark -h "${HOST}" -p "${port}" -t set -n 1000 -c 10 -d 64 -q >/dev/null 2>&1 || true
    
    # 生成测试结果表头
    {
        echo ""
        echo "## ${cluster_name}集群测试结果"
        echo ""
    } >> "${RESULT_FILE}"
    
    local total_max_qps=0
    local best_operation=""
    
    for operation in "${TEST_OPERATIONS[@]}"; do
        {
            echo "### ${operation} 操作性能"
            echo "| 并发数 | 请求数 | QPS |"
            echo "|--------|--------|-----|"
        } >> "${RESULT_FILE}"
        
        local operation_max_qps=0
        local operation_best_config=""
        
        for concurrency in "${CONCURRENCY_LEVELS[@]}"; do
            for requests in "${REQUEST_COUNTS[@]}"; do
                local qps
                qps=$(run_benchmark_optimized "${cluster_name}" "${port}" "${operation}" "${concurrency}" "${requests}")
                
                echo "| ${concurrency} | ${requests} | ${qps} |" >> "${RESULT_FILE}"
                
                # 更新最大QPS（使用算术比较）
                if (( qps > operation_max_qps )); then
                    operation_max_qps=$qps
                    operation_best_config="并发:${concurrency}, 请求:${requests}"
                fi
                
                if (( qps > total_max_qps )); then
                    total_max_qps=$qps
                    best_operation="${operation}"
                fi
                
                # 测试间隔，避免资源竞争
                sleep 1
            done
        done
        
        {
            echo ""
            echo "**${operation} 最大QPS:** ${operation_max_qps} (${operation_best_config})"
            echo ""
        } >> "${RESULT_FILE}"
    done
    
    {
        echo "### ${cluster_name}集群总结"
        echo "- **最高QPS:** ${total_max_qps}"
        echo "- **最佳操作:** ${best_operation}"
        echo ""
    } >> "${RESULT_FILE}"
    
    log_success "${cluster_name}集群测试完成，最高QPS: ${total_max_qps}"
}

# 生成优化的报告头部
generate_optimized_header() {
    cat > "${RESULT_FILE}" << 'EOF'
# Redis集群终极性能测试报告

**测试版本:** 高效优化版 v2.0
**测试时间:** $(date '+%Y-%m-%d %H:%M:%S')
**测试目标:** 3节点 vs 6节点集群性能对比
**优化特性:**
- ✅ 多策略测试，确保兼容性
- ✅ 超时保护，避免卡死
- ✅ 智能QPS提取
- ✅ 集群预热机制
- ✅ 资源竞争优化

**测试参数:**
- **数据大小:** 64 bytes
- **测试操作:** set, get, incr
- **并发级别:** 25, 50
- **请求数量:** 5000, 10000
- **超时设置:** 30秒

---
EOF
    
    # 替换时间戳
    sed -i "s/\$(date '+%Y-%m-%d %H:%M:%S')/$(date '+%Y-%m-%d %H:%M:%S')/g" "${RESULT_FILE}"
}

# 生成性能对比分析
generate_comparison() {
    log_info "生成性能对比分析..."
    
    cat >> "${RESULT_FILE}" << 'EOF'

## 性能对比分析

### 理论分析
- **3节点集群:** 3个主节点，数据分布在3个分片
- **6节点集群:** 6个主节点，数据分布在6个分片，理论上有更好的并行性

### 单机环境限制
- CPU和内存资源共享
- 网络IO在同一台机器上
- 磁盘IO竞争

### 优化建议
1. **生产环境部署:** 使用多台物理机器
2. **资源隔离:** 使用容器或虚拟机隔离
3. **网络优化:** 配置专用网络
4. **存储优化:** 使用SSD和独立存储

EOF
}

# 主函数
main() {
    log_info "启动Redis集群终极性能测试..."
    
    # 依赖检查
    local missing_deps=()
    for cmd in redis-benchmark redis-cli timeout; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "缺少依赖: ${missing_deps[*]}"
        exit 1
    fi
    
    # 创建结果目录
    mkdir -p "${RESULT_DIR}"
    
    # 生成报告头部
    generate_optimized_header
    
    # 测试3节点集群
    if test_cluster_optimized "3节点" "${CLUSTER_3_PORT}"; then
        log_success "3节点集群测试完成"
    else
        log_error "3节点集群测试失败"
    fi
    
    # 系统稳定等待
    log_info "等待系统稳定..."
    sleep 5
    
    # 测试6节点集群
    if test_cluster_optimized "6节点" "${CLUSTER_6_PORT}"; then
        log_success "6节点集群测试完成"
    else
        log_error "6节点集群测试失败"
    fi
    
    # 生成对比分析
    generate_comparison
    
    log_success "终极性能测试完成！"
    log_info "结果文件: ${RESULT_FILE}"
    log_info "查看结果: cat ${RESULT_FILE}"
}

# 错误处理
trap 'log_error "脚本执行出错，行号: $LINENO"' ERR

# 运行主函数
main "$@"