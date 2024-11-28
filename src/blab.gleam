import chat_registry.{
  CreateChat, CreateChatDto, DeleteChat, GetChat, ListChats, chat_registry_loop,
}
import chat_room.{GetAllMessages, NewMessage, Publish, Subscribe, Unsubscribe}
import decoders.{create_chat_from_json, text_message_from_json}
import encoders.{chat_list_to_json, chat_message_to_json, chat_to_json}
import gleam/dict
import gleam/erlang/process
import gleam/function
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/otp/actor
import gleam/string_tree
import helpers.{body_json, new_response}
import mist.{type Connection, type ResponseData}

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
