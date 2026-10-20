# Watch audio queue regression

Run `python3 Tests/WatchAudioQueue/run.py` from the repository with Swift 6.2+
on Linux. The runner creates and deletes a temporary Swift package and isolates
application data using `XDG_DATA_HOME` and `XDG_CONFIG_HOME`.

The harness compiles the actual `LocalStore`, `TextDeliveryQueue`,
`DirectSendConfiguration`, and `DaySelection` sources. It removes only unavailable
module imports and supplies platform adapters. It does not replace queue logic.
Settings return an enabled Direct Send webhook configuration. WatchConnectivity
accepts transfers but never delivers a phone ACK or a processed-query reply.

The regression queues audio, persists an expired transfer, reloads the store,
and checks that sync resubmits the same UUID while retaining the file until ACK.
It also checks that fresh transfers are not repeatedly submitted and that an
unavailable transport leaves expired audio retryable across reload.

This tests local queue recovery, not watchOS scheduling, real file transport,
phone transcription, or webhook delivery. MacroMarkKit's full test target uses
Apple-only modules, including Security and SwiftData, and cannot build on Linux.

Swift 6.4's default build system requires sockets unavailable in some sandboxes;
the runner selects the native build system. If the Swift installation needs a
local library or module-cache workaround, pass those environment variables to
the runner. It preserves them for the Swift subprocess.
