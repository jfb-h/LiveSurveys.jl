using LiveSurveys
using LiveSurveys: RespondHandler, Store, SurveyRuntime, form_content, form_page
using Test
using JSON
using Observables: Observable, to_value
using WGLMakie: Makie, Point2f
using Bonito: Bonito, DOM

module Scratch

using LiveSurveys
using Bonito: DOM

struct Data
    height::Union{Missing,Float64}
    shoe::Union{Missing,Float64}
end

LiveSurveys.render_form(::Type{Data}) = DOM.div("scratch form"; class="field")

function LiveSurveys.validate_data(::Type{Data}, d)
    return (ismissing(d.height) || (70 <= d.height <= 260)) &&
           (ismissing(d.shoe)   || (15 <= d.shoe <= 60))
end

LiveSurveys.render_results(::Type{Data}, data, n) = DOM.div("scratch results")

end

module Derived

using LiveSurveys

struct Data
    height::Float64
    shoe::Float64
    bmi::Float64
end

function LiveSurveys.preprocess_submission(::Type{Data}, fields)
    result = copy(fields)
    height = Float64(result["height"]) / 100
    result["bmi"] = Float64(result["shoe"]) / height^2
    return result
end

LiveSurveys.validate_data(::Type{Data}, data) = 10 <= data.bmi <= 100

end

module Catalog

using LiveSurveys
using Bonito: DOM

struct Data
    rating::Union{Missing,Int}
    topics::Union{Missing,String}
    consent::Bool
end

LiveSurveys.render_form(::Type{Data}) = DOM.div(
    likert_scale(id = "rating", label = "How fun was the lecture?",
                 left_label = "boring", right_label = "great"),
    multiple_choice(id = "topics", label = "Favorite topics",
                    options = ["Bayes" => "Bayes", "Trees" => "Trees"], hint = "Pick any."),
    consent_checkbox(id = "consent", label = "I consent to analysis of my answers",
                     required = true),
)

function LiveSurveys.preprocess_submission(::Type{Data}, fields)
    fields["rating"] = something(tryparse(Int, string(fields["rating"])), missing)
    return fields
end

LiveSurveys.validate_data(::Type{Data}, d) = !ismissing(d.rating) && 1 <= d.rating <= 5

LiveSurveys.render_results(::Type{Data}, data, n) = DOM.div("catalog results")

end

using .Scratch

function setup()
    survey = Survey(Scratch; slug="scratch", title="Scratch", subtitle="scratch sub")
    store = Store(Scratch.Data, ":memory:", survey.slug)
    return survey, SurveyRuntime(store)
end

function respond(survey, runtime, body; method="POST")
    context = (request=(method=method, body=body),)
    return Bonito.HTTPServer.apply_handler(RespondHandler(survey, runtime), context)
end

@testset "survey construction" begin
    survey = Survey(Scratch; slug="scratch", title="Scratch", subtitle="scratch sub")
    @test survey isa LiveSurveys.Survey{Scratch.Data}
    @test LiveSurveys._response_type(Scratch) === Scratch.Data
    @test survey.slug == "scratch"
    @test survey.title == "Scratch"
    @test survey.subtitle == "scratch sub"
    @test_throws Exception Survey(Scratch; slug="bad slug", title="x")
    @test_throws Exception Survey(Real; slug="abstract", title="x")
    @test_throws Exception Survey(Scratch.Data; slug="ok", title="")
    @test_throws Exception Survey(Base; slug="nope", title="x")
    @test @inferred(Survey(Scratch.Data; slug="inferred", title="Inferred")) !== nothing
end

@testset "endpoint" begin
    survey, runtime = setup()

    response = respond(survey, runtime, """{"height": 175.5, "shoe": 42}""")
    @test response.status == 200
    @test JSON.parse(String(response.body))["count"] == 1

    @test respond(survey, runtime, """{"height": 500, "shoe": 42}""").status == 400

    response = respond(survey, runtime, """{"height": 175.5}""")
    @test response.status == 400
    @test occursin("shoe", String(response.body))

    @test respond(survey, runtime, """{"height": 175.5, "shoe": 42, "bogus": 1}""").status == 400
    @test respond(survey, runtime, """{"height": null, "shoe": 42}""").status == 200
    @test respond(survey, runtime, "{not json").status == 400
    @test respond(survey, runtime, """{"height": 175.5, "shoe": 42}"""; method="GET").status == 405
    close(runtime)
