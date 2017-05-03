module Index exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Json.Encode exposing (..)
import Json.Decode exposing (map, decodeValue)
import Html.Events.Extra exposing (targetValueIntParse)
import WebSocket
import List.Extra exposing (..)


main =
  Html.program
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }

wsServer : String
wsServer =
  "wss://elm-avalon.herokuapp.com/"

roomGen : String
roomGen = wsServer++"gen_room"

joinRoom : String
joinRoom = wsServer++"join_room"

playerList : String
playerList = wsServer++"player_list"

createRoles : String
createRoles = wsServer++"create_roles"

retrieveRole : String
retrieveRole = wsServer++"retrieve_role"

charInfo : String
charInfo = wsServer++"char_info"

setQuestMembers : String
setQuestMembers = wsServer++"set_quest_members"

generateQuest : String
generateQuest = wsServer++"generate_quest"

retrieveQuest : String
retrieveQuest = wsServer++"retrieve_quest"

receiveQuestTeam : String
receiveQuestTeam = wsServer++"retrieve_quest_members"

sendVotes : String
sendVotes = wsServer++"receive_votes"

taskApproval : String
taskApproval = wsServer++"task_approval"
-- Type definitions

-- Define possible roles for players
-- TODO: Come up with original names for these roles
type Role
  = Merlin
  | Member
  | Minion
  | Percival
  | Morgana
  | Oberon
  | Mordred
  | Unassigned

type Alignment
  = Good
  | Evil
  | Assassin
  | Unaligned

type GameState
  = Home
  | Setup
  | TeamBuild
  | Vote
  | Wait
  | Decide
  | Final
  | Victory

type alias Player =
  { name : String
  , role : Role
  , alignment: Alignment
  }

type alias Quest =
  { name: String
  , playersRequired : Int
  , players : List String
  , yesVotes : List String
  , noVotes : List String
  , flavorText : String
  , timesTried: Int
  , toFail: Int
  }

type alias Task =
  { text: String
  , approveVotes: Int
  , disapproveVotes: Int
  , status: String
  }

-- MODEL

type alias Model =
  { user : Player
  , room : String
  , maxPlayers : Int
  , currentPlayers : List String -- Only contains usernames to not give away roles
  , chatBox : String
  , chatMessages : List String
  , state : GameState
  , leaderPosition : Int
  , currentRound : Int
  , evilVictories : Int
  , revealedInfo : String
  , quest : Quest
  , previousGroup: List String
  , lastTaskResult: Task
  , errors : String
  , victory: String
  }


model : Model
model =
  Model (Player "" Unassigned Unaligned) "" 5 [] "" [] Home 0 0 0 "" (Quest "" 2 [] [] [] "" 0 2) [] (Task "" 0 0 "") "" ""

-- INIT

init : (Model, Cmd Msg)
init =
  (model, Cmd.none)

-- UPDATE

type Msg
    = Name String
    | RoomCode String
    | JoinRoom String
    | SetMaxPlayers Int
    | PlayerList String
    | CreateRoles String
    | RetrieveRole String
    | GenRoomCode
    | GenRoom String
    | GenerateQuest String
    | RetrieveQuest String
    | SetRoom
    | Input String
    | Send
    | UpdateQuestTeam String
    | ReceiveQuestTeam String
    | SubmitQuestTeam
    | NewMessage String
    | CharInfo String
    | VoteForTeam String
    | ReceiveVotes String
    | ApproveTask
    | SabotageTask
    | ReceiveTask String
    | SetAssassinateTarget String


questDecoder : Json.Decode.Decoder Quest
questDecoder =
  Json.Decode.map8
    Quest
    (Json.Decode.at ["name"] Json.Decode.string)
    (Json.Decode.at ["required_players"] Json.Decode.int)
    (Json.Decode.at ["players"] (Json.Decode.list Json.Decode.string))
    (Json.Decode.at ["votes"] (Json.Decode.at ["yesVotes"] (Json.Decode.list Json.Decode.string)))
    (Json.Decode.at ["votes"] (Json.Decode.at ["noVotes"] (Json.Decode.list Json.Decode.string)))
    (Json.Decode.at ["flavor_text"] Json.Decode.string)
    (Json.Decode.at ["times_tried"] Json.Decode.int)
    (Json.Decode.at ["to_fail"] Json.Decode.int)

