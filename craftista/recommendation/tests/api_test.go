package tests

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"

	"recommendation/api"
)

// Проверяем, что обработчик "оригами дня" отвечает 200 и возвращает JSON с названием.
func TestOrigamiOfTheDay(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.GET("/api/origami-of-the-day", api.GetOrigamiOfTheDay)

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/api/origami-of-the-day", nil)
	router.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("ожидался статус 200, получен %d", rec.Code)
	}

	var body map[string]interface{}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("ответ не является JSON-объектом: %v", err)
	}
	if name, ok := body["name"].(string); !ok || name == "" {
		t.Fatalf("в ответе нет поля name: %v", body)
	}
}
