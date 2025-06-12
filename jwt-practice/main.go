package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/gorilla/mux"
	"golang.org/x/crypto/bcrypt"
)

// JWT密钥 - 生产环境中应该使用环境变量
var jwtKey = []byte("your-secret-key")

// 用户结构体
type User struct {
	ID       int    `json:"id"`
	Username string `json:"username"`
	Password string `json:"password,omitempty"`
	Email    string `json:"email"`
}

// 登录请求结构体
type LoginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

// JWT Claims结构体
type Claims struct {
	UserID   int    `json:"user_id"`
	Username string `json:"username"`
	Email    string `json:"email"`
	jwt.RegisteredClaims
}

// 响应结构体
type Response struct {
	Success bool        `json:"success"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

// Token响应结构体
type TokenResponse struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	ExpiresIn    int64  `json:"expires_in"`
}

// 模拟用户数据库
var users = map[string]User{
	"admin": {
		ID:       1,
		Username: "admin",
		Password: "$2a$10$PjX0.82.3nj1DaU6NIT69.TPw0tFIcInCLmoIliTh6G0tarecAFXu", // bcrypt hash of "admin123"
		Email:    "admin@example.com",
	},
	"user1": {
		ID:       2,
		Username: "user1",
		Password: "$2a$10$RUvcffqE1ajH4Akl3jekjOninMA/JTkuSrVWbsxSinfCS5T8XT/0C", // bcrypt hash of "user123"
		Email:    "user1@example.com",
	},
}

// 生成JWT Token
func generateToken(user User) (string, string, error) {
	// Access Token (短期有效，15分钟)
	accessClaims := &Claims{
		UserID:   user.ID,
		Username: user.Username,
		Email:    user.Email,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(15 * time.Minute)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    "jwt-practice",
			Subject:   user.Username,
		},
	}

	accessToken := jwt.NewWithClaims(jwt.SigningMethodHS256, accessClaims)
	accessTokenString, err := accessToken.SignedString(jwtKey)
	if err != nil {
		return "", "", err
	}

	// Refresh Token (长期有效，7天)
	refreshClaims := &Claims{
		UserID:   user.ID,
		Username: user.Username,
		Email:    user.Email,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(7 * 24 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    "jwt-practice",
			Subject:   user.Username,
		},
	}

	refreshToken := jwt.NewWithClaims(jwt.SigningMethodHS256, refreshClaims)
	refreshTokenString, err := refreshToken.SignedString(jwtKey)
	if err != nil {
		return "", "", err
	}

	return accessTokenString, refreshTokenString, nil
}

// 验证JWT Token
func validateToken(tokenString string) (*Claims, error) {
	claims := &Claims{}
	token, err := jwt.ParseWithClaims(tokenString, claims, func(token *jwt.Token) (interface{}, error) {
		return jwtKey, nil
	})

	if err != nil {
		return nil, err
	}

	if !token.Valid {
		return nil, fmt.Errorf("invalid token")
	}

	return claims, nil
}

// 用户登录处理
func loginHandler(w http.ResponseWriter, r *http.Request) {
	var loginReq LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&loginReq); err != nil {
		sendErrorResponse(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	// 验证用户名密码
	user, exists := users[loginReq.Username]
	if !exists {
		sendErrorResponse(w, http.StatusUnauthorized, "Invalid username or password")
		return
	}

	// 验证密码
	if err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(loginReq.Password)); err != nil {
		sendErrorResponse(w, http.StatusUnauthorized, "Invalid username or password")
		return
	}

	// 生成Token
	accessToken, refreshToken, err := generateToken(user)
	if err != nil {
		sendErrorResponse(w, http.StatusInternalServerError, "Failed to generate token")
		return
	}

	tokenResp := TokenResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    15 * 60, // 15分钟
	}

	sendSuccessResponse(w, "Login successful", tokenResp)
}

// 获取用户信息（需要认证）
func getUserInfoHandler(w http.ResponseWriter, r *http.Request) {
	claims, ok := r.Context().Value("user").(*Claims)
	if !ok {
		sendErrorResponse(w, http.StatusUnauthorized, "Unauthorized")
		return
	}

	user := User{
		ID:       claims.UserID,
		Username: claims.Username,
		Email:    claims.Email,
	}

	sendSuccessResponse(w, "User info retrieved", user)
}

// 刷新Token
func refreshTokenHandler(w http.ResponseWriter, r *http.Request) {
	var request struct {
		RefreshToken string `json:"refresh_token"`
	}

	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		sendErrorResponse(w, http.StatusBadRequest, "Invalid request body")
		return
	}

	// 验证refresh token
	claims, err := validateToken(request.RefreshToken)
	if err != nil {
		sendErrorResponse(w, http.StatusUnauthorized, "Invalid refresh token")
		return
	}

	// 获取用户信息
	user, exists := users[claims.Username]
	if !exists {
		sendErrorResponse(w, http.StatusUnauthorized, "User not found")
		return
	}

	// 生成新的Token
	accessToken, refreshToken, err := generateToken(user)
	if err != nil {
		sendErrorResponse(w, http.StatusInternalServerError, "Failed to generate token")
		return
	}

	tokenResp := TokenResponse{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresIn:    15 * 60,
	}

	sendSuccessResponse(w, "Token refreshed", tokenResp)
}

// JWT中间件
func jwtMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// 从Header中获取Authorization
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			sendErrorResponse(w, http.StatusUnauthorized, "Missing authorization header")
			return
		}

		// 检查Bearer格式
		tokenParts := strings.Split(authHeader, " ")
		if len(tokenParts) != 2 || tokenParts[0] != "Bearer" {
			sendErrorResponse(w, http.StatusUnauthorized, "Invalid authorization header format")
			return
		}

		// 验证Token
		claims, err := validateToken(tokenParts[1])
		if err != nil {
			sendErrorResponse(w, http.StatusUnauthorized, "Invalid token: "+err.Error())
			return
		}

		// 将用户信息添加到请求上下文
		ctx := context.WithValue(r.Context(), "user", claims)
		r = r.WithContext(ctx)

		next.ServeHTTP(w, r)
	})
}

// 发送成功响应
func sendSuccessResponse(w http.ResponseWriter, message string, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	response := Response{
		Success: true,
		Message: message,
		Data:    data,
	}
	json.NewEncoder(w).Encode(response)
}

// 发送错误响应
func sendErrorResponse(w http.ResponseWriter, statusCode int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	response := Response{
		Success: false,
		Message: message,
	}
	json.NewEncoder(w).Encode(response)
}

// 生成密码hash（用于测试）
func generatePasswordHash(password string) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("Password hash for '%s': %s\n", password, string(hash))
}

func main() {
	// 初始化路由
	router := mux.NewRouter()

	// API路由
	api := router.PathPrefix("/api/v1").Subrouter()

	// 公开端点
	api.HandleFunc("/login", loginHandler).Methods("POST")
	api.HandleFunc("/refresh", refreshTokenHandler).Methods("POST")

	// 受保护的端点（需要JWT认证）
	protected := api.PathPrefix("/protected").Subrouter()
	protected.Use(jwtMiddleware)
	protected.HandleFunc("/user", getUserInfoHandler).Methods("GET")

	// 静态文件服务（可选）
	router.PathPrefix("/").Handler(http.FileServer(http.Dir("./static/")))

	fmt.Println("JWT Authentication Server starting on :8080")
	fmt.Println("API Endpoints:")
	fmt.Println("  POST /api/v1/login - User login")
	fmt.Println("  POST /api/v1/refresh - Refresh token")
	fmt.Println("  GET  /api/v1/protected/user - Get user info (requires JWT)")
	fmt.Println("\nTest users:")
	fmt.Println("  username: admin, password: admin123")
	fmt.Println("  username: user1, password: user123")

	// 启动服务器
	log.Fatal(http.ListenAndServe(":8080", router))
}
