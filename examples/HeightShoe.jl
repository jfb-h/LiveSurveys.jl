module HeightShoe

using LiveSurveys: LiveSurveys, Components
using Bonito: DOM
using WGLMakie: Figure, Axis, Point2f, scatter!, xlims!, ylims!

struct Data
    height::Union{Missing, Float64}
    shoe::Union{Missing, Float64}
    gender::Union{Missing, String}
end

LiveSurveys.validate_data(::Type{Data}, d) =
    !ismissing(d.height) && !ismissing(d.shoe) &&
        (70 <= d.height <= 260) && (15 <= d.shoe <= 60)

LiveSurveys.render_form(::Type{Data}) = DOM.div(
    Components.number_input(
        id = "height",
        label = "Body height (cm)",
        placeholder = "e.g. 172",
        min = 70,
        max = 260,
        step = 0.5,
        hint = "Between 70 and 260 centimetres.",
    ),
    Components.number_input(
        id = "shoe",
        label = "Shoe size",
        placeholder = "e.g. 42",
        min = 15,
        max = 60,
        step = 1,
        hint = "EU size, whole or half numbers.",
    ),
    Components.single_choice(
        id = "gender",
        label = "Gender",
        options = ["male" => "Male", "female" => "Female", "other" => "Other"],
    ),
)

function LiveSurveys.render_results(::Type{Data}, data, n)
    fig = Figure(size = (760, 520))
    ax = Axis(fig[1, 1]; xlabel = "Body height (cm)", ylabel = "Shoe size")
    pts = map(rows -> Point2f[Point2f(r.height, r.shoe) for r in rows], data)
    colors = Dict(
        "male" => :cornflowerblue,
        "female" => :orange,
        "other" => :tomato,
        missing => :gray,
    )
    col = map(rows -> [colors[r.gender] for r in rows], data)
    scatter!(ax, pts; markersize = 10, color = col, strokecolor = :black, strokewidth = 0.6)
    xlims!(ax, 70, 260)
    ylims!(ax, 15, 60)
    return DOM.div(DOM.p(DOM.strong("n = ", n, " submissions")), fig)
end

end # module HeightShoe