taskDecoder : Json.Decode.Decoder Task
taskDecoder =
  Json.Decode.map4
    Task
    (Json.Decode.at ["text"] Json.Decode.string)
    (Json.Decode.at ["approves"] Json.Decode.int)
    (Json.Decode.at ["disapproves"] Json.Decode.int)
    (Json.Decode.at ["status"] Json.Decode.string)

checkTaskDecoder : Result String Task -> Task
checkTaskDecoder decoded =
  case decoded of
    Ok task ->
      task
    Err err ->
      (Task "" 0 0 "")

checkVictoryConditions : Model -> Model
checkVictoryConditions model =
  if model.evilVictories >= 3 then
    {model | state = Victory, victory = "The hackers have managed destroy the project. Hackers victory"}
  else if model.quest.timesTried >= 5 then
    {model | state = Victory, victory = "The hackers have sufficently delayed the project. Hackers Win."}
  else
    model


updateModelOnTask : Model -> Model
updateModelOnTask model =
  if model.lastTaskResult.status == "fail" then
    checkVictoryConditions {model | evilVictories = model.evilVictories + 1}
  else
    checkVictoryConditions model

checkQuestDecoder : Result String Quest -> Model -> Model
checkQuestDecoder decoded model=
  case decoded of
    Ok quest ->
      {model | quest = quest}

    Err err->
      {model | errors = err}

checkQuestVotes : Model -> Model
checkQuestVotes model =
  if List.length model.quest.noVotes >= List.length model.quest.yesVotes then
    checkVictoryConditions {model | state = TeamBuild}
  else
    checkVictoryConditions {model | state = Decide}

getListPosition: List String -> Int -> String
getListPosition list index =
  (checkList (List.head (List.drop index list)))

checkList : Maybe String -> String
checkList str =
  case str of
    Just string -> string
    Nothing -> ""

readAlign : String -> Alignment
readAlign str =
  case str of
    "Good" -> Good
    "Evil" -> Evil
    "Assassin" -> Assassin
    _ -> Unaligned

readRole : String -> Role
readRole str =
  case str of
    "Merlin" -> Merlin
    "Member" -> Member
    "Minion" -> Minion
    "Percival" -> Percival
    "Morgana" -> Morgana
    "Oberon" -> Oberon
    "Mordred" -> Mordred
    _ -> Unassigned

parseRoleResponse: String -> Player -> Player
parseRoleResponse str player =
  parseRoleResp (String.split "," str) player

parseRoleResp: List String -> Player -> Player
parseRoleResp list player =
  Player player.name (parseRole (List.head list)) (parseAlignment (List.head (List.drop 1 list)))

parseRole: Maybe String -> Role
parseRole str =
  case str of
    Just string -> readRole string
    Nothing ->
      Unassigned

