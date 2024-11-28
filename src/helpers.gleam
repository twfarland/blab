import gleam/bit_array
import gleam/bytes_tree
import gleam/http/request.{type Request}
import gleam/http/response
import gleam/json
import gleam/result
import mist.{type Connection}

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

pub fn new_response(status: Int, body: String) {
  response.new(status)
  |> response.set_body(body |> bytes_tree.from_string |> mist.Bytes)
}
