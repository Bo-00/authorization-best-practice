#!/bin/bash

# =============================================================================
# Google OAuth2 认证系统测试脚本
# =============================================================================
# 该脚本用于测试Google OAuth2认证系统，包括：
# 1. 环境变量检查
# 2. 服务器启动检查
# 3. 基本功能测试
# 4. API接口测试
# =============================================================================

# 颜色输出设置
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# 检查环境变量
check_environment() {
    print_header "检查环境变量"
    
    if [ -z "$GOOGLE_CLIENT_ID" ]; then
        print_error "GOOGLE_CLIENT_ID 环境变量未设置"
        print_info "请设置: export GOOGLE_CLIENT_ID='your-client-id'"
        ENV_ERROR=true
    else
        print_success "GOOGLE_CLIENT_ID 已设置"
        print_info "Client ID: ${GOOGLE_CLIENT_ID:0:20}..."
    fi
    
    if [ -z "$GOOGLE_CLIENT_SECRET" ]; then
        print_error "GOOGLE_CLIENT_SECRET 环境变量未设置"
        print_info "请设置: export GOOGLE_CLIENT_SECRET='your-client-secret'"
        ENV_ERROR=true
    else
        print_success "GOOGLE_CLIENT_SECRET 已设置"
        print_info "Client Secret: ${GOOGLE_CLIENT_SECRET:0:10}..."
    fi
    
    if [ "$ENV_ERROR" = true ]; then
        print_warning "请先设置Google OAuth2环境变量后再运行测试"
        echo ""
        echo "🔗 获取Google OAuth2凭据的步骤:"
        echo "1. 访问 https://console.cloud.google.com/"
        echo "2. 创建或选择项目"
        echo "3. 启用 Google+ API"
        echo "4. 创建 OAuth 2.0 客户端ID"
        echo "5. 添加重定向URI: http://localhost:8080/auth/google/callback"
        echo "6. 复制Client ID和Client Secret"
        echo ""
        return 1
    fi
}

# 检查服务器状态
check_server() {
    print_header "检查服务器状态"
    
    print_info "检查服务器是否在 http://localhost:8080 运行..."
    
    if curl -s --connect-timeout 5 http://localhost:8080 > /dev/null 2>&1; then
        print_success "服务器运行正常"
        return 0
    else
        print_warning "服务器未运行"
        print_info "请在另一个终端运行: go run main.go"
        print_info "然后重新执行此测试脚本"
        return 1
    fi
}

# 测试基本HTTP端点
test_basic_endpoints() {
    print_header "测试基本HTTP端点"
    
    # 测试主页
    print_info "测试主页 GET /"
    if curl -s http://localhost:8080/ | grep -q "Google OAuth2"; then
        print_success "主页加载成功"
    else
        print_error "主页加载失败"
    fi
    
    # 测试Google登录重定向
    print_info "测试Google登录重定向 GET /login/google"
    REDIRECT_RESPONSE=$(curl -s -I http://localhost:8080/login/google)
    if echo "$REDIRECT_RESPONSE" | grep -q "Location.*accounts.google.com"; then
        print_success "Google登录重定向正常"
        # 提取重定向URL
        REDIRECT_URL=$(echo "$REDIRECT_RESPONSE" | grep "Location:" | cut -d' ' -f2- | tr -d '\r')
        print_info "重定向到: ${REDIRECT_URL:0:80}..."
    else
        print_error "Google登录重定向失败"
    fi
    
    # 测试未登录时的API访问
    print_info "测试未登录时的API访问 GET /api/user"
    API_RESPONSE=$(curl -s http://localhost:8080/api/user)
    if echo "$API_RESPONSE" | grep -q "Not logged in"; then
        print_success "未登录API访问正确被拒绝"
    else
        print_warning "未登录API访问处理异常"
        echo "响应: $API_RESPONSE"
    fi
}

# 模拟OAuth2流程（无法完全自动化，需要用户交互）
test_oauth_flow_info() {
    print_header "OAuth2流程测试指南"
    
    print_info "由于OAuth2需要用户交互，无法完全自动化测试"
    print_info "请按以下步骤手动测试完整的OAuth2流程:"
    
    echo ""
    echo "🔄 完整测试流程:"
    echo "1. 浏览器打开: http://localhost:8080"
    echo "2. 点击 '使用 Google 账号登录' 按钮"
    echo "3. 在Google页面完成登录和授权"
    echo "4. 查看返回的用户信息页面"
    echo "5. 点击 '测试API调用' 按钮"
    echo "6. 点击 '查看原始数据' 按钮"
    echo "7. 点击 '退出登录' 测试登出功能"
    
    echo ""
    print_info "如果一切正常，您应该看到："
    echo "✅ Google登录页面正常显示"
    echo "✅ 用户信息正确获取和展示"
    echo "✅ API调用返回正确的JSON数据"
    echo "✅ 登出功能正常工作"
}

# 检查项目文件结构
check_project_structure() {
    print_header "检查项目文件结构"
    
    REQUIRED_FILES=(
        "main.go"
        "go.mod"
        "templates/index.html"
        "templates/profile.html"
        "README.md"
    )
    
    for file in "${REQUIRED_FILES[@]}"; do
        if [ -f "$file" ]; then
            print_success "文件存在: $file"
        else
            print_error "文件缺失: $file"
        fi
    done
    
    # 检查目录
    if [ -d "templates" ]; then
        print_success "模板目录存在"
    else
        print_error "模板目录缺失"
    fi
    
    if [ -d "static" ]; then
        print_success "静态文件目录存在"
    else
        print_warning "静态文件目录不存在（可选）"
    fi
}

# 显示有用的信息
show_useful_info() {
    print_header "有用的信息"
    
    echo "📱 重要URL:"
    echo "  主页: http://localhost:8080"
    echo "  Google登录: http://localhost:8080/login/google"
    echo "  用户API: http://localhost:8080/api/user"
    echo "  登出: http://localhost:8080/logout"
    
    echo ""
    echo "🔧 开发工具:"
    echo "  查看服务器日志: 检查运行 'go run main.go' 的终端"
    echo "  重启服务器: Ctrl+C 然后重新运行 'go run main.go'"
    echo "  清除cookies: 浏览器开发者工具 > Application > Cookies"
    
    echo ""
    echo "🐛 常见问题:"
    echo "  1. 如果重定向失败，检查Google Console中的重定向URI设置"
    echo "  2. 如果获取用户信息失败，检查API是否启用"
    echo "  3. 如果cookies有问题，尝试清除浏览器cookies"
    
    echo ""
    echo "📚 与JWT项目对比:"
    echo "  JWT项目: 自己处理用户认证，需要用户名密码"
    echo "  OAuth2项目: 委托给Google认证，用户无需注册"
}

# 主函数
main() {
    echo "🧪 Google OAuth2 认证系统测试"
    echo "=================================="
    echo "测试时间: $(date)"
    echo ""
    
    # 检查项目文件
    check_project_structure
    
    # 检查环境变量
    if ! check_environment; then
        exit 1
    fi
    
    # 检查服务器
    if ! check_server; then
        print_info "请先启动服务器，然后重新运行测试"
        exit 1
    fi
    
    # 测试基本功能
    test_basic_endpoints
    
    # OAuth2流程指南
    test_oauth_flow_info
    
    # 显示有用信息
    show_useful_info
    
    print_header "测试总结"
    print_success "基础测试完成！"
    print_info "现在请在浏览器中手动测试完整的OAuth2流程"
    print_info "浏览器打开: http://localhost:8080"
}

# 运行主函数
main "$@" 