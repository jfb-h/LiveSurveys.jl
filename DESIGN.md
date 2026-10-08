# LiveSurveys.jl — Design Document

> A survey is a module that defines a response `Data` struct and four methods
> (`render_form`, `preprocess_submission`, `validate_data`, `render_results`).
> `Survey(Mod; slug, title, subtitle)` binds that module to a slug, and
> `serve!(survey)` installs the static form, the JSON response endpoint, and the
> reactive Bonito results view. Form inputs come from the reusable
> `LiveSurveys.Components` catalog. A combined all-in-one macro and richer
> aggregation defaults remain future work (see the last section).

```julia
using LiveSurveys

include("examples/HeightShoe.jl")
using .HeightShoe

survey = Survey(HeightShoe; slug="height-shoe", title="Statistics survey")
server = serve!(survey; port=8888, database="responses.duckdb")
```

## Goals

The package scaffolds paired **interactive survey + live result viewer** apps for
stats lectures, so a new survey pair can be created in a few lines of Julia.

**Concrete goals:**
1. **Survey tool** — a mobile-friendly, modern web form respondents open on their
   phones; submissions are written to DuckDB as they trickle in.
2. **Live viewer** — updates the aggregate results instantly as responses arrive.
3. **Easy per-survey authoring** — the semester has many surveys that vary in
   design; creating a new pair must be a short, declarative step.
4. **Reusable input catalog** — a library of pre-made, styled form inputs
   (Likert, single-choice, numeric, map, …) that survey authors compose.
5. **Clean separation of concerns** — response typing, DuckDB persistence, form
   rendering, and the served frontend are built by independent, individually
   testable pieces.

**Deliberately out of scope (phase 1):** response analytics/grading features,
auth for individual respondents, multi-user editing, and the combined all-in-one
macro (comes after the pieces work independently).

## Design principles

- **The response struct is the single source of truth.** One `struct Data`
  declares the fields, their Julia types, and therefore the DuckDB schema, the
  JSON submission shape, and the queryable row type. The server derives
  everything from it; it never trusts the client to describe the data's own shape.
- **Types over stringly-typed specs.** A response is a concrete struct; JSON is
  parsed straight into it and database rows are reconstructed into it. There is
  no runtime `kind` discriminator or item hierarchy.
- **Idiomatic Julia.** Methods are dispatched on the response type `R`; survey
  modules extend `LiveSurveys.render_form(::Type{Data})` et al. Macros are not
  required — a plain module is the unit of survey authoring.
- **Robustness over cleverness.** State is funneled through explicit,
  synchronized channels (a store lock), so HTTP concurrency cannot corrupt
  DuckDB or the live-update notifier.

## Architecture

```
                     ┌─────────────────── Bonito Server ───────────────────┐
  student (mobile) ─►│  GET  /<slug>              → static form HTML        │
  POST flat JSON ───►                     │  POST /api/<slug>/respond  → parse/validate/insert   │
                     │        └─► push onto notifier Channel → bump         │
                     │                     Observable (single consumer task)│
  lecturer ─────────►│  GET  /<slug>/results      → reactive Bonito viewer  │
  GET / ────────────►│        └─► 302 redirect to /<slug>                   │
                     │        re-query → rebuild stats                     │
                     └──────────────────────────────────────────────────────┘
```

- **Survey form is static**: a server-rendered HTML page (generated once per
  request, no per-respondent websocket session) whose vanilla JS `fetch`-POSTs
  the submission (`src/form.jl`). Robust on flaky classroom wifi, works at
  50–200 students, and is naturally static-exportable.
- **Viewer is reactive Bonito** (websocket to the lecturer only) — `results_app`
  in `src/results.jl`.
- Student and lecturer routes are separate. The viewer is currently **open**
  (not token-gated); gating is a remaining decision below.
