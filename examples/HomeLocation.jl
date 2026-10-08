module HomeLocation

using LiveSurveys: LiveSurveys, Components
using Bonito: DOM
using JSON
using Observables: throttle

struct Data
    place::Union{Missing, String}
    home_lat::Union{Missing, Float64}
    home_lon::Union{Missing, Float64}
end

LiveSurveys.render_form(::Type{Data}) = DOM.div(
    Components.text_input(
        id = "place",
        label = "Place name (optional)",
        placeholder = "e.g. Göttingen",
        required = false,
        hint = "If your place has a name, tell us what it is.",
    ),
    Components.map_picker(
        id = "home",
        label = "Where do you live?",
        hint = "Click on the map to drop a marker at your home.",
        center = (51.5, 10.5),
        zoom = 5,
        height = "360px",
        geolocate = true,
    ),
)

# The map cannot express "required" through HTML validation (hidden inputs are
# exempt), so the location is enforced here.
function LiveSurveys.validate_data(::Type{Data}, d)
    return !ismissing(d.home_lat) && !ismissing(d.home_lon) &&
        (-90 <= d.home_lat <= 90) && (-180 <= d.home_lon <= 180)
end

# One live-updating map with a marker per response. The mapped Observable
# re-renders the whole map DOM whenever (throttled) new responses arrive;
# Bonito executes the embedded scripts on each swap.
function results_map(rows)
    points = JSON.json(Any[
        [Float64(r.home_lat), Float64(r.home_lon),
         ismissing(r.place) ? "" : String(r.place)]
        for r in rows if !ismissing(r.home_lat) && !ismissing(r.home_lon)
    ])
    # keep the embedded JSON from breaking out of the <script> context
    points = replace(points, "<" => "\\u003c")
    return DOM.div(
        DOM.link(; rel = "stylesheet",
                 href = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"),
        DOM.script(; src = "https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"),
        DOM.div(; id = "results-map", style =
            "height: 480px; border: 1px solid #cbd5e1; border-radius: 8px;"),
        DOM.script("""
            (function () {
                var points = $(points);
                function init(L) {
                    var map = L.map("results-map").setView([51.5, 10.5], 5);
                    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
                        maxZoom: 19,
                        attribution: "&copy; OpenStreetMap contributors"
                    }).addTo(map);
                    var layer = L.layerGroup().addTo(map);
                    points.forEach(function (p) {
                        L.circleMarker([p[0], p[1]], {
                            radius: 7, weight: 1.5, color: "#1d4ed8",
                            fillColor: "#3b82f6", fillOpacity: 0.85,
                        }).addTo(layer).bindTooltip(p[2] ? p[2] : "anonymous response");
                    });
                    if (points.length) {
                        map.fitBounds(L.latLngBounds(points).pad(0.3));
                    }
                }
                if (window.L) { init(window.L); return; }
                var tags = document.querySelectorAll("script[src*='leaflet']");
                var leaflet_tag = tags[tags.length - 1];
                if (!leaflet_tag) return;
                leaflet_tag.addEventListener("load", function () { init(window.L); });
            })();
        """),
    )
end

function LiveSurveys.render_results(::Type{Data}, data, n)
    smooth = throttle(1.0, data)  # at most one map rebuild per second
    map_view = Base.map(smooth) do rows
        results_map(rows)
    end
    return DOM.div(
        DOM.p(DOM.strong("n = ", n, " submissions")),
        map_view,
    )
end

end # module HomeLocation
