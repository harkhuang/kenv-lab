#!/bin/bash

# Redis集群单机环境优化性能测试脚本
# 针对单台虚拟机环境的3节点 vs 6节点集群性能对比

set -e

# 配置参数
RESULT_DIR="/home/k/kenv-lab/cluster-comparison-results"
TEST_TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
RESULT_FILE="${RESULT_DIR}/optimized_cluster_comparison_${TEST_TIMESTAMP}.md"
DATA_SIZE=64

# 优化的测试参数
TEST_OPERATIONS=("set" "get" "incr")
# 降低并发数，避免资源竞争
CONCURRENCY_LEVELS=(50 100 200 300)
# 增加请求数，更好体现吞吐差异
REQUEST_COUNTS=(100000 200000 500000)

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

# 系统资源监控
monitor_system_resources() {
    local cluster_name=$1
    echo "\n### ${cluster_name}集群系统资源使用情况" >> "$RESULT_FILE"
    echo "\n| 指标 | 值 |" >> "$RESULT_FILE"
    echo "|------|-----|" >> "$RESULT_FILE"
    
    # CPU使用率
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    echo "| CPU使用率 | ${cpu_usage}% |" >> "$RESULT_FILE"
    
    # 内存使用
    local mem_info=$(free -h | grep "Mem:")
    local mem_used=$(echo $mem_info | awk '{print $3}')
    local mem_total=$(echo $mem_info | awk '{print $2}')
    echo "| 内存使用 | ${mem_used}/${mem_total} |" >> "$RESULT_FILE"
    
    # Redis进程数
    local redis_processes=$(ps aux | grep redis-server | grep -v grep | wc -l)
    echo "| Redis进程数 | ${redis_processes} |" >> "$RESULT_FILE"
    
    # 负载平均值
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    echo "| 负载平均值(1min) | ${load_avg} |" >> "$RESULT_FILE"
    
    echo "" >> "$RESULT_FILE"
}

# 预热集群
warmup_cluster() {
    local port=$1
    local cluster_name=$2
    
    log_info "预热${cluster_name}集群..."
    
    # 预填充数据，确保所有分片都有数据
    redis-benchmark -h ${HOST} -p ${port} --cluster \
        -t set -n 10000 -c 50 -d ${DATA_SIZE} \
        -r 10000 --quiet > /dev/null 2>&1
    
    log_success "${cluster_name}集群预热完成"
}

