"""
    LiveSurveys.Components

A library of standard survey form components. Every component returns a styled
DOM node that can be composed inside `render_form`, submits a single field
under its `id` as the field name, and documents the Julia type its submission
parses to. Typical usage:

```julia
using LiveSurveys

LiveSurveys.render_form(::Type{Data}) = DOM.div(
    likert_scale(id = "fun", label = "How fun was the lecture?";
                 left_label = "boring", right_label = "great"),
    number_input(id = "height", label = "Body height (cm)";
                 min = 70, max = 260, step = 0.5),
)
```

Components submit values as JSON through the standard form runtime:

- `text_input`, `textarea_input`, `email_input`, `date_input`, `dropdown`,
  `single_choice`, `yes_no` submit strings (`String` fields).
- `number_input` and `range_slider` submit numbers (`Float64`/`Int` fields).
- `likert_scale` submits the chosen level as a string (`"1"` to `"levels"`);
  parse it in `preprocess_submission` (e.g. with `tryparse`) to keep an `Int`
  field.
- `multiple_choice` submits the checked values as one comma-joined string
  (analyse it with [`split_multi`](@ref)); unanswered submits `missing`.
- `consent_checkbox` submits a `Bool` (checked or not).
- `map_picker` submits two numbers under `<id>_lat` and `<id>_lon`
  (`Float64` fields); a cleared map submits `missing` for both.

Unanswered optional inputs submit `null` and parse to `missing`, so response
fields should usually be `Union{Missing, T}` unless the input is required.
"""
module Components

using Bonito: DOM

export text_input,
    textarea_input,
    number_input,
    email_input,
    date_input,
    range_slider,
    dropdown,
    single_choice,
    multiple_choice,
    likert_scale,
    yes_no,
    consent_checkbox,
    map_picker,
    split_multi

# Shared field wrapper: label + input + hint, styled by the form CSS.
# Use it when the label targets the element with `id`; group-style components
# (radio/checkbox lists) inline their own wrapper instead.
function field(input_element; id, label = "", hint = "")
    label_element = isempty(label) ?
        nothing :
        DOM.label(label; class = "label", var"for" = id)
    hint_element = isempty(hint) ? nothing : DOM.div(hint; class = "hint")
    return DOM.div(label_element, input_element, hint_element; class = "field")
end

"""
    text_input(; id, label, placeholder="", hint="", maxlength=nothing, required=true)

Single-line free-text input. Submits a `String`.
"""
function text_input(;
    id,
    label,
    placeholder = "",
    hint = "",
    maxlength = nothing,
    required = true,
)
    maxlen = maxlength === nothing ? (;) : (; maxlength)
    req = required ? (; required) : (;)
    input = DOM.input(;
        id,
        name = id,
        type = "text",
        class = "input",
        placeholder,
        maxlen...,
        req...,
    )
    return field(input; id, label, hint)
end

"""
    textarea_input(; id, label, placeholder="", hint="", rows=4, maxlength=nothing, required=true)

Multi-line free-text input. Submits a `String`.
"""
function textarea_input(;
    id,
    label,
    placeholder = "",
    hint = "",
    rows = 4,
    maxlength = nothing,
    required = true,
)
    maxlen = maxlength === nothing ? (;) : (; maxlength)
    req = required ? (; required) : (;)
    input = DOM.textarea(;
        id,
        name = id,
        class = "input",
        rows,
        placeholder,
        maxlen...,
        req...,
    )
    return field(input; id, label, hint)
end

"""
    number_input(; id, label, placeholder="", hint="", min=nothing, max=nothing,
                 step=nothing, required=true)

Numeric input (`type="number"`). Submits a `Float64` or `Int`.
"""
function number_input(;
    id,
    label,
    placeholder = "",
    hint = "",
    min = nothing,
    max = nothing,
    step = nothing,
    required = true,
)
    req = required ? (; required) : (;)

    input = DOM.input(;
        id,
        name = id,
        type = "number",
        inputmode = "decimal",
        class = "input",
        placeholder,
        min,
        max,
        step,
        req...,
    )

    return field(input; id, label, hint)
end

