struct Survey{R}
    slug::String
    title::String
    subtitle::String
end

function Survey(::Type{R}; slug::String, title::String, subtitle::String="") where R
    isconcretetype(R) || error("Survey: response type $R must be concrete")
    isempty(fieldnames(R)) && error("Survey: $R must have at least one field")
    valid_slug(slug) || error("Survey: invalid slug $(repr(slug)) (use [a-z0-9-])")
    isempty(title) && error("Survey: title must not be empty")
    return Survey{R}(slug, title, subtitle)
end

Survey(mod::Module; kwargs...) = Survey(_response_type(mod); kwargs...)

function _response_type(mod::Module)
    isdefined(mod, :Data) || error(
        "Survey(::Module): $mod has no `Data` binding. Define `struct Data` in it, " *
        "or pass the response type directly: Survey($(mod).Data; ...).")
    return getproperty(mod, :Data)
end

valid_slug(slug::String) = !isempty(slug) && !occursin(r"[^a-z0-9-]", slug)
