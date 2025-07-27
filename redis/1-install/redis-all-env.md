# 基于ITS现状的Redis工程化问题梳理

## redis指定版本安装

### 1. 获取指定版本redis压缩包



```bash
# 下载Redis 7.2.4版本（示例）
wget https://download.redis.io/releases/redis-7.2.4.tar.gz

# 或者使用curl
curl -O https://download.redis.io/releases/redis-7.2.4.tar.gz

# 验证下载文件
ls -la redis-7.2.4.tar.gz
```

### 2. 根据压缩包安装redis
```bash
# 解压缩包
tar -xzf redis-7.2.4.tar.gz
cd redis-7.2.4

# 编译安装
make
sudo make install

# 或者指定安装目录
sudo make install PREFIX=/usr/local/redis
```

### 3. 配置环境变量
```bash
# 编辑环境变量文件
vim ~/.bashrc

# 添加以下内容到文件末尾
export REDIS_HOME=/usr/local/redis
export PATH=$REDIS_HOME/bin:$PATH

# 使环境变量生效
source ~/.bashrc
```

### 4. 测试是否可用
```bash
# 启动Redis服务器
redis-server &

# 测试Redis客户端连接
redis-cli ping
# 期望输出: PONG

# 查看Redis版本
redis-server --version

# 简单功能测试
redis-cli set test_key "hello redis"
redis-cli get test_key
# 期望输出: "hello redis"
```

### 5. 创建Redis配置文件（可选）
```bash
# 复制默认配置文件
sudo cp redis.conf /etc/redis/redis.conf

# 编辑配置文件
sudo vim /etc/redis/redis.conf

# 使用配置文件启动
redis-server /etc/redis/redis.conf
```

## redis 配置文件

## redis 环境变量相关配置



## redis 基础性能测试
## redis 多节点性能测试


########## 




# 检查当前版本
redis-server --version

# 备份数据
redis-cli BGSAVE

# 升级建议路径
# 6.0.x → 6.2.19 → 7.2.10 → 8.0.3
# 6.2.x → 7.2.10 → 8.0.3  
# 7.0.x → 7.2.10 → 8.0.3
# 7.2.x → 8.0.3