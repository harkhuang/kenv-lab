# kenv-lab
auto shell for environment lab code。


# 3节点和6节点性能测试比较
bash redis-cluster-performance-comparison-simple.sh 

[SUCCESS] 3节点集群连接正常
3节点 - set: 并发:1000, 请求:100000, QPS:198413
3节点 - get: 并发:1000, 请求:100000, QPS:198807
3节点 - incr: 并发:1000, 请求:100000, QPS:198807


[SUCCESS] 开始测试 6节点集群吞吐性能...
6节点 - set: 并发:1000, 请求:100000, QPS:393701
6节点 - get: 并发:1000, 请求:100000, QPS:395257
6节点 - incr: 并发:1000, 请求:100000, QPS:196464
[SUCCESS] 6节点集群测试完成