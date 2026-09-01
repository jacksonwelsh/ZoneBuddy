# Cyclone export storage

Cyclone adds only optional fields and fields with defaults to `WorkoutSession`.
SwiftData can apply this as a lightweight additive migration to local and CloudKit stores.
Existing sessions fall back to their retained FIT or TCX data and then to summary data.
The normalized export envelope uses external storage and is captured only for new sessions while Cyclone is enrolled.
