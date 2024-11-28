import chat_registry.{type CreateChatDto, CreateChatDto}
import chat_room.{type TextMessage, TextMessage}
import gleam/dynamic
import gleam/json

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
