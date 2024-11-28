import gleam/erlang/process.{type Subject}
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
