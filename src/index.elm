module Index exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Random exposing (..)
import Json.Decode as Json
import Html.Events.Extra exposing (targetValueIntParse)

main =
  Html.program
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }


type User = Anonymous | Named String

-- MODEL


type alias Model =
  { username : User
  , room : String
  , maxPlayers : Int
  }


model : Model
model =
  Model Anonymous "" 0


-- INIT


init : (Model, Cmd Msg)
init =
  (Model Anonymous "" 0, Cmd.none )


-- UPDATE

type Msg
    = Name String
    | RoomCode String
    | JoinRoom Int
    | SetMaxPlayers Int
    | GenCode
    | Submit


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    Name name ->
      ({ model | username = Named name }, Cmd.none)

    RoomCode room ->
      ({ model | room = room }, Cmd.none)

    JoinRoom code ->
      ({ model | room = toString code}, Cmd.none)

    SetMaxPlayers players ->
      ({ model | maxPlayers = players}, Cmd.none)

    GenCode ->
      (model, Random.generate JoinRoom (Random.int 10000 99999))
      -- TODO: Figure out if a room code is already taken
      -- May require a connection to the WS server

    Submit ->
        (model, Cmd.none)
        -- Will change the cmd to indicate a change in view

-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.none


-- VIEW

playerOption maxPlayers =
  option [ value (toString maxPlayers)] [ text (toString maxPlayers)]

view : Model -> Html Msg
view model =
  let
    selectEvent =
            on "change"
                (Json.map SetMaxPlayers targetValueIntParse)
  in
  div []
    [ input [ type_ "text", placeholder "Name", onInput Name ] []
    , input [ type_ "text", placeholder "Room Code", onInput RoomCode] []
    , select [ selectEvent] (List.map playerOption (List.range 5 10))
    , button [ onClick GenCode] [text "Start a room"]
    , button [ onClick Submit] [text "Join Game"]
    , viewValidation model
    ]


viewValidation : Model -> Html msg
viewValidation model =
  let
    (color, message) =
      if model.room /= "" then
        ("black", model.room)
      else
        ("red", "No room exists yet")
  in
    div [ style [("color", color)] ] [ text message ]
