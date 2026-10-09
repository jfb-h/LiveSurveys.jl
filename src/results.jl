function results_app(survey::Survey{R}, runtime::SurveyRuntime{R}) where R
    return App(title="$(survey.title) — results") do _
        data = Observable{Vector{R}}(runtime.data[])
        on(runtime.data) do rows
            data[] = rows
        end
        count = map(length, data)
        DOM.div(
            DOM.h1(survey.title),
            DOM.p(survey.subtitle; class="subtitle"),
            render_results(R, data, count),
        ; style=Styles(
            "font-family" => "system-ui, sans-serif",
            "width" => "fit-content",
            "margin" => "0 auto",
            "padding" => "1rem",
        ))
    end
end
