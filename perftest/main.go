package main

import (
	"fmt"
	"github.com/gorilla/websocket"
	"github.com/kelseyhightower/envconfig"
	"go.uber.org/zap"
	"log"
	"net/url"
	"os"
	"os/signal"
	"time"
)

type EnvSpecification struct {
	Host string `required:"true" envconfig:"HOST" default:"0.0.0.0:3000"`
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

type SessionConfig struct {
	host      string
	sessionId int
}

func startProducer(config SessionConfig) {
	u := url.URL{
		Scheme:   "ws",
		Host:     config.host,
		Path:     "/create",
		RawQuery: fmt.Sprintf("sessionId=%d", config.sessionId),
	}
	log.Printf("connecting to %s", u.String())

	c, _, err := websocket.DefaultDialer.Dial(u.String(), nil)
	if err != nil {
		log.Fatal("dial:", err)
		return
	}
	defer c.Close()

	done := make(chan struct{})

	go func() {
		defer close(done)
		for {
			_, message, err := c.ReadMessage()
			if err != nil {
				log.Println("read:", err)
				return
			}
			log.Printf("recv: %s", message)
		}
	}()

	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-done:
			return
		case t := <-ticker.C:
			err := c.WriteMessage(websocket.TextMessage, []byte(t.String()))
			if err != nil {
				log.Println("write:", err)
				return
			}
		}
	}
}

func main() {
	defer baseLogger.Sync()

	config := readConfig()

	interrupt := make(chan os.Signal, 1)
	signal.Notify(interrupt, os.Interrupt)

	for i := 0; i < 10000; i++ {
		time.Sleep(time.Millisecond * 10)
		go startProducer(SessionConfig{
			host:      config.Host,
			sessionId: i,
		})
	}

	<-interrupt
}