end

@testset "preprocess submission" begin
    survey = Survey(Derived; slug="derived", title="Derived")
    state = SurveyRuntime(Store(Derived.Data, ":memory:", survey.slug))
    response = respond(survey, state, """{"height": 180, "shoe": 80, "bmi": 999}""")
    @test response.status == 200
    for _ in 1:100
        !isempty(state.data[]) && break
        sleep(0.01)
    end
    @test only(state.data[]).bmi == 80 / 1.8^2

    @test respond(survey, state, """{"height": 180, "shoe": 80}""").status == 200
    close(state)
end

@testset "runtime and consumer task" begin
    survey, state = setup()
    @test @inferred(state.data[]) isa Vector{Scratch.Data}

    before = state.count[]
    @test respond(survey, state, """{"height": 175.5, "shoe": 42}""").status == 200
    for _ in 1:100
        state.count[] == before + 1 && break
        sleep(0.05)
    end
    @test state.count[] == before + 1
    @test length(state.data[]) == before + 1
    @test state.data[][end].height == 175.5
    @test @inferred(state.count[]) isa Int
    close(state)
end

@testset "form/render protocol" begin
    survey, state = setup()
    html = sprint(io -> show(io, MIME"text/html"(), form_content(survey)))
    @test occursin("scratch form", html)
    @test occursin("survey-form", html)
    @test occursin("data-endpoint=\"api/scratch/respond\"", html)
    @test LiveSurveys.FORM_JS isa String

    response = form_page(survey)
    page = String(response.body)
    @test response.status == 200
    @test occursin("<!doctype html>", page)
    @test occursin("<title>Scratch</title>", page)
    @test occursin("scratch sub", page)
    @test occursin("submit-status", page)
    close(state)
end

module Drift

struct OldData
    height::Float64
    shoe::Float64
end

struct NewData
    height::Union{Missing,Float64}
    shoe::Union{Missing,Float64}
    gender::Union{Missing,String}
end

end

@testset "schema drift: added response fields" begin
    path = tempname() * ".duckdb"
    old_store = Store(Drift.OldData, path, "drift")
    LiveSurveys.insert_response!(old_store, Drift.OldData(180.0, 44.0))
    close(old_store)

    new_store = Store(Drift.NewData, path, "drift")
    rows = LiveSurveys.load_responses(new_store)
    @test length(rows) == 1
    @test rows[1].height == 180.0
    @test rows[1].shoe == 44.0
    @test rows[1].gender === missing

    LiveSurveys.insert_response!(new_store, Drift.NewData(175.5, 42.0, "male"))
    rows = LiveSurveys.load_responses(new_store)
    @test length(rows) == 2
    @test rows[2].gender == "male"
    close(new_store)
    rm(path; force=true)
end

