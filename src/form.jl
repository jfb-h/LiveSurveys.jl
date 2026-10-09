const FORM_CSS = raw"""
*, *::before, *::after { box-sizing: border-box; }
html { -webkit-text-size-adjust: 100%; }
body { background: #f1f5f9; font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
       margin: 0; display: flex; justify-content: center; -webkit-tap-highlight-color: transparent;
       padding: 1.5rem max(1rem, env(safe-area-inset-left));
       padding-bottom: calc(1.5rem + env(safe-area-inset-bottom)); }
.wrap { max-width: 560px; width: 100%; }
h1   { font-size: clamp(1.35rem, 5vw, 1.6rem); color: #0f172a; margin: 0 0 0.25rem; }
.subtitle { color: #475569; margin: 0 0 1.25rem; line-height: 1.5; }
.field { background: #ffffff; border: 1px solid #e2e8f0; border-radius: 12px;
         padding: 1.25rem; box-shadow: 0 4px 12px rgba(15, 23, 42, 0.06);
         margin-bottom: 1rem; }
.label { display: block; font-weight: 600; color: #0f172a; margin-bottom: 0.35rem; }
button, input, select, textarea { font-family: inherit; }
.input { width: 100%; padding: 0.6rem 0.75rem; font-size: 1rem; min-height: 44px;
         border: 1px solid #cbd5e1; border-radius: 8px; }
.input:focus { outline: 2px solid #3b82f6; border-color: transparent; }
.hint { color: #64748b; font-size: 0.85rem; margin-top: 0.3rem; }
.choices { display: flex; flex-direction: column; gap: 0.3rem; margin: 0.45rem 0 0.1rem; }
.choice { display: flex; align-items: center; gap: 0.5rem; font-size: 1rem;
          color: #0f172a; cursor: pointer; touch-action: manipulation; }
.choice input[type="radio"], .choice input[type="checkbox"] { width: 1.35rem; height: 1.35rem; accent-color: #3b82f6; flex: none; }
.scale-row { display: flex; gap: 0.4rem; margin: 0.45rem 0 0.1rem; }
.scale-opt { flex: 1; min-width: 0; display: flex; flex-direction: column; align-items: center;
             gap: 0.2rem; font-size: 0.85rem; color: #475569; cursor: pointer; touch-action: manipulation; }
.scale-opt input { width: 1.35rem; height: 1.35rem; accent-color: #3b82f6; }
.scale-ends { display: flex; justify-content: space-between; gap: 1rem; margin-top: 0.25rem; }
select.input, textarea.input { height: auto; }
textarea.input { resize: vertical; }
.map-picker { height: 320px; border: 1px solid #cbd5e1; border-radius: 8px; background: #e2e8f0; }
.map-actions { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-top: 0.45rem; }
.map-btn { padding: 0.5rem 1rem; min-height: 44px; font-size: 0.95rem; border: 1px solid #cbd5e1;
           background: #f8fafc; border-radius: 8px; cursor: pointer; color: #0f172a; touch-action: manipulation; }
.map-btn:hover { background: #e2e8f0; }
.map-btn:disabled { opacity: 0.6; cursor: default; }
.map-readout { margin-top: 0.35rem; font-size: 0.9rem; color: #475569; }
.submit { width: 100%; margin-top: 0.5rem; padding: 0.8rem; min-height: 48px; font-size: 1.05rem;
          font-weight: 600; color: #ffffff; background: #3b82f6; border: none; border-radius: 8px;
          cursor: pointer; touch-action: manipulation; }
.submit:hover { background: #2563eb; }
.submit:disabled { opacity: 0.6; cursor: default; }
.status { margin-top: 1rem; padding: 0.6rem 0.75rem; border-radius: 8px; display: none;
          color: #0f172a; background: #e2e8f0; }
.status.ok { display: block; color: #166534; background: #dcfce7; }
.status.error { display: block; color: #991b1b; background: #fee2e2; }
@media (max-width: 480px) {
    body { padding: 1rem max(0.75rem, env(safe-area-inset-left));
           padding-bottom: calc(1rem + env(safe-area-inset-bottom)); }
    .field { padding: 1rem; border-radius: 10px; }
}
"""

const FORM_JS = raw"""
(() => {
    const form = document.getElementById("survey-form");
    const status = document.getElementById("submit-status");
    if (!(form && status)) return;
    const setStatus = (msg, kind) => {
        status.textContent = msg;
        status.className = "status" + (kind ? " " + kind : "");
    };
    form.addEventListener("submit", async (event) => {
        event.preventDefault();
        const payload = {};
        const radios = [];
        for (const el of form.elements) {
            if (!el.name) continue;
            if (el.type === "number" || el.type === "range") {
                payload[el.name] = el.value === "" ? null : el.valueAsNumber;
            } else if (el.type === "radio") {
                if (radios.indexOf(el.name) < 0) radios.push(el.name);
                if (el.checked) payload[el.name] = el.value;
            } else if (el.type === "checkbox") {
                payload[el.name] = el.checked;
            } else {
                payload[el.name] = el.value === "" ? null : el.value;
            }
        }
        for (const name of radios) {
            if (!(name in payload)) payload[name] = null;
        }
        const btn = form.querySelector("button[type=submit]");
        btn.disabled = true;
        setStatus("Submitting…");
        try {
            const res = await fetch(form.dataset.endpoint, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify(payload),
            });
            let result = null;
            try { result = await res.json(); } catch (_) { result = null; }
            if (res.ok) {
                const n = (result && result.count) || 0;
                setStatus("Thank you! Your answer was recorded." +
                          (n ? " (" + n + " submissions so far)" : ""), "ok");
                form.reset();
            } else {
                setStatus("Could not save your answer: " +
                          ((result && result.message) ? result.message : "invalid response"), "error");
            }
        } catch (err) {
            setStatus("Network error - please check your connection and try again.", "error");
        } finally {
            btn.disabled = false;
        }
    });
})();
"""

function form_content(survey::Survey{R}) where R
    attributes = Dict{Symbol,Any}(
        :id => "survey-form",
        :class => "form",
        Symbol("data-endpoint") => "api/$(survey.slug)/respond",
    )
    return DOM.form(
        render_form(R),
        DOM.button("Submit answer"; class="submit", type="submit");
        attributes...,
    )
end

function html_response(title, content)
    page = DOM.html(
        DOM.head(
            DOM.meta(; charset="utf-8"),
            DOM.meta(; name="viewport", content="width=device-width, initial-scale=1"),
            DOM.meta(; name="theme-color", content="#f1f5f9"),
            DOM.title(title),
            DOM.style(FORM_CSS),
        ),
        DOM.body(content),
    )
    body = sprint(io -> show(io, MIME"text/html"(), page))
    return Response(200, ["Content-Type" => "text/html; charset=utf-8"], "<!doctype html>" * body)
end

function form_page(handle::Survey{R}) where R
    subtitle = isempty(handle.subtitle) ? nothing : DOM.p(handle.subtitle; class="subtitle")
    content = DOM.div(
        DOM.h1(handle.title),
        subtitle,
        form_content(handle),
        DOM.div(; id="submit-status", class="status"),
        DOM.script(FORM_JS),
    ; class="wrap")
    return html_response(handle.title, content)
end
