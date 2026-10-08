using LiveSurveys

include("HeightShoe.jl")
using .HeightShoe

survey = Survey(
    HeightShoe;
    slug = "height-shoe",
    title = "Statistics survey",
    subtitle = "Tell us your height and shoe size.",
)

server = serve!(survey; port = 8888, database = "responses.duckdb")
wait(server)
