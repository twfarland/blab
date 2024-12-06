import chat_registry.{
  CreateChat, CreateChatDto, DeleteChat, GetChat, ListChats, chat_list_to_json,
  chat_registry_loop, chat_to_json, create_chat_client, create_chat_from_json,
}
import chat_room.{
  NewMessage, Publish, Unsubscribe, chat_message_to_json, text_message_from_json,
}
import cors_builder as cors
import gleam/dict
import gleam/erlang/process
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{Some}
import gleam/otp/actor
import gleam/string_tree
import helpers.{body_json, new_response}
import mist.{type Connection, type ResponseData}

fn cors() {
  cors.new()
  |> cors.allow_origin("http://localhost:3000")
  |> cors.allow_origin("http://127.0.0.1:3000")
  |> cors.allow_method(http.Get)
  |> cors.allow_method(http.Post)
}

pub fn main() {
  let not_found = new_response(404, "")

  let assert Ok(chat_registry) = actor.start(dict.new(), chat_registry_loop)

  let assert Ok(_) =
    fn(req: Request(Connection)) -> Response(ResponseData) {
      use req <- cors.mist_middleware(req, cors())

      case req.method, request.path_segments(req) {
        // Create a new chat room in the registry, this starts its actor
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

        // List all chats in the registry
        http.Get, ["chat"] -> {
          actor.call(chat_registry, fn(reply) { ListChats(reply) }, 100)
          |> chat_list_to_json
          |> json.to_string
          |> new_response(200, _)
        }

        // Get a chat room from the registry
        http.Get, ["chat", id] -> {
          case
            actor.call(chat_registry, fn(reply) { GetChat(reply, id) }, 100)
          {
            Ok(chat) ->
              chat |> chat_to_json |> json.to_string |> new_response(200, _)
            Error(_) -> not_found
          }
        }

        // Delete a chat room from the registry
        http.Delete, ["chat", id] -> {
          case
            actor.call(chat_registry, fn(reply) { DeleteChat(reply, id) }, 100)
          {
            Ok(msg) -> new_response(200, msg)
            Error(msg) -> new_response(404, msg)
          }
        }

        // Create a new chat room in the registry
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

        // Connect to a chat room server sent events stream
        http.Get, ["chat", id, "sse"] -> {
          case
            actor.call(chat_registry, fn(reply) { GetChat(reply, id) }, 100)
          {
            Ok(chat) ->
              mist.server_sent_events(
                req,
                response.new(200),
                init: fn() {
                  let #(client, selector) = create_chat_client(chat)
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

        // Chat room websocket interface 
        http.Get, ["chat", id, "ws"] -> {
          case
            actor.call(chat_registry, fn(reply) { GetChat(reply, id) }, 100)
          {
            Ok(chat) -> {
              let #(client, selector) = create_chat_client(chat)

              mist.websocket(
                request: req,
                on_init: fn(_conn) { #(Nil, Some(selector)) },
                on_close: fn(_state) { Nil },
                handler: fn(state, conn, message) {
                  case message {
                    mist.Text(text) -> {
                      case text_message_from_json(text) {
                        Ok(msg) -> {
                          process.send(chat.subject, Publish(NewMessage(msg)))
                        }
                        Error(_) -> {
                          let _ = mist.send_text_frame(conn, "Invalid message")
                          Nil
                        }
                      }
                      actor.continue(state)
                    }

                    mist.Binary(_) -> actor.continue(state)

                    mist.Closed | mist.Shutdown -> {
                      process.send(chat.subject, Unsubscribe(client))
                      actor.Stop(process.Normal)
                    }

                    mist.Custom(msg) -> {
                      let assert Ok(_) =
                        msg
                        |> chat_message_to_json
                        |> json.to_string
                        |> mist.send_text_frame(conn, _)

                      actor.continue(state)
                    }
                  }
                },
              )
            }
            Error(_) -> not_found
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
