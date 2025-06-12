package main

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"

	"os"

	"github.com/gin-gonic/gin"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
	"gopkg.in/yaml.v3"
)

// 配置结构体
type Config struct {
	Google struct {
		ClientID     string `yaml:"client_id"`
		ClientSecret string `yaml:"client_secret"`
	} `yaml:"google"`
}

// 全局配置变量
var config Config

// Google OAuth2 配置
var googleOauthConfig *oauth2.Config

// 用户信息结构体
type GoogleUser struct {
	ID            string `json:"id"`
	Email         string `json:"email"`
	VerifiedEmail bool   `json:"verified_email"`
	Name          string `json:"name"`
	GivenName     string `json:"given_name"`
	FamilyName    string `json:"family_name"`
	Picture       string `json:"picture"`
	Locale        string `json:"locale"`
}

// 会话存储（生产环境应该使用Redis或数据库）
var sessions = make(map[string]GoogleUser)

// 生成随机状态字符串（防止CSRF攻击）
func generateStateOauthCookie() string {
	b := make([]byte, 16)
	rand.Read(b)
	return base64.URLEncoding.EncodeToString(b)
}

// 主页处理器
func indexHandler(c *gin.Context) {
	// 检查是否已登录
	sessionID, err := c.Cookie("session_id")
	if err == nil {
		if user, exists := sessions[sessionID]; exists {
			// 已登录，显示用户信息
			c.HTML(http.StatusOK, "profile.html", gin.H{
				"User": user,
			})
			return
		}
	}

	// 未登录，显示登录页面
	c.HTML(http.StatusOK, "index.html", gin.H{
		"Title": "Google OAuth2 Demo",
	})
}

// Google登录处理器
func googleLoginHandler(c *gin.Context) {
	// 生成状态参数防止CSRF攻击
	oauthState := generateStateOauthCookie()

	// 设置状态cookie
	c.SetCookie("oauthstate", oauthState, 3600, "/", "localhost", false, true)

	// 重定向到Google授权页面
	url := googleOauthConfig.AuthCodeURL(oauthState, oauth2.AccessTypeOffline)
	c.Redirect(http.StatusTemporaryRedirect, url)
}

// Google回调处理器
func googleCallbackHandler(c *gin.Context) {
	// 验证状态参数
	oauthState, _ := c.Cookie("oauthstate")
	if c.Query("state") != oauthState {
		log.Println("Invalid oauth google state")
		c.Redirect(http.StatusTemporaryRedirect, "/")
		return
	}

	// 获取授权码
	code := c.Query("code")
	if code == "" {
		log.Println("Code not found")
		c.JSON(http.StatusBadRequest, gin.H{"error": "Code not found"})
		return
	}

	// 用授权码换取token
	token, err := googleOauthConfig.Exchange(context.Background(), code)
	if err != nil {
		log.Printf("oauthConfig.Exchange() failed: %s", err.Error())
		c.Redirect(http.StatusTemporaryRedirect, "/")
		return
	}

	// 用token获取用户信息
	user, err := getUserInfoFromGoogle(token.AccessToken)
	if err != nil {
		log.Printf("Failed to get user info: %s", err.Error())
		c.Redirect(http.StatusTemporaryRedirect, "/")
		return
	}

	// 生成会话ID
	sessionID := generateStateOauthCookie()

	// 存储用户信息到会话
	sessions[sessionID] = *user

	// 设置会话cookie
	c.SetCookie("session_id", sessionID, 86400, "/", "localhost", false, true) // 24小时

	// 重定向到首页
	c.Redirect(http.StatusTemporaryRedirect, "/")
}

