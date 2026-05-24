"""Minimal backend for the React Native Phase 0 spike.

Run with:
    jac start backend/main.jac --no-client --api-port 8000 --host 0.0.0.0

The `ping` walker is invoked from `App.tsx` via `jacSpawn("ping")` to prove
the compiled-bundle -> native_runtime -> fetch round-trip works.
"""

import datetime;

walker ping {
    can run with `root entry {
        report {
            "ok": True,
            "ts": str(datetime.datetime.now()),
            "message": "pong from jac"
        };
    }
}
