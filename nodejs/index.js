const WebSocket = require('ws');
const url = require('url');

const wss = new WebSocket.Server({port: 3000});

const sessions = {};

wss.on('connection', function connection(ws, req) {
  const uri = url.parse(req.url, true);

  const path = uri.pathname;
  const sessionId = uri.query["sessionId"];

  if (!sessionId) {
    ws.close();
    return
  }

  switch (path) {
    case "/create": {

      sessions[sessionId] = [];

      ws.on('message', function incoming(message) {
        for (let frontendWS of sessions[sessionId]) {
          frontendWS.send(message);
        }
      });

      ws.on('close', function incoming() {
        for (let frontendWS of sessions[sessionId]) {
          frontendWS.close();
        }

        sessions[sessionId] = null;
        delete sessions[sessionId];
      });

    }
      break;
    case "/join": {
      const sessionGroup = sessions[sessionId];

      if (sessionGroup) {
        sessionGroup.push(ws);
      } else {
        ws.close();
        return
      }

      ws.on('close', function incoming() {
        if (sessions[sessionId]) {
          sessions[sessionId] = sessions[sessionId].filter((socket) => {
            return socket !== ws;
          })
        }
      });

    }
      break;
    default: {
      ws.close();
    }
  }
});