# 多客户端并行测试
parallel_benchmark() {
    local cluster_name=$1
    local port=$2
    local operation=$3
    local concurrency=$4
    local requests=$5
    
    log_info "并行测试 ${cluster_name} - $operation (并发:$concurrency, 请求:$requests)"
    
    # 创建临时目录
    local temp_dir="/tmp/redis_parallel_test_$$"
    mkdir -p "$temp_dir"
    
    # 分割请求到多个客户端
    local num_clients=4
    local requests_per_client=$((requests / num_clients))
    local concurrency_per_client=$((concurrency / num_clients))
    
    # 启动多个并行测试
    local pids=()
    for i in $(seq 1 $num_clients); do
        {
            redis-benchmark -h ${HOST} -p ${port} --cluster \
                -t ${operation} -n ${requests_per_client} -c ${concurrency_per_client} -d ${DATA_SIZE} \
                -r 100000 --csv > "${temp_dir}/client_${i}.csv" 2>/dev/null
        } &
        pids+=($!)
    done
    
    # 等待所有客户端完成
    for pid in "${pids[@]}"; do
        wait $pid
    done
    
    # 聚合结果
    local total_qps=0
    local valid_results=0
    
    for i in $(seq 1 $num_clients); do
        if [ -f "${temp_dir}/client_${i}.csv" ]; then
            local qps=$(tail -1 "${temp_dir}/client_${i}.csv" | cut -d',' -f2 | tr -d '"')
            if [[ "$qps" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                total_qps=$(echo "$total_qps + $qps" | bc -l)
                valid_results=$((valid_results + 1))
            fi
        fi
    done
    
    # 清理临时文件
    rm -rf "$temp_dir"
    
    if [ $valid_results -gt 0 ]; then
        printf "%.0f" "$total_qps"
    else
        echo "0"
    fi
}

# 执行单个基准测试（优化版）
run_optimized_benchmark() {
    local cluster_name=$1
    local port=$2
    local operation=$3
    local concurrency=$4
    local requests=$5
    
    # 测试前清理缓存
    sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    
    # 设置Redis进程优先级（如果可能）
    local redis_pids=$(pgrep redis-server || true)
    for pid in $redis_pids; do
        renice -10 $pid 2>/dev/null || true
    done
    
    # 执行并行测试
    local qps=$(parallel_benchmark "$cluster_name" "$port" "$operation" "$concurrency" "$requests")
    
    echo "$qps"
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
    
    # 检查集群节点数
    local node_count=$(redis-cli -h ${HOST} -p ${port} cluster nodes | wc -l)
    log_success "${cluster_name}集群连接正常，节点数: $node_count"
}

# 测试单个集群
test_cluster_optimized() {
    local cluster_name=$1
    local port=$2
    
    log_info "开始测试${cluster_name}集群 (端口: $port)"
    
    # 检查集群状态
    check_cluster $port "$cluster_name" || return 1
    
    # 预热集群
    warmup_cluster $port "$cluster_name"
    
    # 监控系统资源
    monitor_system_resources "$cluster_name"
    
    # 生成测试结果表头
    echo "\n## ${cluster_name}集群优化测试结果\n" >> "$RESULT_FILE"
    
    for operation in "${TEST_OPERATIONS[@]}"; do
        echo "\n### $operation 操作吞吐性能\n" >> "$RESULT_FILE"
        echo "| 并发数 | 请求数 | QPS | 性能等级 |" >> "$RESULT_FILE"
        echo "|--------|--------|-----|----------|" >> "$RESULT_FILE"
        
        local max_qps=0
        local best_config=""
        
        for concurrency in "${CONCURRENCY_LEVELS[@]}"; do
            for requests in "${REQUEST_COUNTS[@]}"; do
                local qps=$(run_optimized_benchmark "$cluster_name" "$port" "$operation" "$concurrency" "$requests")
                
                # 性能等级评估
                local performance_level=""
                if (( $(echo "$qps >= 300000" | bc -l) )); then
                    performance_level="🚀 优秀"
                elif (( $(echo "$qps >= 200000" | bc -l) )); then
                    performance_level="⚡ 良好"
                elif (( $(echo "$qps >= 100000" | bc -l) )); then
                    performance_level="✅ 一般"
                else
                    performance_level="⚠️ 较低"
                fi
                
                echo "|    $concurrency |  $requests | $qps | $performance_level |" >> "$RESULT_FILE"
                
                # 记录最大QPS
                if (( $(echo "$qps > $max_qps" | bc -l) )); then
                    max_qps=$qps
                    best_config="并发:$concurrency, 请求:$requests"
                fi
                
                # 避免系统过载，测试间隔
                sleep 2
            done
        done
        
        echo "\n**$operation 最大QPS:** $max_qps ($best_config)\n" >> "$RESULT_FILE"
    done
    
    log_success "${cluster_name}集群测试完成"
}

# 生成详细对比分析
generate_detailed_comparison() {
    cat >> "$RESULT_FILE" << 'EOF'

---

## 详细性能对比分析

### 测试环境优化说明

1. **多客户端并行测试**: 使用4个并行客户端，更好地利用集群分片
2. **系统资源监控**: 实时监控CPU、内存、负载等指标
3. **集群预热**: 测试前预填充数据，确保所有分片均匀分布
4. **进程优先级**: 提高Redis进程优先级，减少调度延迟
5. **缓存清理**: 测试前清理系统缓存，确保测试环境一致

### 单机环境限制分析

#### 资源竞争问题
- **3节点集群**: 6个Redis进程（3主3从）
- **6节点集群**: 12个Redis进程（6主6从）
- **CPU竞争**: 更多进程导致CPU时间片竞争加剧
- **内存竞争**: 内存带宽成为瓶颈

#### 网络开销
- **集群通信**: 6节点集群的Gossip协议开销更大
- **重定向成本**: 更多的MOVED/ASK重定向
- **连接管理**: 客户端需要维护更多连接

### C++客户端优化建议

```cpp
// 1. 使用连接池
#include <redis++/redis++.h>

class RedisClusterManager {
private:
    sw::redis::RedisCluster cluster;
    
public:
    RedisClusterManager(const std::vector<std::string>& nodes) 
        : cluster(nodes.begin(), nodes.end()) {
        
        // 优化连接池配置
        sw::redis::ConnectionPoolOptions pool_opts;
        pool_opts.size = 10;  // 每个节点10个连接
        pool_opts.wait_timeout = std::chrono::milliseconds(100);
        
        sw::redis::ConnectionOptions conn_opts;
        conn_opts.socket_timeout = std::chrono::milliseconds(50);
        conn_opts.connect_timeout = std::chrono::milliseconds(100);
        
        cluster = sw::redis::RedisCluster(nodes.begin(), nodes.end(), 
                                         conn_opts, pool_opts);
    }
    
    // 批量操作优化
    void batchSet(const std::vector<std::pair<std::string, std::string>>& kvs) {
        auto pipe = cluster.pipeline();
        for (const auto& kv : kvs) {
            pipe.set(kv.first, kv.second);
        }
        auto replies = pipe.exec();
    }
};

// 2. 异步操作
#include <future>
#include <thread>

class AsyncRedisClient {
public:
    std::future<std::string> asyncGet(const std::string& key) {
        return std::async(std::launch::async, [this, key]() {
            return cluster.get(key).value_or("");
        });
    }
    
    void parallelOperations() {
        std::vector<std::future<std::string>> futures;
        
        // 并行执行多个操作
        for (int i = 0; i < 100; ++i) {
            futures.push_back(asyncGet("key_" + std::to_string(i)));
        }
        
        // 等待所有操作完成
        for (auto& future : futures) {
            auto result = future.get();
        }
    }
};
```

### 性能优化策略

#### 1. 硬件层面
- **CPU绑定**: 将Redis进程绑定到特定CPU核心
- **内存优化**: 使用大页内存，减少TLB miss
- **网络优化**: 调整网络缓冲区大小

#### 2. Redis配置优化
```bash
# redis.conf 优化配置
tcp-backlog 511
tcp-keepalive 300
timeout 0

# 内存优化
maxmemory-policy allkeys-lru
hash-max-ziplist-entries 512
hash-max-ziplist-value 64

# 网络优化
so-keepalive yes
tcp-nodelay yes
```

#### 3. 系统级优化
```bash
# 系统参数调优
echo 'net.core.somaxconn = 65535' >> /etc/sysctl.conf
echo 'vm.overcommit_memory = 1' >> /etc/sysctl.conf
echo 'net.ipv4.tcp_max_syn_backlog = 65535' >> /etc/sysctl.conf
sysctl -p

# 文件描述符限制
echo '* soft nofile 65535' >> /etc/security/limits.conf
echo '* hard nofile 65535' >> /etc/security/limits.conf
```

### 真实场景测试建议

1. **分布式部署**: 将集群节点部署到不同物理机
2. **真实负载**: 模拟实际业务场景的读写比例
3. **长时间测试**: 进行持续负载测试，观察性能稳定性
4. **故障恢复**: 测试节点故障时的性能表现

EOF
}

# 创建结果目录
create_result_dir() {
    mkdir -p "$RESULT_DIR"
    log_info "结果将保存到: $RESULT_FILE"
}

# 生成报告头部
generate_report_header() {
    cat > "$RESULT_FILE" << EOF
# Redis集群优化性能对比报告

**测试目标:** 单机环境下3节点 vs 6节点集群性能对比（优化版）
**关键指标:** QPS (每秒查询数)
**测试时间:** $(date '+%Y-%m-%d %H:%M:%S')
**数据大小:** ${DATA_SIZE} bytes
**测试操作:** ${TEST_OPERATIONS[*]}
**并发级别:** ${CONCURRENCY_LEVELS[*]}
**请求数量:** ${REQUEST_COUNTS[*]}

> 🎯 **优化重点**: 多客户端并行测试 + 系统资源监控 + 集群预热

---

EOF
}

# 主函数
main() {
    log_info "开始Redis集群优化性能对比测试..."
    
    # 检查依赖
    if ! command -v redis-benchmark &> /dev/null; then
        log_error "redis-benchmark 命令未找到，请安装Redis工具"
        exit 1
    fi
    
    if ! command -v bc &> /dev/null; then
        log_error "bc 命令未找到，请安装: sudo apt-get install bc"
        exit 1
    fi
    
    # 初始化
    create_result_dir
    generate_report_header
    
    # 测试3节点集群
    test_cluster_optimized "3节点" $CLUSTER_3_PORT
    
    # 等待系统稳定
    log_info "等待系统稳定..."
    sleep 10
    
    # 测试6节点集群
    test_cluster_optimized "6节点" $CLUSTER_6_PORT
    
    # 生成详细对比分析
    generate_detailed_comparison
    
    log_success "优化性能对比测试完成！结果保存在: $RESULT_FILE"
    log_info "使用以下命令查看结果: cat $RESULT_FILE"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi