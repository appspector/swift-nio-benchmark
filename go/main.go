package main

import (
	"fmt"
	"github.com/gorilla/websocket"
	"github.com/kelseyhightower/envconfig"
	"go.uber.org/zap"
	"log"
	"net/http"
	"time"
)

type Frontend struct {
	socket *websocket.Conn
}

func (f Frontend) close() {
	_ = f.socket.WriteControl(websocket.CloseMessage, make([]byte, 0), time.Now().Add(time.Second*5))
	_ = f.socket.Close()
}

type SessionGroup struct {
	socket              *websocket.Conn
	FrontendConnections []Frontend
}

func (sg *SessionGroup) addFrontend(frontend Frontend) {
	sg.FrontendConnections = append(sg.FrontendConnections, frontend)
}

func NewSessionGroup(socket *websocket.Conn) *SessionGroup {
	return &SessionGroup{
		socket:              socket,
		FrontendConnections: make([]Frontend, 0),
	}
}

type Dispatcher struct {
	Sessions   map[string]*SessionGroup
	wsUpgrader websocket.Upgrader
}

func NewDispatcher() *Dispatcher {
	return &Dispatcher{
		wsUpgrader: websocket.Upgrader{
			ReadBufferSize:  1024,
			WriteBufferSize: 1024,
			CheckOrigin: func(r *http.Request) bool {
				return true
			},
		},
		Sessions: make(map[string]*SessionGroup),
	}
}

func (d Dispatcher) start() {

}

func (d Dispatcher) create(w http.ResponseWriter, r *http.Request) {
	socket, err := d.wsUpgrader.Upgrade(w, r, nil)

	if err != nil {
		logger.Errorf("Failed to create session due to websocket upgrade error::", err)
		return
	}
	defer socket.Close()

	sessionId := r.URL.Query().Get("sessionId")

	if len(sessionId) == 0 {
		logger.Errorf("Failed to create session: missing sessionId")
		return
	}

	sessionGroup := NewSessionGroup(socket)

	d.Sessions[sessionId] = sessionGroup

	for {
		messageType, rawMessage, err := socket.ReadMessage()
		if err != nil {
			logger.Infow("Failed to read message:", "sessionId", sessionId, "error", err.Error())
			break
		}

		for _, frontendChannel := range sessionGroup.FrontendConnections {
			err = frontendChannel.socket.WriteMessage(messageType, rawMessage)

			if err != nil {
				logger.Infow("Failed to send message:", "sessionId", sessionId, "error", err.Error())
				break
			}
		}
	}

	delete(d.Sessions, sessionId)
	for _, frontendChannel := range sessionGroup.FrontendConnections {
		frontendChannel.close()
	}
}

func (d Dispatcher) join(w http.ResponseWriter, r *http.Request) {
	socket, err := d.wsUpgrader.Upgrade(w, r, nil)

	if err != nil {
		logger.Errorf("Failed to join session due to websocket upgrade error:", err)
		return
	}
	defer socket.Close()

	sessionId := r.URL.Query().Get("sessionId")

	if len(sessionId) == 0 {
		logger.Errorf("Failed to join session: missing sessionId")
		return
	}

	frontendConnection := Frontend{
		socket: socket,
	}

	sessionGroup := d.Sessions[sessionId]

	if sessionGroup == nil {
		logger.Errorf("Session does not exist", "sessionId", sessionId)
		return
	}

	sessionGroup.addFrontend(frontendConnection)

	for {
		_, _, err = socket.ReadMessage()

		if err != nil {
			break
		}
	}
}

type EnvSpecification struct {
	Port string `required:"true" envconfig:"PORT" default:"3000"`
}

func readConfig() EnvSpecification {
	var config EnvSpecification

	err := envconfig.Process("", &config)
	if err != nil {
		log.Fatal(err.Error())
	}
	return config
}

var baseLogger, _ = zap.NewDevelopment()
var logger = baseLogger.Sugar()

func main() {
	defer baseLogger.Sync()

	config := readConfig()

	dispatcher := NewDispatcher()

	dispatcher.start()

	http.HandleFunc("/create", dispatcher.create)
	http.HandleFunc("/join", dispatcher.join)

	server := &http.Server{
		Addr:         fmt.Sprintf(":%s", config.Port),
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	logger.Debugw("Starting server", "port", config.Port)

	log.Fatal(server.ListenAndServe())
}
