'use strict';

const express = require('express');
const SocketServer = require('ws').Server;
const path = require('path');
const url = require('url');

const PORT = process.env.PORT || 3000;
const INDEX = path.join(__dirname, 'index.html');

const server = express()
  .use((req, res) => res.sendFile(INDEX) )
  .listen(PORT, () => console.log(`Listening on ${ PORT }`));

const wss = new SocketServer({ server });

var rooms = {};
var current_rooms = [];
var users = [];
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

function generateRoles(players)
{
  var roles = {"good": ["Member", "Percival"],
               "evil": ["Minion", "Morgana", "Oberon", "Mordred"]
             };
  var templates = {5: {"Good": 3, "Evil" : 1, "Assassin": 1},
                   6: {"Good": 4, "Evil": 1, "Assassin": 1},
                   7: {"Good": 4, "Evil": 2, "Assassin": 1},
                   8: {"Good": 5, "Evil": 2, "Assassin": 1},
                   9: {"Good": 6, "Evil": 2, "Assassin": 1},
                   10: {"Good": 6, "Evil": 3, "Assassin": 1},
                 };
   var goodCount = templates[players]["Good"] - 1; // Remove 1 for Merlin, who always exists
   var evilCount = templates[players]["Evil"];
   var assassinCount = templates[players]["Assassin"];;

   var acc = [["Merlin", "Good"]]
   for (var i = 1; i < players; i++)
   {
     if(goodCount > 0)
     {
       var index = Math.floor(Math.random() * roles["good"].length);
       var role = roles["good"][index];
       if(index > 0) // Want to keep member around permanently
       {
          roles["good"].splice(index, 1)
       }
       acc[i] = [role, "Good"];
       goodCount--;
     }
     else {
       var index = Math.floor(Math.random() * roles["evil"].length);
       var role = roles["evil"][index];
       if(index > 0) // Want to keep Minion around permanently
       {
         roles["evil"].splice(index, 1)
       }
       var align = "Evil"
       if (assassinCount > 0)
       {
         var flip = Math.floor(Math.random() * (assassinCount + evilCount));
         if(flip == 0 || evilCount == 0)
         {
           align = "Assassin";
           assassinCount--;
         }
         else {
           evilCount--;
         }
       }
       acc[i] = [role, align];
     }
   }
   return acc;
}

function shuffle(a) {
    var j, x, i;
    for (i = a.length; i; i--) {
        j = Math.floor(Math.random() * i);
        x = a[i - 1];
        a[i - 1] = a[j];
        a[j] = x;
    }
    return a
}

wss.on('connection', (ws) => {
  console.log('Client connected');
  var location = url.parse(ws.upgradeReq.url, true)
  var path = location.pathname
  switch (path){
    case "/gen_room":
    ws.on('message', function(msg) {
      var code = "";
      while(code == "" || Object.keys(rooms).indexOf(code) > 1){
        code = randomString(5, '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ')
      }
      ws.send(code)
      rooms[code] = {"users": {}, "roles": false}

      current_rooms.push("/"+code)


      });
      break;
    case "/join_room":
      ws.on('message', function(msg) {
        console.log("JOIN " + msg)
        if(Object.keys(rooms).indexOf(msg) >= 0)
        {
          ws.send('OK')
        }
        else {
          ws.send("Room isn't registered")
        }
      });
      break;
    case "/player_list":
      ws.on("message", function(msg){
        var parsed = JSON.parse(msg)
        console.log(Object.keys(rooms[parsed["room"]]["users"]))
        ws.send(Object.keys(rooms[parsed["room"]]["users"]).join(","))
      });
      break;

    case "/create_roles":
      ws.on("message", function(msg){
      var parsed = JSON.parse(msg)
      if (parsed["maxPlayers"] - Object.keys(rooms[parsed['room']]['users']).length == 0)
      {
        if(!rooms[parsed['room']]['roles']){
          var roles = shuffle(generateRoles(parsed['maxPlayers']))
          console.log("Creating roles")
          var index = 0;
          for(var key in rooms[parsed['room']]["users"]){
            rooms[parsed['room']]['users'][key]['role'] = roles[index];
            index++;
          }
          rooms[parsed['room']]['roles'] = true;
        }
          ws.send("OK")
        }
        else {
          ws.send("NEP")
        }
      });
      break;
    case "/retrieveRole":
      ws.on("message", function(msg){
        var parsed = JSON.parse(msg)
        console.log(Object.keys(rooms[parsed["room"]]["users"]))
        ws.send(rooms[parsed["room"]]["users"][parsed['user']]['role'].join(","))
      });
      break;
    case '/char_info':
      ws.on("message", function(msg){
        var parsed = JSON.parse(msg)
        var role = rooms[parsed['room']]['users'][parsed['user']]['role']

        // Special characters
        var acc = []
        var sent = false
        switch(role[0]){
          case "Merlin":
            for(var key in rooms[parsed['room']]["users"]){
              var char_role = rooms[parsed['room']]['users'][key]['role'];
              if(char_role[1] != "Good" && char_role[0] != "Mordred")
                acc.push(key)
            }
            ws.send("As Merlin, you revealed " + acc.join(", ") + " to be evil");
            break;
          case "Percival":
            for(var key in rooms[parsed['room']]["users"]){
              var char_role = rooms[parsed['room']]['users'][key]['role'];
              if(char_role[0] == "Merlin" || char_role[0] == "Morgana")
                acc.push(key)
            }
            ws.send("As Percival, you revealed " + acc.join(", ") + " to be Merlin");
            break;
        }
        // This case is ignored by our specials above, as their both always good
        // so we can still use acc safely
        if(role[1] != "Good" && role[0] != "Oberon")
        {
          for(var key in rooms[parsed['room']]["users"]){
            var char_role = rooms[parsed['room']]['users'][key]['role'];
            if(char_role[1] != 'Good' && char_role['0'] != "Oberon")
              acc.push(key)
          }
          ws.send("As an evil-doer, you know your fellow evildoers are " + acc.join(', '))
        }
        else if(role[0] == "Member"){
          ws.send("As a member, you have no one revealed! Pay close attention to the conversation to try and get info")
        }
        else if (role[0] == "Oberon")
          ws.send("As Oberon, you don't know who your fellow evil-doers are! Pay close attention to the conversation to try and get info")

        });
        break;
  }

  if(current_rooms.indexOf(path) >= 0){
    var code = path.split("/")[1] // Retrieve the room code
    ws.on('message', function(msg){
      ws.set
        var parsed = JSON.parse(msg)
        if(findObject(ws, rooms[code]) < 0)
        {
          rooms[code]["users"][parsed["name"]] = {"connections": {"chat": ws}};
        }
        for(var key in rooms[code]["users"]){
          rooms[code]["users"][key]["connections"]["chat"].send(parsed["name"] + ": " + parsed["msg"])
        }


      })
  }
  ws.on('close', () => {
    console.log('Client disconnected')
    var dc = []
    for(var code in rooms){
      for(var key in rooms[code]["users"]){
        if(rooms[code]["users"][key]["connections"]["chat"] === ws)
        {
          delete rooms[code]["users"][key];
          dc = [key, code];
        }
      }
    }
    if (dc != [])
    {
      console.log(dc)
      if(Object.keys(rooms[code]["users"]).length == 0 )
      {
        delete rooms[dc[1]];
      }
      else
      {
        for (var key in rooms[dc[1]]["users"])
        {
          rooms[dc[1]]["users"][key]["connections"]["chat"].send(dc[0] + " has connected");
        }
      }
    }
  });
});