"""
    email_input(; id, label, placeholder="", hint="", required=true)

Email input (`type="email"`). Submits a `String`.
"""
function email_input(; id, label, placeholder = "", hint = "", required = true)
    req = required ? (; required) : (;)
    input = DOM.input(;
        id,
        name = id,
        type = "email",
        inputmode = "email",
        class = "input",
        placeholder,
        req...,
    )
    return field(input; id, label, hint)
end

"""
    date_input(; id, label, hint="", min=nothing, max=nothing, required=true)

Date picker (`type="date"`). Submits an ISO-8601 `String` like `"2026-09-11"`.
"""
function date_input(; id, label, hint = "", min = nothing, max = nothing, required = true)
    req = required ? (; required) : (;)
    input = DOM.input(; id, name = id, type = "date", class = "input", min, max, req...)
    return field(input; id, label, hint)
end

"""
    range_slider(; id, label, min, max, step=1, hint="", required=true)

Slider input (`type="range"`); `min` and `max` are required. Submits the
current value as a number.
"""
function range_slider(; id, label, min, max, step = 1, hint = "", required = true)
    req = required ? (; required) : (;)
    input = DOM.input(;
        id,
        name = id,
        type = "range",
        class = "input",
        min,
        max,
        step,
        req...,
    )
    return field(input; id, label, hint)
end

"""
    dropdown(; id, label, options, prompt="Please select…", hint="", required=true)

Single-choice dropdown (`<select>`). `options` is a `Vector` of `value => label`
pairs. Submits the chosen value as a `String`; unanswered optional dropdowns
submit `missing`.
"""
function dropdown(;
    id,
    label,
    options::AbstractVector{<:Pair},
    prompt = "Please select…",
    hint = "",
    required = true,
)
    placeholder = isempty(prompt) ?
        nothing :
        required ?
            DOM.option(prompt; value = "", selected = true, disabled = true) :
            DOM.option(prompt; value = "", selected = true)
    choices = [DOM.option(text; value = value) for (value, text) in options]
    req = required ? (; required) : (;)
    select = DOM.select(placeholder, choices...; id, name = id, class = "input", req...)
    return field(select; id, label, hint)
end

"""
    single_choice(; id, label, options, hint="", required=true)

Single-choice radio list. `options` is a `Vector` of `value => label` pairs.
Submits the chosen value as a `String`; unanswered optional items submit
`missing`.
"""
function single_choice(;
    id,
    label,
    options::AbstractVector{<:Pair},
    hint = "",
    required = true,
)
    req = required ? (; required) : (;)
    choices = [
        DOM.label(
            DOM.input(;
                type = "radio",
                name = id,
                id = "$(id)-$(index)",
                value = value,
                req...,
            ),
            DOM.span(text);
            class = "choice",
        )
        for (index, (value, text)) in enumerate(options)
    ]
    return DOM.div(
        isempty(label) ? nothing : DOM.label(label; class = "label", var"for" = "$(id)-1"),
        DOM.div(choices...; class = "choices"),
        isempty(hint) ? nothing : DOM.div(hint; class = "hint"),
        class = "field",
    )
end

"""
    multiple_choice(; id, label, options, hint="")

Multiple-choice checkbox list; any number of options may be checked. `options`
is a `Vector` of `value => label` pairs. The checked values are submitted as one
comma-joined `String` (unanswered submits `missing`); split it again with
[`split_multi`](@ref). HTML validation cannot enforce "at least one" here —
reject empty answers in `validate_data`.
"""
function multiple_choice(; id, label, options::AbstractVector{<:Pair}, hint = "")
    boxes = [
        DOM.label(
            DOM.input(; type = "checkbox", value = value),
            DOM.span(text);
            class = "choice",
        )
        for (value, text) in options
    ]
    hidden = DOM.input(; type = "hidden", id = id, name = id, value = "")
    group_id = "$(id)-group"
    choices = DOM.div(hidden, boxes...; class = "choices", id = group_id)
    script = """
        (function () {
            var root = document.getElementById("$group_id");
            var target = document.getElementById("$id");
            if (!root || !target) return;
            var sync = function () {
                var picked = [];
                var boxes = root.querySelectorAll("input[type=checkbox]");
                for (var i = 0; i < boxes.length; i++) {
                    if (boxes[i].checked) picked.push(boxes[i].value);
                }
                target.value = picked.join(", ");
            };
            root.addEventListener("change", sync);
            var form = root.closest ? root.closest("form") : null;
            if (form) form.addEventListener("reset", function () { setTimeout(sync, 0); });
        })();
    """
    return DOM.div(
        isempty(label) ? nothing : DOM.span(label; class = "label"),
        DOM.div(choices, DOM.script(script)),
        isempty(hint) ? nothing : DOM.div(hint; class = "hint"),
        class = "field",
    )
