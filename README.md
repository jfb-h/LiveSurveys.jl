# LiveSurveys.jl

LiveSurveys is a julia package for building small web surveys using `Bonito.jl`: respondents fill in
a form on their phone, and the answers are rendered as a custom `WGLMakie.jl` view which is updated live. Responses are additionally stored in a DuckDB database so survey data is available for later use.

## How it works

A survey is a Julia module with a struct definition (`Data`) for a single response
and four functions that describe how to show the form, check answers, and draw
the results. A `Survey` names that module, gives it a slug, and can be `serve!`'d.

## Minimal example

Save this as `Mood.jl`:

```julia
module Mood

using LiveSurveys: LiveSurveys, Components
using Bonito: DOM

struct Data
    rating::Union{Missing, Int}
    comment::Union{Missing, String}
end

LiveSurveys.render_form(::Type{Data}) = DOM.div(
    Components.likert_scale(id = "rating", label = "How was the lecture?",
                            left_label = "boring", right_label = "great"),
    Components.textarea_input(id = "comment", label = "Anything to add?",
                              required = false),
)

# Form data can be preprocessed (e.g. parse likert rating as int)
function LiveSurveys.preprocess_submission(::Type{Data}, fields)
    fields["rating"] = something(tryparse(Int, string(fields["rating"])), missing)
    return fields
end

LiveSurveys.validate_data(::Type{Data}, d) =
    !ismissing(d.rating) && 1 <= d.rating <= 5

LiveSurveys.render_results(::Type{Data}, data, count) = DOM.div(
    DOM.p(DOM.strong("n = ", count, " responses")),
    DOM.p("Average: ", map(rows -> isempty(rows) ? 0 :
        sum(r.rating for r in rows) / length(rows), data)),
)

end
```

Then run it:

```julia
using LiveSurveys

include("Mood.jl")
using .Mood

survey = Survey(Mood; slug = "mood", title = "Lecture mood")
server = serve!(survey; port = 8888, database = "responses.duckdb")
wait(server)
```

Open `http://localhost:8888/mood` on a phone and
`http://localhost:8888/mood/results` on the projector.

## Notes

- A field typed `Union{Missing, T}` is optional; the browser may leave it out.
- Radio, dropdown, and Likert inputs submit strings, so parse numeric ones in
  `preprocess_submission` (see the rating field above).
- Inputs come from `LiveSurveys.Components`. There are text, number, date,
  dropdown, radio, checkbox, Likert, and map inputs. See `src/components.jl` for
  the full list and what each one submits.
- Results render as plain DOM or a WGLMakie figure.
- `examples/` has two complete surveys (`HeightShoe`, `HomeLocation`) and a
  runnable `app.jl`.
