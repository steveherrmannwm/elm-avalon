import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
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
  "ws://localhost:8080"



-- MODEL


type alias Model =
  { input : String
  , messages : List String
  , room : String
  }


init : (Model, Cmd Msg)
init =
  (Model "" [], Cmd.none, "")



-- UPDATE


type Msg
  = Input String
  | Send
  | NewMessage String


update : Msg -> Model -> (Model, Cmd Msg)
update msg {input, messages} =
  case msg of
    Input newInput ->
      (Model newInput messages, Cmd.none)

    Send ->
      (Model "" messages, WebSocket.send wsServer ++ "/" ++ room input, room)

    NewMessage str ->
      (Model input (str :: messages), Cmd.none, room)



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
  WebSocket.listen wsServer NewMessage



-- VIEW


view : Model -> Html Msg
view model =
  div []
    [ input [onInput Input] []
    , button [onClick Send] [text "Send"]
    , div [] (List.map viewMessage (List.reverse model.messages))
    ]


viewMessage : String -> Html msg
viewMessage msg =
  div [] [ text msg ]
