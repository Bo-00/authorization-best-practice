#!/bin/bash

# =============================================================================
# JWT 认证系统完整测试脚本
# =============================================================================
# 该脚本用于测试JWT认证系统的所有功能，包括：
# 1. 用户登录认证
# 2. JWT Token获取和验证
# 3. 受保护资源访问
# 4. Token刷新机制
# 5. 错误场景处理
# =============================================================================

# 设置脚本执行参数
set -e  # 遇到错误立即退出
# set -x  # 取消注释以显示详细执行过程

# 配置服务器地址
SERVER_URL="http://localhost:8080"
API_BASE="$SERVER_URL/api/v1"

# 颜色输出设置
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_header() {
    echo -e "\n${BLUE}==================== $1 ====================${NC}"
}

# 检查必要的工具是否安装
check_dependencies() {
    print_header "检查系统依赖"
    
    # 检查curl是否安装
    if ! command -v curl &> /dev/null; then
        print_error "curl 未安装，请先安装 curl"
        exit 1
    fi
    print_success "curl 已安装"
    
    # 检查jq是否安装
    if ! command -v jq &> /dev/null; then
        print_warning "jq 未安装，JSON输出将不会格式化"
        print_info "建议安装jq: brew install jq (macOS)"
        JQ_AVAILABLE=false
    else
        print_success "jq 已安装"
        JQ_AVAILABLE=true
    fi
}

# 格式化JSON输出
format_json() {
    if [ "$JQ_AVAILABLE" = true ]; then
        echo "$1" | jq '.'
    else
        echo "$1"
    fi
}

# 检查服务器是否运行
check_server() {
    print_header "检查服务器状态"
    
    print_info "检查服务器是否在 $SERVER_URL 运行..."
    
    # 尝试连接服务器
    if curl -s --connect-timeout 5 "$SERVER_URL" > /dev/null 2>&1; then
        print_success "服务器运行正常"
    else
        print_error "无法连接到服务器 $SERVER_URL"
        print_info "请确保JWT服务器正在运行: go run main.go"
        exit 1
    fi
}

