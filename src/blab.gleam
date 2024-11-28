import chat_registry.{
  type ChatRecord, CreateChat, DeleteChat, GetChat, ListChats,
  chat_registry_loop,
}
import chat_room.{
  type ChatMessage, type TextMessage, AllMessages, GetAllMessages, NewMessage,
  Publish, Subscribe, TextMessage, Unsubscribe,
}
import gleam/bit_array
import gleam/bytes_tree
import gleam/dict
import gleam/dynamic
import gleam/erlang/process
import gleam/function
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/otp/actor
import gleam/result
import gleam/string_tree
import mist.{type Connection, type ResponseData}

pub type CreateChatDto {
  CreateChatDto(id: String, title: String)
}

// Decoders

pub fn create_chat_from_json(
  json_string: String,
) -> Result(CreateChatDto, json.DecodeError) {
  json.decode(
    from: json_string,
    using: dynamic.decode2(
      CreateChatDto,
      dynamic.field("id", of: dynamic.string),
      dynamic.field("title", of: dynamic.string),
    ),
  )
}

pub fn text_message_from_json(
  json_string: String,
) -> Result(TextMessage, json.DecodeError) {
  json.decode(
    from: json_string,
    using: dynamic.decode4(
      TextMessage,
      dynamic.field("id", of: dynamic.string),
      dynamic.field("name", of: dynamic.string),
      dynamic.field("time", of: dynamic.int),
      dynamic.field("content", of: dynamic.string),
    ),
  )
}

// Encoders

pub fn chat_to_json(chat: ChatRecord) {
  json.object([
    #("id", json.string(chat.id)),
    #("title", json.string(chat.title)),
  ])
}

pub fn chat_list_to_json(chat_list: List(ChatRecord)) {
  json.array(chat_list, of: chat_to_json)
}

pub fn text_message_to_json(text_message: TextMessage) {
  json.object([
    #("id", json.string(text_message.id)),
    #("name", json.string(text_message.name)),
    #("time", json.int(text_message.time)),
    #("content", json.string(text_message.content)),
  ])
}

pub fn chat_message_to_json(chat_message: ChatMessage) {
  case chat_message {
    NewMessage(text_message) ->
      json.object([
        #("type", json.string("new_message")),
        #("message", text_message_to_json(text_message)),
      ])
    AllMessages(messages) ->
      json.object([
        #("type", json.string("all_messages")),
        #("messages", json.array(messages, of: text_message_to_json)),
      ])
  }
}

// Helpers

pub fn body_json(
  req: Request(Connection),
  dto_from_json: fn(String) -> Result(dto, json.DecodeError),
) -> Result(dto, String) {
  use body <- result.try(
    req
    |> mist.read_body(10_024 * 10_024 * 8)
    |> result.replace_error("Could not read request body."),
  )
  use json_string <- result.try(
    body.body
    |> bit_array.to_string
    |> result.replace_error("Could not convert request body to string."),
  )
  json_string |> dto_from_json |> result.replace_error("Failed")
}

fn new_response(status: Int, body: String) {
  response.new(status)
  |> response.set_body(body |> bytes_tree.from_string |> mist.Bytes)
}

// Main

pub fn main() {
  let not_found = new_response(404, "")

  let assert Ok(chat_registry) = actor.start(dict.new(), chat_registry_loop)

  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      case req.method, request.path_segments(req) {
        http.Post, ["chat"] ->
          case body_json(req, create_chat_from_json) {
            Ok(CreateChatDto(id, title)) -> {
              let assert Ok(ok_message) =
                actor.call(
                  chat_registry,
                  fn(reply) { CreateChat(reply, id, title) },
                  100,
                )
              ok_message |> new_response(200, _)
            }
            Error(error_message) -> {
              error_message |> new_response(422, _)
            }
          }

        http.Get, ["chat"] -> {
          actor.call(chat_registry, fn(reply) { ListChats(reply) }, 100)
          |> chat_list_to_json
          |> json.to_string
          |> new_response(200, _)
        }

        http.Get, ["chat", id] -> {
          case
            actor.call(chat_registry, fn(reply) { GetChat(reply, id) }, 100)
          {
            Ok(chat) ->
              chat |> chat_to_json |> json.to_string |> new_response(200, _)
            Error(_) -> not_found
          }
        }

        http.Get, ["chat", id, "stream"] -> {
          case
            actor.call(chat_registry, fn(reply) { GetChat(reply, id) }, 100)
          {
            Ok(chat) ->
              mist.server_sent_events(
                req,
                response.new(200),
                init: fn() {
                  let client = process.new_subject()

                  process.send(chat.subject, Subscribe(client))
                  process.send(chat.subject, GetAllMessages(client))

                  let selector =
                    process.new_selector()
                    |> process.selecting(client, function.identity)

                  actor.Ready(client, selector)
                },
                loop: fn(message, connection, client) {
                  case
                    mist.send_event(
                      connection,
                      message
                        |> chat_message_to_json
                        |> json.to_string
                        |> string_tree.from_string
                        |> mist.event,
                    )
                  {
                    Ok(_) -> actor.continue(client)
                    Error(_) -> {
                      process.send(chat.subject, Unsubscribe(client))
                      actor.Stop(process.Normal)
                    }
                  }
                },
              )
            Error(_) -> not_found
          }
        }

        http.Post, ["chat", id] -> {
          case
            actor.call(chat_registry, fn(reply) { GetChat(reply, id) }, 100)
          {
            Ok(chat) -> {
              case body_json(req, text_message_from_json) {
                Ok(text_message) -> {
                  process.send(chat.subject, Publish(NewMessage(text_message)))
                  new_response(200, "Message sent")
                }
                Error(error_message) -> {
                  error_message |> new_response(422, _)
                }
              }
            }
            Error(_) -> not_found
          }
        }

        http.Delete, ["chat", id] -> {
          case
            actor.call(chat_registry, fn(reply) { DeleteChat(reply, id) }, 100)
          {
            Ok(msg) -> new_response(200, msg)
            Error(msg) -> new_response(404, msg)
          }
        }

        _, _ -> not_found
      }
    }
    |> mist.new
    |> mist.port(3000)
    |> mist.start_http

  process.sleep_forever()
}
