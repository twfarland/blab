import chat_registry.{type ChatRecord}
import chat_room.{
  type ChatMessage, type TextMessage, AllMessages, NewMessage, TextMessage,
}
import gleam/json

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
