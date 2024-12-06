import gleam/dynamic
import gleam/erlang/process.{type Subject}
import gleam/json
import gleam/list
import gleam/otp/actor

pub type TextMessage {
  TextMessage(id: String, name: String, time: Int, content: String)
}

pub type ChatMessage {
  NewMessage(TextMessage)
  AllMessages(messages: List(TextMessage))
}

pub type ChatRoomMessage {
  Subscribe(client: Subject(ChatMessage))
  Unsubscribe(client: Subject(ChatMessage))
  Publish(message: ChatMessage)
  GetAllMessages(client: Subject(ChatMessage))
  Stop
}

pub type ChatRoomState {
  ChatRoomState(
    conversation: List(TextMessage),
    clients: List(Subject(ChatMessage)),
  )
}

pub fn chat_room_loop(message: ChatRoomMessage, state: ChatRoomState) {
  case message {
    Subscribe(client) -> {
      ChatRoomState(..state, clients: [client, ..state.clients])
      |> actor.continue
    }

    Unsubscribe(client) -> {
      ChatRoomState(
        ..state,
        clients: state.clients |> list.filter(fn(c) { c != client }),
      )
      |> actor.continue
    }

    Publish(message) -> {
      case message {
        NewMessage(msg) as new_message -> {
          state.clients |> list.each(process.send(_, new_message))
          ChatRoomState(..state, conversation: [msg, ..state.conversation])
          |> actor.continue
        }
        _ -> {
          state |> actor.continue
        }
      }
    }

    GetAllMessages(client) -> {
      process.send(client, AllMessages(state.conversation))
      state |> actor.continue
    }

    Stop -> {
      actor.Stop(process.Normal)
    }
  }
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
