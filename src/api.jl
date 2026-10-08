"""
    render_form(::Type{R}) -> DOM node

Return the survey-specific form fields for response type `R`.
"""
function render_form end

"""
    validate_data(::Type{R}, response) -> Bool

Validate a parsed response. A `false` result is returned to the client as HTTP
400.
"""
function validate_data end

"""
    preprocess_submission(::Type{R}, fields) -> fields

Transform the parsed JSON object before it is constructed as `R`. The hook may
add derived fields or normalize raw values. It must return a dictionary-like
object whose keys match the fields expected by `R`.
"""
function preprocess_submission end

preprocess_submission(::Type{R}, fields) where R = fields

"""
    render_results(::Type{R}, data, count) -> DOM node

Return the live result view for response type `R`. `data` and `count` are
updated by the runtime when responses arrive.
"""
function render_results end
