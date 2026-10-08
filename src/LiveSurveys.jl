module LiveSurveys

using Observables
using JSON
using DBInterface
using DuckDB
using Tables
using StructUtils
using Bonito: Bonito, App, Styles, DOM
using Bonito.HTTPServer: Server, route!, Response

export Survey, serve!
export render_form, validate_data, render_results, preprocess_submission

include("api.jl")
include("survey.jl")
include("mapping.jl")
include("store.jl")
include("runtime.jl")
include("submission.jl")
include("components.jl")
include("endpoint.jl")
include("form.jl")
include("results.jl")
include("server.jl")

using .Components
export Components
export text_input, textarea_input, number_input, email_input, date_input,
       range_slider, dropdown, single_choice, multiple_choice, likert_scale,
       yes_no, consent_checkbox, map_picker, split_multi

end
