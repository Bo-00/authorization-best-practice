#!/bin/bash

# JWT Token 解码工具
# 用于展示JWT Token的Header、Payload、Signature结构

if [ $# -eq 0 ]; then
    echo "用法: $0 <JWT_TOKEN>"
    echo "示例: $0 eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
    exit 1
fi

JWT_TOKEN="$1"

echo "🔍 JWT Token 结构分析"
echo "======================================"

# 分割JWT Token
IFS='.' read -ra PARTS <<< "$JWT_TOKEN"

if [ ${#PARTS[@]} -ne 3 ]; then
    echo "❌ 无效的JWT Token格式"
    exit 1
fi

HEADER="${PARTS[0]}"
PAYLOAD="${PARTS[1]}" 
SIGNATURE="${PARTS[2]}"

echo "📋 JWT Token 完整内容:"
echo "$JWT_TOKEN"
echo ""

# 解码Header
echo "🔧 Header (头部):"
echo "原始: $HEADER"
# 添加padding
case $((${#HEADER} % 4)) in
    2) HEADER="${HEADER}==" ;;
    3) HEADER="${HEADER}=" ;;
esac

if HEADER_DECODED=$(echo "$HEADER" | base64 -d 2>/dev/null); then
    echo "解码后:"
    if command -v jq &> /dev/null; then
        echo "$HEADER_DECODED" | jq '.'
    else
        echo "$HEADER_DECODED"
    fi
else
    echo "❌ Header解码失败"
fi

echo ""

# 解码Payload  
echo "📦 Payload (载荷):"
echo "原始: $PAYLOAD"
# 添加padding
case $((${#PAYLOAD} % 4)) in
    2) PAYLOAD="${PAYLOAD}==" ;;
    3) PAYLOAD="${PAYLOAD}=" ;;
esac

if PAYLOAD_DECODED=$(echo "$PAYLOAD" | base64 -d 2>/dev/null); then
    echo "解码后:"
    if command -v jq &> /dev/null; then
        echo "$PAYLOAD_DECODED" | jq '.'
        
        # 解析时间戳
        if command -v jq &> /dev/null; then
            IAT=$(echo "$PAYLOAD_DECODED" | jq -r '.iat // empty')
            EXP=$(echo "$PAYLOAD_DECODED" | jq -r '.exp // empty')
            
            if [ -n "$IAT" ] && [ "$IAT" != "null" ]; then
                IAT_DATE=$(date -r "$IAT" 2>/dev/null || echo "无法解析")
                echo "🕐 签发时间 (iat): $IAT_DATE"
            fi
            
            if [ -n "$EXP" ] && [ "$EXP" != "null" ]; then
                EXP_DATE=$(date -r "$EXP" 2>/dev/null || echo "无法解析")
                echo "⏰ 过期时间 (exp): $EXP_DATE"
                
                # 检查是否过期
                CURRENT_TIME=$(date +%s)
                if [ "$EXP" -lt "$CURRENT_TIME" ]; then
                    echo "❌ Token已过期"
                else
                    REMAINING=$((EXP - CURRENT_TIME))
                    echo "✅ Token还有 $REMAINING 秒有效"
                fi
            fi
        fi
    else
        echo "$PAYLOAD_DECODED"
    fi
else
    echo "❌ Payload解码失败"
fi

echo ""

# 显示Signature
echo "🔐 Signature (签名):"
echo "原始: $SIGNATURE"
echo "说明: 这是用服务器密钥生成的HMAC-SHA256签名"
echo "作用: 验证Token未被篡改"

echo ""
echo "✅ JWT Token 分析完成" 