# 测试用户登录功能
test_login() {
    print_header "测试用户登录功能"
    
    # 测试admin用户登录
    print_info "测试admin用户登录 (用户名: admin, 密码: admin123)"
    
    LOGIN_RESPONSE=$(curl -s -X POST "$API_BASE/login" \
        -H "Content-Type: application/json" \
        -d '{"username":"admin","password":"admin123"}')
    
    # 检查登录响应
    if echo "$LOGIN_RESPONSE" | grep -q '"success":true'; then
        print_success "admin用户登录成功"
        format_json "$LOGIN_RESPONSE"
        
        # 提取token
        if [ "$JQ_AVAILABLE" = true ]; then
            ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.data.access_token')
            REFRESH_TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.data.refresh_token')
            EXPIRES_IN=$(echo "$LOGIN_RESPONSE" | jq -r '.data.expires_in')
        else
            # 如果没有jq，使用sed提取token（简单方法）
            ACCESS_TOKEN=$(echo "$LOGIN_RESPONSE" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
            REFRESH_TOKEN=$(echo "$LOGIN_RESPONSE" | sed -n 's/.*"refresh_token":"\([^"]*\)".*/\1/p')
        fi
        
        print_info "Access Token (前50字符): ${ACCESS_TOKEN:0:50}..."
        print_info "Refresh Token (前50字符): ${REFRESH_TOKEN:0:50}..."
        [ -n "$EXPIRES_IN" ] && print_info "Token过期时间: $EXPIRES_IN 秒"
        
    else
        print_error "admin用户登录失败"
        format_json "$LOGIN_RESPONSE"
        return 1
    fi
    
    echo ""
    
    # 测试user1用户登录
    print_info "测试user1用户登录 (用户名: user1, 密码: user123)"
    
    USER1_RESPONSE=$(curl -s -X POST "$API_BASE/login" \
        -H "Content-Type: application/json" \
        -d '{"username":"user1","password":"user123"}')
    
    if echo "$USER1_RESPONSE" | grep -q '"success":true'; then
        print_success "user1用户登录成功"
        format_json "$USER1_RESPONSE"
    else
        print_error "user1用户登录失败"
        format_json "$USER1_RESPONSE"
    fi
}

# 测试受保护资源访问
test_protected_resource() {
    print_header "测试受保护资源访问"
    
    if [ -z "$ACCESS_TOKEN" ]; then
        print_error "没有有效的Access Token，跳过受保护资源测试"
        return 1
    fi
    
    print_info "使用Access Token访问受保护的用户信息接口"
    
    USER_INFO_RESPONSE=$(curl -s -X GET "$API_BASE/protected/user" \
        -H "Authorization: Bearer $ACCESS_TOKEN")
    
    if echo "$USER_INFO_RESPONSE" | grep -q '"success":true'; then
        print_success "成功访问受保护资源"
        format_json "$USER_INFO_RESPONSE"
    else
        print_error "访问受保护资源失败"
        format_json "$USER_INFO_RESPONSE"
    fi
}

# 测试Token刷新功能
test_token_refresh() {
    print_header "测试Token刷新功能"
    
    if [ -z "$REFRESH_TOKEN" ]; then
        print_error "没有有效的Refresh Token，跳过刷新测试"
        return 1
    fi
    
    print_info "使用Refresh Token获取新的Access Token"
    
    REFRESH_RESPONSE=$(curl -s -X POST "$API_BASE/refresh" \
        -H "Content-Type: application/json" \
        -d "{\"refresh_token\":\"$REFRESH_TOKEN\"}")
    
    if echo "$REFRESH_RESPONSE" | grep -q '"success":true'; then
        print_success "Token刷新成功"
        format_json "$REFRESH_RESPONSE"
        
        # 更新token
        if [ "$JQ_AVAILABLE" = true ]; then
            NEW_ACCESS_TOKEN=$(echo "$REFRESH_RESPONSE" | jq -r '.data.access_token')
            print_info "获得新的Access Token (前50字符): ${NEW_ACCESS_TOKEN:0:50}..."
        fi
    else
        print_error "Token刷新失败"
        format_json "$REFRESH_RESPONSE"
    fi
}

# 测试错误场景
test_error_scenarios() {
    print_header "测试错误场景处理"
    
    # 测试错误密码
    print_info "测试错误密码登录"
    ERROR_LOGIN_RESPONSE=$(curl -s -X POST "$API_BASE/login" \
        -H "Content-Type: application/json" \
        -d '{"username":"admin","password":"wrongpassword"}')
    
    if echo "$ERROR_LOGIN_RESPONSE" | grep -q '"success":false'; then
        print_success "错误密码正确被拒绝"
        format_json "$ERROR_LOGIN_RESPONSE"
    else
        print_error "错误密码应该被拒绝但没有"
        format_json "$ERROR_LOGIN_RESPONSE"
    fi
    
    echo ""
    
    # 测试不存在的用户
    print_info "测试不存在的用户登录"
    NOUSER_RESPONSE=$(curl -s -X POST "$API_BASE/login" \
        -H "Content-Type: application/json" \
        -d '{"username":"nonexistent","password":"password"}')
    
    if echo "$NOUSER_RESPONSE" | grep -q '"success":false'; then
        print_success "不存在用户正确被拒绝"
        format_json "$NOUSER_RESPONSE"
    else
        print_error "不存在用户应该被拒绝但没有"
        format_json "$NOUSER_RESPONSE"
    fi
    
    echo ""
    
    # 测试无效token
    print_info "测试使用无效Token访问受保护资源"
    INVALID_TOKEN_RESPONSE=$(curl -s -X GET "$API_BASE/protected/user" \
        -H "Authorization: Bearer invalid-token-here")
    
    if echo "$INVALID_TOKEN_RESPONSE" | grep -q '"success":false'; then
        print_success "无效Token正确被拒绝"
        format_json "$INVALID_TOKEN_RESPONSE"
    else
        print_error "无效Token应该被拒绝但没有"
        format_json "$INVALID_TOKEN_RESPONSE"
    fi
    
    echo ""
    
    # 测试缺少Authorization头
    print_info "测试缺少Authorization头访问受保护资源"
    NO_AUTH_RESPONSE=$(curl -s -X GET "$API_BASE/protected/user")
    
    if echo "$NO_AUTH_RESPONSE" | grep -q '"success":false'; then
        print_success "缺少Authorization头正确被拒绝"
        format_json "$NO_AUTH_RESPONSE"
    else
        print_error "缺少Authorization头应该被拒绝但没有"
        format_json "$NO_AUTH_RESPONSE"
    fi
}

# JWT Token解码展示（如果有base64工具）
show_token_details() {
    print_header "JWT Token详细信息"
    
    if [ -z "$ACCESS_TOKEN" ]; then
        print_warning "没有Access Token可以解码"
        return
    fi
    
    print_info "JWT Token结构分析"
    echo "JWT Token由三部分组成: Header.Payload.Signature"
    
    # 尝试解码JWT的Payload部分
    if command -v base64 &> /dev/null; then
        print_info "尝试解码JWT Payload部分..."
        
        # 提取payload部分（第二段）
        PAYLOAD=$(echo "$ACCESS_TOKEN" | cut -d. -f2)
        
        # 添加padding如果需要
        case $((${#PAYLOAD} % 4)) in
            2) PAYLOAD="${PAYLOAD}==" ;;
            3) PAYLOAD="${PAYLOAD}=" ;;
        esac
        
        # 解码payload
        if DECODED_PAYLOAD=$(echo "$PAYLOAD" | base64 -d 2>/dev/null); then
            print_success "JWT Payload内容:"
            format_json "$DECODED_PAYLOAD"
        else
            print_warning "无法解码JWT Payload"
        fi
    else
        print_warning "base64工具不可用，无法解码JWT"
    fi
}

# 性能测试
performance_test() {
    print_header "简单性能测试"
    
    print_info "执行10次登录请求测试性能..."
    
    start_time=$(date +%s.%N)
    
    for i in {1..10}; do
        curl -s -X POST "$API_BASE/login" \
            -H "Content-Type: application/json" \
            -d '{"username":"admin","password":"admin123"}' > /dev/null
    done
    
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc 2>/dev/null || echo "无法计算")
    
    if [ "$duration" != "无法计算" ]; then
        avg_time=$(echo "scale=3; $duration / 10" | bc 2>/dev/null || echo "N/A")
        print_success "10次登录请求完成"
        print_info "总耗时: ${duration}秒"
        print_info "平均每次: ${avg_time}秒"
    else
        print_warning "性能测试完成，但无法计算精确时间"
    fi
}

# 主测试函数
main() {
    echo "🧪 JWT 认证系统完整测试开始"
    echo "================================"
    echo "测试目标: $SERVER_URL"
    echo "测试时间: $(date)"
    echo ""
    
    # 执行所有测试
    check_dependencies
    check_server
    test_login
    test_protected_resource
    test_token_refresh
    test_error_scenarios
    show_token_details
    performance_test
    
    print_header "测试总结"
    print_success "JWT认证系统测试完成！"
    print_info "如果看到任何错误，请检查服务器日志或配置"
    print_info "建议在生产环境中添加更多的安全测试"
}

# 清理函数
cleanup() {
    print_info "清理测试环境..."
    # 这里可以添加清理代码
}

# 设置退出时的清理
trap cleanup EXIT

# 检查是否直接运行脚本
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi 