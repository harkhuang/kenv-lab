# Redis集群修复版性能测试报告

**测试目标:** 3节点 vs 6节点集群性能对比（修复版）
**测试时间:** 2025-07-27 23:51:11
**数据大小:** 64 bytes
**测试操作:** set get incr
**并发级别:** 50 100
**请求数量:** 10000 50000

> 🔧 **修复说明**: 解决了redis-benchmark参数兼容性问题

---

## 3节点集群测试结果

### set 操作性能
| 并发数 | 请求数 | QPS |
|--------|--------|-----|
| 50 | 10000 | [0;34m[INFO][0m 测试 3节点 - set (并发:50, 请求:10000)
[0;31m[ERROR][0m 测试失败: set (并发:50, 请求:10000)
错误输出:
 SET: rps=0.0 (overall: -nan) avg_msec=-nan (overall: -nan)Error from server: MOVED 13782 127.0.0.1:7003
0 |
| 50 | 50000 | [0;34m[INFO][0m 测试 3节点 - set (并发:50, 请求:50000)
[0;31m[ERROR][0m 测试失败: set (并发:50, 请求:50000)
错误输出:
 SET: rps=0.0 (overall: -nan) avg_msec=-nan (overall: -nan)Error from server: MOVED 13782 127.0.0.1:7003
0 |
| 100 | 10000 | [0;34m[INFO][0m 测试 3节点 - set (并发:100, 请求:10000)
[0;31m[ERROR][0m 测试失败: set (并发:100, 请求:10000)
错误输出:
 SET: rps=0.0 (overall: -nan) avg_msec=-nan (overall: -nan)Error from server: MOVED 13782 127.0.0.1:7003
0 |
| 100 | 50000 | [0;34m[INFO][0m 测试 3节点 - set (并发:100, 请求:50000)
[0;31m[ERROR][0m 测试失败: set (并发:100, 请求:50000)
错误输出:
 SET: rps=0.0 (overall: -nan) avg_msec=-nan (overall: -nan)Error from server: MOVED 13782 127.0.0.1:7003
0 |

**set 最大QPS:** 0 ()

### get 操作性能
| 并发数 | 请求数 | QPS |
|--------|--------|-----|
| 50 | 10000 | [0;34m[INFO][0m 测试 3节点 - get (并发:50, 请求:10000)
[0;31m[ERROR][0m 测试失败: get (并发:50, 请求:10000)
错误输出:
 GET: rps=0.0 (overall: -nan) avg_msec=-nan (overall: -nan)Error from server: MOVED 13782 127.0.0.1:7003
0 |