- HTTP.jl (under Bonito's `Server`) serves requests on concurrent tasks, possibly
  across threads. All state transitions (DuckDB writes *and* notifier bumps) are
  therefore funneled through a single lock in the store; the notifier is a
  `Channel` consumed by one task that bumps the `Observable`. No assumption of a
  single event loop.

## Survey definition

### Response type + extension points

A survey is an ordinary module whose `Data` struct describes one response. The
package owns the protocol; the module owns the four extension points:

```julia
module HeightShoe

using LiveSurveys: LiveSurveys, Components
using Bonito: DOM

struct Data
    height::Union{Missing, Float64}
    shoe::Union{Missing, Float64}
    gender::Union{Missing, String}
end

LiveSurveys.render_form(::Type{Data}) = DOM.div(
    Components.number_input(id = "height", label = "Body height (cm)";
                            min = 70, max = 260, step = 0.5),
    Components.number_input(id = "shoe", label = "Shoe size";
                            min = 15, max = 60, step = 1),
    Components.single_choice(id = "gender", label = "Gender",
                             options = ["male" => "Male", "female" => "Female"]),
)

LiveSurveys.validate_data(::Type{Data}, d) =
    !ismissing(d.height) && !ismissing(d.shoe) &&
    (70 <= d.height <= 260) && (15 <= d.shoe <= 60)

LiveSurveys.render_results(::Type{Data}, data, n) = # … Bonito/WGLMakie view …

end
```

`src/api.jl` declares the four hook functions:

| Function | Required | Purpose |
| --- | --- | --- |
| `render_form(::Type{R})` | yes | Return the Bonito DOM fields for `R`. |
| `validate_data(::Type{R}, response)` | yes | Semantic validation; `false` → HTTP 400. |
| `preprocess_submission(::Type{R}, fields)` | no | Mutate/normalize the parsed JSON dict before construction (default: identity). |
| `render_results(::Type{R}, data, count)` | yes | Return the live view; `data`/`count` are Observables. |

**`render_form` has no fallback**: calling it on a type without a method raises a
`MethodError` (the idiomatic, informative failure).

### The `Survey` type

```julia
struct Survey{R}
    slug::String
    title::String
    subtitle::String
end
```

`R` is the response type. `Survey(::Type{R}; slug, title, subtitle="")` validates
that `R` is concrete and has at least one field, that `slug` matches `[a-z0-9-]`,
and that `title` is non-empty. For convenience, `Survey(mod::Module; kwargs...)`
looks up `mod.Data`, so `Survey(HeightShoe; …)` is equivalent to
`Survey(HeightShoe.Data; …)`.

- `slug` is the stable machine id (DuckDB table name suffix + route path).
  It is currently **mandatory** (no `slugify` default).
- `title` is display text; `subtitle` is optional supporting text under the
  heading on both the form and the results page.

### The response container

There is no separate package-level response wrapper. The user's `Data` struct
*is* the response container: heterogeneous optional fields are typed
`Union{Missing, T}` so unanswered inputs parse to `missing`. Per-field dispatch is
preserved by the concrete struct type.

### The `Components` catalog

`src/components.jl` defines a `Components` submodule exporting styled DOM
constructors that each submit a single named field (their `id`):

- `text_input`, `textarea_input`, `email_input`, `date_input`, `dropdown`,
  `single_choice`, `yes_no` → submit strings (`String` fields).
- `number_input`, `range_slider` → submit numbers (`Float64`/`Int` fields).
- `likert_scale` → submits the chosen level as a string (`"1"`…`"levels"`);
  parse it in `preprocess_submission` (e.g. with `tryparse`).
- `multiple_choice` → submits checked values as one comma-joined string
  (analyse with `split_multi`); unanswered submits `missing`.
- `consent_checkbox` → submits a `Bool`.
- `map_picker` → submits two numbers under `<id>_lat` and `<id>_lon`
  (`Float64` fields); a cleared map submits `missing` for both.

`split_multi` helps analyse `multiple_choice` answers; numeric inputs are parsed
with ordinary `parse`/`tryparse` in `preprocess_submission`. Components are
re-exported at the package top level.

### Submission wiring (JSON.jl + StructUtils.jl)

- **The form POSTs a flat JSON object keyed by field name**:
  `{"height": 175.5, "shoe": 42, "gender": "male"}`. No `kind` discriminator —
  the client never declares the data's types.
- The server is the source of truth (`src/submission.jl`): it parses the JSON
  object, calls `preprocess_submission(R, fields)`, then **rejects unknown keys,
  requires every field to be present**, and finally constructs `R` via
  `JSON.parse(JSON.json(fields), R; null=missing)`. `preprocess_submission` may
  add derived fields before construction; client-supplied values for derived
  fields are overwritten by the hook.
- Error messages are intentionally coarse (e.g. "Invalid value for one of the
  fields.") so the client learns nothing about the schema.
- StructUtils is used only for **trusted database-row reconstruction** via
  `StructUtils.make(R, row)`; it never chooses types from untrusted input.

## Persistence

Implemented in `src/store.jl`:

```julia
Store(::Type{R}, path, slug)   # opens DuckDB, derives table "responses_<slug>"
LiveSurveys.create_table!(store, R)   # CREATE TABLE IF NOT EXISTS
LiveSurveys.insert_response!(store, response)::Int   # validated insert, returns row count
LiveSurveys.load_responses(store)::Vector{R}         # typed rows via StructUtils
```

- **One wide table per survey**: columns are exactly the response struct's field
  names, with DuckDB types mapped from the Julia field types by
  `src/mapping.jl` — `Integer`→`BIGINT`, `AbstractFloat`→`DOUBLE`,
  `AbstractString`→`VARCHAR`, `Bool`→`BOOLEAN`. `Union{Missing, T}` unwraps to
  `T`'s SQL type. Direct SQL aggregations run per column.
- There is currently **no** `id`, `respondent_id`, or `submitted_at` column;
  those are future work (see below).
- `create_table!` is idempotent (never drops data between class sessions). A
  response struct gaining fields against an existing table is handled by
  `add_missing_columns!` → DuckDB `ALTER TABLE ADD COLUMN` (new cells are NULL for
  old rows). Renames/type changes are an explicit, manual migration step.
- **Thread-safety**: DuckDB.jl connections are not thread-safe. All writes funnel
  through the store's `ReentrantLock`; the notifier is a bounded `Channel` whose
  single consumer task bumps the survey's `Observable`.

## Serving + live viewer

Implemented in `src/form.jl`, `src/results.jl`, and `src/server.jl`:

```julia
form_page(survey)          # static HTML form (calls render_form(R) once)
results_app(survey, runtime)   # reactive Bonito App (calls render_results(R, data, count))
serve!(survey; host, port, database, proxy_url)   # builds Store + SurveyRuntime, registers routes
```

`proxy_url` is the external URL the server is reached at when deployed behind a
reverse proxy (e.g. `https://example.org/statistik/`). It is forwarded to
Bonito's `Server` so asset and websocket URLs are prefixed correctly, and used
for the root redirect. The form's `fetch` endpoint is proxy-relative, so it
works both at the site root and under a path prefix.

`serve!` registers four routes:

| Method | Path | Handler |
| --- | --- | --- |
| GET | `/` | 302 redirect to `/<slug>` |
| GET | `/<slug>` | static form page |
| POST | `/api/<slug>/respond` | `RespondHandler` → parse/validate/insert/notify |
| GET | `/<slug>/results` | reactive Bonito results app |

- **Form returns static HTML** by serializing Bonito DOM nodes once
  (`sprint(show, MIME"text/html"(), …)`); there is no websocket per respondent.
- **Viewer runtime** (`src/runtime.jl`): `SurveyRuntime{R}` holds the store, a
  bounded `Channel{Bool}` notifier, `data::Observable{Vector{R}}`, and
  `count::Observable{Int}`. One consumer task reloads responses on each
  notification. `results_app` mirrors `runtime.data` into an app-local
  Observable so the view can mutate it.
- **Live plots**: `render_results` may return WGLMakie figures (as the bundled
  `HeightShoe` example does) or any Bonito DOM; there is no server-side
  aggregation default yet.
- **Throttling** is not yet a package policy; examples apply
  `Observables.throttle` themselves where needed (`examples/HomeLocation.jl`).
- Duplicate submissions are currently **not** rejected (no respondent token).

## Not yet implemented (future work)

- **Per-item aggregation catalog with defaults** (Likert mean/sd/distribution,
  SingleChoice counts, numeric summary) instead of author-written
  `render_results`.
- **Respondent identity**: a per-browser `respondent_id` token, a
  `submitted_at = now(UTC)` timestamp, and soft de-duplication.
- **Package-level throttling policy** for the viewer notifier.
- **Token-gated viewer** access.
- **`export_static`**: optional server-free export of the form/viewer.
- **Combined all-in-one macro** (`@survey DB tablename "Title" begin … end`),
  which would need an idempotency strategy: `CREATE TABLE IF NOT EXISTS`, a route
  registry keyed by table name (replace, not append), and notifier lookup by
  slug — so REPL re-evaluation never duplicates tables/routes/handlers.
- **Typed question catalog**: an earlier design proposed `AbstractQuestionItem`
  structs with an `@item` macro. That direction was set aside in favour of the
  response-struct + `Components` approach above.

## Package layout

```
src/
  LiveSurveys.jl      # module, dependencies, include order, public exports
  api.jl              # survey extension points
  survey.jl           # Survey{R} metadata + module/response-type binding
  mapping.jl          # Julia response-field type → DuckDB type mapping
  store.jl            # DuckDB schema, transactions, ALTER-TABLE drift, row decoding
  runtime.jl          # notifier, observables, and serialized reload task
  submission.jl       # JSON parsing and typed response construction/validation
  components.jl       # reusable styled form input catalog (Components submodule)
  endpoint.jl         # HTTP adapter (RespondHandler)
  form.jl             # static survey form (HTML + vanilla-JS submit)
  results.jl          # reactive Bonito results app
  server.jl           # route construction and lifecycle
examples/
  HeightShoe.jl       # WGLMakie scatter example
  HomeLocation.jl     # Leaflet map example
  app.jl              # runnable entry point
test/
  runtests.jl
```

**Dependencies:** `Bonito`, `DuckDB.jl`, `DBInterface.jl`, `Tables.jl`, `JSON.jl`,
`StructUtils.jl`, `Observables.jl`, `WGLMakie`; `HypertextTemplates` and
`ReloadableMiddleware` are declared for richer serving. (`Statistics` is *not* a
dependency; examples import WGLMakie directly.)

## Remaining decisions

- **Slug**: keep mandatory-explicit (current) vs default `slugify(title)` with a
  `slug=` override.
- **Viewer access**: token-gated vs open (currently open).
- **De-duplication**: whether to introduce a browser-localStorage
  `respondent_id` soft key, and how to surface repeat submissions.
