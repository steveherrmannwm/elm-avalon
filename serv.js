const WebSocket = require('ws');

const wss = new WebSocket.Server({ port: 8080 });

var rooms = {}

//TODO: Figure out a more scalable solution to this issue
wss.on('connection', function connection(ws) {
  //console.log(ws)
  var roomCode = ws.upgradeReq.url

  if(rooms[roomCode] == undefined){
    rooms[roomCode] = [ws]
  }
  else {
    rooms[roomCode].push(ws)
  }

  ws.on('message', function incoming(message) {
    for(var i = 0; i < rooms[roomCode].length; i++)
    {
      if(rooms[roomCode][i].readyState == WebSocket.OPEN)
        rooms[roomCode][i].send(message);
    }
  });
});
