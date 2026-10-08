const _server_ref = Ref{Union{Nothing,Server}}(nothing)
const _runtime_ref = Ref{Union{Nothing,SurveyRuntime}}(nothing)

function serve!(survey::Survey{R}; host::String="0.0.0.0", port::Int=8888,
                database::AbstractString="responses.duckdb") where R
    store = Store(R, database, survey.slug)
    runtime = SurveyRuntime(store)
    previous_runtime = _runtime_ref[]
    previous_runtime === nothing || close(previous_runtime)
    previous_server = _server_ref[]
    previous_server === nothing || close(previous_server)
    _runtime_ref[] = runtime
    server = Server(host, port)
    _server_ref[] = server

    route!(server, "/" => _redirect("/$(survey.slug)"))
    route!(server, "/$(survey.slug)" => _form_handler(survey))
    route!(server, "/api/$(survey.slug)/respond" => RespondHandler(survey, runtime))
    route!(server, "/$(survey.slug)/results" => results_app(survey, runtime))

    println("Survey form:   http://localhost:$port/$(survey.slug)")
    println("Live results:  http://localhost:$port/$(survey.slug)/results")
    return server
end

_form_handler(survey::Survey) = _ -> form_page(survey)
_redirect(location::AbstractString) = _ -> Response(302, ["Location" => location], "")
