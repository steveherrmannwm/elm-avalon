'use strict';

const express = require('express');
const WebSocket = require('ws');
const SocketServer = require('ws').Server;
const path = require('path');
const url = require('url');

const PORT = process.env.PORT || 3000;
const INDEX = path.join(__dirname, 'index.html');

const server = express()
  .use((req, res) => {
    res.sendFile(INDEX);
    req.setTimeout(60 * 1000 * 20);
  })
  .listen(PORT, () => console.log(`Listening on ${ PORT }`));

const wss = new SocketServer({ server });
console.log(wss);

var rooms = {};
var current_rooms = [];
var users = [];

var quests = {"Bug Investigation" : {"flavor_text": "Someone has to figure out why that one function doesn't work",
                                     "on_success": "Congrats! Your team found the source of the bug",
                                     "on_fail": "Your team failed to resolve this bug. Was it the work of a hacker on the inside"
                                    },
              "Order Pizzas" : {"flavor_text": "Every group needs break-time, but someone has to pay for it",
                                "on_success": "The group happily devours a delicious meal after a session of hard work.",
                                "on_fail": "Somebody ordered pizza with pineapple and mushrooms on it. Now nobody can be happy. Thanks Hackers :/"
                               },
              "Create Unit Tests" : {"flavor_text": "Build the code to the spec, not the spec to code",
                                     "on_success": "Your team built the tests before you coded the application. Way to go!",
                                     "on_fail": "Your team built the tests after coding the application, and now nothing meets the build spec. Clearly the work of some hacker."
                                    },
              "Merge the most recent pull request" : {"flavor_text":"There are few things in live more tedious than resolving a merge conflict",
                                                      "on_success": "A few changes were needed here or there, but the job got successfully finished. Nice job team!",
                                                      "on_fail": "Somebody decided to just force push, and now everything is broken. This must be the work of an enemy hacker."
                                                     },
              "Find deployment solutions" : {"flavor_text": "Programs are only useful to those who can use them.",
                                             "on_success": "Your team managed to find an effective deployment solution to cater to your target audience.",
                                             "on_fail": "The report for this task just says \"It works on my PC.\". Did you assign some hacker to this task?"
                                            }
             }

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

