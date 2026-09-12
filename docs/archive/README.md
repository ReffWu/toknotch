# Archive

Working documents from Codenotch, the project TokNotch was forked from. They
are kept because the design frames in `docs/design/` are quoted from them and
because the geometry decisions still hold — but they describe the **pre-rewrite**
app, which read vendor quota APIs and showed how much of a session limit you had
burned.

TokNotch does none of that. It reads local usage through tokscale and has no
concept of a limit to run out of. Where these documents and
[`../ARCHITECTURE.md`](../ARCHITECTURE.md) disagree, the latter is right.
