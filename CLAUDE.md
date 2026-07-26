# Claude Code Guidelines for MacroMark

@AGENTS.md

## Product context

- MacroMark is an MIT-licensed iPhone and Apple Watch capture tool.
- `LocalStore` durably queues watch captures before WatchConnectivity transfer.
- The phone transcribes when needed, expands macros, records the result, and
  exports it. ACK only after durable processing and successful export or a
  retryable durable state.

## Architecture notes

- Prefer concrete constructor or closure injection. Do not add a protocol merely
  to create an abstract-looking seam.
- Keep views focused; place persistence, sync, validation, and processing in
  testable concrete types.
- Use structured concurrency and `os.Logger`; never block async work with a
  semaphore.
- Read the reliability documents named in `AGENTS.md` when the task touches
  their subject. Update docs only when the implementation makes them inaccurate.

## Workflow

The promotion ladder, publication rules, and build/test commands are canonical
in `AGENTS.md`. Preserve the watch-to-phone durability guarantee regardless of
which surface is being changed.