@testset "component rendering" begin
    dom = DOM.div(
        text_input(id = "name", label = "Name", placeholder = "Jane", maxlength = 40),
        textarea_input(id = "comments", label = "Comments", rows = 5),
        number_input(id = "age", label = "Age", min = 0, max = 130, step = 1),
        email_input(id = "mail", label = "Email"),
        date_input(id = "day", label = "Day"),
        range_slider(id = "mood", label = "Mood", min = 1, max = 10, step = 1),
        dropdown(id = "major", label = "Major", options = ["Physics" => "Physics", "Chem" => "Chem"]),
        dropdown(id = "pair", label = "Paired",
                 options = ["p1" => "Physics", "p2" => "Chemistry"]),
        single_choice(id = "minor", label = "Minor", options = ["A" => "Astro", "B" => "B"]),
        multiple_choice(id = "tags", label = "Tags", options = ["x" => "x", "y" => "y"]),
        likert_scale(id = "q1", label = "Rate", levels = 5,
                     left_label = "low", right_label = "high"),
        yes_no(id = "yn", label = "Happy?"),
        consent_checkbox(id = "ok", label = "I agree", required = true),
        map_picker(id = "venue", label = "Where do you live?",
                   center = (48.14, 11.58), zoom = 6),
    )
    html = sprint(io -> show(io, MIME"text/html"(), dom))
    @test Base.count("type=\"number\"", html) == 3  # age + venue_lat + venue_lon
    @test count("type=\"range\"", html) == 1
    @test count("type=\"date\"", html) == 1
    @test count("type=\"email\"", html) == 1
    @test occursin("<textarea", html)
    @test count("name=\"minor\"", html) == 2
    @test occursin("value=\"p2\"", html)
    @test occursin("value=\"yes\"", html)
    @test occursin("maxlength=\"40\"", html)
    @test occursin("id=\"tags-group\"", html)
    @test occursin("<script>", html)
    @test occursin("scale-opt", html)
    @test occursin("scale-ends", html)
    @test occursin("name=\"ok\"", html)
    @test occursin("id=\"venue-map\"", html)
    @test Base.count("type=\"number\"", html) == 3  # age + venue_lat + venue_lon
    @test occursin("name=\"venue_lat\"", html)
    @test occursin("name=\"venue_lon\"", html)
    @test occursin("hidden=\"true\"", html)
    @test occursin("unpkg.com/leaflet@1.9.4/dist/leaflet.js", html)
    @test occursin("unpkg.com/leaflet@1.9.4/dist/leaflet.css", html)
    @test occursin("setView([48.14, 11.58], 6)", html)
    @test occursin("tile.openstreetmap.org", html)
    @test occursin("id=\"venue-clear\"", html)
    @test !occursin("Use my location", html)

    geolocated = map_picker(id = "home", label = "Home", geolocate = true)
    geolocated_html = sprint(io -> show(io, MIME"text/html"(), geolocated))
    @test occursin("id=\"home-locate\"", geolocated_html)
    @test_throws ArgumentError map_picker(id = "x", label = "y", center = ("52.5", 13.4))
    @test_throws ArgumentError map_picker(id = "x", label = "y", zoom = 1)
    # optional items must not render any form of the required attribute
    optional = DOM.div(
        single_choice(id = "opt", label = "Optional", options = ["a" => "a"], required = false),
        likert_scale(id = "optlik", label = "Optional Likert", required = false),
        dropdown(id = "optdd", label = "Optional Dropdown",
                 options = ["a" => "a"], required = false),
        consent_checkbox(id = "optcb", label = "Optional consent"),
    )
    opt_html = sprint(io -> show(io, MIME"text/html"(), optional))
    @test !occursin("required", opt_html)
    @test_throws ArgumentError likert_scale(id = "q", label = "x", levels = 1)
    @test_throws TypeError single_choice(id = "x", label = "y", options = "oops")
    @test occursin("radio", LiveSurveys.FORM_JS)
end

@testset "multi-value splitting" begin
    @test split_multi("Bayes, Trees,  X") == ["Bayes", "Trees", "X"]
    @test split_multi(missing) == String[]
end

@testset "component survey end-to-end" begin
    survey = Survey(Catalog; slug = "catalog", title = "Catalog")
    state = SurveyRuntime(Store(Catalog.Data, ":memory:", survey.slug))

    response = respond(survey, state,
        """{"rating": "4", "topics": "Bayes, Trees", "consent": true}""")
    @test response.status == 200
    for _ in 1:100
        !isempty(state.data[]) && break
        sleep(0.01)
    end
    row = only(state.data[])
    @test row.rating === 4
    @test row.topics == "Bayes, Trees"
    @test row.consent === true

    response = respond(survey, state,
        """{"rating": null, "topics": null, "consent": true}""")
    @test response.status == 400

    response = respond(survey, state,
        """{"rating": "9", "topics": "Bayes", "consent": true}""")
    @test response.status == 400

    response = respond(survey, state,
        """{"rating": "2", "topics": null, "consent": true}""")
    @test response.status == 200
    for _ in 1:100
        length(state.data[]) == 2 && break
        sleep(0.01)
    end
    @test length(state.data[]) == 2
    @test state.data[][2].rating === 2
    @test state.data[][2].topics === missing

    html = sprint(io -> show(io, MIME"text/html"(), Catalog.render_form(Catalog.Data)))
    @test occursin("name=\"rating\"", html)
    @test occursin("id=\"topics\"", html)
    @test occursin("type=\"hidden\"", html)
    @test occursin("name=\"consent\"", html)

    close(state)
end

