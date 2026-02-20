package turn

import (
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"fmt"
	"time"

	"github.com/gofrs/uuid"
)

type Credentials struct {
	Username string   `json:"username"`
	Password string   `json:"password"`
	TTL      int64    `json:"ttl"`
	URLs     []string `json:"urls"`
}

type Generator struct {
	staticURL  string
	staticUser string
	staticPass string
	secretKey  []byte
}

func New() *Generator {
	secret := uuid.Must(uuid.NewV4()).String()
	return &Generator{
		secretKey: []byte(secret),
	}
}

func (g *Generator) SetStaticTURN(url, username, password string) {
	g.staticURL = url
	g.staticUser = username
	g.staticPass = password
}

func (g *Generator) GenerateCredentials(username, password string) Credentials {
	if g.staticURL != "" {
		return Credentials{
			Username: g.staticUser,
			Password: g.staticPass,
			TTL:      86400,
			URLs:     []string{g.staticURL},
		}
	}

	creds := g.generateTOTPCredentials(username)
	creds.URLs = []string{
		"stun:stun.l.google.com:19302",
		"stun:stun1.l.google.com:19302",
	}

	return creds
}

func (g *Generator) generateTOTPCredentials(username string) Credentials {
	now := time.Now()
	ttl := int64(86400)

	expiry := now.Unix() + ttl
	username = fmt.Sprintf("%d:%s", expiry, username)

	password := g.generatePassword(username, now)

	return Credentials{
		Username: username,
		Password: password,
		TTL:      ttl,
	}
}

func (g *Generator) generatePassword(username string, t time.Time) string {
	key := g.secretKey
	hmacGenerator := hmac.New(sha1.New, key)
	hmacGenerator.Write([]byte(username))

	hash := hmacGenerator.Sum(nil)
	return base64.StdEncoding.EncodeToString(hash)
}

func (g *Generator) GenerateCloudflareCredentials(username string) Credentials {
	now := time.Now()
	expiry := now.Add(24 * time.Hour).Unix()

	username = fmt.Sprintf("%d:%s", expiry, username)

	secret := []byte(g.staticPass)
	hmacGenerator := hmac.New(sha1.New, secret)
	hmacGenerator.Write([]byte(username))
	hash := hmacGenerator.Sum(nil)
	password := base64.StdEncoding.EncodeToString(hash)

	return Credentials{
		Username: username,
		Password: password,
		TTL:      86400,
		URLs:     []string{g.staticURL},
	}
}
