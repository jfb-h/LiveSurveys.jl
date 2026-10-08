using DuckDB

struct Store{R}
    database::DuckDB.DB
    table::String
    lock::ReentrantLock
end

function Store(::Type{R}, path::AbstractString, slug::AbstractString) where {R}
    database = DuckDB.DB(path)
    table = "responses_$(slug)"
    store = Store{R}(database, table, ReentrantLock())
    create_table!(store, R)
    return store
end

function create_table!(store::Store, ::Type{R}) where {R}
    columns = join(
        ["\"$(field)\" $(duckdb_type(fieldtype(R, field)))" for field in fieldnames(R)],
        ", ",
    )
    DBInterface.execute(
        store.database,
        "CREATE TABLE IF NOT EXISTS \"$(store.table)\" ($columns)",
    )
    add_missing_columns!(store, R)
    return nothing
end

# Schema-drift policy (DESIGN.md): fields added to a response struct are
# appended to an existing table via ALTER TABLE, with NULL for existing rows.
# Renames/type changes are explicit manual migrations.
function add_missing_columns!(store::Store, ::Type{R}) where {R}
    result = DBInterface.execute(
        store.database,
        "SELECT column_name FROM information_schema.columns WHERE table_name = ?",
        [store.table],
    )
    existing = Set{String}(
        row.column_name for row in Tables.rows(Tables.columns(result))
    )
    for field in fieldnames(R)
        name = string(field)
        name in existing && continue
        DBInterface.execute(
            store.database,
            "ALTER TABLE \"$(store.table)\" ADD COLUMN \"$(name)\" " *
            duckdb_type(fieldtype(R, field)),
        )
    end
    return nothing
end

function insert_response!(store::Store{R}, response::R) where {R}
    fields = collect(fieldnames(R))
    columns = join(["\"$(field)\"" for field in fields], ", ")
    placeholders = join(fill("?", length(fields)), ", ")
    values = [getfield(response, field) for field in fields]
    count = Ref(0)
    DBInterface.transaction(store.database) do
        DBInterface.execute(
            store.database,
            "INSERT INTO \"$(store.table)\" ($columns) VALUES ($placeholders)",
            values,
        )
        result = DBInterface.execute(
            store.database,
            "SELECT COUNT(*) AS count FROM \"$(store.table)\"",
        )
        count[] = Int(getproperty(only(Tables.rows(Tables.columns(result))), :count))
    end
    return count[]
end

function load_responses(store::Store{R}) where {R}
    columns = join(["\"$(field)\"" for field in fieldnames(R)], ", ")
    result = DBInterface.execute(
        store.database,
        "SELECT $columns FROM \"$(store.table)\"",
    )
    return R[StructUtils.make(R, row) for row in Tables.rows(Tables.columns(result))]
end

function Base.close(store::Store)
    DBInterface.close!(store.database)
    return nothing
end
