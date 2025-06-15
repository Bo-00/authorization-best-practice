# 鉴权认证方案总结

本文档总结了常见的鉴权认证方案，从最简单的密码认证到现代的 OAuth 2.0 体系。

## 目录

1. [基础概念](#基础概念)
2. [简单认证方案](#简单认证方案)
3. [基于 Token 的认证](#基于token的认证)
4. [OAuth 体系](#oauth体系)
5. [企业级方案](#企业级方案)
6. [最佳实践](#最佳实践)

## 基础概念

在开始之前，需要明确三个核心概念：

- **Authentication（认证）**：确认访问者的身份，回答"你是谁？"
- **Authorization（授权）**：确认已认证用户的权限，回答"你能做什么？"
- **Accounting（审计）**：记录用户的操作行为和发生时间

## 简单认证方案

### 1. 用户名密码认证

**生成过程：**

```
1. 用户注册：password → bcrypt/scrypt/PBKDF2 → hash存储到数据库
2. 加盐哈希：password + salt → hash函数 → salted_hash
```

**验证过程：**

```
1. 用户提交：username + password（明文）
2. 服务器查询：根据username获取stored_hash和salt
3. 计算验证：password + salt → hash函数 → computed_hash
4. 比较结果：computed_hash == stored_hash ? 通过 : 拒绝
```

**加密细节：**

- **数据源**：用户输入的明文密码
- **加密方式**：bcrypt（自带盐值）、scrypt、PBKDF2 等慢哈希函数
- **存储**：只存储哈希值，不存储明文
- **解密**：单向哈希，无法解密，只能验证

**安全要点：**

- 密码传输必须 HTTPS 加密
- 使用慢哈希防暴力破解
- 强制密码复杂度策略

### 2. HTTP Basic Authentication

**生成过程：**

```
1. 客户端：username:password → Base64编码 → dXNlcm5hbWU6cGFzc3dvcmQ=
2. 请求头：Authorization: Basic dXNlcm5hbWU6cGFzc3dvcmQ=
```

**验证过程：**

```
1. 服务器接收：Authorization头中的Base64字符串
2. 解码：Base64解码 → username:password
3. 分割：按冒号分割获取用户名和密码
4. 验证：与数据库中的凭据比较
```

**加密细节：**

- **编码方式**：Base64（仅编码，非加密）
- **传输安全**：依赖 HTTPS 传输层加密
- **解码**：任何人都可以 Base64 解码
- **存储**：服务器端密码存储同方案 1

**示例：**

```bash
# 编码
echo -n "admin:password123" | base64
# 结果：YWRtaW46cGFzc3dvcmQxMjM=

# 解码
echo "YWRtaW46cGFzc3dvcmQxMjM=" | base64 -d
# 结果：admin:password123
```

### 3. HTTP Digest Authentication

**生成过程：**

```
1. 服务器发送挑战：nonce（随机数）+ realm（域）
2. 客户端计算：
   HA1 = MD5(username:realm:password)
   HA2 = MD5(method:uri)
   response = MD5(HA1:nonce:HA2)
```

**验证过程：**

```
1. 服务器接收：username, realm, nonce, uri, response
2. 服务器计算：
   HA1 = MD5(username:realm:stored_password)
   HA2 = MD5(method:uri)
   expected = MD5(HA1:nonce:HA2)
3. 比较：response == expected ? 通过 : 拒绝
```

**加密细节：**

- **哈希算法**：MD5（已不推荐，可升级为 SHA-256）
- **防重放**：nonce 确保每次请求唯一
- **数据保护**：密码不以明文传输
- **解密**：MD5 单向，无法反推密码

**安全机制：**

- nonce 防重放攻击
- 客户端和服务器都不传输明文密码
- 每次请求的 response 都不同

### 4. API Key 认证

**生成过程：**

```
1. 服务器生成：crypto.randomBytes(32) → hex编码 → API Key
2. 或UUID：uuidv4() → 550e8400-e29b-41d4-a716-446655440000
3. 存储：api_key → hash(api_key) 存储到数据库（可选）
```

**验证过程：**

```
1. 客户端发送：X-API-Key: abc123def456...
2. 服务器查询：在数据库中查找该 API Key
3. 验证状态：检查是否有效、未过期、权限范围
4. 返回结果：有效则通过，否则拒绝
```

**加密细节：**

- **生成方式**：加密随机数生成器
- **传输**：明文传输（依赖 HTTPS）
- **存储**：可以明文存储或哈希存储
- **长度**：通常 32-64 字符

**管理机制：**

```
API Key 结构示例：
ak_live_1234567890abcdef...  # 前缀标识环境和类型
```

## 基于 Token 的认证

### 5. Session-based Authentication

**生成过程：**

```
1. 用户登录成功后：
   session_id = random_string(32)  # 生成随机会话ID
   session_data = {user_id, permissions, expire_time}

2. 服务器存储：
   Redis/Memory: session_id → session_data

3. 返回客户端：
   Set-Cookie: session_id=abc123; HttpOnly; Secure
```

**验证过程：**

```
1. 客户端请求：Cookie中自动携带session_id
2. 服务器查询：从存储中获取session_data
3. 验证有效性：
   - session存在？
   - 未过期？
   - 用户状态正常？
4. 授权检查：根据session_data中的权限判断
```

**数据流：**

- **Session ID**：32-128 位随机字符串
- **Session Data**：JSON 格式用户信息
- **存储位置**：服务器内存/Redis/数据库
- **客户端存储**：HttpOnly Cookie（防 XSS）

**安全特性：**

- Session ID 无法伪造（足够长的随机数）
- 服务器可随时撤销
- 支持过期时间自动清理

### 6. Bearer Token

**生成过程：**

```
1. 登录成功后生成：
   token_data = {user_id, permissions, exp}
   secret_key = server_secret
   token = sign(token_data, secret_key)  # 可以是JWT或自定义格式

2. 返回客户端：
   {
     "access_token": "eyJhbGciOiJ...",
     "token_type": "Bearer",
     "expires_in": 3600
   }
```

**验证过程：**

```
1. 客户端发送：Authorization: Bearer eyJhbGciOiJ...
2. 服务器验证：
   - 提取token
   - verify(token, secret_key) → token_data
   - 检查过期时间
   - 验证用户状态
3. 授权：根据token中的权限信息判断
```

**加密细节：**

- **签名算法**：HMAC-SHA256 或 RSA
- **密钥管理**：服务器端保管签名密钥
- **数据保护**：token 防篡改，但内容可能可读
- **解密**：只有持有密钥的服务器能验证

### 7. JWT (JSON Web Token)

**结构：** `Header.Payload.Signature`

**生成过程：**

```
1. Header（头部）:
   {
     "alg": "HS256",    # 签名算法
     "typ": "JWT"       # 令牌类型
   } → Base64URL编码

2. Payload（负载）:
   {
     "sub": "1234567890",      # 主题（用户ID）
     "name": "John Doe",       # 用户名
     "iat": 1516239022,        # 签发时间
     "exp": 1516242622         # 过期时间
   } → Base64URL编码

3. Signature（签名）:
   HMACSHA256(
     base64UrlEncode(header) + "." + base64UrlEncode(payload),
     secret_key
   )

4. 最终JWT = header + "." + payload + "." + signature
```

**验证过程：**

```
1. 分割Token：按"."分割成3部分
2. 验证格式：检查是否为有效的Base64URL
3. 重新计算签名：
   expected_signature = HMACSHA256(header + "." + payload, secret_key)
4. 签名比较：provided_signature == expected_signature
5. 检查时间：验证exp（过期时间）和nbf（生效时间）
6. 提取信息：Base64URL解码payload获取用户信息
```

**数据示例：**

```javascript
// Payload 解码后
{
  "sub": "1234567890",
  "name": "John Doe",
  "admin": true,
  "iat": 1516239022,  // 签发时间
  "exp": 1516242622   // 过期时间
}
```

**安全机制：**

- **防篡改**：任何修改都会导致签名验证失败
- **自包含**：包含所有必要的用户信息
- **无状态**：服务器无需存储，但无法主动撤销
- **Base64URL**：URL 安全的编码方式

**密钥管理：**

- **对称算法（HS256）**：服务器持有 secret_key，用于签名和验证
- **非对称算法（RS256）**：私钥签名，公钥验证

## OAuth 体系

### 8. OAuth 2.0

**角色定义：**

- **Resource Owner**：资源拥有者（用户）
- **Client**：客户端应用
- **Resource Server**：资源服务器（API）
- **Authorization Server**：授权服务器

#### 授权码模式（Authorization Code Flow）

**详细流程：**

```
1. 用户访问：Client → 重定向到Authorization Server
   GET /authorize?
     response_type=code&
     client_id=CLIENT_ID&
     redirect_uri=CALLBACK_URL&
     scope=read+write&
     state=RANDOM_STRING

2. 用户授权：Authorization Server → 用户登录并同意授权

3. 返回授权码：Authorization Server → Client
   GET CALLBACK_URL?code=AUTH_CODE&state=RANDOM_STRING

4. 交换访问令牌：Client → Authorization Server
   POST /token
   {
     "grant_type": "authorization_code",
     "code": "AUTH_CODE",
     "redirect_uri": "CALLBACK_URL",
     "client_id": "CLIENT_ID",
     "client_secret": "CLIENT_SECRET"
   }

5. 返回访问令牌：Authorization Server → Client
   {
     "access_token": "ACCESS_TOKEN",
     "token_type": "Bearer",
     "expires_in": 3600,
     "refresh_token": "REFRESH_TOKEN"
   }

6. 访问资源：Client → Resource Server
   Authorization: Bearer ACCESS_TOKEN
```

**数据验证：**

- **state 参数**：防 CSRF 攻击，Client 生成随机字符串
- **授权码**：一次性使用，5-10 分钟过期
- **访问令牌**：Bearer Token 格式，通常是 JWT
- **刷新令牌**：长期有效，用于获取新的访问令牌

**安全机制：**

- 授权码模式最安全，授权码不直接暴露给用户代理
- client_secret 只在后端使用，不暴露给前端
- state 参数防止 CSRF 攻击
- 访问令牌短期有效，刷新令牌长期有效

#### PKCE（Proof Key for Code Exchange）

**适用场景：**移动应用和单页应用（无法安全存储 client_secret）

**增强流程：**

```
1. 生成Code Verifier：
   code_verifier = base64url(random(32))  # 43-128字符

2. 生成Code Challenge：
   code_challenge = base64url(sha256(code_verifier))

3. 授权请求添加：
   code_challenge=CODE_CHALLENGE&
   code_challenge_method=S256

4. Token交换添加：
   code_verifier=CODE_VERIFIER
```

**验证过程：**

```
Authorization Server验证：
sha256(received_code_verifier) == stored_code_challenge
```

## 企业级方案

### 10. SAML (Security Assertion Markup Language)

基于 XML 的企业级单点登录方案。

**优点：**

- 企业级安全标准
- 支持复杂的身份联合
- 详细的审计日志

**缺点：**

- 实现复杂
- XML 格式冗余
- 主要适用于企业内部

### 11. OpenID Connect

基于 OAuth 2.0 的身份认证层。

**特点：**

- OAuth 2.0 + 身份信息
- 标准化的身份声明
- 适合现代 Web 应用

### 12. CAS (Central Authentication Service)

企业级单点登录解决方案。

**优点：**

- 中央认证服务
- 支持多种认证方式
- 企业级功能完备

## 最佳实践

### 安全原则

1. **最小权限原则**：只授予必要的权限
2. **纵深防御**：多层安全控制
3. **定期轮换**：定期更换密钥和令牌
4. **安全传输**：始终使用 HTTPS
5. **输入验证**：严格验证所有输入

### 选择指南

| 场景       | 推荐方案         | 理由                   |
| ---------- | ---------------- | ---------------------- |
| 简单 API   | API Key          | 实现简单，满足基本需求 |
| Web 应用   | Session + JWT    | 平衡安全性和用户体验   |
| 移动应用   | OAuth 2.0 + PKCE | 安全性高，适合移动环境 |
| 第三方集成 | OAuth 2.0        | 标准化，权限控制精细   |
| 企业内部   | SAML/CAS         | 企业级功能，安全管控强 |
| 微服务     | JWT              | 无状态，适合分布式     |

### 实施建议

1. **令牌生命周期管理**

   - 访问令牌短期有效（15 分钟-1 小时）
   - 刷新令牌长期有效（30 天-90 天）
   - 实现令牌撤销机制

2. **安全存储**

   - 前端：使用 HttpOnly Cookie 或安全的存储方案
   - 后端：使用环境变量或密钥管理服务
   - 移动端：使用系统钥匙串

3. **监控和审计**

   - 记录所有认证授权事件
   - 监控异常登录行为
   - 实现实时告警机制

4. **错误处理**
   - 不泄露敏感信息
   - 统一的错误响应格式
   - 防止时序攻击

## 参考资源

- [RFC 6749: OAuth 2.0 Authorization Framework](https://tools.ietf.org/html/rfc6749)
- [RFC 7519: JSON Web Token (JWT)](https://tools.ietf.org/html/rfc7519)
- [RFC 7235: HTTP Authentication](https://tools.ietf.org/html/rfc7235)
- [OWASP Authentication Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html)

## 相关项目

- [Authorization Best Practice 练习工程](https://github.com/Bo-00/authorization-best-practice)

---

_本文档持续更新，如有问题或建议，欢迎提出 Issue。_