end

"""
    likert_scale(; id, label, levels=5, left_label="", right_label="", hint="", required=true)

Likert item rendered as a row of `levels` radio buttons labelled `1:levels`,
with optional anchor labels below the two ends. Submits the chosen level as a
string; parse it in `preprocess_submission` to keep an `Int` field, e.g.
`fields["rating"] = something(tryparse(Int, string(fields["rating"])), missing)`.
"""
function likert_scale(;
    id,
    label,
    levels = 5,
    left_label = "",
    right_label = "",
    hint = "",
    required = true,
)
    levels >= 2 || throw(ArgumentError("likert_scale: levels must be at least 2"))
    req = required ? (; required) : (;)
    dots = [
        DOM.label(
            DOM.input(; type = "radio", name = id, value = string(k), req...),
            DOM.span(string(k));
            class = "scale-opt",
        )
        for k in 1:levels
    ]
    ends = isempty(left_label) && isempty(right_label) ?
        nothing :
        DOM.div(
            DOM.span(left_label; class = "hint"),
            DOM.span(right_label; class = "hint");
            class = "scale-ends",
        )
    body = ends === nothing ?
        DOM.div(dots...; class = "scale-row") :
        DOM.div(DOM.div(dots...; class = "scale-row"), ends)
    return DOM.div(
        isempty(label) ? nothing : DOM.span(label; class = "label"),
        body,
        isempty(hint) ? nothing : DOM.div(hint; class = "hint"),
        class = "field",
    )
end

"""
    yes_no(; id, label, hint="", required=true, yes="Yes", no="No")

Yes/no question (a `single_choice` with values `"yes"` and `"no"`). Submits a
`String`.
"""
function yes_no(; id, label, hint = "", required = true, yes = "Yes", no = "No")
    return single_choice(; id, label, hint, required, options = ["yes" => yes, "no" => no])
end

"""
    consent_checkbox(; id, label, hint="", required=false)

Single checkbox (e.g. for consent statements). Submits a `Bool`; when
`required = true` the browser refuses to submit until it is checked.
"""
function consent_checkbox(; id, label, hint = "", required = false)
    req = required ? (; required) : (;)
    box = DOM.label(
        DOM.input(; type = "checkbox", id, name = id, req...),
        DOM.span(label);
        class = "choice",
    )
    hint_el = isempty(hint) ? nothing : DOM.div(hint; class = "hint")
    return DOM.div(box, hint_el; class = "field")
end

"""
    map_picker(; id, label, hint="", center=(52.52, 13.40), zoom=5,
               height="320px", geolocate=false)

Interactive Leaflet map: a click drops (or moves) a marker on the map; the
picked location is submitted as two number fields named `<id>_lat` and
`<id>_lon`. `center` is a `(lat, lon)` tuple. "Clear selection" resets the
answer (both fields submit `missing`); with `geolocate = true` a second button
asks the browser for the current position. HTML constraint validation cannot
enforce a selection here — reject `ismissing` in `validate_data` when the
answer is mandatory.

The response struct must declare both fields, e.g. for `id = "venue"`:

```julia
struct Data
    venue_lat::Union{Missing,Float64}
    venue_lon::Union{Missing,Float64}
end

LiveSurveys.render_form(::Type{Data}) =
    DOM.div(map_picker(id = "venue", label = "Where do you live?"))
```

Leaflet and the map style are loaded from a CDN and tiles come from
OpenStreetMap, so the form page requires internet access.
"""
const _LEAFLET_VERSION = "1.9.4"

