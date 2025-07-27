# 对每个节点分别测试，然后聚合
for port in "${REDIS_PORTS[@]}"; do
    # 每个节点测试 requests/3 个请求
    redis-benchmark -h ${REDIS_HOST} -p ${port} \
        -c $((clients / 3)) -n $((TEST_REQUESTS / 3)) -d ${DATA_SIZE} \
        -t set --csv > "${temp_file}" 2>/dev/null
    
    # 累加各节点QPS
    total_qps=$(echo "$total_qps + $qps" | bc -l)
done