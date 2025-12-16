import gleam/bytes_tree
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/io
import gleam/json
import gleam/option.{Some}
import mist.{type Connection, type ResponseData}

pub fn main() {
  // These values are for the Websocket process initialized below
  let selector = process.new_selector()
  let state = Nil

  let not_found =
    response.new(404)
    |> response.set_body(mist.Bytes(bytes_tree.new()))

  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      case request.path_segments(req) {
        // root
        [] ->
          mist.websocket(
            request: req,
            on_init: fn(_) { #(state, Some(selector)) },
            on_close: fn(_) { io.println("goodbye!") },
            handler: handle_ws_message,
          )

        _ -> not_found
      }
    }
    |> mist.new
    |> mist.port(8080)
    |> mist.start

  process.sleep_forever()
}

pub type Event {
  Event(
    id: String,
    pubkey: String,
    kind: Int,
    sig: String,
    content: String,
    created_at: Int,
    tags: List(List(String)),
  )
}

fn event_decoder() -> decode.Decoder(Event) {
  use id <- decode.field("id", decode.string)
  use pubkey <- decode.field("pubkey", decode.string)
  use kind <- decode.field("kind", decode.int)
  use sig <- decode.field("sig", decode.string)
  use content <- decode.field("content", decode.string)
  use created_at <- decode.field("created_at", decode.int)
  use tags <- decode.field("tags", decode.list(decode.list(decode.string)))
  decode.success(Event(id:, pubkey:, kind:, sig:, content:, created_at:, tags:))
}

pub type Filter {
  // TODO: Add tag filtering support
  // TODO: Add optional parameter support
  Filter(
    ids: List(String),
    authors: List(String),
    kinds: List(Int),
    since: Int,
    until: Int,
    limit: Int,
  )
}

fn filter_decoder() -> decode.Decoder(Filter) {
  use ids <- decode.field("ids", decode.list(decode.string))
  use authors <- decode.field("authors", decode.list(decode.string))
  use kinds <- decode.field("kinds", decode.list(decode.int))
  use since <- decode.field("since", decode.int)
  use until <- decode.field("until", decode.int)
  use limit <- decode.field("limit", decode.int)
  decode.success(Filter(ids:, authors:, kinds:, since:, until:, limit:))
}

fn handle_ws_message(state, message, conn) {
  case message {
    mist.Text("[\"EVENT\"," <> _ as req) -> {
      let payload_decoder = {
        use typ <- decode.subfield([0], decode.string)
        use event <- decode.subfield([1], event_decoder())
        decode.success(#(typ, event))
      }
      let assert Ok(#(_, event)) = json.parse(req, using: payload_decoder)
      let assert Ok(_) =
        mist.send_text_frame(conn, "[\"OK\",\"" <> event.id <> "\",true,\"\"]")
      mist.continue(state)
    }
    mist.Text("[\"REQ\"," <> _ as req) -> {
      // TODO: Add multiple filter support
      let payload_decoder = {
        use typ <- decode.subfield([0], decode.string)
        use subid <- decode.subfield([1], decode.string)
        use filter <- decode.subfield([2], filter_decoder())
        decode.success(#(typ, subid, filter))
      }
      let assert Ok(#(_, subid, _)) = json.parse(req, using: payload_decoder)
      let assert Ok(_) =
        mist.send_text_frame(conn, "[\"EOSE\",\"" <> subid <> "\"]")
      mist.continue(state)
    }
    mist.Text(_) | mist.Binary(_) | mist.Custom(_) -> mist.continue(state)
    mist.Closed | mist.Shutdown -> mist.stop()
  }
}
