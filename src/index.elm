module Index exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Random exposing (..)
import Json.Decode as Json
import Html.Events.Extra exposing (targetValueIntParse)
import WebSocket


main =
  Html.program
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }

wsServer : String
wsServer =
  "ws://localhost:8080/"

roomGen : String
roomGen = wsServer++"gen_room"

joinRoom : String
joinRoom = wsServer++"join_room"

-- Type definitions
type LobbyRole = Host | Client | Waiting
-- Need a better name for this attribute


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

type GameState
  = Home
  | Setup
  | TeamBuild
  | Vote
  | Final

type alias Player =
  { name : String
  , role : Role
  , lobbyRole : LobbyRole
  }


-- MODEL


type alias Model =
  { user : Player
  , room : String
  , maxPlayers : Int
  , chatBox : String
  , chatMessages : List String
  , state : GameState
  }


model : Model
model =
  Model (Player "" Unassigned Waiting) "" 0 "" [] Home


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
    | GenRoomCode
    | GenRoom String
    | SetRoom
    | Input String
    | Send
    | NewMessage String


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Name name ->
      ({ model | user = Player name Unassigned Waiting }, Cmd.none)

    RoomCode room ->
      ({ model | room = room},
      Cmd.none)

    JoinRoom response ->
      if response == "OK" then
        ({ model | state = Setup}, WebSocket.send (wsServer ++ model.room)
          (model.user.name ++ " has entered the room"))
      else
        (model, Cmd.none)
        -- TODO: Add error handling

    SetRoom ->
      ({model | user = Player model.user.name Unassigned Client}, WebSocket.send joinRoom model.room)

    GenRoom room ->
      ({model | room = room, user = Player model.user.name Unassigned Host}, WebSocket.send joinRoom room)

    GenRoomCode ->
      (model, WebSocket.send roomGen "")
      -- TODO: Figure out if a room code is already taken

    SetMaxPlayers players ->
      ({ model | maxPlayers = players}, Cmd.none)

    Input newInput ->
      ({model | chatBox = newInput}, Cmd.none)

    Send ->
      (model, WebSocket.send (wsServer ++ model.room) (model.user.name ++ ": " ++ model.chatBox))

    NewMessage str ->
      ({model | chatMessages = (str :: model.chatMessages)}, Cmd.none)

-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.batch
  [ WebSocket.listen (wsServer ++ model.room) NewMessage
  , WebSocket.listen roomGen GenRoom
  , WebSocket.listen joinRoom JoinRoom
  ]
  -- TODO: Add listeners for other

-- VIEW

playerOption maxPlayers =
  option [ value (toString maxPlayers)] [ text (toString maxPlayers)]

view : Model -> Html Msg
view model =
  if model.state == Home then
    let
      selectEvent =
              on "change"
                  (Json.map SetMaxPlayers targetValueIntParse)
    in
    div [][
        input [ type_ "text", placeholder "Name", onInput Name, name "uname", value model.user.name] []
        , input [ type_ "text", placeholder "Room Code", onInput RoomCode, name "roomcode", value model.room] []
        , select [ selectEvent] (List.map playerOption (List.range 5 10))
        , button [ type_ "button", onClick GenRoomCode] [text "Start a room"]
        , button [ type_ "button", onClick SetRoom] [text "Join Game"]
        ]
  else
    div []
      [ input [onInput Input, placeholder "Chat with others!"] []
      , button [onClick Send] [text "Send"]
      , div [] (List.map viewMessage (List.reverse model.chatMessages))
      , div [] [text ("Your room code is " ++ model.room)]
      ]

viewMessage : String -> Html msg
viewMessage msg =
  div [] [ text msg ]