parseAlignment: Maybe String -> Alignment
parseAlignment str =
  case str of
    Just string -> readAlign string
    Nothing ->
      Unaligned

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Name name ->
      ({ model | user = Player name Unassigned Unaligned}, Cmd.none)

    RoomCode room ->
      ({ model | room = room},
      Cmd.none)

    JoinRoom response ->
      if response == "OK" then
        ({ model | state = Setup, errors = ""}, WebSocket.send (wsServer ++ model.room)
          (Json.Encode.encode 0 (Json.Encode.object [("name", string model.user.name), ("msg", string "has connected")])))
      else
        ({model | errors = response}, Cmd.none)

    SetRoom ->
      ({model | user = Player model.user.name Unassigned Unaligned}, WebSocket.send joinRoom (Json.Encode.encode 0 (Json.Encode.object [("name", string model.user.name), ("room", string model.room)])))

    GenRoom room ->
      ({model | room = room, user = Player model.user.name Unassigned Unaligned}, WebSocket.send joinRoom (Json.Encode.encode 0 (Json.Encode.object [("name", string model.user.name), ("room", string room)])))

    GenRoomCode ->
      (model, WebSocket.send roomGen "")

    PlayerList list ->
      ({model | currentPlayers = String.split "," list}, WebSocket.send createRoles
      (Json.Encode.encode 0 (Json.Encode.object [("room", string model.room), ("maxPlayers", Json.Encode.int model.maxPlayers)])))

    CreateRoles response ->
      if response /= "NEP" then -- No Enough players
        (model, WebSocket.send retrieveRole (Json.Encode.encode 0 (Json.Encode.object [("room", string model.room), ("user", string model.user.name)])))
      else
        (model, Cmd.none)

    RetrieveQuest response ->
      (checkQuestDecoder (Json.Decode.decodeString questDecoder response) ({model | state = TeamBuild}), WebSocket.send setQuestMembers (Json.Encode.encode 0 (Json.Encode.object [("room", string model.room), ("user", string model.user.name)])))

    GenerateQuest response ->
        (model, WebSocket.send retrieveQuest (Json.Encode.encode 0 (Json.Encode.object [("room", string model.room)])))

    CharInfo response ->
      ({model | revealedInfo = response, errors = ""},
      WebSocket.send generateQuest (Json.Encode.encode 0 (Json.Encode.object [("room", string model.room), ("roundNumber", Json.Encode.int model.currentRound), ("maxPlayers", Json.Encode.int model.maxPlayers)])))

    RetrieveRole response ->
      ({model | user = parseRoleResponse response model.user},
      WebSocket.send charInfo (Json.Encode.encode 0 (Json.Encode.object [("room", string model.room), ("user", string model.user.name)])))

    SetMaxPlayers players ->
      ({ model | maxPlayers = players}, Cmd.none)

    Input newInput ->
      ({model | chatBox = newInput}, Cmd.none)

    UpdateQuestTeam player ->
      if (List.member player model.quest.players) then
        ({model | quest = Quest model.quest.name model.quest.playersRequired (List.Extra.remove player model.quest.players) model.quest.yesVotes model.quest.noVotes model.quest.flavorText model.quest.timesTried model.quest.toFail}, Cmd.none)
      else
        ({model | quest = Quest model.quest.name model.quest.playersRequired (player::model.quest.players) model.quest.yesVotes model.quest.noVotes model.quest.flavorText model.quest.timesTried model.quest.toFail}, Cmd.none)

    Send ->
      (model, WebSocket.send (wsServer ++ model.room)
      (Json.Encode.encode 0 (Json.Encode.object [("name", string model.user.name), ("msg", string model.chatBox)])))
      -- model.user.name ++ ": " ++ model.chatBox

    NewMessage str ->
      ({model | chatMessages = (str :: model.chatMessages)}, WebSocket.send playerList
      (Json.Encode.encode 0 (Json.Encode.object [("name", string model.user.name), ("room", string model.room)])))

    SubmitQuestTeam ->
      if model.quest.playersRequired == (List.length model.quest.players) then
        ({model | errors = ""}, WebSocket.send setQuestMembers
        (Json.Encode.encode 0 (Json.Encode.object [("room", string model.room), ("players", Json.Encode.list (List.map string model.quest.players))])))
      else if model.quest.playersRequired > (List.length model.quest.players) then
        ({model | errors = "Need more players on this quest"}, Cmd.none)
      else
        ({model | errors = "Too many players selected on quest"}, Cmd.none)

    ReceiveQuestTeam response ->
      if response /= "registered" then
        (checkQuestDecoder (Json.Decode.decodeString questDecoder response) ({model | state = Vote}), Cmd.none)
      else
        (model, Cmd.none)

    VoteForTeam vote ->
        (model, WebSocket.send sendVotes
        (Json.Encode.encode 0 (Json.Encode.object [("room", string model.room), ("vote", string vote), ("user", string model.user.name) ])))

    ReceiveVotes response ->
      if response == "Vote received" then
        ({model | state = Wait}, WebSocket.send taskApproval (Json.Encode.encode 0 (Json.Encode.object [("room", string model.room), ("user", string model.user.name)])))
      else
        (checkQuestVotes (checkQuestDecoder (Json.Decode.decodeString questDecoder response) ({model | leaderPosition = (model.leaderPosition + 1) % (model.maxPlayers), previousGroup = model.quest.players})), Cmd.none)

    ApproveTask ->
      (model, WebSocket.send taskApproval
      (Json.Encode.encode 0 (Json.Encode.object [("room", string model.room), ("user", string model.user.name), ("vote", string "Approve")])))

    SabotageTask ->
      (model, WebSocket.send taskApproval
      (Json.Encode.encode 0 (Json.Encode.object [("room", string model.room), ("user", string model.user.name), ("vote", string "Disapprove")])))

    ReceiveTask response ->
      if response == "Action received" then
        ({model | state = Wait}, Cmd.none)
      else
        (updateModelOnTask {model | lastTaskResult = (checkTaskDecoder (Json.Decode.decodeString taskDecoder response)), state = TeamBuild, currentRound = model.currentRound + 1}, WebSocket.send generateQuest (Json.Encode.encode 0 (Json.Encode.object [("room", string model.room), ("roundNumber", Json.Encode.int model.currentRound), ("maxPlayers", Json.Encode.int model.maxPlayers)])))

    SetAssassinateTarget target ->
      (model, Cmd.none)