// 从Google获取用户信息
func getUserInfoFromGoogle(accessToken string) (*GoogleUser, error) {
	// 调用Google API获取用户信息
	response, err := http.Get("https://www.googleapis.com/oauth2/v2/userinfo?access_token=" + accessToken)
	if err != nil {
		return nil, fmt.Errorf("failed getting user info: %s", err.Error())
	}
	defer response.Body.Close()

	// 读取响应
	contents, err := io.ReadAll(response.Body)
	if err != nil {
		return nil, fmt.Errorf("failed reading response body: %s", err.Error())
	}

	// 解析JSON
	var user GoogleUser
	if err := json.Unmarshal(contents, &user); err != nil {
		return nil, fmt.Errorf("failed parsing user info: %s", err.Error())
	}

	return &user, nil
}

// 登出处理器
func logoutHandler(c *gin.Context) {
	// 获取会话ID
	sessionID, err := c.Cookie("session_id")
	if err == nil {
		// 删除会话
		delete(sessions, sessionID)
	}

	// 清除cookies
	c.SetCookie("session_id", "", -1, "/", "localhost", false, true)
	c.SetCookie("oauthstate", "", -1, "/", "localhost", false, true)

	// 重定向到首页
	c.Redirect(http.StatusTemporaryRedirect, "/")
}

// API: 获取当前用户信息
func apiUserHandler(c *gin.Context) {
	sessionID, err := c.Cookie("session_id")
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Not logged in"})
		return
	}

	if user, exists := sessions[sessionID]; exists {
		c.JSON(http.StatusOK, gin.H{
			"success": true,
			"user":    user,
		})
	} else {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid session"})
	}
}

// 加载配置文件
func loadConfig() error {
	data, err := os.ReadFile("config.yaml")
	if err != nil {
		return fmt.Errorf("failed to read config.yaml: %v", err)
	}

	err = yaml.Unmarshal(data, &config)
	if err != nil {
		return fmt.Errorf("failed to parse config.yaml: %v", err)
	}

	return nil
}

// 初始化OAuth2配置
func initOAuth2Config() {
	googleOauthConfig = &oauth2.Config{
		RedirectURL:  "http://localhost:8080/auth/google/callback",
		ClientID:     config.Google.ClientID,
		ClientSecret: config.Google.ClientSecret,
		Scopes: []string{
			"https://www.googleapis.com/auth/userinfo.email",
			"https://www.googleapis.com/auth/userinfo.profile",
		},
		Endpoint: google.Endpoint,
	}
}

// 检查OAuth2配置
func checkConfig() {
	if config.Google.ClientID == "" {
		log.Fatal("❌ Google Client ID not configured in config.yaml")
	}
	if config.Google.ClientSecret == "" {
		log.Fatal("❌ Google Client Secret not configured in config.yaml")
	}
	log.Println("✅ Google OAuth2 configuration loaded from config.yaml")
}

func main() {
	// 加载配置文件
	if err := loadConfig(); err != nil {
		log.Fatalf("❌ Failed to load configuration: %v", err)
	}

	// 初始化OAuth2配置
	initOAuth2Config()

	// 检查配置
	checkConfig()

	// 创建Gin实例
	r := gin.Default()

	// 加载HTML模板
	r.LoadHTMLGlob("templates/*")

	// 静态文件服务
	r.Static("/static", "./static")

	// 路由设置
	r.GET("/", indexHandler)
	r.GET("/login/google", googleLoginHandler)
	r.GET("/auth/google/callback", googleCallbackHandler)
	r.GET("/logout", logoutHandler)

	// API路由
	api := r.Group("/api")
	{
		api.GET("/user", apiUserHandler)
	}

	// 启动信息
	fmt.Println("🚀 Google OAuth2 Demo Server Starting...")
	fmt.Println("📍 Server: http://localhost:8080")
	fmt.Println("🔑 Google Login: http://localhost:8080/login/google")
	fmt.Println("📱 API Endpoint: http://localhost:8080/api/user")
	fmt.Println("\n⚠️  请确保已配置 config.yaml 文件:")
	fmt.Println("   请查看 config.yaml 文件设置 Google OAuth2 credentials")

	// 启动服务器
	log.Fatal(r.Run(":8080"))
}
