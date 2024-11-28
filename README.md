# blab

[![Package Version](https://img.shields.io/hexpm/v/blab)](https://hex.pm/packages/blab)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/blab/)

```sh
gleam add blab@1
```

```gleam
import blab

pub fn main() {
  // TODO: An example of the project in use
}
```

Further documentation can be found at <https://hexdocs.pm/blab>.

## Development

```sh
gleam run   # Run the project
gleam test  # Run the tests
```

## Roadmap

- Implement basic chat with registry, chats in actors and mist
- Add supervision
- Add persistence/hydration port (hexagonal)
- Add mnesia/amnesiac adapter
- Add postgres/squirrel adapter
- Try to use wisp with SSR, fork and PR if necessary
- Add tests
- Try to get working with otp observer
- Add more features, message types, privacy, invites/acceptance, LLM agents etc