-- SUBSCRIPTIONS

subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.batch
  [ WebSocket.listen (wsServer ++ model.room) NewMessage
  , WebSocket.listen roomGen GenRoom
  , WebSocket.listen joinRoom JoinRoom
  , WebSocket.listen playerList PlayerList
  , WebSocket.listen createRoles CreateRoles
  , WebSocket.listen retrieveRole RetrieveRole
  , WebSocket.listen charInfo CharInfo
  , WebSocket.listen generateQuest GenerateQuest
  , WebSocket.listen retrieveQuest RetrieveQuest
  , WebSocket.listen setQuestMembers ReceiveQuestTeam
  , WebSocket.listen sendVotes ReceiveVotes
  , WebSocket.listen taskApproval ReceiveTask
  ]
  -- TODO: Add listeners for other

-- VIEW

playerOption maxPlayers =
  option [ Html.Attributes.value (toString maxPlayers)] [ text (toString maxPlayers)]

playersOption playerName =
  option [ Html.Attributes.value (toString playerName)] [ text (toString playerName)]

view : Model -> Html Msg
view model =
  case model.state of
    Home ->
      let
        selectEvent =
                on "change"
                    (Json.Decode.map SetMaxPlayers targetValueIntParse)
      in
      div [][
          input [ type_ "text", placeholder "Name", onInput Name, name "uname", Html.Attributes.value model.user.name] []
          , input [ type_ "text", placeholder "Room Code", onInput RoomCode, name "roomcode", Html.Attributes.value model.room] []
          , Html.select [ selectEvent] (List.map playerOption (List.range 5 10))
          , button [ type_ "button", onClick GenRoomCode] [text "Start a room"]
          , button [ type_ "button", onClick SetRoom] [text "Join Game"]
          , div [] [text model.errors]
          ]
    Setup ->
      div []
        [ input [onInput Input, placeholder "Chat with others!"] []
        , button [onClick Send] [text "Send"]
        , div [] (List.map viewMessage (List.reverse model.chatMessages))
        , div [] [text ("Your room code is " ++ model.room)]
        , div [] [text ("The game will begin when " ++ (toString (model.maxPlayers - List.length model.currentPlayers)) ++ " players join")]
        , div [] [text (model.revealedInfo)]
        , div [] [text model.errors]
        ]
    TeamBuild ->
      let
        selectionBlock =
          if getListPosition model.currentPlayers model.leaderPosition ==  model.user.name then
            [div [] [ text ("You're the current quest leader. Please select " ++ toString model.quest.playersRequired ++ " players to go on the quest")]
            ,div [] [(fieldset [] (List.map createCheckboxes model.currentPlayers))]
            ,button [ type_ "button", onClick SubmitQuestTeam] [ text ("Submit Quest Players")]
            ]
          else
            [div [] [text ("Waiting for "++ getListPosition model.currentPlayers model.leaderPosition ++ " to finish selecting a team")]]
      in
      div []
      [ input [onInput Input, placeholder "Chat with others!"] []
      , button [onClick Send] [text "Send"]
      , div [] (List.map viewMessage (List.reverse model.chatMessages))
      , div [] [text (model.quest.name)]
      , div [] [text (model.quest.flavorText)]
      , div [] [text ("It takes " ++ (toString model.quest.toFail) ++ " failures to fail this task.")]
      , div [] [text ("You've tried to complete this quest " ++ (toString model.quest.timesTried) ++ " times. If you fail to assign a team " ++ (toString (5 - model.quest.timesTried)) ++ " more times then the hackers win.")]
      , div [] [text (model.revealedInfo)]
      , div [] selectionBlock
      , div [] [text model.errors]
      ]
    Vote -> div []
      [ input [onInput Input, placeholder "Chat with others!"] []
      , button [onClick Send] [text "Send"]
      , div [] (List.map viewMessage (List.reverse model.chatMessages))
      , div [] [text (model.quest.name)]
      , div [] [text (model.quest.flavorText)]
      , div [] [text ("It takes " ++ (toString model.quest.toFail) ++ " failures to fail this task.")]
      , div [] [text ("The proposed team is " ++ (appendToComma (List.head model.quest.players) (List.drop 1 model.quest.players) ""))]
      , div [] [text ("Is this team ok to complete the task?"), fieldset [] [
            button [type_ "button", onClick (VoteForTeam "Yes")] [text ("Yes")]
          , button [type_ "button", onClick (VoteForTeam "No")] [text ("No")]]
      ]
      , div [] [text ("You've tried to complete this quest " ++ (toString model.quest.timesTried) ++ " times. If you fail to assign a team " ++ (toString (5 - model.quest.timesTried)) ++ " more times then the hackers win.")]
      , div [] [text (model.revealedInfo)]
      , div [] [text model.errors]
      ]
    Wait -> div []
      [ input [onInput Input, placeholder "Chat with others!"] []
      , button [onClick Send] [text "Send"]
      , div [] (List.map viewMessage (List.reverse model.chatMessages))
      , div [] [text (model.quest.name)]
      , div [] [text (model.quest.flavorText)]
      , div [] [text ("It takes " ++ (toString model.quest.toFail) ++ " failures to fail this task.")]
      , div [] [text ("You've tried to complete this quest " ++ (toString model.quest.timesTried) ++ " times. If you fail to assign a team " ++ (toString (5 - model.quest.timesTried)) ++ " more times then the hackers win.")]
      , div [] [text ("You've vote has been received, please hold on while other players make their decisions")]
      , div [] [text (model.revealedInfo)]
      , div [] [text model.errors]
      ]
    Decide ->
      let
        decisions = if List.member model.user.name model.quest.players then
          div [] [fieldset []
          (if model.user.alignment /= Good then
                [button [type_ "button", onClick ApproveTask] [text "Approve Task"]
                ,button [type_ "button", onClick SabotageTask] [text "Sabotage Task"]]
          else
              [button [type_ "button", onClick ApproveTask] [text "Approve Task"]]
          )
          ]
        else
          div [] [text ("Please wait while the chosen players determine the outcome of the task.")]
      in
      div []
      [ input [onInput Input, placeholder "Chat with others!"] []
      , div [] [text (model.quest.name)]
      , div [] [text (model.quest.flavorText)]
      , button [onClick Send] [text "Send"]
      , div [] (List.map viewMessage (List.reverse model.chatMessages))
      , div [] [text ("You've tried to complete this quest " ++ (toString model.quest.timesTried) ++ " times. If you fail to assign a team " ++ (toString (5 - model.quest.timesTried)) ++ " more times then the hackers win.")]
      , div [] [text ("It takes " ++ (toString model.quest.toFail) ++ " failures to fail this task.")]
      , decisions
      , div [] [text (model.revealedInfo)]
      , div [] [text model.errors]
      ]
    Final ->
      let
        selectEvent =
                on "change"
                    (Json.Decode.map SetAssassinateTarget Html.Events.targetValue)
      in
      div []
      [ input [onInput Input, placeholder "Chat with others!"] []
      , button [onClick Send] [text "Send"]
      , div [] (List.map viewMessage (List.reverse model.chatMessages))
      , Html.select [ selectEvent] (List.map playersOption model.currentPlayers)
      ]
    Victory -> div [] [text (model.victory)]

appendToComma : Maybe String -> List String -> String -> String
appendToComma head tail acc =
  case head of
    Just str -> (appendToComma (List.head tail) (List.drop 1 tail) (str ++ ", " ++ acc))
    Nothing -> String.dropRight 2 acc -- Remove the last comma

viewMessage : String -> Html msg
viewMessage msg =
  div [] [ text msg ]

createCheckboxes : String -> Html Msg
createCheckboxes msg =
  label [] [ text msg, input [ type_ "checkbox", onClick (UpdateQuestTeam msg)] [] ]