function pickRandomProperty(obj) {
    var result;
    var count = 0;
    for (var prop in obj)
        if (Math.random() < 1/++count)
           result = prop;
    return result;
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

function generateQuest(roundNumber, maxPlayers, questTexts){
  var templates = {5: [{"players": 2, "to_fail": 1},
                       {"players": 3, "to_fail": 1},
                       {"players": 2, "to_fail": 1},
                       {"players": 3, "to_fail": 1},
                       {"players": 3, "to_fail": 1},
                      ],
                   6: [{"players": 2, "to_fail": 1},
                       {"players": 3, "to_fail": 1},
                       {"players": 4, "to_fail": 1},
                       {"players": 3, "to_fail": 1},
                       {"players": 4, "to_fail": 1},
                     ],
                   7: [{"players": 2, "to_fail": 1},
                       {"players": 3, "to_fail": 1},
                       {"players": 3, "to_fail": 1},
                       {"players": 4, "to_fail": 2},
                       {"players": 4, "to_fail": 1},
                      ],
                   8: [{"players": 3, "to_fail": 1},
                       {"players": 4, "to_fail": 1},
                       {"players": 4, "to_fail": 1},
                       {"players": 5, "to_fail": 2},
                       {"players": 5, "to_fail": 1},
                      ],
                   9: [{"players": 3, "to_fail": 1},
                       {"players": 4, "to_fail": 1},
                       {"players": 4, "to_fail": 1},
                       {"players": 5, "to_fail": 2},
                       {"players": 5, "to_fail": 1},
                      ],
                   10: [{"players": 3, "to_fail": 1},
                       {"players": 4, "to_fail": 1},
                       {"players": 4, "to_fail": 1},
                       {"players": 5, "to_fail": 2},
                       {"players": 5, "to_fail": 1},
                      ]
                 };
  var quest_template = templates[maxPlayers][roundNumber];
  var key = pickRandomProperty(questTexts)
  return {"name": key,
          "required_players": quest_template["players"],
          "flavor_text": questTexts[key]["flavor_text"],
          "to_fail": quest_template["to_fail"],
          "on_success": questTexts[key]["on_success"],
          "on_fail": questTexts[key]["on_fail"],
          "votes": {"yesVotes": [], "noVotes": []},
          "approval_count": 0,
          "disapproval_count": 0,
          "times_tried" : 0,
          "players": []
         }
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
  var location = url.parse(ws.upgradeReq.url, true)
  var path = location.pathname
    console.log("WS CONNECTED")
  switch (path){
    case "/gen_room":
    ws.on('message', function(msg) {
      var code = "";
      while(code == "" || Object.keys(rooms).indexOf(code) > 1){
        code = randomString(5, '23456789abcdefghijkmnpqrstuvwxyzABCDEFGHIJKMNPQRSTUVWXYZ') // Took out 0,1,o,l
      }
      console.log("CODE GENERATED")
      console.log(code);
      ws.send(code)
      rooms[code] = {"users": {},
                     "roles": false,
                     "available_quests": Object.assign({}, quests),
                     "create_quest": false,
                     "quest": {"name": "", "required_players": 2, "flavor_text":"",
                               "to_fail": 1, "on_success":"", "on_fail":"", "times_tried": 0,
                               "players": [], "votes" : {"yesVotes": [], "noVotes": []}, "approval_count": 0,
                               "disapproval_count": 0
                              }
                    }
      current_rooms.push("/"+code)
      });
      break;

    case "/join_room":
      ws.on('message', function(msg) {
        var parsed = JSON.parse(msg)
        console.log(parsed)
        console.log(parsed['user'] == '')
        if (parsed['user'] == '')
        {
          ws.send("Illegal username");
        }
        else{


          if(Object.keys(rooms).indexOf(parsed["room"]) >= 0)
          {
            if(Object.keys(rooms[parsed["room"]]["users"]).indexOf(parsed["name"]) >= 0)
            {
              ws.send("Username is taken in this room")
            }
            else
            {
              ws.send('OK')
            }

          }
          else {
            ws.send("Room isn't registered")
          }
        }
      });
      break;
  }

  if(current_rooms.indexOf(path) >= 0){
    console.log(path +" FOUND")
    var code = path.split("/")[1] // Retrieve the room code
    ws.on('message', function(msg){
        var parsed = JSON.parse(msg)


        switch (parsed['function']){
            case "PlayerList":
            var json = {"players": Object.keys(rooms[code]["users"])}
            ws.send(JSON.stringify(json))
            break;

            case "CreateRoles":
            if (parsed["maxPlayers"] - Object.keys(rooms[code]['users']).length == 0)
            {
                if(!rooms[code]['roles']){
                  var roles = shuffle(generateRoles(parsed['maxPlayers']))
                  console.log("Creating roles")
                  var index = 0;
                  for(var key in rooms[code]["users"]){
                    rooms[code]['users'][key]['role'] = roles[index];
                    index++;
                  }
                rooms[code]['roles'] = true;
                }
              ws.send("OK")
            }
            else {
              ws.send("NEP")
            }
            break;

            case "RetrieveRole":
                console.log("Retrieving a role")
                console.log(rooms[code]['users'])
                ws.send(rooms[code]["users"][parsed['user']]['role'].join(","))
                break;
            case 'CharInfo':
            var role = rooms[code]['users'][parsed['user']]['role']

            console.log(rooms[code])
            // Special characters
            var acc = []
            var sent = false
            switch(role[0]){
              case "Merlin":
                for(var key in rooms[code]["users"]){
                  var char_role = rooms[code]['users'][key]['role'];
                  if(char_role[1] != "Good" && char_role[0] != "Mordred")
                    acc.push(key)
                }
                ws.send("As the SysAdmin, you revealed " + acc.join(", ") + " to be evil");
                break;
              case "Percival":
                for(var key in rooms[code]["users"]){
                  var char_role = rooms[code]['users'][key]['role'];
                  if(char_role[0] == "Merlin" || char_role[0] == "Morgana")
                    acc.push(key)
                }
                ws.send("As the Manager, you revealed " + acc.join(", ") + " to be the SysAdmin");
                break;
            }
            // This case is ignored by our specials above, as their both always good
            // so we can still use acc safely
            if(role[1] != "Good" && role[0] != "Oberon")
            {
              for(var key in rooms[code]["users"]){
                var char_role = rooms[code]['users'][key]['role'];
                if(char_role[1] != 'Good' && char_role['0'] != "Oberon")
                  acc.push(key)
              }
              ws.send("As a hacker, you know your fellow hackers are " + acc.join(', '))
            }
            else if(role[0] == "Member"){
              ws.send("As a programmer, you have no one revealed! Pay close attention to the conversation to try and get info")
            }
            else if (role[0] == "Oberon")
              ws.send("As the lone wolf, you don't know who the other hackers are! Pay close attention to the conversation to try and get info")
            break;

            case "GenerateQuest":
              console.log("GENERATING A QUEST")
              if(!rooms[code]['create_quest']){
                rooms[code]['create_quest'] = true;
                if(Object.keys(rooms[code]['available_quests']).length == 0){
                  var quest = {"name": "", "required_players": 2, "flavor_text":"",
                          "to_fail": 1, "on_success":"", "on_fail":"", "times_tried": 0,
                          "players": [], "votes" : {"yesVotes": [], "noVotes": []}, "approval_count": 0,
                          "disapproval_count": 0}
                }
                else{
                  var quest = generateQuest(parsed['roundNumber'], parsed['maxPlayers'], room[code]['available_quests'])
                }
                rooms[code]['quest'] = quest

                delete rooms[code]['available_quests'][quest['name']] // Prevent the same quest from being selected
              }
              ws.send("OK")
            break;

            case "RetrieveQuest":
              var clientQuest = {"name": rooms[code]["quest"]["name"],
                                 "required_players": rooms[code]["quest"]["required_players"],
                                 "flavor_text":rooms[code]["quest"]["flavor_text"],
                                 "votes": {"yesVotes":[], "noVotes": []},
                                 "to_fail": rooms[code]["quest"]["to_fail"],
                                 "times_tried": rooms[code]["quest"]["times_tried"],
                                 "players": rooms[code]["quest"]["players"]
                               }
              ws.send(JSON.stringify(clientQuest))
            break;

            case "SetQuestMembers":
              console.log("SETTING QUEST MEMBERS")
              console.log("THIS IS THE ROOMS:")
              console.log(rooms)
              console.log(parsed)
              if (parsed["user"])
              {
                ws.send("registered")
              }
              else{
                rooms[code]['quest']['players'] = parsed['players'];
                var clientQuest = {"name": rooms[code]["quest"]["name"],
                                   "required_players": rooms[code]["quest"]["required_players"],
                                   "flavor_text":rooms[code]["quest"]["flavor_text"],
                                   "votes": {"yesVotes":[], "noVotes": []},
                                   "to_fail": rooms[code]["quest"]["to_fail"],
                                   "times_tried": rooms[code]["quest"]["times_tried"],
                                   "players": rooms[code]["quest"]["players"]
                                 }
                for(var key in rooms[code]["users"]){
                  if(rooms[code]["users"][key]["connection"].readyState == WebSocket.OPEN){
                    rooms[code]["users"][key]["connection"].send(JSON.stringify(clientQuest));
                  }
                }
              }
            break;

            case "ReceiveVotes":
              try{
                  rooms[code]['users'][parsed['user']]['connection'] = ws;
                  // Make sure the user hasn't already voted
                  if(rooms[code]['quest']['votes']['yesVotes'].indexOf(parsed['user']) < 0 &&
                     rooms[code]['quest']['votes']['noVotes'].indexOf(parsed['user']) < 0){
                    if (parsed['vote'] == 'Yes' || parsed['vote'] == 'No')
                    {
                      if (parsed['vote'] == 'Yes')
                        rooms[code]['quest']['votes']['yesVotes'].push(parsed['user']);
                      else
                        rooms[code]['quest']['votes']['noVotes'].push(parsed['user']);
                      if (rooms[code]['quest']['votes']['noVotes'].length + rooms[code]['quest']['votes']['yesVotes'].length == Object.keys(rooms[code]['users']).length)
                      {
                        if (rooms[code]['quest']['votes']['noVotes'].length >= rooms[code]['quest']['votes']['yesVotes'].length)
                        {
                            var clientQuest = {"name": rooms[code]["quest"]["name"],
                                           "required_players": rooms[code]["quest"]["required_players"],
                                           "flavor_text":rooms[code]["quest"]["flavor_text"],
                                           "votes": rooms[code]['quest']['votes'],
                                           "to_fail": rooms[code]["quest"]["to_fail"],
                                           "times_tried": rooms[code]["quest"]["times_tried"]+1,
                                           "players": []
                                         };
                        }
                        else {
                          var clientQuest = {"name": rooms[code]["quest"]["name"],
                                         "required_players": rooms[code]["quest"]["required_players"],
                                         "flavor_text":rooms[code]["quest"]["flavor_text"],
                                         "votes": rooms[code]['quest']['votes'],
                                         "to_fail": rooms[code]["quest"]["to_fail"],
                                         "times_tried": rooms[code]["quest"]["times_tried"],
                                         "players": rooms[code]["quest"]["players"]
                                       };
                        }

                        for(var key in rooms[code]["users"]){
                          if(rooms[code]["users"][key]["connection"].readyState === WebSocket.OPEN){
                            rooms[code]["users"][key]["connection"].send(JSON.stringify(clientQuest));
                          }
                        }
                        rooms[code]['create_quest'] = false
                        if(rooms[code]['quest']['votes']['noVotes'].length >= rooms[code]['quest']['votes']['yesVotes'].length)
                        {
                            rooms[code]['quest']['times_tried'] += 1;
                            rooms[code]['quest']['votes']['noVotes'] = []
                            rooms[code]['quest']['votes']['yesVotes'] = []

                        }
                      }
                      else {
                        ws.send("Vote received");
                      }
                    }
                    else{
                      ws.send("An error occurred")
                    }

                }
                else{
                  ws.send("You've already voted")
                }
              }
              catch (e){
                  ws.send("An error occurred, please restart the game");
                  console.log(e)
              }
            break;
            case "TaskApproval":
              try{
                var parsed = JSON.parse(msg);
                if(parsed['vote'])
                {
                  if(parsed['vote'] == 'Approve')
                    rooms[code]['quest']['approval_count'] += 1;
                  else if(parsed['vote'] == 'Disapprove')
                    rooms[code]['quest']['disapproval_count'] += 1;
                  console.log(rooms[code]['quest'])
                  if(rooms[code]['quest']['disapproval_count'] + rooms[code]['quest']['approval_count'] == rooms[code]['quest']['required_players'])
                  {
                    var toReturn = {
                                    "text":rooms[code]['quest']['on_success'],
                                    "approves": rooms[code]['quest']['approval_count'],
                                    "disapproves": rooms[code]['quest']['disapproval_count'],
                                    "status": "success"
                                   }
                    if(rooms[code]['quest']['disapproval_count'] >= rooms[code]['quest']['to_fail'])
                    {
                      toReturn["text"] = rooms[code]['quest']['on_fail'];
                      toReturn["status"] = "fail";
                    }
                    for(var key in rooms[code]["users"]){
                      if(rooms[code]["users"][key]["connection"].readyState === WebSocket.OPEN){
                        rooms[code]["users"][key]["connection"].send(JSON.stringify(toReturn));
                      }
                    }
                  }
                  else {
                    ws.send("Action received");
                  }
                }
                else {
                  ws.send("Registered");
                }
              }
              catch (e)
              {
                console.log(e)
                ws.send("An error occurred, please restart the game");
              }
            break;
        case "":
            if(findObject(ws, rooms[code]) < 0)
            {
              rooms[code]["users"][parsed["name"]] = {"connection": ws};
            }
            var message = parsed

            for(var key in rooms[code]["users"]){
              if(rooms[code]["users"][key]["connection"].readyState === WebSocket.OPEN){
                rooms[code]["users"][key]["connection"].send(JSON.stringify(parsed))
              }
            }
            break;

        }

    })
  }
  /*ws.on('close', function (code, reason)  {
    console.log('Client disconnected')
    console.log(code);
    console.log(reason);
    var dc = null
    for(var code in rooms){
      for(var key in rooms[code]["users"]){
        if(rooms[code]["users"][key]["connections"]["chat"] === ws)
        {
          console.log("Deleting " + key)
          delete rooms[code]["users"][key];
          dc = [key, code];
        }
      }
    }
    if (dc != null)
    {
      if(Object.keys(rooms[code]["users"]).length == 0 )
      {
        delete rooms[dc[1]];
        current_rooms.splice(current_rooms.indexOf(dc[1]), 1);
      }
      else
      {
        for (var key in rooms[dc[1]]["users"])
        {
          rooms[dc[1]]["users"][key]["connections"]["chat"].send(dc[0] + " has disconnected");
        }
      }
    }
  });*/
});
