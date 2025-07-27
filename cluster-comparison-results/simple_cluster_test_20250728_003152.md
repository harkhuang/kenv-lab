# Redis集群简化性能测试报告

**测试目标:** 3节点 vs 6节点集群性能对比（简化版）
**测试时间:** 2025-07-28 00:31:52
**数据大小:** 64 bytes
**测试操作:** set get incr
**并发级别:** 50 100 200
**请求数量:** 10000 50000

> 📝 **说明**: 简化版测试，避免大数据量导致的资源问题

---

\n## 3节点集群测试结果\n
\n### set 操作性能\n
| 并发数 | 请求数 | QPS |
|--------|--------|-----|
|    50 |  10000 | [0;34m[INFO][0m 测试 3节点 - set (并发:50, 请求:10000)
[0;31m[ERROR][0m 测试失败: set (并发:50, 请求:10000)
Invalid option "--quiet" or option argument missing

Usage: redis-benchmark [OPTIONS] [COMMAND ARGS...]

Options:
 -h <hostname>      Server hostname (default 127.0.0.1)
 -p <port>          Server port (default 6379)
 -s <socket>        Server socket (overrides host and port)
 -a <password>      Password for Redis Auth
 --user <username>  Used to send ACL style 'AUTH username pass'. Needs -a.
 -u <uri>           Server URI.
 -c <clients>       Number of parallel connections (default 50).
                    Note: If --cluster is used then number of clients has to be
                    the same or higher than the number of nodes.
 -n <requests>      Total number of requests (default 100000)
 -d <size>          Data size of SET/GET value in bytes (default 3)
 --dbnum <db>       SELECT the specified db number (default 0)
 -3                 Start session in RESP3 protocol mode.
 --threads <num>    Enable multi-thread mode.
 --cluster          Enable cluster mode.
                    If the command is supplied on the command line in cluster
                    mode, the key must contain "{tag}". Otherwise, the
                    command will not be sent to the right cluster node.
 --enable-tracking  Send CLIENT TRACKING on before starting benchmark.
 -k <boolean>       1=keep alive 0=reconnect (default 1)
 -r <keyspacelen>   Use random keys for SET/GET/INCR, random values for SADD,
                    random members and scores for ZADD.
                    Using this option the benchmark will expand the string
                    __rand_int__ inside an argument with a 12 digits number in
                    the specified range from 0 to keyspacelen-1. The
                    substitution changes every time a command is executed.
                    Default tests use this to hit random keys in the specified
                    range.
                    Note: If -r is omitted, all commands in a benchmark will
                    use the same key.
 -P <numreq>        Pipeline <numreq> requests. Default 1 (no pipeline).
 -q                 Quiet. Just show query/sec values
 --precision        Number of decimal places to display in latency output (default 0)
 --csv              Output in CSV format
 -l                 Loop. Run the tests forever
 -t <tests>         Only run the comma separated list of tests. The test
                    names are the same as the ones produced as output.
                    The -t option is ignored if a specific command is supplied
                    on the command line.
 -I                 Idle mode. Just open N idle connections and wait.
 -x                 Read last argument from STDIN.
 --seed <num>       Set the seed for random number generator. Default seed is based on time.
 --help             Output this help and exit.
 --version          Output version and exit.

Examples:

 Run the benchmark with the default configuration against 127.0.0.1:6379:
   $ redis-benchmark

 Use 20 parallel clients, for a total of 100k requests, against 192.168.1.1:
   $ redis-benchmark -h 192.168.1.1 -p 6379 -n 100000 -c 20

 Fill 127.0.0.1:6379 with about 1 million keys only using the SET test:
   $ redis-benchmark -t set -n 1000000 -r 100000000

 Benchmark 127.0.0.1:6379 for a few commands producing CSV output:
   $ redis-benchmark -t ping,set,get -n 100000 --csv

 Benchmark a specific command line:
   $ redis-benchmark -r 10000 -n 10000 eval 'return redis.call("ping")' 0

 Fill a list with 10000 random elements:
   $ redis-benchmark -r 10000 -n 10000 lpush mylist __rand_int__

 On user specified command lines __rand_int__ is replaced with a random integer
 with a range of values selected by the -r option.
0 |
|    50 |  50000 | [0;34m[INFO][0m 测试 3节点 - set (并发:50, 请求:50000)
[0;31m[ERROR][0m 测试失败: set (并发:50, 请求:50000)
Invalid option "--quiet" or option argument missing

Usage: redis-benchmark [OPTIONS] [COMMAND ARGS...]

Options:
 -h <hostname>      Server hostname (default 127.0.0.1)
 -p <port>          Server port (default 6379)
 -s <socket>        Server socket (overrides host and port)
 -a <password>      Password for Redis Auth
 --user <username>  Used to send ACL style 'AUTH username pass'. Needs -a.
 -u <uri>           Server URI.
 -c <clients>       Number of parallel connections (default 50).
                    Note: If --cluster is used then number of clients has to be
                    the same or higher than the number of nodes.
 -n <requests>      Total number of requests (default 100000)
 -d <size>          Data size of SET/GET value in bytes (default 3)
 --dbnum <db>       SELECT the specified db number (default 0)
 -3                 Start session in RESP3 protocol mode.
 --threads <num>    Enable multi-thread mode.
 --cluster          Enable cluster mode.
                    If the command is supplied on the command line in cluster
                    mode, the key must contain "{tag}". Otherwise, the
                    command will not be sent to the right cluster node.
 --enable-tracking  Send CLIENT TRACKING on before starting benchmark.
 -k <boolean>       1=keep alive 0=reconnect (default 1)
 -r <keyspacelen>   Use random keys for SET/GET/INCR, random values for SADD,
                    random members and scores for ZADD.
                    Using this option the benchmark will expand the string
                    __rand_int__ inside an argument with a 12 digits number in
                    the specified range from 0 to keyspacelen-1. The
                    substitution changes every time a command is executed.
                    Default tests use this to hit random keys in the specified
                    range.
                    Note: If -r is omitted, all commands in a benchmark will
                    use the same key.
 -P <numreq>        Pipeline <numreq> requests. Default 1 (no pipeline).
 -q                 Quiet. Just show query/sec values
 --precision        Number of decimal places to display in latency output (default 0)
 --csv              Output in CSV format
 -l                 Loop. Run the tests forever
 -t <tests>         Only run the comma separated list of tests. The test
                    names are the same as the ones produced as output.
                    The -t option is ignored if a specific command is supplied
                    on the command line.
 -I                 Idle mode. Just open N idle connections and wait.
 -x                 Read last argument from STDIN.
 --seed <num>       Set the seed for random number generator. Default seed is based on time.
 --help             Output this help and exit.
 --version          Output version and exit.

Examples:

 Run the benchmark with the default configuration against 127.0.0.1:6379:
   $ redis-benchmark

 Use 20 parallel clients, for a total of 100k requests, against 192.168.1.1:
   $ redis-benchmark -h 192.168.1.1 -p 6379 -n 100000 -c 20

 Fill 127.0.0.1:6379 with about 1 million keys only using the SET test:
   $ redis-benchmark -t set -n 1000000 -r 100000000

 Benchmark 127.0.0.1:6379 for a few commands producing CSV output:
   $ redis-benchmark -t ping,set,get -n 100000 --csv

 Benchmark a specific command line:
   $ redis-benchmark -r 10000 -n 10000 eval 'return redis.call("ping")' 0

 Fill a list with 10000 random elements:
   $ redis-benchmark -r 10000 -n 10000 lpush mylist __rand_int__

 On user specified command lines __rand_int__ is replaced with a random integer
 with a range of values selected by the -r option.
0 |
|    100 |  10000 | [0;34m[INFO][0m 测试 3节点 - set (并发:100, 请求:10000)
[0;31m[ERROR][0m 测试失败: set (并发:100, 请求:10000)
Invalid option "--quiet" or option argument missing

Usage: redis-benchmark [OPTIONS] [COMMAND ARGS...]

Options:
 -h <hostname>      Server hostname (default 127.0.0.1)
 -p <port>          Server port (default 6379)
 -s <socket>        Server socket (overrides host and port)
 -a <password>      Password for Redis Auth
 --user <username>  Used to send ACL style 'AUTH username pass'. Needs -a.
 -u <uri>           Server URI.
 -c <clients>       Number of parallel connections (default 50).
                    Note: If --cluster is used then number of clients has to be
                    the same or higher than the number of nodes.
 -n <requests>      Total number of requests (default 100000)
 -d <size>          Data size of SET/GET value in bytes (default 3)
 --dbnum <db>       SELECT the specified db number (default 0)
 -3                 Start session in RESP3 protocol mode.
 --threads <num>    Enable multi-thread mode.
 --cluster          Enable cluster mode.
                    If the command is supplied on the command line in cluster
                    mode, the key must contain "{tag}". Otherwise, the
                    command will not be sent to the right cluster node.
 --enable-tracking  Send CLIENT TRACKING on before starting benchmark.
 -k <boolean>       1=keep alive 0=reconnect (default 1)
 -r <keyspacelen>   Use random keys for SET/GET/INCR, random values for SADD,
                    random members and scores for ZADD.
                    Using this option the benchmark will expand the string
                    __rand_int__ inside an argument with a 12 digits number in
                    the specified range from 0 to keyspacelen-1. The
                    substitution changes every time a command is executed.
                    Default tests use this to hit random keys in the specified
                    range.
                    Note: If -r is omitted, all commands in a benchmark will
                    use the same key.
 -P <numreq>        Pipeline <numreq> requests. Default 1 (no pipeline).
 -q                 Quiet. Just show query/sec values
 --precision        Number of decimal places to display in latency output (default 0)
 --csv              Output in CSV format
 -l                 Loop. Run the tests forever
 -t <tests>         Only run the comma separated list of tests. The test
                    names are the same as the ones produced as output.
                    The -t option is ignored if a specific command is supplied
                    on the command line.
 -I                 Idle mode. Just open N idle connections and wait.
 -x                 Read last argument from STDIN.
 --seed <num>       Set the seed for random number generator. Default seed is based on time.
 --help             Output this help and exit.
 --version          Output version and exit.

Examples:

 Run the benchmark with the default configuration against 127.0.0.1:6379:
   $ redis-benchmark

 Use 20 parallel clients, for a total of 100k requests, against 192.168.1.1:
   $ redis-benchmark -h 192.168.1.1 -p 6379 -n 100000 -c 20

 Fill 127.0.0.1:6379 with about 1 million keys only using the SET test:
   $ redis-benchmark -t set -n 1000000 -r 100000000

 Benchmark 127.0.0.1:6379 for a few commands producing CSV output:
   $ redis-benchmark -t ping,set,get -n 100000 --csv

 Benchmark a specific command line:
   $ redis-benchmark -r 10000 -n 10000 eval 'return redis.call("ping")' 0

 Fill a list with 10000 random elements:
   $ redis-benchmark -r 10000 -n 10000 lpush mylist __rand_int__

 On user specified command lines __rand_int__ is replaced with a random integer
 with a range of values selected by the -r option.
0 |
