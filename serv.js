var express = require('express');
var app = express();
var expressWs = require('express-ws')(app);

var rooms = {};

function randomString(length, chars) {
    var result = '';
    for (var i = length; i > 0; --i) result += chars[Math.floor(Math.random() * chars.length)];
    return result;
}

function findObject(obj, list) {
    var i;
    for (i = 0; i < list.length; i++) {
        if (list[i] === obj) {
            return i;
        }
    }

    return -1;
}

app.use(function (req, res, next) {
  req.testing = 'testing';
  return next();
});


app.ws('/gen_room', function(ws, req) {
  ws.on('message', function(msg) {
    var code = "";
    while(code == "" || Object.keys(rooms).indexOf(code) > 1){
      code = randomString(5, '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ')
    }
    ws.send(code)
    rooms[code] = []
    console.log("GEN " + code)

    app.ws('/' + code, function(ws, req) {
      ws.on('message', function(msg){
          if(findObject(ws, rooms[code]) < 0)
          {
            rooms[code].push(ws)
          }
          for(var i = 0; i < rooms[code].length; i++){
            rooms[code][i].send(msg)
          }
        })
      ws.on('close', function(){
        // Remove the connection from the list, and broadcast a message to other clients
        rooms[code].splice(findObject(ws, rooms[code]), 1)
        for(var i = 0; i < rooms[code].length; i++){
          rooms[code][i].send("A user disconnected")
        }
      })
      })
  });
});

app.ws('/join_room', function(ws, req){
  ws.on('message', function(msg) {
    console.log("JOIN " + msg)
    if(Object.keys(rooms).indexOf(msg) >= 0)
    {
      ws.send('OK')
    }
    else {
      ws.send("Room isn't registered")
    }
  })
})


app.ws('/echo', function(ws, req) {
  ws.on('message', function(msg) {
    console.log(msg);
    ws.send(msg)
  });
  console.log('socket', req.testing);
});

app.listen(8080);
