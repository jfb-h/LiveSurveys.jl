const JSON_HEADERS = ["Content-Type" => "application/json"]

json_error(status, message) =
    Response(status, JSON_HEADERS, JSON.json(Dict("message" => message)))

json_ok(payload) = Response(200, JSON_HEADERS, JSON.json(payload))

struct RespondHandler{R}
    survey::Survey{R}
    runtime::SurveyRuntime{R}
end

function Bonito.HTTPServer.apply_handler(handler::RespondHandler, context)
    request = context.request
    request.method == "POST" || return json_error(405, "Only POST is allowed here.")
    return submit_response(handler.survey, handler.runtime, request.body)
end

function submit_response(survey::Survey{R}, runtime::SurveyRuntime{R}, raw) where R
    row = try
        parse_submission(raw, R)
    catch error
        error isa SubmissionError || rethrow()
        return json_error(400, error.message)
    end
    validate_data(R, row) || return json_error(400, "Values out of range.")

    count = lock(runtime.store.lock) do
        insert_response!(runtime.store, row)
    end
    notify!(runtime)
    return json_ok(Dict("status" => "ok", "count" => count))
end