function map_picker(;
    id,
    label,
    hint = "",
    center = (52.52, 13.4),
    zoom = 5,
    height = "320px",
    geolocate = false,
)
    center isa Tuple{Real, Real} ||
        throw(ArgumentError("map_picker: center must be a (lat, lon) tuple of numbers"))
    2 <= zoom <= 19 || throw(ArgumentError("map_picker: zoom must be in 2:19"))
    version = _LEAFLET_VERSION
    base = "https://unpkg.com/leaflet@$(version)/dist"
    leaflet_css = DOM.link(; rel = "stylesheet", href = "$(base)/leaflet.css")
    leaflet_js = DOM.script(; src = "$(base)/leaflet.js")
    lat_input = DOM.input(;
        type = "number",
        step = "any",
        id = "$(id)_lat",
        name = "$(id)_lat",
        value = "",
        hidden = true,
    )
    lon_input = DOM.input(;
        type = "number",
        step = "any",
        id = "$(id)_lon",
        name = "$(id)_lon",
        value = "",
        hidden = true,
    )
    map_div = DOM.div(;
        id = "$(id)-map",
        class = "map-picker",
        style = "height: $(height);",
    )
    readout = DOM.div(
        "No location selected yet.";
        id = "$(id)-readout",
        class = "map-readout",
    )
    buttons = Any[DOM.button(
        "Clear selection";
        type = "button",
        class = "map-btn",
        id = "$(id)-clear",
    )]
    geolocate &&
        push!(
            buttons,
            DOM.button(
                "Use my location";
                type = "button",
                class = "map-btn",
                id = "$(id)-locate",
            ),
        )
    script = """
        (function () {
            if (typeof L === "undefined") return;
            var map = L.map("$(id)-map").setView([$(center[1]), $(center[2])], $(zoom));
            L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
                maxZoom: 19,
                attribution: "&copy; OpenStreetMap contributors"
            }).addTo(map);
            var marker = null;
            var latInput = document.getElementById("$(id)_lat");
            var lonInput = document.getElementById("$(id)_lon");
            var readout = document.getElementById("$(id)-readout");
            function setPoint(lat, lon) {
                var la = Number(lat).toFixed(6);
                var lo = Number(lon).toFixed(6);
                if (marker) {
                    marker.setLatLng([lat, lon]);
                } else {
                    marker = L.marker([lat, lon]).addTo(map);
                }
                latInput.value = la;
                lonInput.value = lo;
                readout.textContent = "Selected: " + la + ", " + lo;
            }
            function clearPoint() {
                if (marker) { map.removeLayer(marker); marker = null; }
                latInput.value = "";
                lonInput.value = "";
                readout.textContent = "No location selected yet.";
            }
            map.on("click", function (e) { setPoint(e.latlng.lat, e.latlng.lng); });
            document.getElementById("$(id)-clear").addEventListener("click", clearPoint);
            var locateButton = document.getElementById("$(id)-locate");
            if (locateButton) {
                locateButton.addEventListener("click", function () {
                    if (!navigator.geolocation) return;
                    locateButton.disabled = true;
                    navigator.geolocation.getCurrentPosition(function (position) {
                        locateButton.disabled = false;
                        var la = position.coords.latitude;
                        var lo = position.coords.longitude;
                        map.setView([la, lo], 13);
                        setPoint(la, lo);
                    }, function () { locateButton.disabled = false; });
                });
            }
            var form = map.getContainer().closest ? map.getContainer().closest("form") : null;
            if (form) form.addEventListener("reset", clearPoint);
        })();
    """
    return DOM.div(
        DOM.span(label; class = "label"),
        leaflet_css, leaflet_js,
        lat_input, lon_input,
        map_div,
        DOM.div(buttons...; class = "map-actions"),
        readout,
        isempty(hint) ? nothing : DOM.div(hint; class = "hint"),
        DOM.script(script),
    ; class = "field")
end

"""
    split_multi(value) -> Vector{String}

Split a comma-joined [`multiple_choice`](@ref) submission into its individual
values. `missing` yields an empty vector.
"""
function split_multi(value::AbstractString)
    return String[strip(part) for part in split(value, ','; keepempty = false)]
end
split_multi(::Missing) = String[]

end # module Components
