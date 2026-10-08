struct SurveyRuntime{R}
    store::Store{R}
    notifier::Channel{Bool}
    data::Observable{Vector{R}}
    count::Observable{Int}
    task::Task
end

function SurveyRuntime(store::Store{R}) where R
    data = Observable{Vector{R}}(lock(store.lock) do
        load_responses(store)
    end)
    count = map(length, data)
    notifier = Channel{Bool}(32)
    task = @async while take!(notifier)
        snapshot = lock(store.lock) do
            load_responses(store)
        end
        data[] = snapshot
    end
    return SurveyRuntime{R}(store, notifier, data, count, task)
end

notify!(runtime::SurveyRuntime) = put!(runtime.notifier, true)

function Base.close(runtime::SurveyRuntime)
    put!(runtime.notifier, false)
    wait(runtime.task)
    close(runtime.store)
    return nothing
end
