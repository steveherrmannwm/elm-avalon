module Index exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Random exposing (..)
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
  "https://elm-avalon.herokuapp.com/"

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
  | Decide
  | Wait
  | Final

type alias Player =
  { name : String
  , role : Role
  , alignment: Alignment
  }

type alias Quest =
  { name: String
  , playersRequired : Int
  , players : List String
  , votes : Int
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
  , revealedInfo : String
  , quest : Quest
  , errors : String
  }


model : Model
model =
  Model (Player "" Unassigned Unaligned) "" 5 [] "" [] Home -1 "" (Quest "" 2 [] 0) ""


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
    | SetRoom
    | Input String
    | Send
    | UpdateQuestTeam String
    | SubmitQuestTeam
    | NewMessage String
    | CharInfo String

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
      ({model | user = Player model.user.name Unassigned Unaligned}, WebSocket.send joinRoom model.room)

    GenRoom room ->
      ({model | room = room, user = Player model.user.name Unassigned Unaligned}, WebSocket.send joinRoom room)

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

    CharInfo response ->
      ({model | revealedInfo = response, state = TeamBuild, errors = "", leaderPosition = (model.leaderPosition + 1) % List.length (model.currentPlayers)}, Cmd.none)

    RetrieveRole response ->
      ({model | user = parseRoleResponse response model.user},
      WebSocket.send charInfo (Json.Encode.encode 0 (Json.Encode.object [("room", string model.room), ("user", string model.user.name)])))

    SetMaxPlayers players ->
      ({ model | maxPlayers = players}, Cmd.none)

    Input newInput ->
      ({model | chatBox = newInput}, Cmd.none)

    UpdateQuestTeam player ->
      if (List.member player model.quest.players) then
        ({model | quest = Quest model.quest.name model.quest.playersRequired (List.Extra.remove player model.quest.players) model.quest.votes}, Cmd.none)
      else
        ({model | quest = Quest model.quest.name model.quest.playersRequired (player::model.quest.players) model.quest.votes}, Cmd.none)

    Send ->
      (model, WebSocket.send (wsServer ++ model.room)
      (Json.Encode.encode 0 (Json.Encode.object [("name", string model.user.name), ("msg", string model.chatBox)])))
      -- model.user.name ++ ": " ++ model.chatBox

    NewMessage str ->
      ({model | chatMessages = (str :: model.chatMessages)}, WebSocket.send playerList
      (Json.Encode.encode 0 (Json.Encode.object [("name", string model.user.name), ("room", string model.room)])))

    SubmitQuestTeam ->
      (model, WebSocket.send setQuestMembers (Json.Encode.encode 0 (Json.Encode.object [("name", string model.user.name), ("room", string model.room)])))

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
  ]
  -- TODO: Add listeners for other

-- VIEW

playerOption maxPlayers =
  option [ Html.Attributes.value (toString maxPlayers)] [ text (toString maxPlayers)]

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
            ]
          else
            [div [] [text ("Waiting for "++ getListPosition model.currentPlayers model.leaderPosition ++ " to finish selecting a team")]]
      in
      div []
      [ input [onInput Input, placeholder "Chat with others!"] []
      , button [onClick Send] [text "Send"]
      , div [] (List.map viewMessage (List.reverse model.chatMessages))
      , div [] [text (model.revealedInfo)]
      , div [] selectionBlock
      , div [] [text model.errors]
      ]
    Vote -> div []
      [ input [onInput Input, placeholder "Chat with others!"] []
      , button [onClick Send] [text "Send"]
      , div [] (List.map viewMessage (List.reverse model.chatMessages))
      , div [] [text (model.revealedInfo)]
      , div [] [text model.errors]
      ]
    Decide -> div []
      [ input [onInput Input, placeholder "Chat with others!"] []
      , button [onClick Send] [text "Send"]
      , div [] (List.map viewMessage (List.reverse model.chatMessages))
      , div [] [text (model.revealedInfo)]
      , div [] [text model.errors]
      ]
    Wait -> div []
      [ input [onInput Input, placeholder "Chat with others!"] []
      , button [onClick Send] [text "Send"]
      , div [] (List.map viewMessage (List.reverse model.chatMessages))
      , div [] [text (model.revealedInfo)]
      , div [] [text model.errors]
      ]
    Final -> div []
      [ input [onInput Input, placeholder "Chat with others!"] []
      , button [onClick Send] [text "Send"]
      , div [] (List.map viewMessage (List.reverse model.chatMessages))]

viewMessage : String -> Html msg
viewMessage msg =
  div [] [ text msg ]

createCheckboxes : String -> Html Msg
createCheckboxes msg =
  label [] [ text msg, input [ type_ "checkbox", onClick (UpdateQuestTeam msg)] [] ]
