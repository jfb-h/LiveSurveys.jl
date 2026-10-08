duckdb_type(T::Type) = duckdb_type(Base.nonmissingtype(T))
duckdb_type(::Type{<:Integer}) = "BIGINT"
duckdb_type(::Type{<:AbstractFloat}) = "DOUBLE"
duckdb_type(::Type{<:AbstractString}) = "VARCHAR"
duckdb_type(::Type{Bool}) = "BOOLEAN"
duckdb_type(T) = error("Unsupported DuckDB response field type: $T")