@testset "HomeLocation example survey" begin
    include(joinpath(@__DIR__, "..", "examples", "HomeLocation.jl"))
    using .HomeLocation

    form_html = sprint(io -> show(io, MIME"text/html"(), LiveSurveys.render_form(HomeLocation.Data)))
    @test occursin("name=\"home_lat\"", form_html)
    @test occursin("name=\"home_lon\"", form_html)
    @test occursin("name=\"place\"", form_html)
    @test occursin("id=\"home-map\"", form_html)
    @test occursin("Use my location", form_html)

    survey = Survey(HomeLocation; slug = "home-location", title = "Where do you live?")
    state = SurveyRuntime(Store(HomeLocation.Data, ":memory:", survey.slug))

    response = respond(survey, state,
        """{"place": "Göttingen", "home_lat": 51.53, "home_lon": 9.93}""")
    @test response.status == 200

    # the map item is mandatory (enforced in validate_data)
    @test respond(survey, state, """{"place": null, "home_lat": null, "home_lon": null}""").status == 400
    @test respond(survey, state, """{"place": null, "home_lat": 95.0, "home_lon": 10.0}""").status == 400

    for _ in 1:100
        !isempty(state.data[]) && break
        sleep(0.01)
    end
    row = only(state.data[])
    @test row.home_lat == 51.53
    @test row.home_lon == 9.93
    @test row.place == "Göttingen"

    results_dom = LiveSurveys.render_results(HomeLocation.Data, state.data, state.count)
    @test results_dom !== nothing
    map_view = Base.getfield(results_dom, :children)[2]
    @test map_view isa Observable
    map_html = sprint(io -> show(io, MIME"text/html"(), to_value(map_view)))
    @test occursin("id=\"results-map\"", map_html)
    @test occursin("51.53", map_html)
    @test occursin("circleMarker", map_html)
    @test occursin("Göttingen", map_html)
    close(state)
end

@testset "results protocol" begin
    survey, state = setup()
    dom = Scratch.render_results(Scratch.Data, state.data, state.count)
    html = sprint(io -> show(io, MIME"text/html"(), dom))
    @test occursin("scratch results", html)
    close(state)
end

@testset "DuckDB persistence" begin
    path = tempname() * ".duckdb"
    survey = Survey(Scratch; slug="scratch", title="Scratch")
    first = SurveyRuntime(Store(Scratch.Data, path, survey.slug))
    @test respond(survey, first, """{"height":180,"shoe":44}""").status == 200

    second = SurveyRuntime(Store(Scratch.Data, path, survey.slug))
    @test length(second.data[]) == 1
    close(first)
    close(second)
    rm(path; force=true)
end

@testset "real HeightShoe survey renders results" begin
    include(joinpath(@__DIR__, "..", "examples", "HeightShoe.jl"))
    using .HeightShoe

    rows = HeightShoe.Data[
        HeightShoe.Data(175.5, 42.0, "female"),
        HeightShoe.Data(162.0, 36.0, "other"),
    ]
    data = Observable{Vector{HeightShoe.Data}}(rows)
    count = Observable(2)
    dom = LiveSurveys.render_results(HeightShoe.Data, data, count)
    @test dom !== nothing
    @test count[] == 2

    form_html = sprint(io -> show(io, MIME"text/html"(), LiveSurveys.render_form(HeightShoe.Data)))
    @test Base.count("type=\"number\"", form_html) == 2
    @test occursin("min=\"70\"", form_html)
    @test occursin("step=\"0.5\"", form_html)
    @test Base.count("name=\"gender\"", form_html) == 3

    fig = Base.getfield(dom, :children)[2]
    ax = Makie.content(fig.layout[1, 1])
    sc = ax.scene.plots[1]
    pts0 = to_value(sc[1])
    @test pts0 isa Vector{Point2f}
    @test length(pts0) == 2

    data[] = vcat(rows, [HeightShoe.Data(190.0, 47.0, "male")])
    for _ in 1:200
        length(to_value(sc[1])) == 3 && break
        sleep(0.02)
    end
    @test length(to_value(sc[1])) == 3
end

@testset "proxy path handling" begin
    @test LiveSurveys._external_path(nothing, "scratch") == "/scratch"
    @test LiveSurveys._external_path("", "scratch") == "/scratch"
    @test LiveSurveys._external_path(".", "scratch") == "/scratch"
    @test LiveSurveys._external_path("https://example.org/statistik/", "scratch") ==
          "https://example.org/statistik/scratch"
    @test LiveSurveys._external_path("https://example.org/statistik", "scratch") ==
          "https://example.org/statistik/scratch"
end

println("ALL TESTS PASSED")
