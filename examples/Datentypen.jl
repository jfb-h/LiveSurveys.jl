module SurveyDataTypes

using LiveSurveys: LiveSurveys, Components
using Bonito: DOM, Card
using WGLMakie

const CHOICES = [
    "num-kon" => "numerisch (kontinuierlich)",
    "num-dis" => "numerisch (diskret)",
    "kat-nom" => "kategorisch (nominal)",
    "kat-ord" => "kategorisch (ordinal)",
]

const QUESTIONS = [
    :bip => "Das deutsche BIP",
    :co2 => "Die CO₂-Konzentration in der Atmosphäre",
    :stars => "Sterne zur Produktbewertung bei Amazon",
    :likes => "Likes eines Youtube-Videos",
    :shf => "Der Anteil weiblicher Studierender",
    :gen => "Generationszugehörigkeit (Boomer, Millennials, Gen Z, …)",
]

const LABELS = [
    :bip => "BIP",
    :co2 => "CO₂-Konzentration",
    :stars => "Produktbewertung",
    :likes => "Likes",
    :shf => "Frauenanteil",
    :gen => "Generationszugehörigkeit",
]

const VALUES = first.(CHOICES)
const KEYS = first.(QUESTIONS)

struct Data
    bip::Union{Missing, String}
    co2::Union{Missing, String}
    stars::Union{Missing, String}
    likes::Union{Missing, String}
    shf::Union{Missing, String}
    gen::Union{Missing, String}
end

LiveSurveys.render_form(::Type{Data}) = DOM.div([
    Components.single_choice(id = string(key), label = label, options = CHOICES)
    for (key, label) in QUESTIONS
]...)

function LiveSurveys.validate_data(::Type{Data}, d)
    for key in KEYS
        value = getfield(d, key)
        ismissing(value) && return false
        value in VALUES || return false
    end
    return true
end

function counts_for(rows, key)
    return [count(r -> getfield(r, key) == value, rows) for value in VALUES]
end

function LiveSurveys.render_results(::Type{Data}, data, n)
    fig = Figure(size = (980, 560))

    for (index, (key, label)) in enumerate(LABELS)
        ax = Axis(
            fig[cld(index, 3), mod1(index, 3)];
            title = label,
            titlesize = 16,
            xticks = (1:length(VALUES), VALUES),
            yticks = WilkinsonTicks(10),
            xticklabelsize = 12,
        )
        bars = map(rows -> counts_for(rows, key), data)
        barplot!(ax, bars; color = :tomato)
        on(bars) do counts
            ylims!(ax, 0, max(1, maximum(counts)))
        end
    end

    rowgap!(fig.layout, 1, Relative(0.1))

    return DOM.div(DOM.p(DOM.strong("n = ", n, " Antworten")), fig)
end

end # module SurveyDataTypes
