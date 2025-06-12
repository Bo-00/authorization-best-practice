# JWT 认证实践

这是一个使用 Golang 实现的 JWT（JSON Web Token）认证系统示例。

## 功能特性

- 用户登录认证
- JWT Token 生成和验证
- Access Token 和 Refresh Token 机制
- JWT 中间件保护 API 端点
- bcrypt 密码哈希
- RESTful API 设计

## 技术栈

- Go 1.21
- JWT (github.com/golang-jwt/jwt/v5)
- Gorilla Mux 路由器
- bcrypt 密码加密

## 🏗️ 系统架构与交互流程

### JWT 认证完整交互流程图

```mermaid
sequenceDiagram
    participant U as 👤 用户/客户端
    participant S as 🖥️ 服务器
    participant DB as 💾 用户数据库
    participant JWT as 🔐 JWT验证器

    Note over U,S: 1️⃣ 用户登录阶段
    U->>S: POST /api/v1/login<br/>{"username":"admin", "password":"admin123"}
    S->>DB: 查询用户信息
    DB->>S: 返回用户数据<br/>(包含bcrypt加密密码)
    S->>S: bcrypt.Compare()<br/>验证明文密码与加密密码

    alt 密码正确
        S->>S: 生成JWT Token<br/>Header: {"alg":"HS256","typ":"JWT"}<br/>Payload: {"user_id":1,"username":"admin"}<br/>Signature: HMAC-SHA256(Header.Payload, "your-secret-key")
        S->>U: 200 OK<br/>{"access_token":"eyJ...", "refresh_token":"eyJ...", "expires_in":900}
    else 密码错误
        S->>U: 401 Unauthorized<br/>{"success":false, "message":"Invalid username or password"}
    end

    Note over U,S: 2️⃣ 访问受保护资源阶段
    U->>S: GET /api/v1/protected/user<br/>Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
    S->>JWT: 解析JWT Token
    JWT->>JWT: 1. 分离Header.Payload.Signature
    JWT->>JWT: 2. 用secret_key重新计算签名
    JWT->>JWT: 3. 对比原签名与新计算签名
    JWT->>JWT: 4. 检查Token过期时间

    alt JWT验证通过
        JWT->>S: Token有效<br/>返回用户信息{"user_id":1,"username":"admin"}
        S->>S: 提取用户信息到请求上下文
        S->>U: 200 OK<br/>{"success":true, "data":{"id":1,"username":"admin","email":"admin@example.com"}}
    else JWT验证失败
        JWT->>S: Token无效/过期/被篡改
        S->>U: 401 Unauthorized<br/>{"success":false, "message":"Invalid token"}
    end

    Note over U,S: 3️⃣ Token刷新阶段
    U->>S: POST /api/v1/refresh<br/>{"refresh_token":"eyJ..."}
    S->>JWT: 验证Refresh Token
    JWT->>S: Refresh Token有效
    S->>S: 生成新的Access Token和Refresh Token
    S->>U: 200 OK<br/>{"access_token":"new_eyJ...", "refresh_token":"new_eyJ...", "expires_in":900}
```

### 🔐 安全机制详解

#### 1. **密码验证阶段**

- **输入**: 用户名 + 明文密码
- **处理**: bcrypt 对比明文密码与数据库中的哈希密码
- **输出**: 验证成功/失败

#### 2. **JWT 生成阶段**

- **Header**: `{"alg":"HS256","typ":"JWT"}` (算法和类型)
- **Payload**: `{"user_id":1,"username":"admin","exp":...}` (用户信息)
- **Signature**: `HMAC-SHA256(base64(header)+"."+base64(payload), secret_key)`
- **最终 Token**: `base64(header).base64(payload).signature`

#### 3. **JWT 验证阶段**

- **分解**: 将 Token 按"."分割成三部分
- **重计算**: 用服务器密钥重新计算签名
- **对比**: 原签名 vs 新计算签名
- **检查**: Token 是否过期

#### 4. **受保护资源访问**

- **中间件拦截**: 检查 Authorization 头
- **Token 提取**: 从"Bearer tokenstring"中提取 token
- **验证通过**: 将用户信息注入请求上下文
- **业务处理**: 控制器获取用户信息并返回数据

## 快速开始

### 1. 安装依赖

```bash
go mod tidy
```

### 2. 运行服务器

```bash
go run main.go
```

服务器将在 http://localhost:8080 启动

### 3. 测试用户

系统预设了以下测试用户：

- 用户名: `admin`, 密码: `admin123`
- 用户名: `user1`, 密码: `user123`

## API 端点

### 公开端点

#### 用户登录

```bash
POST /api/v1/login
Content-Type: application/json

{
  "username": "admin",
  "password": "admin123"
}
```

响应：

```json
{
  "success": true,
  "message": "Login successful",
  "data": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "expires_in": 900
  }
}
```

#### 刷新令牌

```bash
POST /api/v1/refresh
Content-Type: application/json

{
  "refresh_token": "your-refresh-token-here"
}
```

### 受保护端点（需要认证）

#### 获取用户信息

```bash
GET /api/v1/protected/user
Authorization: Bearer your-access-token-here
```

响应：

```json
{
  "success": true,
  "message": "User info retrieved",
  "data": {
    "id": 1,
    "username": "admin",
    "email": "admin@example.com"
  }
}
```

## 测试示例

### 1. 用户登录

```bash
curl -X POST http://localhost:8080/api/v1/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"admin123"}'
```

### 2. 访问受保护资源

```bash
# 使用返回的 access_token
curl -X GET http://localhost:8080/api/v1/protected/user \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

### 3. 刷新令牌

```bash
curl -X POST http://localhost:8080/api/v1/refresh \
  -H "Content-Type: application/json" \
  -d '{"refresh_token":"YOUR_REFRESH_TOKEN"}'
```

## 安全特性

### Token 生命周期

- **Access Token**: 15 分钟有效期，用于 API 访问
- **Refresh Token**: 7 天有效期，用于刷新 Access Token

### 密码安全

- 使用 bcrypt 进行密码哈希
- 密码不会以明文存储

### JWT 安全

- 使用 HMAC SHA256 签名算法
- 包含用户信息和过期时间
- 支持令牌验证和撤销

## 项目结构

```
jwt-practice/
├── main.go          # 主程序文件
├── go.mod           # Go 模块文件
├── go.sum           # 依赖校验文件
└── README.md        # 项目文档
```

## 生产环境注意事项

1. **密钥管理**: 将 JWT 密钥存储在环境变量中
2. **HTTPS**: 生产环境必须使用 HTTPS
3. **数据库**: 使用真实数据库替代内存存储
4. **日志**: 添加完整的日志记录
5. **监控**: 实现认证失败监控和告警
6. **密码策略**: 实施强密码策略
7. **令牌撤销**: 实现令牌黑名单机制

## 扩展功能

- 用户注册
- 密码重置
- 多因素认证 (MFA)
- 角色权限管理 (RBAC)
- 令牌撤销列表
- 审计日志
