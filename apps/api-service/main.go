package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"time"

	_ "github.com/lib/pq"
)

// connInfo mirrors the JSON written by modules/cloudsql to the
// `<prefix>-db-connection` Secret Manager entry. Apps read the secret as a
// single env var (DB_CONNECTION) instead of templating the private IP into
// deploy.yaml — IP changes when the instance is recreated, and Secret Manager
// gives us a stable indirection.
type connInfo struct {
	Host   string `json:"host"`
	Port   int    `json:"port"`
	DBName string `json:"db_name"`
	DBUser string `json:"db_user"`
}

type Server struct {
	db *sql.DB
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	db, err := connectDB()
	if err != nil {
		fmt.Fprintln(os.Stderr, "db connect:", err)
		os.Exit(1)
	}
	defer db.Close()

	s := &Server{db: db}
	mux := http.NewServeMux()
	mux.HandleFunc("/", s.handleRoot)
	mux.HandleFunc("/health", s.handleHealth)
	mux.HandleFunc("/items", s.handleItems)

	fmt.Printf("api-service listening on :%s\n", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func connectDB() (*sql.DB, error) {
	if dsn := os.Getenv("DATABASE_URL"); dsn != "" {
		return openAndPing(dsn)
	}

	host, port, dbName, dbUser, err := resolveConnTarget()
	if err != nil {
		return nil, err
	}
	password := os.Getenv("DB_PASSWORD")

	// sslmode=require: Cloud SQL is configured with ssl_mode=ENCRYPTED_ONLY
	// (see modules/cloudsql/main.tf) so plaintext connections are rejected
	// by the server. For verify-ca/verify-full, fetch the server CA via
	// google_sql_ssl_cert and mount it as a Secret — tracked in
	// README → Future Work.
	dsn := fmt.Sprintf(
		"host=%s port=%d user=%s password=%s dbname=%s sslmode=require",
		host, port, dbUser, password, dbName,
	)
	return openAndPing(dsn)
}

func resolveConnTarget() (host string, port int, dbName, dbUser string, err error) {
	// Preferred: DB_CONNECTION holds the JSON blob from Secret Manager.
	if blob := os.Getenv("DB_CONNECTION"); blob != "" {
		var c connInfo
		if jerr := json.Unmarshal([]byte(blob), &c); jerr != nil {
			return "", 0, "", "", fmt.Errorf("DB_CONNECTION json: %w", jerr)
		}
		if c.Port == 0 {
			c.Port = 5432
		}
		return c.Host, c.Port, c.DBName, c.DBUser, nil
	}
	// Fallback: individual env vars, useful for local development against a
	// docker-compose Postgres without Secret Manager in the loop.
	host = os.Getenv("DB_HOST")
	if host == "" {
		host = "localhost"
	}
	return host, 5432, os.Getenv("DB_NAME"), os.Getenv("DB_USER"), nil
}

func openAndPing(dsn string) (*sql.DB, error) {
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(10)
	db.SetConnMaxLifetime(time.Minute)
	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("ping: %w", err)
	}
	return db, nil
}

func (s *Server) handleRoot(w http.ResponseWriter, r *http.Request) {
	fmt.Fprintln(w, "api-service")
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if err := s.db.Ping(); err != nil {
		http.Error(w, "db unhealthy: "+err.Error(), http.StatusServiceUnavailable)
		return
	}
	w.WriteHeader(http.StatusOK)
	fmt.Fprintln(w, "ok")
}

func (s *Server) handleItems(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	rows, err := s.db.QueryContext(r.Context(), "SELECT id, name, created_at FROM items ORDER BY id LIMIT 20")
	if err != nil {
		http.Error(w, "query error: "+err.Error(), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	type Item struct {
		ID        int       `json:"id"`
		Name      string    `json:"name"`
		CreatedAt time.Time `json:"created_at"`
	}
	var items []Item
	for rows.Next() {
		var item Item
		if err := rows.Scan(&item.ID, &item.Name, &item.CreatedAt); err != nil {
			http.Error(w, "scan error: "+err.Error(), http.StatusInternalServerError)
			return
		}
		items = append(items, item)
	}
	if err := rows.Err(); err != nil {
		http.Error(w, "query error: "+err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(items)
}
