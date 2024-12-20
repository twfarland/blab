import chat_room.{type ChatRoomMessage, ChatRoomState, Stop, chat_room_loop}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor

pub type ChatId =
  String

pub type ChatRecord {
  ChatRecord(id: ChatId, title: String, subject: Subject(ChatRoomMessage))
}

pub type CreateChatDto {
  CreateChatDto(id: ChatId, title: String)
}

pub type ChatRegistryMessage {
  CreateChat(reply: Subject(Result(String, String)), id: ChatId, title: String)
  GetChat(reply: Subject(Result(ChatRecord, Nil)), id: ChatId)
  ListChats(reply: Subject(List(ChatRecord)))
  DeleteChat(reply: Subject(Result(String, String)), id: ChatId)
}

pub type ChatRegistryState =
  Dict(ChatId, ChatRecord)

pub fn chat_registry_loop(
  message: ChatRegistryMessage,
  state: ChatRegistryState,
) {
  case message {
    CreateChat(reply, id, title) -> {
      case dict.has_key(state, id) {
        True -> {
          reply |> process.send(Error("Chat with that id already exists"))
          state |> actor.continue
        }
        _ -> {
          let assert Ok(subject) =
            actor.start(ChatRoomState([], []), chat_room_loop)

          reply |> process.send(Ok("Chat created"))

          dict.insert(state, id, ChatRecord(id, title, subject))
          |> actor.continue
        }
      }
    }

    GetChat(reply, id) -> {
      reply |> process.send(dict.get(state, id))
      state |> actor.continue
    }

    ListChats(reply) -> {
      reply |> process.send(dict.values(state))
      state |> actor.continue
    }

    DeleteChat(reply, id) -> {
      case dict.get(state, id) {
        Ok(chat) -> {
          process.send(chat.subject, Stop)
          reply |> process.send(Ok("Deleted chat"))
          dict.delete(state, id) |> actor.continue
        }
        _ -> {
          reply |> process.send(Error("Chat not found"))
          state |> actor.continue
        }
      }
    }
  }
}
