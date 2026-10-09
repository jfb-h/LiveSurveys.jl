using LiveSurveys

include("HeightShoe.jl")
using .HeightShoe

include("Datentypen.jl")
using .SurveyDataTypes

survey = Survey(
    SurveyDataTypes;
    slug = "height-shoe",
    title = "Statistics survey",
    subtitle = "Tell us your height and shoe size.",
)

server = serve!(survey; port = 8888, database = "responses.duckdb")
wait(server)
