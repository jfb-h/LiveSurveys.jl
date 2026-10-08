struct SubmissionError <: Exception
    message::String
end

Base.showerror(io::IO, error::SubmissionError) = print(io, error.message)

function parse_submission(raw, ::Type{R}) where R
    body = raw isa AbstractString ? raw : String(raw)
    fields = try
        JSON.parse(body)
    catch
        throw(SubmissionError("Expected a JSON object body."))
    end
    fields isa AbstractDict || throw(SubmissionError("Expected a JSON object body."))
    fields = try
        preprocess_submission(R, fields)
    catch
        throw(SubmissionError("Invalid value for one of the fields."))
    end
    fields isa AbstractDict || throw(SubmissionError("Expected a JSON object body."))

    known = Set(string(field) for field in fieldnames(R))
    for key in keys(fields)
        key in known || throw(SubmissionError("Unknown field $(repr(key))."))
    end
    for field in fieldnames(R)
        haskey(fields, string(field)) ||
            throw(SubmissionError("Missing field $(string(field))."))
    end

    try
        return JSON.parse(JSON.json(fields), R; null=missing)
    catch
        throw(SubmissionError("Invalid value for one of the fields."))
    end
end
